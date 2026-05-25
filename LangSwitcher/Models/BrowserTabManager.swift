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

// MARK: - JXA 아웃프로세스 제어 커널

func executeJXAWithTimeout(script: String, timeoutSeconds: Double = 1.5) async throws -> String? {
    return try await withThrowingTaskGroup(of: String?.self) { group in
        let process = Process()
        process.launchPath = "/usr/bin/osascript"
        process.arguments = ["-l", "JavaScript", "-e", script]

        let pipe = Pipe()
        process.standardOutput = pipe
        let errorPipe = Pipe()
        process.standardError = errorPipe

        group.addTask {
            return try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { [weak process] p in
                    defer {
                        try? pipe.fileHandleForReading.close()
                        try? pipe.fileHandleForWriting.close()
                        try? errorPipe.fileHandleForReading.close()
                        try? errorPipe.fileHandleForWriting.close()
                        process?.terminationHandler = nil
                    }

                    if p.terminationStatus == 0 {
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                        continuation.resume(returning: output)
                    } else {
                        continuation.resume(throwing: JXAError.scriptFailed("Process terminated or failed"))
                    }
                }

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: JXAError.scriptFailed(error.localizedDescription))
                }
            }
        }

        group.addTask { () -> String? in
            try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
            throw JXAError.timeout
        }

        do {
            let firstResult = try await group.next()
            group.cancelAll()
            return firstResult ?? nil
        } catch {
            group.cancelAll()
            if process.isRunning {
                process.terminate()
            }
            throw error
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

    // 🌟 1. 스로틀링/디바운싱 시스템이 탑재된 이벤트 제어 스코프 수복 완료
    func handleBrowserTabChanged(bundleID: String, appName: String) {
        guard SettingsManager.shared.snapshot.isBrowserTabMemoryEnabled || SettingsManager.shared.snapshot.isBrowserDomainModeEnabled else { return }
        guard let adapter = adapters[bundleID] else { return }

        // 현재 탭의 언어 상태 백업 집행
        saveCurrentContext()
        
        // 유저가 탭을 빠르게 전환 중이라면 이전 예약된 JXA 아웃프로세스 실행 계획을 즉시 무조건 사살(Cancel)합니다.
        fetchTask?.cancel()

        // 새로운 150ms 보호망 타스크 개설
        fetchTask = Task(priority: .userInitiated) { [weak self] in
            // 150ms 동안 대기하며 연속적인 전환 입력 충격을 모두 흡수합니다.
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }

            // 폭풍이 지나간 후 최종 안착한 단 하나의 탭에 대해서만 무거운 프로세스 포크 실행
            let result = await adapter.fetchActiveTabInfo(appName: appName)
            guard !Task.isCancelled else { return }

            // 🌟 [최적화] Task 자체가 메인 액터 격리 구역에서 생성되었으므로,
            // 불필요한 MainActor.run 래퍼를 전면 제거하고 직통으로 연산 효율을 높입니다.
            guard let self = self else { return }
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
                        InputSourceManager.shared.switchLanguage(to: matchedRule.targetInputSourceID)

                        let trace = TraceFactory.create(
                            event: .languageSwitch, result: .switched,
                            reason: .domainRule(domain: host), appName: bundleID, domain: host
                        )
                        DecisionTraceManager.shared.record(trace)
                        
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

                let trace = TraceFactory.create(
                    event: .languageSwitch, result: .switched,
                    reason: .browserTabRestore, appName: bundleID
                )
                DecisionTraceManager.shared.record(trace)
                
                self.currentKey = newKey
                self.tabMemory[newKey] = defaultLang
                return
            }
        }

        self.currentKey = newKey

        if SettingsManager.shared.snapshot.isBrowserTabMemoryEnabled {
            self.restoreContext(for: newKey, bundleID: bundleID)
        }
    }

    private func restoreContext(for key: String, bundleID: String) {
        if let savedSourceID = tabMemory[key] {
            InputSourceManager.shared.switchLanguage(to: savedSourceID)

            let trace = TraceFactory.create(
                event: .restore, result: .restored,
                reason: .browserTabRestore, appName: bundleID
            )
            DecisionTraceManager.shared.record(trace)
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
    }

    // MARK: - LRU Cache Management (분할상환 O(1) 고성능 튜닝 완료)

    private func touchTabMemory(key: String) {
        currentTick += 1
        if currentTick >= 1_000_000 { rebuildTicksFromScratch(); return }

        // 🌟 [핵심 최적화] 해당 키가 맵에 아예 없던 '새로운 키'인지 사전에 판별합니다.
        let isNewKey = (tabAccessTicks[key] == nil)
        tabAccessTicks[key] = currentTick

        // 🌟 오직 '새로운 탭'이 진입하여 캐시 최대 한도를 정말로 넘어섰을 때만 min(by:) 스캔을 격리 실행합니다.
        // 유저가 기존에 열어둔 탭들을 순회할 때는 이 블록을 완벽하게 건너뛰어 대규모 CPU 연산 낭비를 0%로 통제합니다.
        if isNewKey && tabAccessTicks.count > maxTabMemoryLimit {
            if let (oldestKey, _) = tabAccessTicks.min(by: { $0.value < $1.value }) {
                tabMemory.removeValue(forKey: oldestKey)
                lastEvaluatedHostForTab.removeValue(forKey: oldestKey)
                tabAccessTicks.removeValue(forKey: oldestKey)
            }
        }
    }

    private func rebuildTicksFromScratch() {
        currentTick = 0
        tabMemory.removeAll()
        tabAccessTicks.removeAll()
        lastEvaluatedHostForTab.removeAll()
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
