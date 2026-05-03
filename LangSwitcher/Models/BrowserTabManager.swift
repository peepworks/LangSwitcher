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

// 🌟 [핵심] 이 클래스의 모든 동작은 메인 스레드에서 안전하게 실행됨을 보장합니다.
@MainActor
class BrowserTabManager {
    static let shared = BrowserTabManager()
        
    private var adapters: [String: BrowserAdapter] = [:]
        
    // 🌟 무거운 accessQueue를 제거하고, 원래의 가장 단순하고 빠른 딕셔너리 형태로 돌아왔습니다.
    private var tabMemory: [String: String] = [:]
    var currentKey: String? = nil
    
    // 🌟 1. 디바운스를 위한 타이머(WorkItem) 변수 추가
    private var jxaWorkItem: DispatchWorkItem?
        
    func clearMemory() {
        tabMemory.removeAll()
        currentKey = nil
    }
    
    private init() {
        // 어댑터 등록
        let chromium = ChromiumAdapter()
        for id in chromium.supportedBundleIDs { adapters[id] = chromium }
        
        let safari = SafariAdapter()
        for id in safari.supportedBundleIDs { adapters[id] = safari }
    }
    
    // 🌟 2. 디바운스가 적용된 새로운 진입점
    func handleBrowserTabChanged(bundleID: String, appName: String) {
        guard SettingsManager.shared.isBrowserTabMemoryEnabled else { return }
        guard let adapter = adapters[bundleID] else { return }

        // 떠나기 전 현재 탭의 언어는 즉시 저장합니다. (저장은 가벼운 작업이므로 딜레이 불필요)
        saveCurrentContext()
                
        // [핵심] 0.1초 안에 탭이 또 바뀌어서 이 함수가 다시 불렸다면?
        // 기존에 출발하려고 대기 중이던 JXA 작업을 취소(Cancel)해버립니다. (새치기 방지)
        jxaWorkItem?.cancel()
                
        // 새로운 작업을 생성합니다.
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            // 진짜 무거운 JXA 스크립트 실행은 이 안에서 진행됩니다.
            self.executeTabFetchAndRestore(bundleID: bundleID, appName: appName, adapter: adapter)
        }

        // 타이머 변수에 덮어씌웁니다.
        jxaWorkItem = item

        // 0.1초(100ms) 뒤에 예약된 작업을 실행합니다.
        // 0.1초 안에 또 탭을 넘기면 위에서 cancel() 되므로 절대 중복 실행되지 않습니다.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: item)
    }
        
    // 🌟 3. 기존에 있던 JXA 호출 및 복원 로직을 별도의 함수로 분리합니다.
    private func executeTabFetchAndRestore(bundleID: String, appName: String, adapter: BrowserAdapter) {
        adapter.fetchActiveTabInfo(appName: appName) { [weak self] context in
            DispatchQueue.main.async {
                guard let self = self, let context = context else { return }
                    
                if self.isNewTab(context: context) {
                    let defaultLang = SettingsManager.shared.newTabDefaultLanguage
                    if defaultLang != "None" && !defaultLang.isEmpty {
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
    }
    
    // 🌟 브라우저별 새 탭 주소 패턴 감지
    private func isNewTab(context: TabContext) -> Bool {
        // 비교를 위해 URL을 모두 소문자로 변환합니다.
        guard let url = context.url?.lowercased() else { return true }
            
        // 주요 브라우저의 새 탭 특수 주소들
        let newTabPatterns = [
            "chrome://newtab",
            "edge://newtab",
            "brave://newtab",
            "about:blank",
            "favorites://",                 // Safari: 즐겨찾기 시작 페이지
            "topsites://",                  // Safari: 과거 버전의 탑 사이트
            "safari-resource://topsites",   // 🌟 [추가됨] Safari: 최신 버전의 탑 사이트 명시적 지정 (소문자)
            "safari-resource://"            // Safari: 기타 모든 내부 리소스 포괄
        ]
            
        // URL이 비어있거나 위 패턴으로 시작하면 새 탭으로 간주
        return url.isEmpty || newTabPatterns.contains { url.starts(with: $0) }
    }
    
    func handleBrowserDeactivated() {
        saveCurrentContext()
        currentKey = nil
    }
    
    private func saveCurrentContext() {
        guard let key = currentKey else { return }
        let currentSource = InputSourceManager.shared.currentInputSourceID()
        
        // 🌟 헬퍼 메서드 대신 아주 직관적인 원래 코드로 복구
        tabMemory[key] = currentSource
    }
    
    private func restoreContext(for key: String) {
        if let savedSourceID = tabMemory[key] {
            // 🌟 이미 @MainActor 덕분에 메인 스레드임이 보장되므로 DispatchQueue.main.async를 한 번 더 씌울 필요가 없습니다.
            InputSourceManager.shared.switchLanguage(to: savedSourceID)
        }
    }
    
    private func generateKey(from context: TabContext, bundleID: String) -> String? {
        let isDomainMode = SettingsManager.shared.isBrowserDomainModeEnabled
        
        if isDomainMode {
            guard let host = context.host else { return nil }
            return "\(bundleID)_\(host)"
        } else {
            if let id = context.id { return "\(bundleID)_tab_\(id)" }
            if let url = context.url { return "\(bundleID)_url_\(url)" }
            return nil
        }
    }
}
