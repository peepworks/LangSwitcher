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
        executeJXA(script: script, completion: completion)
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
        executeJXA(script: script, completion: completion)
    }
}

// MARK: - JXA Helper

private func executeJXA(script: String, completion: @escaping (TabContext?) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
        let process = Process()
        process.launchPath = "/usr/bin/osascript"
        process.arguments = ["-l", "JavaScript", "-e", script]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               let jsonData = output.data(using: .utf8) {
                
                DispatchQueue.main.async {
                    let context = try? JSONDecoder().decode(TabContext.self, from: jsonData)
                    completion(context)
                }
            } else {
                DispatchQueue.main.async { completion(nil) }
            }
        } catch {
            DispatchQueue.main.async { completion(nil) }
        }
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
    private func touchTabMemory(key: String) {
        // 1. 배열을 뒤질 필요 없이, O(1) 속도로 해당 탭에 최신 번호표(Tick)를 부여합니다.
        currentTick += 1
        tabAccessTicks[key] = currentTick
        
        // 2. 100개가 넘었을 때만 가장 오래된(번호표가 가장 작은) 탭을 찾아 삭제합니다.
        if tabAccessTicks.count > maxTabMemoryLimit {
            if let oldest = tabAccessTicks.min(by: { $0.value < $1.value }) {
                let oldestKey = oldest.key
                tabMemory.removeValue(forKey: oldestKey)
                lastEvaluatedHostForTab.removeValue(forKey: oldestKey)
                tabAccessTicks.removeValue(forKey: oldestKey)
            }
        }
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
