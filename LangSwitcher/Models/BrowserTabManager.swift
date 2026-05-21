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

enum BrowserFetchError: Error {
    case timeout
    case permissionDenied
    case noWindow
    case unsupportedBrowser
    case executionFailed(String)
    case decodingFailed
}

enum JXAError: Error {
    case timeout
    case scriptFailed(String)
}

// MARK: - Adapter Protocol

protocol BrowserAdapter: Sendable {
    var supportedBundleIDs: [String] { get }
    func fetchActiveTabInfo(appName: String) async -> Result<TabContext, BrowserFetchError>
}

// MARK: - JXA Execution Engine

private let jxaExecutionQueue = DispatchQueue(label: "com.peepboy.LangSwitcher.JXAQueue", qos: .userInitiated)

actor JXARaceManager {
    private var isCompleted = false
    func complete() -> Bool {
        if isCompleted { return false }
        isCompleted = true
        return true
    }
}

// 🌟 [핵심 개선] TaskGroup과 ThrowingContinuation을 결합한 완벽한 안전 구조
func executeJXAWithTimeout(script: String, timeoutSeconds: Double = 1.5) async throws -> String? {
    
    // 두 개의 작업을 동시에 실행하고, 먼저 완료된 결과를 반환하는 그룹
    return try await withThrowingTaskGroup(of: String?.self) { group in
        
        // 작업 1: 실제 JXA 스크립트 실행
        group.addTask {
            return try await withCheckedThrowingContinuation { continuation in
                // 백그라운드 큐로 보내어 메인 스레드나 액터가 멈추는 것을 방지
                DispatchQueue.global(qos: .userInitiated).async {
                    guard let jsLanguage = OSALanguage(forName: "JavaScript") else {
                        // 🚨 실패 경로 1: 엔진 초기화 실패 시 반드시 resume(throwing:) 호출
                        continuation.resume(throwing: JXAError.scriptFailed("JS 엔진 초기화 실패"))
                        return
                    }
                    
                    let osaScript = OSAScript(source: script, language: jsLanguage)
                    var errorInfo: NSDictionary?
                    
                    // JXA 실행 (동기 블로킹 발생 가능 구간)
                    let result = osaScript.executeAndReturnError(&errorInfo)
                    
                    if let errorInfo = errorInfo {
                        // 🚨 실패 경로 2: 스크립트 실행 중 에러 발생 시 반드시 resume(throwing:) 호출
                        let errorMsg = errorInfo[OSAScriptErrorMessageKey] as? String ?? "알 수 없는 JXA 에러"
                        continuation.resume(throwing: JXAError.scriptFailed(errorMsg))
                    } else {
                        // ✅ 성공 경로: 정상적으로 완료 시 resume(returning:) 호출
                        continuation.resume(returning: result?.stringValue)
                    }
                }
            }
        }
        
        // 작업 2: 타임아웃 타이머
        group.addTask {
            // 지정된 시간만큼 대기
            try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
            // 시간이 다 지나면 무자비하게 타임아웃 에러를 던짐
            throw JXAError.timeout
        }
        
        // 🌟 둘 중 먼저 완료되는 작업의 결과를 가져옴 (스크립트 완료 vs 타임아웃)
        guard let firstResult = try await group.next() else {
            throw JXAError.scriptFailed("실행 결과를 가져오지 못했습니다.")
        }
        
        // 승자가 결정되었으니 남아있는 패자(느려진 스크립트 or 아직 안 끝난 타이머)는 즉시 취소시킴
        group.cancelAll()
        
        return firstResult
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
        
        do {
            guard let jsonString = try await executeJXAWithTimeout(script: script) else {
                return .failure(.executionFailed("No result from JXA"))
            }
            
            if jsonString.hasPrefix("ERROR:") {
                if jsonString.contains("NO_WINDOW") { return .failure(.noWindow) }
                if jsonString.contains("PERMISSION") { return .failure(.permissionDenied) }
                return .failure(.executionFailed(jsonString))
            }
            
            guard let data = jsonString.data(using: .utf8),
                  let context = try? JSONDecoder().decode(TabContext.self, from: data) else {
                return .failure(.decodingFailed)
            }
            return .success(context)
            
        } catch JXAError.timeout {
            return .failure(.timeout)
        } catch JXAError.scriptFailed(let errorMessage) {
            return .failure(.executionFailed(errorMessage))
        } catch {
            return .failure(.executionFailed(error.localizedDescription))
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
        
        do {
            guard let jsonString = try await executeJXAWithTimeout(script: script) else {
                return .failure(.executionFailed("No result from JXA"))
            }
            
            if jsonString.hasPrefix("ERROR:") {
                if jsonString.contains("NO_WINDOW") { return .failure(.noWindow) }
                if jsonString.contains("PERMISSION") { return .failure(.permissionDenied) }
                return .failure(.executionFailed(jsonString))
            }
            
            guard let data = jsonString.data(using: .utf8),
                  let context = try? JSONDecoder().decode(TabContext.self, from: data) else {
                return .failure(.decodingFailed)
            }
            return .success(context)
            
        } catch JXAError.timeout {
            return .failure(.timeout)
        } catch JXAError.scriptFailed(let errorMessage) {
            return .failure(.executionFailed(errorMessage))
        } catch {
            return .failure(.executionFailed(error.localizedDescription))
        }
    }
}

// MARK: - Core Manager

@MainActor
class BrowserTabManager {
    static let shared = BrowserTabManager()

    private var adapters: [String: BrowserAdapter] = [:]

    private var tabMemory: [String: String] = [:]
    private var lastEvaluatedHostForTab: [String: String] = [:]
    private var tabAccessTicks: [String: Int] = [:]
    private var currentTick: Int = 0
    private let maxTabMemoryLimit = 100

    var currentKey: String? = nil
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
        fetchTask?.cancel()

        fetchTask = Task(priority: .userInitiated) { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }

            let result = await adapter.fetchActiveTabInfo(appName: appName)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self = self else { return }
                switch result {
                case .success(let context):
                    self.processTabContext(context, bundleID: bundleID)
                case .failure(let error):
                    self.handleFetchFailure(error: error, appName: appName)
                }
            }
        }
    }

    private func processTabContext(_ context: TabContext, bundleID: String) {
        guard let newKey = generateTabKey(from: context, bundleID: bundleID) else { return }

        self.touchTabMemory(key: newKey)
        let isTabSwitched = (self.currentKey != newKey)

        // 1. 도메인 규칙
        if SettingsManager.shared.snapshot.isBrowserDomainModeEnabled, let urlString = context.url, let host = context.host {
            let lastHost = self.lastEvaluatedHostForTab[newKey]

            if lastHost != host || isTabSwitched {
                self.lastEvaluatedHostForTab[newKey] = host

                if let matchedRule = DomainRuleManager.shared.findMatchingRule(for: urlString, browserBundleID: bundleID) {
                    let hasManualMemory = (self.tabMemory[newKey] != nil)
                    if isTabSwitched && SettingsManager.shared.snapshot.isBrowserTabMemoryEnabled && hasManualMemory {
                        // 수동 탭 메모리에 양보
                    } else {
                        Task { @MainActor in
                            InputSourceManager.shared.switchLanguage(to: matchedRule.targetInputSourceID)
                            
                            let trace = TraceFactory.create(
                                event: .languageSwitch, result: .switched,
                                reason: .domainRule(domain: host), appName: bundleID, domain: host
                            )
                            DecisionTraceManager.shared.record(trace)
                        }
                        self.currentKey = newKey
                        self.tabMemory[newKey] = matchedRule.targetInputSourceID
                        return
                    }
                }
            }
        }

        if !isTabSwitched { return }

        // 2. 새 탭 규칙
        if self.isNewTab(context: context) {
            let defaultLang = SettingsManager.shared.snapshot.newTabDefaultLanguage
            if defaultLang != "None" && !defaultLang.isEmpty {
                Task { @MainActor in
                    InputSourceManager.shared.switchLanguage(to: defaultLang)
                    
                    let trace = TraceFactory.create(
                        event: .languageSwitch, result: .switched,
                        reason: .browserTabRestore, appName: bundleID
                    )
                    DecisionTraceManager.shared.record(trace)
                }
                self.currentKey = newKey
                self.tabMemory[newKey] = defaultLang
                return
            }
        }

        self.currentKey = newKey
        
        // 3. 탭 메모리 복구
        if SettingsManager.shared.snapshot.isBrowserTabMemoryEnabled {
            self.restoreContext(for: newKey, bundleID: bundleID)
        }
    }

    private func restoreContext(for key: String, bundleID: String) {
        if let savedSourceID = tabMemory[key] {
            Task { @MainActor in
                InputSourceManager.shared.switchLanguage(to: savedSourceID)
                
                let trace = TraceFactory.create(
                    event: .restore, result: .restored,
                    reason: .browserTabRestore, appName: bundleID
                )
                DecisionTraceManager.shared.record(trace)
            }
        }
    }

    private func handleFetchFailure(error: BrowserFetchError, appName: String) {
        let failureReason: FailureReason
        let logMessage: String

        switch error {
        case .timeout:
            failureReason = .unknown
            logMessage = "JXA Timeout (1.5s exceeded)"
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
            timestamp: Date(), targetApp: appName, appliedRule: "Tab Memory Fallback",
            finalInputSource: logMessage, result: .failure, failureReason: failureReason
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

    private func generateTabKey(from context: TabContext, bundleID: String) -> String? {
        if let id = context.id { return "\(bundleID)_tab_\(id)" }
        if let url = context.url { return "\(bundleID)_url_\(url)" }
        return nil
    }
}
