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
import OSAKit // 🌟 [추가] 인프로세스 JXA 실행을 위한 Apple 공식 프레임워크

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
        
        // 🌟 [수정됨] 클로저 방식이 아닌, 즉시 값을 변수(resultString)로 받아옵니다.
        let resultString = executeJXA(script: script)
        
        guard let resultString = resultString,
              let data = resultString.data(using: .utf8),
              let context = try? JSONDecoder().decode(TabContext.self, from: data) else {
            completion(nil)
            return
        }
        completion(context)
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
        
        // 🌟 [수정됨] 사파리 역시 동일하게 클로저 대신 변수로 결과값을 즉시 받습니다.
        let resultString = executeJXA(script: script)
        
        guard let resultString = resultString,
              let data = resultString.data(using: .utf8),
              let context = try? JSONDecoder().decode(TabContext.self, from: data) else {
            completion(nil)
            return
        }
        completion(context)
    }
}

// MARK: - JXA 스크립트 비동기 실행 (Thread Explosion 방지 적용)
// 🌟 [수정됨] 무거운 Process() 대신 앱 내부 메모리에서 즉시 실행되는 OSAKit 사용
private func executeJXA(script: String) -> String? {
    // JXA(JavaScript) 언어 엔진을 불러옵니다.
    guard let language = OSALanguage(forName: "JavaScript") else {
        print("JavaScript for Automation 언어 엔진을 찾을 수 없습니다.")
        return nil
    }
    
    // 스크립트 객체를 생성합니다.
    let osaScript = OSAScript(source: script, language: language)
    var errorInfo: NSDictionary?
    
    // 🌟 [수정됨] osaScript는 Optional이 아니므로 물음표(?)를 제거합니다.
    let result = osaScript.executeAndReturnError(&errorInfo)
    
    if let error = errorInfo {
        print("JXA 실행 에러: \(error)")
        return nil
    }
    
    // 실행 결과를 문자열로 반환합니다.
    return result?.stringValue
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
        // 🌟 [수정됨] 0.3초로 늘려, 탭 이동이 완전히 끝난 후 한 번만 스크립트가 돌도록(Debounce) 안정화합니다.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
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
