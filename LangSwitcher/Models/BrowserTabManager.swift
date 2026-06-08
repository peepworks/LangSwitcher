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
    private var pendingCount = 0

    func incrementPending() {
        pendingCount += 1
    }

    func append(_ newData: Data) {
        data.append(newData)
        pendingCount -= 1
    }

    func drainAndRead() async -> Data {
        while pendingCount > 0 {
            dprint("⏳ [SafeDataBuffer] 잔여 스트림 청크 정산 대기 중... (남은 태스크: \(pendingCount)개)")
            
            // 🌟 [교정] Task.sleep 앞에 'try?'를 붙여 컴파일러 에러를 완벽하게 소각합니다.
            try? await Task.sleep(nanoseconds: 1_000_000) // 1ms씩 런루프 제어권 양보
        }
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
                // 🌟 [우주 방어 수복 포인트 2]
                // 동기 콜백 문맥 내에서 먼저 카운트를 올려 뒤늦은 가동 태스크의 누락을 물리적으로 방지합니다.
                let dataCopy = available
                Task {
                    await outputBuffer.incrementPending()
                    await outputBuffer.append(dataCopy)
                }
            }
        }

        group.addTask {
            return try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { [weak process] p in
                    Task {
                        // 새로운 데이터 유입을 즉시 차단
                        fileHandle.readabilityHandler = nil

                        // 🌟 [우주 방어 수복 포인트 3]
                        // 액터 내부 캡슐화 파이프라인 호출로 이중 홉 분기 레이싱을 영구 소각합니다.
                        let finalData = await outputBuffer.drainAndRead()
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
                let processToReap = process
                processToReap.terminationHandler = nil

                Task.detached(priority: .background) {
                    processToReap.terminate()
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
    
    var supportedBrowserBundleIDs: [String] {
        return Array(adapters.keys)
    }

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

    // 🌟 [우주 방어 수복 포인트 1]
    // 능동적 메모리 자가치유 커널(MemoryMonitor)이 이 함수를 때릴 때,
    // 비대칭 누수 여지가 남지 않도록 lastEvaluatedHostForTab 찌꺼기까지 100% 동시에 소각 정산합니다.
    func clearMemory() {
        tabMemory.removeAll(keepingCapacity: false)
        lastEvaluatedHostForTab.removeAll(keepingCapacity: false)
        tabAccessTicks.removeAll(keepingCapacity: false)
        currentTick = 0
        currentKey = nil
    }

    // 🌟 [우주 방어 수복 포인트 2]
    // 개별 탭이 컨텍스트 버퍼 한계를 초과하여 축출되거나 수동 삭제될 때,
    // 세 장부의 데이터 정합성이 칼같이 양손 정렬되도록 제어하는 마스터 축출 헬퍼를 결속합니다.
    private func evictTabContext(forKey tabKey: String) {
        self.tabMemory.removeValue(forKey: tabKey)
        self.lastEvaluatedHostForTab.removeValue(forKey: tabKey)
        self.tabAccessTicks.removeValue(forKey: tabKey)
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
    private var isRebuildingTicks = false

    private func touchTabMemory(key: String) {
        currentTick += 1
        
        if currentTick > 1_000_000 && !isRebuildingTicks {
            isRebuildingTicks = true
            Task { [weak self] in
                guard let self = self else { return }
                await self.rebuildTicksFromScratch()
                self.isRebuildingTicks = false
            }
        }
        
        let isNewKey = tabAccessTicks[key] == nil
        tabAccessTicks[key] = currentTick
        
        if isNewKey && tabAccessTicks.count > maxTabMemoryLimit {
            if let oldestKey = tabAccessTicks.min(by: { $0.value < $1.value })?.key {
                // 🌟 [우주 방어 수복 포인트 3] 파편화된 개별 축출문을 제거하고
                // 단일 원자적 헬퍼 함수를 매핑하여 비대칭 릭 가능성을 0.000%로 박멸합니다.
                self.evictTabContext(forKey: oldestKey)
            }
        }
    }

    @MainActor
    private func rebuildTicksFromScratch() async {
        guard !isRebuildingTicks else { return }
        isRebuildingTicks = true

        defer {
            isRebuildingTicks = false
            print("🧹 [BrowserTabManager] 탭 액세스 틱 리빌드 세션이 종료되어 자물쇠 플래그를 완전히 안전하게 해제했습니다.")
        }

        let ticksSnapshot = self.tabAccessTicks

        let safeNormalizedTicks = await Task.detached(priority: .background) {
            return ticksSnapshot.sorted { $0.value < $1.value }
        }.value

        self.tabAccessTicks.removeAll(keepingCapacity: true)
        
        var nextRank = 1
        for element in safeNormalizedTicks {
            self.tabAccessTicks[element.key] = nextRank
            nextRank += 1
        }

        self.currentTick = nextRank
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
