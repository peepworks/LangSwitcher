//
//  LangSwitcher
//  Copyright (C) 2026 peepboy
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//

import Cocoa
import Foundation

// MARK: - Data Models

struct TabContext: Codable, Sendable {
    let id: String?
    let url: String?
    
    var host: String? {
        guard let urlStr = url, let urlObj = URL(string: urlStr) else { return nil }
        return urlObj.host
    }
}

// MARK: - Adapter Protocol

protocol BrowserAdapter {
    var supportedBundleIDs: [String] { get }
    func fetchActiveTabInfo(appName: String, completion: @escaping (TabContext?) -> Void)
}

// MARK: - Chromium Adapter

class ChromiumAdapter: BrowserAdapter {
    let supportedBundleIDs = [
        "com.google.Chrome",
        "com.microsoft.edgemac",
        "com.brave.Browser"
    ]
    
    func fetchActiveTabInfo(appName: String, completion: @escaping (TabContext?) -> Void) {
        let script = """
        function run(argv) {
            try {
                var browser = Application("\(appName)");
                if (browser.windows.length > 0) {
                    var tab = browser.windows[0].activeTab();
                    return JSON.stringify({ "id": tab.id().toString(), "url": tab.url() });
                }
            } catch(e) {}
            return null;
        }
        """
        
        // 🌟 [수정됨] executeJXA에서 넘어온 String을 JSON 파싱하여 TabContext로 변환 후 completion 호출
        executeJXA(script: script) { resultString in
            guard let resultString = resultString,
                  let data = resultString.data(using: .utf8),
                  let context = try? JSONDecoder().decode(TabContext.self, from: data) else {
                completion(nil)
                return
            }
            completion(context)
        }
    }
}

// MARK: - Safari Adapter

class SafariAdapter: BrowserAdapter {
    let supportedBundleIDs = ["com.apple.Safari"]
    
    func fetchActiveTabInfo(appName: String, completion: @escaping (TabContext?) -> Void) {
        let script = """
        function run(argv) {
            try {
                var browser = Application("Safari");
                if (browser.windows.length > 0) {
                    var tab = browser.windows[0].currentTab();
                    return JSON.stringify({ "id": null, "url": tab.url() });
                }
            } catch(e) {}
            return null;
        }
        """
        
        // 🌟 [수정됨] 동일하게 String 결과값을 TabContext로 변환
        executeJXA(script: script) { resultString in
            guard let resultString = resultString,
                  let data = resultString.data(using: .utf8),
                  let context = try? JSONDecoder().decode(TabContext.self, from: data) else {
                completion(nil)
                return
            }
            completion(context)
        }
    }
}

// MARK: - JXA 스크립트 비동기 실행 (Thread Explosion 방지 적용)
// 🌟 completion 클로저를 통해 결과를 비동기적으로 전달받도록 수정
private func executeJXA(script: String, completion: @escaping (String?) -> Void) {
    let process = Process()
    let pipe = Pipe()
    
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-l", "JavaScript", "-e", script]
    process.standardOutput = pipe
    process.standardError = Pipe() // 에러 로그가 표준 출력에 섞이는 것 방지
    
    // 🌟 [핵심 변경 포인트] waitUntilExit() 대신 terminationHandler 사용
    process.terminationHandler = { proc in
        // 프로세스가 종료되면 이 블록이 실행됩니다. (대기 스레드 없음!)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        
        // 결과를 문자열로 변환하고 공백/줄바꿈 제거
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 결과가 빈 문자열이면 nil로 처리, 아니면 결과 전달
        let finalResult = (output?.isEmpty == true) ? nil : output
        
        // 결과를 메인 스레드나 호출한 쪽에 전달
        completion(finalResult)
    }
    
    do {
        try process.run()
        // ⚠️ 주의: 여기에 process.waitUntilExit()을 절대 쓰면 안 됩니다!
    } catch {
        #if DEBUG
        print("JXA 프로세스 실행 실패: \(error)")
        #endif
        completion(nil)
    }
}

// MARK: - Core Manager

@MainActor
class BrowserTabManager {
    static let shared = BrowserTabManager()
        
    private var adapters: [String: BrowserAdapter] = [:]
        
    // 🌟 탭 메모리 관련 변수들
    private var tabMemory: [String: String] = [:]
    private var lastEvaluatedHostForTab: [String: String] = [:]
    
    // 🌟 [수정됨] Array(O(n))를 버리고, 초고속 O(1) Dictionary와 Tick 카운터를 도입
    private var tabAccessTicks: [String: Int] = [:]
    private var currentTick: Int = 0
    private let maxTabMemoryLimit = 100
    
    var currentKey: String? = nil
    private var jxaWorkItem: DispatchWorkItem?
    
    private var fetchGeneration: Int = 0
        
    func clearMemory() {
        tabMemory.removeAll()
        lastEvaluatedHostForTab.removeAll()
        // 🌟 수정된 변수 초기화
        tabAccessTicks.removeAll()
        currentTick = 0
        
        currentKey = nil
        fetchGeneration = 0
    }
    
    private init() {
        let chromium = ChromiumAdapter()
        for id in chromium.supportedBundleIDs { adapters[id] = chromium }
        
        let safari = SafariAdapter()
        for id in safari.supportedBundleIDs { adapters[id] = safari }
    }
    
    func handleBrowserTabChanged(bundleID: String, appName: String) {
        guard SettingsManager.shared.isBrowserTabMemoryEnabled || SettingsManager.shared.isBrowserDomainModeEnabled else { return }
        guard let adapter = adapters[bundleID] else { return }

        saveCurrentContext()
                
        jxaWorkItem?.cancel()
        
        fetchGeneration += 1
        let currentGeneration = fetchGeneration
                
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.executeTabFetchAndRestore(bundleID: bundleID, appName: appName, adapter: adapter, generation: currentGeneration)
        }

        jxaWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: item)
    }
        
    private func executeTabFetchAndRestore(bundleID: String, appName: String, adapter: BrowserAdapter, generation: Int) {
        adapter.fetchActiveTabInfo(appName: appName) { [weak self] context in
            DispatchQueue.main.async {
                guard let self = self, self.fetchGeneration == generation, let context = context else { return }
                    
                guard let newKey = self.generateTabKey(from: context, bundleID: bundleID) else { return }
                
                // 🌟 [추가됨] 이 탭에 접근했으므로 LRU 캐시 갱신
                self.touchTabMemory(key: newKey)
                
                let isTabSwitched = (self.currentKey != newKey)
                
                if SettingsManager.shared.isBrowserDomainModeEnabled, let urlString = context.url, let host = context.host {
                    let lastHost = self.lastEvaluatedHostForTab[newKey]
                    
                    if lastHost != host || isTabSwitched {
                        self.lastEvaluatedHostForTab[newKey] = host
                        
                        if let matchedRule = DomainRuleManager.shared.findMatchingRule(for: urlString, browserBundleID: bundleID) {
                            let hasManualMemory = (self.tabMemory[newKey] != nil)
                            if isTabSwitched && SettingsManager.shared.isBrowserTabMemoryEnabled && hasManualMemory {
                                // 탭 메모리에 양보
                            } else {
                                InputSourceManager.shared.switchLanguage(to: matchedRule.targetInputSourceID)
                                self.currentKey = newKey
                                self.tabMemory[newKey] = matchedRule.targetInputSourceID
                                return
                            }
                        }
                    }
                }
                    
                if !isTabSwitched { return }
                    
                if self.isNewTab(context: context) {
                    let defaultLang = SettingsManager.shared.newTabDefaultLanguage
                    if defaultLang != "None" && !defaultLang.isEmpty {
                        InputSourceManager.shared.switchLanguage(to: defaultLang)
                        self.currentKey = newKey
                        self.tabMemory[newKey] = defaultLang
                        return
                    }
                }
                    
                self.currentKey = newKey
                if SettingsManager.shared.isBrowserTabMemoryEnabled {
                    self.restoreContext(for: newKey)
                }
            }
        }
    }
    
    // 🌟 [추가됨] LRU 캐시 업데이트 로직 (가장 최근에 본 탭을 위로 올리고, 100개가 넘으면 오래된 탭을 삭제)
    // 🌟 [수정됨] O(n) 선형 탐색을 제거한 초고속 LRU 캐시 갱신
    // 🌟 [수정됨] 이론적인 Int.max 오버플로우 방어 로직 추가
    private func touchTabMemory(key: String) {
        // 1. 번호표 발급기가 한계에 도달했는지 확인 (약 922경 번 접근 시)
        if currentTick == Int.max {
            rebuildTicksFromScratch()
        }
        
        currentTick += 1
        tabAccessTicks[key] = currentTick
        
        if tabAccessTicks.count > maxTabMemoryLimit {
            if let oldest = tabAccessTicks.min(by: { $0.value < $1.value }) {
                let oldestKey = oldest.key
                tabMemory.removeValue(forKey: oldestKey)
                lastEvaluatedHostForTab.removeValue(forKey: oldestKey)
                tabAccessTicks.removeValue(forKey: oldestKey)
            }
        }
    }
    
    // 🌟 [추가됨] 번호표가 꽉 찼을 때, 현재 살아있는 100개의 탭에게만 1번부터 100번까지 새 번호를 부여하는 함수
    private func rebuildTicksFromScratch() {
        // 1. 현재 살아있는 탭들을 번호표가 작은 순서(오래된 순)로 줄을 세웁니다.
        let sortedKeys = tabAccessTicks.sorted { $0.value < $1.value }.map { $0.key }
        
        // 2. 기존 번호표 장부를 싹 비웁니다.
        tabAccessTicks.removeAll(keepingCapacity: true)
        
        // 3. 줄 서 있는 순서대로 1번부터 새로운 번호표를 발급합니다.
        for (index, key) in sortedKeys.enumerated() {
            tabAccessTicks[key] = index + 1 // 1번부터 최대 100번까지 부여됨
        }
        
        // 4. 발급기(currentTick)의 현재 숫자를 살아있는 탭의 개수(예: 100)로 초기화합니다.
        // 다음 탭이 들어오면 101번을 받게 됩니다!
        currentTick = sortedKeys.count
        
        #if DEBUG
        print("BrowserTabManager: LRU Tick 오버플로우 방지를 위해 번호표를 성공적으로 재설정했습니다.")
        #endif
    }
    
    private func isNewTab(context: TabContext) -> Bool {
        guard let url = context.url?.lowercased() else { return true }
            
        let newTabPatterns = [
            "chrome://newtab",
            "edge://newtab",
            "brave://newtab",
            "about:blank",
            "favorites://",
            "topsites://",
            "safari-resource://topsites",
            "safari-resource://"
        ]
            
        return url.isEmpty || newTabPatterns.contains { url.starts(with: $0) }
    }
    
    func handleBrowserDeactivated() {
        saveCurrentContext()
        currentKey = nil
    }
    
    private func saveCurrentContext() {
        guard let key = currentKey else { return }
        let currentSource = InputSourceManager.shared.currentInputSourceID()
        tabMemory[key] = currentSource
        // 🌟 저장할 때도 접근한 것이므로 LRU 갱신
        touchTabMemory(key: key)
    }
    
    private func restoreContext(for key: String) {
        if let savedSourceID = tabMemory[key] {
            InputSourceManager.shared.switchLanguage(to: savedSourceID)
        }
    }
    
    private func generateTabKey(from context: TabContext, bundleID: String) -> String? {
        if let id = context.id { return "\(bundleID)_tab_\(id)" }
        if let url = context.url { return "\(bundleID)_url_\(url)" }
        return nil
    }
}
