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

// 🌟 커스텀 에러 정의 (파일 상단이나 클래스 내부에 선언)
enum JXAError: Error {
    case timeout
    case scriptFailed
}

// MARK: - Adapter Protocol

protocol BrowserAdapter: Sendable {
    var supportedBundleIDs: [String] { get }
    func fetchActiveTabInfo(appName: String) async -> Result<TabContext, BrowserFetchError>
}

// 🌟 [추가] JXA 실행이 절대 겹치지 않도록 교통정리를 해주는 전용 직렬(Serial) 큐
private let jxaExecutionQueue = DispatchQueue(label: "com.peepboy.LangSwitcher.JXAQueue", qos: .userInitiated)

// 🌟 [핵심 개선] TaskGroup을 이용한 완벽한 타임아웃 처리
func executeJXAWithTimeout(script: String, timeoutSeconds: Double = 3.0) async throws -> String? {
    
    // 두 개의 작업을 동시에 실행하고, 먼저 완료된 결과를 반환하는 그룹
    return try await withThrowingTaskGroup(of: String?.self) { group in
        
        // 작업 1: 실제 JXA 스크립트 실행
        group.addTask {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    var errorInfo: NSDictionary?
                    if let appleScript = NSAppleScript(source: script) {
                        let result = appleScript.executeAndReturnError(&errorInfo)
                        
                        // 에러가 발생했거나 스크립트가 실패해도 반드시 resume(throwing:)을 호출!
                        if errorInfo != nil {
                            continuation.resume(throwing: JXAError.scriptFailed)
                        } else {
                            continuation.resume(returning: result.stringValue)
                        }
                    } else {
                        continuation.resume(throwing: JXAError.scriptFailed)
                    }
                }
            }
        }
        
        // 작업 2: 타임아웃 타이머
        group.addTask {
            // 지정된 시간만큼 대기 (나노초 단위)
            try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
            // 시간이 다 지나면 무자비하게 타임아웃 에러를 던짐
            throw JXAError.timeout
        }
        
        // 🌟 둘 중 먼저 완료되는 작업의 결과를 가져옵니다!
        // 3초 안에 스크립트가 끝나면 결과를 받고, 3초가 넘으면 타이머가 에러를 던집니다.
        let result = try await group.next()!
        
        // 승자가 결정되었으니 남아있는 패자(느려진 스크립트 or 아직 안 끝난 타이머)는 즉시 취소시킵니다.
        group.cancelAll()
        
        return result
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
            // 🌟 1. try await로 호출합니다. (에러가 발생하면 catch 블록으로 던져집니다)
            guard let jsonString = try await executeJXAWithTimeout(script: script) else {
                return .failure(.executionFailed("No result from JXA"))
            }
            
            // 🌟 2. JXA 스크립트가 뱉어낸 문자열 에러를 정확하게 스위프트 에러로 변환 (텔레메트리 최적화)
            if jsonString.hasPrefix("ERROR:") {
                if jsonString.contains("NO_WINDOW") { return .failure(.noWindow) }
                if jsonString.contains("PERMISSION") { return .failure(.permissionDenied) }
                return .failure(.executionFailed(jsonString))
            }
            
            // 🌟 3. 정상적인 JSON 응답일 경우 파싱
            guard let data = jsonString.data(using: .utf8),
                  let context = try? JSONDecoder().decode(TabContext.self, from: data) else {
                return .failure(.decodingFailed)
            }
            return .success(context)
            
        } catch JXAError.timeout {
            // 🌟 타임아웃 에러를 감지하여 정확한 에러 타입으로 반환
            return .failure(.timeout)
        } catch {
            // 그 외의 스크립트 실패 등
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
            // 🌟 1. try await 적용
            guard let jsonString = try await executeJXAWithTimeout(script: script) else {
                return .failure(.executionFailed("No result from JXA"))
            }
            
            // 🌟 2. Safari JXA 문자열 에러 매핑
            if jsonString.hasPrefix("ERROR:") {
                if jsonString.contains("NO_WINDOW") { return .failure(.noWindow) }
                if jsonString.contains("PERMISSION") { return .failure(.permissionDenied) }
                return .failure(.executionFailed(jsonString))
            }
            
            // 🌟 3. 정상 파싱
            guard let data = jsonString.data(using: .utf8),
                  let context = try? JSONDecoder().decode(TabContext.self, from: data) else {
                return .failure(.decodingFailed)
            }
            return .success(context)
            
        } catch JXAError.timeout {
            return .failure(.timeout) // 🌟 영구 정지 방지용 타임아웃 캡치
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

        // 이전 요청 취소
        fetchTask?.cancel()

        // 🌟 [Swift 6 대응] [weak self] 캡처를 아예 지워버려서 엄격한 동시성 에러를 원천 차단합니다!
        // 🌟 [수정 1] detached를 빼고 일반 Task를 사용하여 구조적 동시성을 지킵니다.
        fetchTask = Task(priority: .userInitiated) { [weak self] in // 🌟 안전줄(weak self) 장착!
            
            // 150ms 대기 (디바운스 타임)
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }

            // 무거운 JXA 스크립트 실행
            // (adapter가 프로퍼티라면 self?.adapter 로 접근해야 할 수도 있습니다)
            let result = await adapter.fetchActiveTabInfo(appName: appName)

            guard !Task.isCancelled else { return }

            // 다시 메인 스레드로 돌아옵니다.
            await MainActor.run {
                // 🌟 [수정 2] shared를 쓰지 않고, 안전줄이 튼튼한지(메모리에 있는지) 확인 후 self를 사용합니다.
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

        // 1. 도메인 규칙(Domain Rules) 판별 및 로깅
        if SettingsManager.shared.snapshot.isBrowserDomainModeEnabled, let urlString = context.url, let host = context.host {
            let lastHost = self.lastEvaluatedHostForTab[newKey]

            if lastHost != host || isTabSwitched {
                self.lastEvaluatedHostForTab[newKey] = host

                if let matchedRule = DomainRuleManager.shared.findMatchingRule(for: urlString, browserBundleID: bundleID) {
                    let hasManualMemory = (self.tabMemory[newKey] != nil)
                    if isTabSwitched && SettingsManager.shared.snapshot.isBrowserTabMemoryEnabled && hasManualMemory {
                        // 수동 탭 메모리에 양보
                    } else {
                        // 🌟 도메인 규칙 적용 및 로깅
                        DispatchQueue.main.async {
                            InputSourceManager.shared.switchLanguage(to: matchedRule.targetInputSourceID)
                            
                            let trace = TraceFactory.create(
                                event: .languageSwitch,
                                result: .switched,
                                reason: .domainRule(domain: host),
                                appName: bundleID,
                                domain: host
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

        // 2. 새 탭 기본 언어(New Tab Default) 판별 및 로깅
        if self.isNewTab(context: context) {
            let defaultLang = SettingsManager.shared.snapshot.newTabDefaultLanguage
            if defaultLang != "None" && !defaultLang.isEmpty {
                DispatchQueue.main.async {
                    InputSourceManager.shared.switchLanguage(to: defaultLang)
                    
                    // 🌟 새 탭 설정 적용 로깅
                    let trace = TraceFactory.create(
                        event: .languageSwitch,
                        result: .switched,
                        reason: .browserTabRestore, // 또는 필요시 Factory에 newTab용 코드 추가 가능
                        appName: bundleID
                    )
                    DecisionTraceManager.shared.record(trace)
                }
                self.currentKey = newKey
                self.tabMemory[newKey] = defaultLang
                return
            }
        }

        self.currentKey = newKey
        
        // 3. 탭 메모리 복구(Tab Memory Restore) 및 로깅
        if SettingsManager.shared.snapshot.isBrowserTabMemoryEnabled {
            self.restoreContext(for: newKey, bundleID: bundleID)
        }
    }

    // 🌟 파라미터에 bundleID 추가
    private func restoreContext(for key: String, bundleID: String) {
        if let savedSourceID = tabMemory[key] {
            DispatchQueue.main.async {
                InputSourceManager.shared.switchLanguage(to: savedSourceID)
                
                // 🌟 탭 메모리 복구 로깅
                let trace = TraceFactory.create(
                    event: .restore,
                    result: .restored,
                    reason: .browserTabRestore,
                    appName: bundleID
                )
                DecisionTraceManager.shared.record(trace)
            }
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
            DispatchQueue.main.async {
                InputSourceManager.shared.switchLanguage(to: savedSourceID)
            }
        }
    }

    private func generateTabKey(from context: TabContext, bundleID: String) -> String? {
        if let id = context.id { return "\(bundleID)_tab_\(id)" }
        if let url = context.url { return "\(bundleID)_url_\(url)" }
        return nil
    }
}
