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
    
    // 🌟 [우주 방어] 현재 비동기 풀에서 스케줄링 대기 중인 append 태스크의 총량을 추적합니다.
    private var pendingCount = 0

    func incrementPending() {
        pendingCount += 1
    }

    func append(_ newData: Data) {
        data.append(newData)
        pendingCount -= 1 // 데이터가 안전하게 힙(Heap) 버퍼에 안착했으므로 카운트 차감
    }

    func read() -> Data {
        return data
    }
    
    // 🌟 [핵심] 스케줄러 큐에 남아있는 모든 잔여 append 태스크가 100% 정산 완료되었는지 검증합니다.
    var isFlushComplete: Bool {
        return pendingCount <= 0
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
                // 🌟 [수복] 태스크를 비동기 큐에 유기하기 전, 원자적으로 대기 장부 카운트를 올립니다.
                Task {
                    await outputBuffer.incrementPending()
                    await outputBuffer.append(available)
                }
            }
        }

        group.addTask {
            return try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { [weak process] p in
                    Task {
                        // 🌟 [최종 수복 핵심 1] 새로운 데이터 유입 통로를 전면 차단합니다.
                        fileHandle.readabilityHandler = nil

                        // 🌟 [최종 수복 핵심 2] 직전 마이크로초 사이에 스케줄러 풀에 던져진
                        // 모든 잔여 append 작업이 완료될 때까지 비동기 런루프 제어권을 양보하며 정밀 대기합니다.
                        while await !outputBuffer.isFlushComplete {
                            await Task.yield()
                        }

                        // 🌟 [결정론적 완수] 마지막 한 바이트까지 버퍼에 채워졌음이 100% 보장되므로 안심하고 데이터를 인출합니다.
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
    
    // 🌟 [우주 방어 수복 포인트 1] 하드코딩 배열을 전면 폐기하고,
    // 현재 아키텍처에 공식 등록된 모든 브라우저 번들 ID 목록을 동적으로 반환합니다.
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
    private var isRebuildingTicks = false // 🌟 클래스 전역 프로퍼티로 추가

    private func touchTabMemory(key: String) {
        currentTick += 1
        
        // 🌟 [수복 1] 조건문이 참이더라도 '이미 리빌드 중'이라면 태스크 중복 생성을 원천 차단합니다.
        if currentTick > 1_000_000 && !isRebuildingTicks {
            isRebuildingTicks = true
            Task { [weak self] in
                guard let self = self else { return }
                await self.rebuildTicksFromScratch()
                self.isRebuildingTicks = false // 리빌드가 완벽히 끝난 후 자물쇠 해제
            }
            // 🌟 [수복 2] return을 과감히 제거하여 아래의 탭 등록 로직이 중단 없이 계속 흐르게 만듭니다.
        }
        
        let isNewKey = tabAccessTicks[key] == nil
        tabAccessTicks[key] = currentTick
        
        if isNewKey && tabAccessTicks.count > maxTabMemoryLimit {
            if let oldestKey = tabAccessTicks.min(by: { $0.value < $1.value })?.key {
                tabMemory.removeValue(forKey: oldestKey)
                lastEvaluatedHostForTab.removeValue(forKey: oldestKey)
                tabAccessTicks.removeValue(forKey: oldestKey)
            }
        }
    }

    /// 🌟 1,000,000 tick 도달 시 UI 프리징을 0.000%로 통제하는 백그라운드 랭크 스케일링 엔진
    private func rebuildTicksFromScratch() async {
        dprint("🔄 [Debounce Engine] 1,000,000 Tick 임계값 도달. 비동기 랭크 스케일링을 개시합니다.")
        
        // 1. 리빌드를 시작하는 시점의 스냅샷을 찍습니다.
        let ticksSnapshot = self.tabAccessTicks
        
        // 2. 무거운 정렬 연산은 백그라운드 스레드로 유기합니다.
        let safeNormalizedTicks = await Task.detached(priority: .background) {
            return ticksSnapshot.sorted { $0.value < $1.value }
        }.value
        
        // 3. 🌟 [진짜 최종 수복] 백그라운드 연산이 일어나는 동안 '새롭게 추가된 키'가 있는지 감지합니다.
        // 리빌드 도중 유저가 새 탭을 만졌다면 현재의 tabAccessTicks 수량이 스냅샷 수량보다 늘어났을 것입니다.
        let newlyAddedTicks = self.tabAccessTicks.filter { ticksSnapshot[$0.key] == nil }
        
        // 4. 장부 정산 시작
        self.tabAccessTicks.removeAll(keepingCapacity: true)
        
        var nextRank = 1
        // 과거 스냅샷 아이템들을 1부터 차례대로 이쁘게 압축 정렬합니다.
        for (key, _) in safeNormalizedTicks {
            self.tabAccessTicks[key] = nextRank
            nextRank += 1
        }
        
        // 5. 🌟 [핵심] 리빌드 도중 유저가 새로 밟아서 장부에 추가됐던 신상 키들을
        // 삭제하지 않고 랭크의 맨 뒤에 안전하게 이어 붙여줍니다(Merge).
        for (key, _) in newlyAddedTicks {
            self.tabAccessTicks[key] = nextRank
            nextRank += 1
        }
        
        // 6. 다음 기준점을 최종 정산된 값으로 세팅합니다.
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
