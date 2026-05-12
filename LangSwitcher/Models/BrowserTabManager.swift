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
import OSAKit

// MARK: - Data Models

struct TabContext: Codable, Sendable {
    let id: String?
    let url: String?

    var host: String? {
        guard let urlStr = url, let urlObj = URL(string: urlStr) else { return nil }
        return urlObj.host
    }
}

// 🌟 텔레메트리를 위한 브라우저 JXA 에러 타입 정의
enum BrowserFetchError: Error {
    case timeout
    case permissionDenied
    case noWindow
    case unsupportedBrowser
    case executionFailed(String)
    case decodingFailed
}

// MARK: - Adapter Protocol

protocol BrowserAdapter: Sendable {
    var supportedBundleIDs: [String] { get }
    func fetchActiveTabInfo(appName: String) async -> Result<TabContext, BrowserFetchError>
}

// 🌟 [추가] JXA 실행이 절대 겹치지 않도록 교통정리를 해주는 전용 직렬(Serial) 큐
private let jxaExecutionQueue = DispatchQueue(label: "com.peepboy.LangSwitcher.JXAQueue", qos: .userInitiated)

// 🌟 [수정된 함수] 충돌 방지와 타임아웃이 완벽하게 결합된 JXA 실행 엔진
private func executeJXAWithTimeout(script: String) async -> Result<String, BrowserFetchError> {
    return await withCheckedContinuation { continuation in
        // 타임아웃(1초)을 재기 위한 글로벌 백그라운드 큐
        DispatchQueue.global(qos: .userInitiated).async {
            let dispatchGroup = DispatchGroup()
            dispatchGroup.enter()

            var scriptResult: NSAppleEventDescriptor?
            var errorInfo: NSDictionary?

            // 🌟 [핵심 방어] JXA 엔진 접근은 반드시 직렬 큐(jxaExecutionQueue) 안에서만 순서대로 실행됩니다.
            jxaExecutionQueue.async {
                autoreleasepool {
                    // 🌟 매번 독립적인 언어 인스턴스를 생성하여 스레드 충돌 완벽 차단!
                    if let language = OSALanguage(forName: "JavaScript") {
                        let osaScript = OSAScript(source: script, language: language)
                        scriptResult = osaScript.executeAndReturnError(&errorInfo)
                    } else {
                        errorInfo = ["NSLocalizedDescription": "OSALanguage Init Failed"] as NSDictionary
                    }
                    dispatchGroup.leave()
                }
            }

            // 🌟 1.0초 타임아웃 설정 (무한 대기 방지)
            let result = dispatchGroup.wait(timeout: .now() + 1.0)

            if result == .timedOut {
                continuation.resume(returning: .failure(.timeout))
                return
            }

            if let error = errorInfo {
                continuation.resume(returning: .failure(.executionFailed(error.description)))
                return
            }

            let output = scriptResult?.stringValue ?? ""

            // 스크립트에서 반환한 커스텀 에러 파싱
            if output.hasPrefix("ERROR:") {
                let errType = output.replacingOccurrences(of: "ERROR:", with: "")
                switch errType {
                case "NO_WINDOW": continuation.resume(returning: .failure(.noWindow))
                case "PERMISSION": continuation.resume(returning: .failure(.permissionDenied))
                case "UNSUPPORTED": continuation.resume(returning: .failure(.unsupportedBrowser))
                default: continuation.resume(returning: .failure(.executionFailed(errType)))
                }
            } else if !output.isEmpty {
                continuation.resume(returning: .success(output))
            } else {
                continuation.resume(returning: .failure(.executionFailed("Empty Result")))
            }
        }
    }
}

// MARK: - Chromium Adapter

class ChromiumAdapter: BrowserAdapter {
    let supportedBundleIDs = ["com.google.Chrome", "com.microsoft.edgemac", "com.brave.Browser"]

    func fetchActiveTabInfo(appName: String) async -> Result<TabContext, BrowserFetchError> {
        let script = """
        function run(argv) {
            try {
                var browser = Application("\(appName)");
                if (browser.windows.length === 0) return "ERROR:NO_WINDOW";
                var tab = browser.windows[0].activeTab();
                return JSON.stringify({ "id": tab.id().toString(), "url": tab.url() });
            } catch(e) {
                if (e.message.includes("Not authorized")) return "ERROR:PERMISSION";
                return "ERROR:" + e.message;
            }
        }
        """
        
        let result = await executeJXAWithTimeout(script: script)
        
        switch result {
        case .success(let jsonString):
            guard let data = jsonString.data(using: .utf8),
                  let context = try? JSONDecoder().decode(TabContext.self, from: data) else {
                return .failure(.decodingFailed)
            }
            return .success(context)
        case .failure(let err):
            return .failure(err)
        }
    }
}

// MARK: - Safari Adapter

class SafariAdapter: BrowserAdapter {
    let supportedBundleIDs = ["com.apple.Safari"]

    func fetchActiveTabInfo(appName: String) async -> Result<TabContext, BrowserFetchError> {
        let script = """
        function run(argv) {
            try {
                var browser = Application("Safari");
                if (browser.windows.length === 0) return "ERROR:NO_WINDOW";
                var tab = browser.windows[0].currentTab();
                return JSON.stringify({ "id": null, "url": tab.url() });
            } catch(e) {
                if (e.message.includes("Not authorized")) return "ERROR:PERMISSION";
                return "ERROR:" + e.message;
            }
        }
        """
        
        let result = await executeJXAWithTimeout(script: script)
        
        switch result {
        case .success(let jsonString):
            guard let data = jsonString.data(using: .utf8),
                  let context = try? JSONDecoder().decode(TabContext.self, from: data) else {
                return .failure(.decodingFailed)
            }
            return .success(context)
        case .failure(let err):
            return .failure(err)
        }
    }
}

// MARK: - Core Manager

@MainActor
class BrowserTabManager {
    static let shared = BrowserTabManager()

    private var adapters: [String: BrowserAdapter] = [:]

    // 탭 메모리 관련 변수들
    private var tabMemory: [String: String] = [:]
    private var lastEvaluatedHostForTab: [String: String] = [:]

    // LRU 캐시용 변수
    private var tabAccessTicks: [String: Int] = [:]
    private var currentTick: Int = 0
    private let maxTabMemoryLimit = 100

    var currentKey: String? = nil

    // 🌟 연타 방지를 위한 Task 디바운서
    private var fetchTask: Task<Void, Never>?

    private init() {
        let chromium = ChromiumAdapter()
        for id in chromium.supportedBundleIDs { adapters[id] = chromium }

        let safari = SafariAdapter()
        for id in safari.supportedBundleIDs { adapters[id] = safari }
    }

    func clearMemory() {
        tabMemory.removeAll()
        lastEvaluatedHostForTab.removeAll()
        tabAccessTicks.removeAll()
        currentTick = 0
        currentKey = nil
    }

    func handleBrowserTabChanged(bundleID: String, appName: String) {
        guard SettingsManager.shared.snapshot.isBrowserTabMemoryEnabled || SettingsManager.shared.snapshot.isBrowserDomainModeEnabled else { return }
        guard let adapter = adapters[bundleID] else { return }

        saveCurrentContext()

        // 🌟 이전 요청 즉시 취소 (광클 시 Race Condition 완벽 차단)
        fetchTask?.cancel()

        fetchTask = Task {
            // 150ms 대기 (디바운스 타임)
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }

            let result = await adapter.fetchActiveTabInfo(appName: appName)

            // 대기하는 동안 또 다른 탭을 눌렀다면 무시
            guard !Task.isCancelled else { return }

            switch result {
            case .success(let context):
                self.processTabContext(context, bundleID: bundleID)
            case .failure(let error):
                self.handleFetchFailure(error: error, appName: appName)
            }
        }
    }

    private func processTabContext(_ context: TabContext, bundleID: String) {
        guard let newKey = generateTabKey(from: context, bundleID: bundleID) else { return }

        // 🌟 탭 접근 시간 갱신 (LRU)
        self.touchTabMemory(key: newKey)
        
        let isTabSwitched = (self.currentKey != newKey)

        if SettingsManager.shared.snapshot.isBrowserDomainModeEnabled, let urlString = context.url, let host = context.host {
            let lastHost = self.lastEvaluatedHostForTab[newKey]

            if lastHost != host || isTabSwitched {
                self.lastEvaluatedHostForTab[newKey] = host

                if let matchedRule = DomainRuleManager.shared.findMatchingRule(for: urlString, browserBundleID: bundleID) {
                    let hasManualMemory = (self.tabMemory[newKey] != nil)
                    if isTabSwitched && SettingsManager.shared.snapshot.isBrowserTabMemoryEnabled && hasManualMemory {
                        // 수동 탭 메모리에 양보
                    } else {
                        // 도메인 규칙 적용!
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
            let defaultLang = SettingsManager.shared.snapshot.newTabDefaultLanguage
            if defaultLang != "None" && !defaultLang.isEmpty {
                InputSourceManager.shared.switchLanguage(to: defaultLang)
                self.currentKey = newKey
                self.tabMemory[newKey] = defaultLang
                return
            }
        }

        self.currentKey = newKey
        if SettingsManager.shared.snapshot.isBrowserTabMemoryEnabled {
            self.restoreContext(for: newKey)
        }
    }

    // 🌟 JXA 통신 실패 시 ActionLog에 세밀하게 기록 (텔레메트리)
    private func handleFetchFailure(error: BrowserFetchError, appName: String) {
        let failureReason: FailureReason
        let logMessage: String

        switch error {
        case .timeout:
            failureReason = .unknown
            logMessage = "JXA Timeout (1.0s exceeded)"
        case .permissionDenied:
            failureReason = .permissionIssue
            logMessage = "Automation Permission Denied"
        case .noWindow:
            failureReason = .conditionMismatch
            logMessage = "No Active Windows Found"
        case .unsupportedBrowser:
            failureReason = .conditionMismatch
            logMessage = "Unsupported Browser Structure"
        case .executionFailed(let msg):
            failureReason = .unknown
            logMessage = "JXA Error: \(msg)"
        case .decodingFailed:
            failureReason = .unknown
            logMessage = "JSON Decoding Failed"
        }
     
        let log = ActionLog(
            timestamp: Date(),
            targetApp: appName,
            appliedRule: "Tab Memory Fallback",
            finalInputSource: logMessage,
            result: .failure,
            failureReason: failureReason
        )
        SettingsManager.shared.addLog(log)

        #if DEBUG
        print("Tab Memory Failed (\(logMessage)). Fallback to Window Memory for \(appName).")
        #endif
    }

    // MARK: - LRU Cache Management
    
    private func touchTabMemory(key: String) {
        if currentTick == Int.max { rebuildTicksFromScratch() }
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

    private func rebuildTicksFromScratch() {
        let sortedKeys = tabAccessTicks.sorted { $0.value < $1.value }.map { $0.key }
        tabAccessTicks.removeAll(keepingCapacity: true)
        for (index, key) in sortedKeys.enumerated() { tabAccessTicks[key] = index + 1 }
        currentTick = sortedKeys.count
    }

    private func isNewTab(context: TabContext) -> Bool {
        guard let url = context.url?.lowercased() else { return true }
        let newTabPatterns = ["chrome://newtab", "edge://newtab", "brave://newtab", "about:blank", "favorites://", "topsites://", "safari-resource://"]
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
