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

import Foundation
import AppKit
import Combine

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

// MARK: - JXA 아웃프로세스 제어 커널 (Swift 6 넌아이솔레이티드 완전 수복 사양)

// 🌟 [수복 완료] 글로벌 스코프 독립으로 @MainActor 괄호 가두리 완벽 탈출
private final class SafeDataBuffer: @unchecked Sendable {
    // nonisolated(unsafe) — NSLock이 스레드 안전을 보장하므로 컴파일러 격리 추론 완전 차단
    nonisolated(unsafe) private var _data = Data()
    private let lock = NSLock()
    
    nonisolated func append(_ newData: Data) {
        lock.withLock { _data.append(newData) }
    }
    
    nonisolated func read() -> Data {
        lock.withLock { _data }
    }
}

func executeJXAWithTimeout(script: String, timeoutSeconds: Double = 1.5) async throws -> String? {
    return try await withThrowingTaskGroup(of: String?.self) { group in
        let process = Process()
        process.launchPath = "/usr/bin/osascript"
        process.arguments = ["-l", "JavaScript", "-e", script]

        let pipe = Pipe()
        process.standardOutput = pipe
        let errorPipe = Pipe()
        process.standardError = errorPipe

        // 완전히 해방된 비격리 상자 객체 인스턴스 확보
        let outputBuffer = SafeDataBuffer()
        let fileHandle = pipe.fileHandleForReading

        // 백그라운드 시스템 커널 I/O 큐에서 메인 스레드 간섭 없이 원자적으로 고속 적재 실행 (리뷰어 지적 완벽 종결)
        fileHandle.readabilityHandler = { handle in
            let available = handle.availableData
            if !available.isEmpty {
                outputBuffer.append(available)
            }
        }

        group.addTask {
            return try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { [weak process] p in
                    defer {
                        fileHandle.readabilityHandler = nil
                        try? pipe.fileHandleForReading.close()
                        try? pipe.fileHandleForWriting.close()
                        try? errorPipe.fileHandleForReading.close()
                        try? errorPipe.fileHandleForWriting.close()
                        process?.terminationHandler = nil
                    }
                    
                    // 레이스 컨디션 방어: 핸들러 nil 처리 후 잔여 데이터 드레이닝
                    let remaining = fileHandle.availableData
                    if !remaining.isEmpty { outputBuffer.append(remaining) }

                    if p.terminationStatus == 0 {
                        let finalData = outputBuffer.read()
                        let output = String(data: finalData, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        continuation.resume(returning: output)
                    } else {
                        continuation.resume(throwing: JXAError.scriptFailed("Process terminated with code \(p.terminationStatus)"))
                    }
                }

                do {
                    try process.run()
                } catch {
                    fileHandle.readabilityHandler = nil
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
            pipe.fileHandleForReading.readabilityHandler = nil
            return firstResult ?? nil
        } catch {
            group.cancelAll()
            pipe.fileHandleForReading.readabilityHandler = nil
            if process.isRunning {
                process.terminate()
            }
            throw error
        }
    }
}


// MARK: - Chromium Adapter

// 🌟 [동시성 수복] @MainActor를 명시하여 상위 매니저와 격리 계보를 일치시키고 Sendable 제약을 패스합니다.
@MainActor
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

// 🌟 [동시성 수복] 격리 명세 일치화 적용
@MainActor
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
class BrowserTabManager: ObservableObject {
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
            do {
                // 🌟 [리뷰 반영 수복] 순정 try await 구조 및 명시적 취소 체크 확립
                try await Task.sleep(nanoseconds: 150_000_000)
                try Task.checkCancellation()

                let result = await adapter.fetchActiveTabInfo(appName: appName)
                
                guard let self = self, !Task.isCancelled else { return }
                
                switch result {
                case .success(let context):
                    self.processTabContext(context, bundleID: bundleID)
                case .failure(let error):
                    self.handleFetchFailure(error: error, appName: appName)
                }
                
            } catch {
                #if DEBUG
                dprint("🧹 [BrowserTabManager] 디바운스 대기 중 태스크가 정석적으로 취소되어 안전하게 퇴출되었습니다.")
                #endif
                return
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

        let isNewKey = (tabAccessTicks[key] == nil)
        tabAccessTicks[key] = currentTick

        if isNewKey && tabAccessTicks.count > maxTabMemoryLimit {
            if let (oldestKey, _) = tabAccessTicks.min(by: { $0.value < $1.value }) {
                tabMemory.removeValue(forKey: oldestKey)
                lastEvaluatedHostForTab.removeValue(forKey: oldestKey)
                tabAccessTicks.removeValue(forKey: oldestKey)
            }
        }
    }

    /// 1,000,000 tick 도달 시 유저 데이터 파괴 없이 오직 '순서 가중치'만 1부터 재정렬하는 고성능 정규화 엔진
    private func rebuildTicksFromScratch() {
        #if DEBUG
        dprint("🔄 [Debounce Engine] 1,000,000 Tick 임계값 도달. 데이터 보존형 랭크 스케일링을 개시합니다.")
        #endif
        
        // 🌟 [문구 수복] 상대적 대소 관계 보존을 위한 순정 인덱싱 정렬 구동 문맥 일치화
        let normalizedTicks = tabAccessTicks.sorted { $0.value < $1.value }
        
        tabAccessTicks.removeAll(keepingCapacity: true)
        
        var nextRank = 1
        for (key, _) in normalizedTicks {
            tabAccessTicks[key] = nextRank
            nextRank += 1
        }
        
        currentTick = nextRank
        
        #if DEBUG
        dprint("✅ [Debounce Engine] 정규화 완료. 소중한 탭 메모리 자산이 완벽하게 보호되었습니다. (차기 시작 Tick: \(currentTick))")
        #endif
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
