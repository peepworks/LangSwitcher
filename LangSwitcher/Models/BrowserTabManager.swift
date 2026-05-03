//
//  BrowserTabManager.swift
//  LangSwitcher
//
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
        
    private var tabMemory: [String: String] = [:]
    
    // 🌟 [수정] 탭별로 마지막으로 검사/적용한 도메인을 기억합니다. (중복 검사 방지)
    private var lastEvaluatedHostForTab: [String: String] = [:]
    
    var currentKey: String? = nil
    private var jxaWorkItem: DispatchWorkItem?
        
    func clearMemory() {
        tabMemory.removeAll()
        lastEvaluatedHostForTab.removeAll()
        currentKey = nil
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
                
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.executeTabFetchAndRestore(bundleID: bundleID, appName: appName, adapter: adapter)
        }

        jxaWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: item)
    }
        
    private func executeTabFetchAndRestore(bundleID: String, appName: String, adapter: BrowserAdapter) {
        adapter.fetchActiveTabInfo(appName: appName) { [weak self] context in
            DispatchQueue.main.async {
                guard let self = self, let context = context else { return }
                    
                // 🌟 1. 항상 탭 고유 식별자로 키를 생성합니다. (도메인 설정 무관)
                guard let newKey = self.generateTabKey(from: context, bundleID: bundleID) else { return }
                
                let isTabSwitched = (self.currentKey != newKey)
                
                // 🌟 [우선순위 1] 웹사이트별 키보드 자동 전환 (도메인 규칙)
                if SettingsManager.shared.isBrowserDomainModeEnabled, let urlString = context.url, let host = context.host {
                    
                    let lastHost = self.lastEvaluatedHostForTab[newKey]
                    
                    // 호스트(도메인)가 바뀌었거나, 다른 탭으로 넘어왔을 때만 규칙 검사
                    if lastHost != host || isTabSwitched {
                        // 검사 완료 마킹
                        self.lastEvaluatedHostForTab[newKey] = host
                        
                        if let matchedRule = DomainRuleManager.shared.findMatchingRule(for: urlString, browserBundleID: bundleID) {
                            
                            // 단, 다른 탭으로 넘어왔고 && 사용자가 이 탭에서 수동으로 언어를 바꾼 기억(tabMemory)이 있다면 덮어쓰지 않음
                            let hasManualMemory = (self.tabMemory[newKey] != nil)
                            if isTabSwitched && SettingsManager.shared.isBrowserTabMemoryEnabled && hasManualMemory {
                                // 탭 메모리에 양보 (아래 우선순위 3에서 처리)
                            } else {
                                InputSourceManager.shared.switchLanguage(to: matchedRule.targetInputSourceID)
                                self.currentKey = newKey
                                self.tabMemory[newKey] = matchedRule.targetInputSourceID
                                return // 규칙을 적용했으면 종료
                            }
                        }
                    }
                }
                    
                // 완전히 동일한 탭이고 주소도 안 바뀌었으면 종료
                if !isTabSwitched {
                    return
                }
                    
                // 🌟 [우선순위 2] 새 탭(특수 URL) 검사
                if self.isNewTab(context: context) {
                    let defaultLang = SettingsManager.shared.newTabDefaultLanguage
                    if defaultLang != "None" && !defaultLang.isEmpty {
                        InputSourceManager.shared.switchLanguage(to: defaultLang)
                        self.currentKey = newKey
                        self.tabMemory[newKey] = defaultLang
                        return
                    }
                }
                    
                // 🌟 [우선순위 3] 일반적인 탭 메모리 복원
                self.currentKey = newKey
                if SettingsManager.shared.isBrowserTabMemoryEnabled {
                    self.restoreContext(for: newKey)
                }
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
    }
    
    private func restoreContext(for key: String) {
        if let savedSourceID = tabMemory[key] {
            InputSourceManager.shared.switchLanguage(to: savedSourceID)
        }
    }
    
    // 🌟 치명적 버그 수정: 도메인 설정과 상관없이 무조건 탭 고유 식별자로 키를 만듭니다.
    private func generateTabKey(from context: TabContext, bundleID: String) -> String? {
        if let id = context.id { return "\(bundleID)_tab_\(id)" }
        if let url = context.url { return "\(bundleID)_url_\(url)" }
        return nil
    }
}
