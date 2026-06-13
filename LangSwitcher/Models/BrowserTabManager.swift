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

protocol BrowserAdapter: Sendable {
    var supportedBundleIDs: [String] { get }
    func fetchActiveTabInfo(appName: String) async -> Result<TabContext, BrowserFetchError>
}

// MARK: - JXA 고성능 비동기 실행 커널

func executeJXAWithTimeout(script: String, timeoutSeconds: Double = 1.5) async throws -> String? {
    try await withThrowingTaskGroup(of: String?.self) { group in
        group.addTask {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-l", "JavaScript", "-e", script]

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardInput = Pipe() // 파이프 깨짐 방지용 더미 입력 결속
            process.standardOutput = stdout
            process.standardError = stderr

            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    process.terminationHandler = { @Sendable proc in
                        defer {
                            // 🌟 [현대적 I/O 마이그레이션] 구형 closeFile()을 소각하고 최신 표준 close()로 정산
                            try? stdout.fileHandleForReading.close()
                            try? stderr.fileHandleForReading.close()
                            proc.terminationHandler = nil
                        }

                        if proc.terminationStatus == 0 {
                            // 🌟 [현대적 I/O 마이그레이션] readDataToEndOfFile()을 소각하고 넌블로킹 readToEnd()로 전환
                            let data = (try? stdout.fileHandleForReading.readToEnd()) ?? Data()
                            let output = String(data: data, encoding: .utf8)?
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            continuation.resume(returning: output)
                        } else {
                            let errData = (try? stderr.fileHandleForReading.readToEnd()) ?? Data()
                            let errText = String(data: errData, encoding: .utf8)?
                                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Process terminated or failed"
                            continuation.resume(throwing: JXAError.scriptFailed(errText))
                        }
                    }

                    do {
                        if Task.isCancelled {
                            continuation.resume(throwing: JXAError.scriptFailed("Task was cancelled before launch"))
                            return
                        }
                        try process.run()
                    } catch {
                        continuation.resume(throwing: JXAError.scriptFailed(error.localizedDescription))
                    }
                }
            } onCancel: {
                if process.isRunning {
                    process.terminate()
                }
            }
        }

        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
            throw JXAError.timeout
        }

        do {
            let result = try await group.next() ?? nil
            group.cancelAll()
            return result
        } catch {
            group.cancelAll()
            throw error
        }
    }
}

// MARK: - Chromium Adapter

class ChromiumAdapter: BrowserAdapter {
    let supportedBundleIDs = ["com.google.Chrome", "com.microsoft.edgemac", "com.brave.Browser"]

    func fetchActiveTabInfo(appName: String) async -> Result<TabContext, BrowserFetchError> {
        let script = "function run(argv) { try { var browser = Application(\"\(appName)\"); if (browser.windows.length === 0) return \"ERROR:NO_WINDOW\"; var tab = browser.windows[0].activeTab(); return JSON.stringify({ \"id\": tab.id().toString(), \"url\": tab.url() }); } catch(e) { if (e.message.includes(\"Not authorized\")) return \"ERROR:PERMISSION\"; return \"ERROR:\" + e.message; } }"
        do {
            guard let jsonString = try await executeJXAWithTimeout(script: script) else { return .failure(.executionFailed("No result from JXA")) }
            if jsonString.hasPrefix("ERROR:") {
                if jsonString.contains("NO_WINDOW") { return .failure(.noWindow) }
                if jsonString.contains("PERMISSION") { return .failure(.permissionDenied) }
                return .failure(.executionFailed(jsonString))
            }
            guard let data = jsonString.data(using: .utf8), let context = try? JSONDecoder().decode(TabContext.self, from: data) else { return .failure(.decodingFailed) }
            return .success(context)
        } catch JXAError.timeout { return .failure(.timeout) }
        catch JXAError.scriptFailed(let errorMessage) { return .failure(.executionFailed(errorMessage)) }
        catch { return .failure(.executionFailed(error.localizedDescription)) }
    }
}

// MARK: - Safari Adapter

class SafariAdapter: BrowserAdapter {
    let supportedBundleIDs = ["com.apple.Safari"]

    func fetchActiveTabInfo(appName: String) async -> Result<TabContext, BrowserFetchError> {
        let script = "function run(argv) { try { var browser = Application(\"Safari\"); if (browser.windows.length === 0) return \"ERROR:NO_WINDOW\"; var tab = browser.windows[0].currentTab(); return JSON.stringify({ \"id\": null, \"url\": tab.url() }); } catch(e) { if (e.message.includes(\"Not authorized\")) return \"ERROR:PERMISSION\"; return \"ERROR:\" + e.message; } }"
        do {
            guard let jsonString = try await executeJXAWithTimeout(script: script) else { return .failure(.executionFailed("No result from JXA")) }
            if jsonString.hasPrefix("ERROR:") {
                if jsonString.contains("NO_WINDOW") { return .failure(.noWindow) }
                if jsonString.contains("PERMISSION") { return .failure(.permissionDenied) }
                return .failure(.executionFailed(jsonString))
            }
            guard let data = jsonString.data(using: .utf8), let context = try? JSONDecoder().decode(TabContext.self, from: data) else { return .failure(.decodingFailed) }
            return .success(context)
        } catch JXAError.timeout { return .failure(.timeout) }
        catch JXAError.scriptFailed(let errorMessage) { return .failure(.executionFailed(errorMessage)) }
        catch { return .failure(.executionFailed(error.localizedDescription)) }
    }
}

// MARK: - High Performance LRU Infra Engine

class TabNode {
    let tabID: String
    var language: String
    var lastHost: String?

    var prev: TabNode?
    var next: TabNode?

    init(tabID: String, language: String, lastHost: String?) {
        self.tabID = tabID
        self.language = language
        self.lastHost = lastHost
    }
}

class TabLRUCache {
    private let capacity: Int
    private var cache: [String: TabNode] = [:]

    private let head = TabNode(tabID: "", language: "", lastHost: nil)
    private let tail = TabNode(tabID: "", language: "", lastHost: nil)

    init(capacity: Int = 100) {
        self.capacity = capacity
        head.next = tail
        tail.prev = head
    }

    func getTab(for tabID: String) -> TabNode? {
        guard let node = cache[tabID] else { return nil }
        moveToHead(node)
        return node
    }

    func setTab(tabID: String, language: String, lastHost: String?) {
        if let existingNode = cache[tabID] {
            existingNode.language = language
            existingNode.lastHost = lastHost
            moveToHead(existingNode)
        } else {
            let newNode = TabNode(tabID: tabID, language: language, lastHost: lastHost)
            cache[tabID] = newNode
            addNode(newNode)

            if cache.count > capacity {
                if let tailNode = popTail() {
                    cache.removeValue(forKey: tailNode.tabID)
                }
            }
        }
    }

    func clear() {
        cache.removeAll()
        head.next = tail
        tail.prev = head
    }

    private func addNode(_ node: TabNode) {
        node.prev = head; node.next = head.next
        head.next?.prev = node; head.next = node
    }

    private func removeNode(_ node: TabNode) {
        let prev = node.prev; let next = node.next
        prev?.next = next; next?.prev = prev
    }

    private func moveToHead(_ node: TabNode) {
        removeNode(node); addNode(node)
    }

    private func popTail() -> TabNode? {
        let res = tail.prev
        if res === head { return nil }
        if let res = res { removeNode(res) }
        return res
    }
}

// MARK: - Core Manager

@MainActor
class BrowserTabManager {
    static let shared = BrowserTabManager()

    private var adapters: [String: BrowserAdapter] = [:]
    var supportedBrowserBundleIDs: [String] { return Array(adapters.keys) }

    private let tabCache = TabLRUCache(capacity: 100)

    var currentKey: String? = nil
    private var fetchTask: Task<Void, Never>?

    private init() {
        let chromium = ChromiumAdapter()
        for id in chromium.supportedBundleIDs { adapters[id] = chromium }
        let safari = SafariAdapter()
        for id in safari.supportedBundleIDs { adapters[id] = safari }
    }

    func clearMemory() {
        tabCache.clear()
        currentKey = nil
    }

    func updateManualLanguageChange(_ languageID: String) {
        guard let key = currentKey else { return }
        let existingHost = tabCache.getTab(for: key)?.lastHost
        self.tabCache.setTab(tabID: key, language: languageID, lastHost: existingHost)
    }

    func handleBrowserTabChanged(bundleID: String, appName: String) {
        guard SettingsManager.shared.snapshot.isBrowserTabMemoryEnabled || SettingsManager.shared.snapshot.isBrowserDomainModeEnabled else { return }
        guard let adapter = adapters[bundleID] else { return }

        saveCurrentContext()
        fetchTask?.cancel()

        fetchTask = Task(priority: .userInitiated) { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)

            guard !Task.isCancelled, let self = self else { return }

            let result = await adapter.fetchActiveTabInfo(appName: appName)

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

        let existingNode = tabCache.getTab(for: newKey)
        let isTabSwitched = (self.currentKey != newKey)
        let currentOSSource = InputSourceManager.shared.currentInputSourceID()

        // ====================================================================
        // 🌟 [수복 완료] 새 탭 판단 분기선 최상단 격상 완료 (Early Return)
        // 도메인 모드의 캐시 오염 공격을 완벽하게 원천 차단합니다.
        // ====================================================================
        if self.isNewTab(context: context) {
            let defaultLang = SettingsManager.shared.snapshot.newTabDefaultLanguage
            if defaultLang != "None" && !defaultLang.isEmpty {
                let finalLang = existingNode?.language ?? defaultLang
                
                self.tabCache.setTab(tabID: newKey, language: finalLang, lastHost: context.host)
                self.currentKey = newKey
                
                if isTabSwitched && currentOSSource != finalLang {
                    InputSourceManager.shared.switchLanguage(to: finalLang)
                    let trace = TraceFactory.create(event: .languageSwitch, result: .switched, reason: .newTabDefault, appName: bundleID)
                    DecisionTraceManager.shared.record(trace)
                }
                return
            }
        }

        // 1. 도메인 규칙 검사 (이제 일반 사이트 문맥만 청정하게 관통합니다)
        if SettingsManager.shared.snapshot.isBrowserDomainModeEnabled, let urlString = context.url, let host = context.host {
            let lastHost = existingNode?.lastHost

            if lastHost != host || isTabSwitched {
                let currentLang = existingNode?.language ?? currentOSSource

                if let matchedRule = DomainRuleManager.shared.findMatchingRule(for: urlString, browserBundleID: bundleID) {
                    let hasManualMemory = (existingNode != nil)
                    if isTabSwitched && SettingsManager.shared.snapshot.isBrowserTabMemoryEnabled && hasManualMemory {
                        // 패스 유도
                    } else {
                        InputSourceManager.shared.switchLanguage(to: matchedRule.targetInputSourceID)
                        let trace = TraceFactory.create(event: .languageSwitch, result: .switched, reason: .domainRule(domain: host), appName: bundleID, domain: host)
                        DecisionTraceManager.shared.record(trace)
                        
                        self.currentKey = newKey
                        self.tabCache.setTab(tabID: newKey, language: matchedRule.targetInputSourceID, lastHost: host)
                        return
                    }
                } else {
                    self.tabCache.setTab(tabID: newKey, language: currentLang, lastHost: host)
                }
            }
        }

        if !isTabSwitched { return }

        self.currentKey = newKey

        // 3. 탭 캐시 메모리 복구 전개
        if SettingsManager.shared.snapshot.isBrowserTabMemoryEnabled {
            self.restoreContext(for: newKey, bundleID: bundleID)
        }
    }

    private func restoreContext(for key: String, bundleID: String) {
        if let node = tabCache.getTab(for: key) {
            let currentOSSource = InputSourceManager.shared.currentInputSourceID()

            if currentOSSource != node.language {
                InputSourceManager.shared.switchLanguage(to: node.language)
                let trace = TraceFactory.create(event: .restore, result: .restored, reason: .browserTabRestore, appName: bundleID)
                DecisionTraceManager.shared.record(trace)
            }
        } else {
            let currentOSSource = InputSourceManager.shared.currentInputSourceID()
            self.tabCache.setTab(tabID: key, language: currentOSSource, lastHost: nil)
        }
    }

    private func handleFetchFailure(error: BrowserFetchError, appName: String) {
        let failureReason: FailureReason
        let logMessage: String

        switch error {
        case .timeout: failureReason = .unknown; logMessage = "JXA Timeout (1.5s exceeded)"
        case .permissionDenied: failureReason = .permissionIssue; logMessage = "Automation Permission Denied"
        case .noWindow: failureReason = .conditionMismatch; logMessage = "No Active Windows Found"
        case .unsupportedBrowser: failureReason = .conditionMismatch; logMessage = "Unsupported Browser Structure"
        case .executionFailed(let msg): failureReason = .unknown; logMessage = "JXA Error: \(msg)"
        case .decodingFailed: failureReason = .unknown; logMessage = "JSON Decoding Failed"
        }

        let log = ActionLog(timestamp: Date(), targetApp: appName, appliedRule: "Tab Memory Fallback", finalInputSource: logMessage, result: .failure, failureReason: failureReason)
        SettingsManager.shared.addLog(log)
    }

    private func isNewTab(context: TabContext) -> Bool {
        guard let url = context.url?.lowercased() else { return true }
        if url.isEmpty || url == "about:blank" { return true }
        
        let newTabPatterns = [
            "chrome://newtab", "chrome://new-tab-page",
            "edge://newtab", "brave://newtab",
            "favorites://", "topsites://", "safari-resource://"
        ]
        return newTabPatterns.contains { url.starts(with: $0) } || url.contains("chrome/newtab")
    }

    func handleBrowserDeactivated() {
        saveCurrentContext()
        currentKey = nil
    }

    private func saveCurrentContext() {
        guard let key = currentKey else { return }
        let currentSource = InputSourceManager.shared.currentInputSourceID()
        let existingHost = tabCache.getTab(for: key)?.lastHost
        self.tabCache.setTab(tabID: key, language: currentSource, lastHost: existingHost)
    }

    private func generateTabKey(from context: TabContext, bundleID: String) -> String? {
        if let id = context.id { return "\(bundleID)_tab_\(id)" }
        if let url = context.url { return "\(bundleID)_url_\(url)" }
        return nil
    }
}
