//
//  HyperKeyManager.swift
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

// 🌟 [수정됨] Swift 6 동시성 에러 방지를 위해 Sendable 프로토콜 추가
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
    /// 브라우저에 AppleScript/JXA를 전송하여 현재 활성 탭의 정보를 비동기로 가져옵니다.
    func fetchActiveTabInfo(appName: String, completion: @escaping (TabContext?) -> Void)
}

// MARK: - Chromium Adapter (Chrome, Edge, Brave)

class ChromiumAdapter: BrowserAdapter {
    let supportedBundleIDs = [
        "com.google.Chrome",
        "com.microsoft.edgemac",
        "com.brave.Browser"
    ]
    
    func fetchActiveTabInfo(appName: String, completion: @escaping (TabContext?) -> Void) {
        // JXA (JavaScript for Automation)를 사용하여 크롬 계열 브라우저의 활성 탭 id와 url을 추출합니다.
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
        // Safari는 탭 고유 ID 추출이 제한적이므로 url을 우선적으로 추출합니다.
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

// MARK: - JXA Helper (비동기 처리 핵심)

/// 메인 스레드(UI)를 블로킹하지 않도록 백그라운드에서 별도의 프로세스로 JXA 스크립트를 실행합니다.
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
                
                // 🌟 [핵심 수정] Swift 6 동시성 에러 해결
                // 메인 스레드 영역(Main Actor)으로 디코딩 작업을 안전하게 넘깁니다.
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

class BrowserTabManager {
    static let shared = BrowserTabManager()
    
    private var adapters: [String: BrowserAdapter] = [:]
    
    // 메모리 저장소: [브라우저 탭 고유 키: 입력 소스 ID]
    private var tabMemory: [String: String] = [:]
    
    // 현재 포커스 된 탭의 키
    private var currentKey: String?
    
    private init() {
        // 어댑터 등록
        let chromium = ChromiumAdapter()
        for id in chromium.supportedBundleIDs { adapters[id] = chromium }
        
        let safari = SafariAdapter()
        for id in safari.supportedBundleIDs { adapters[id] = safari }
    }
    
    // 🌟 핵심 진입점: 브라우저가 활성화되거나 탭이 전환(Title Change)될 때마다 호출됩니다.
    func handleBrowserTabChanged(bundleID: String, appName: String) {
        guard SettingsManager.shared.isBrowserTabMemoryEnabled else { return }
        guard let adapter = adapters[bundleID] else { return }
            
        saveCurrentContext()
            
        adapter.fetchActiveTabInfo(appName: appName) { [weak self] context in
            guard let self = self, let context = context else { return }
                
            // 🌟 [추가] 새 탭 여부 확인 및 기본 언어 적용
            if self.isNewTab(context: context) {
                let defaultLang = SettingsManager.shared.newTabDefaultLanguage
                if defaultLang != "None" && !defaultLang.isEmpty {
                    // 새 탭이면 기억된 값 무시하고 설정된 기본 언어로 강제 전환
                    InputSourceManager.shared.switchLanguage(to: defaultLang)
                    self.currentKey = nil
                    return
                }
            }
                
            guard let newKey = self.generateKey(from: context, bundleID: bundleID) else { return }
            self.currentKey = newKey
            self.restoreContext(for: newKey)
        }
    }
    
    // 🌟 [추가] 브라우저별 새 탭 주소 패턴 감지
    private func isNewTab(context: TabContext) -> Bool {
        guard let url = context.url?.lowercased() else { return true }
            
        // 주요 브라우저의 새 탭 특수 주소들
        let newTabPatterns = [
            "chrome://newtab",
            "edge://newtab",
            "brave://newtab",
            "about:blank",
            "favorites://", // Safari
            "topsites://"   // Safari
        ]
            
        // URL이 비어있거나 위 패턴으로 시작하면 새 탭으로 간주
        return url.isEmpty || newTabPatterns.contains { url.starts(with: $0) }
    }
    
    // 🌟 앱 포커스가 브라우저가 아닌 다른 곳으로 빠져나갈 때 호출하여 마지막 상태를 저장합니다.
    func handleBrowserDeactivated() {
        saveCurrentContext()
        currentKey = nil
    }
    
    private func saveCurrentContext() {
        guard let key = currentKey else { return }
        // InputSourceManager에서 현재 활성화된 입력 소스 ID(예: com.apple.keylayout.ABC)를 가져옵니다.
        let currentSource = InputSourceManager.shared.currentInputSourceID()
        tabMemory[key] = currentSource
    }
    
    private func restoreContext(for key: String) {
        if let savedSourceID = tabMemory[key] {
            // 🌟 [수정됨] 단순 시스템 API 대신, HUD 등 모든 앱 내장 로직이 포함된 기존 switchLanguage를 호출합니다.
            DispatchQueue.main.async {
                InputSourceManager.shared.switchLanguage(to: savedSourceID)
            }
        }
    }
    
    // 🌟 사용자가 설정한 옵션(탭 단위 vs 사이트 단위)에 따라 고유 키를 생성합니다.
    private func generateKey(from context: TabContext, bundleID: String) -> String? {
        let isDomainMode = SettingsManager.shared.isBrowserDomainModeEnabled
        
        if isDomainMode {
            // 사이트 단위 기억 (예: com.google.Chrome_github.com)
            guard let host = context.host else { return nil }
            return "\(bundleID)_\(host)"
        } else {
            // 탭 단위 기억 (1순위: 탭 고유 ID, 2순위: 전체 URL)
            if let id = context.id { return "\(bundleID)_tab_\(id)" }
            if let url = context.url { return "\(bundleID)_url_\(url)" }
            return nil
        }
    }
    
    // 메모리 최적화를 위해 브라우저 종료 시 호출할 수 있습니다.
    func clearMemory() {
        tabMemory.removeAll()
        currentKey = nil
    }
}
