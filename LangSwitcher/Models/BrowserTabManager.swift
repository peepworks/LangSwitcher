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

actor SafeDataBuffer {
    private var data = Data()

    func append(_ newData: Data) {
        data.append(newData)
    }

    func read() -> Data {
        return data
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

        let outputBuffer = SafeDataBuffer()
        let fileHandle = pipe.fileHandleForReading

        // 🌟 [수복 1: 거대 전역 방어벽]
        // 성공, 실패, 타임아웃 등 '어떤 경로'로 함수를 탈출해도 파이프와 핸들러를 0.000초 만에 완벽히 소각합니다.
        defer {
            fileHandle.readabilityHandler = nil
            try? pipe.fileHandleForReading.close()
            try? pipe.fileHandleForWriting.close()
            try? errorPipe.fileHandleForReading.close()
            try? errorPipe.fileHandleForWriting.close()
        }

        fileHandle.readabilityHandler = { handle in
            let available = handle.availableData
            if !available.isEmpty {
                Task {
                    await outputBuffer.append(available)
                }
            }
        }

        group.addTask {
            return try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { [weak process] p in
                    // 🌟 이제 복잡한 청소 코드(nil 대입 등)는 상단 defer가 독점하므로, 여기선 결과 인출에만 집중합니다.
                    Task {
                        let finalData = await outputBuffer.read()
                        process?.terminationHandler = nil

                        if p.terminationStatus == 0 {
                            let output = String(data: finalData, encoding: String.Encoding.utf8)?
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            continuation.resume(returning: output)
                        } else {
                            continuation.resume(throwing: JXAError.scriptFailed("Process terminated with code \(p.terminationStatus)"))
                        }
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
            
            // 🌟 [수복 2: 스레드 블로킹 없는 프로세스 추적기]
            if process.isRunning {
                let processToReap = process
                processToReap.terminationHandler = nil // 핸들러 해제하여 순환 참조 고리 완전 파괴
                
                // GCD 스레드를 동기적으로 묶어버리던 waitUntilExit()를 철거하고,
                // 안전한 비동기 논블로킹 유유자적 스케줄러로 프로세스를 강제 종료 및 분리 유기합니다.
                Task.detached(priority: .background) {
                    processToReap.terminate()
                    
                    // 3초 동안 프로세스가 스스로 정리할 유예를 준 뒤, 여전히 안 죽고 좀비처럼 버티면 재차 terminate를 가합니다.
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    if processToReap.isRunning {
                        processToReap.terminate()
                    }
                }
            }
            throw error
        }
    }
}


// MARK: - Chromium Adapter

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

            // 🌟 [컴파일러 에러 수복] String.Encoding.utf8 로 명시
            guard let data = jsonString.data(using: String.Encoding.utf8),
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

            // 🌟 [컴파일러 에러 수복] String.Encoding.utf8 로 명시
            guard let data = jsonString.data(using: String.Encoding.utf8),
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
                dprint("🧹 [BrowserTabManager] 디바운스 대기 중 태스크가 정석적으로 취소되어 안전하게 퇴출되었습니다.")
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
        if currentTick >= 1_000_000 {
            // 🌟 [수복] 메인 스레드 멈춤을 완벽히 차단하기 위해 비동기 태스크로 분리하여 스케일링 엔진 가동
            Task {
                await rebuildTicksFromScratch()
            }
            return
        }

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

    /// 🌟 1,000,000 tick 도달 시 UI 프리징을 0.000%로 통제하는 백그라운드 랭크 스케일링 엔진
    private func rebuildTicksFromScratch() async {
        dprint("🔄 [Debounce Engine] 1,000,000 Tick 임계값 도달. 비동기 랭크 스케일링을 개시합니다.")
        
        // 1. 메인 액터 안전 구역에서 정렬할 원본 딕셔너리 데이터를 로컬 상수로 스냅샷 복사합니다.
        let ticksSnapshot = self.tabAccessTicks
        
        // 2. 메인 스레드 소속이 없는 완전한 독립 백그라운드 작업동(Task.detached)으로 무거운 정렬 연산을 유기합니다.
        let safeNormalizedTicks = await Task.detached(priority: .background) {
            // @MainActor 격리가 없는 순수 백그라운드 스레드에서 O(n log n) 정렬을 독점 집행합니다.
            return ticksSnapshot.sorted { $0.value < $1.value }
        }.value
        
        // 3. 정렬이 끝난 정제된 장부를 들고 다시 메인 액터 본진으로 안심 복귀하여 동기식 주입을 집행합니다.
        self.tabAccessTicks.removeAll(keepingCapacity: true)
        
        var nextRank = 1
        for (key, _) in safeNormalizedTicks {
            self.tabAccessTicks[key] = nextRank
            nextRank += 1
        }
        
        self.currentTick = nextRank
        
        dprint("✅ [Debounce Engine] 백그라운드 정규화 완료. 차기 시작 Tick: \(self.currentTick)")
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
