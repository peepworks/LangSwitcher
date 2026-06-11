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
                        pipe.fileHandleForReading.closeFile()
                        errorPipe.fileHandleForReading.closeFile()
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
            try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
            throw JXAError.timeout
        }

        do {
            let firstResult = try await group.next()
            group.cancelAll()
            return firstResult ?? nil
        } catch {
            group.cancelAll()
            if process.isRunning { process.terminate() }
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

// MARK: - High Performance LRU Infra Engine (3번 리뷰 수복 달성)

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

    // 🌟 3대 분산 레거시 딕셔너리를 완벽한 단일 상수 시간 O(1) 캐시 인프라로 결속 정산합니다.
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

        // O(1) 캐시 조회를 가동함과 동시에 우선순위 정산을 내부에서 직결 처리합니다.
        let existingNode = tabCache.getTab(for: newKey)
        let isTabSwitched = (self.currentKey != newKey)
        let currentOSSource = InputSourceManager.shared.currentInputSourceID()

        // 1. 도메인 규칙 검사
        if SettingsManager.shared.snapshot.isBrowserDomainModeEnabled, let urlString = context.url, let host = context.host {
            let lastHost = existingNode?.lastHost

            if lastHost != host || isTabSwitched {
                let currentLang = existingNode?.language ?? currentOSSource
                
                if let matchedRule = DomainRuleManager.shared.findMatchingRule(for: urlString, browserBundleID: bundleID) {
                    let hasManualMemory = (existingNode != nil)
                    if isTabSwitched && SettingsManager.shared.snapshot.isBrowserTabMemoryEnabled && hasManualMemory {
                        // 수동 기억 모드가 있다면 도메인 규칙을 건너뛰고 하단 탭 복원부로 스킵 유도
                    } else {
                        Task { @MainActor in
                            InputSourceManager.shared.switchLanguage(to: matchedRule.targetInputSourceID)
                            let trace = TraceFactory.create(event: .languageSwitch, result: .switched, reason: .domainRule(domain: host), appName: bundleID, domain: host)
                            DecisionTraceManager.shared.record(trace)
                        }
                        self.currentKey = newKey
                        self.tabCache.setTab(tabID: newKey, language: matchedRule.targetInputSourceID, lastHost: host)
                        return
                    }
                } else {
                    // 호스트명이 변경되었거나 탭이 전환된 경우 호스트 장부 원자적 최신화
                    self.tabCache.setTab(tabID: newKey, language: currentLang, lastHost: host)
                }
            }
        }

        if !isTabSwitched { return }

        // 2. 새 탭 규칙 (기본 언어 강제 각인 논리 복구)
        if self.isNewTab(context: context) {
            let defaultLang = SettingsManager.shared.snapshot.newTabDefaultLanguage
            if defaultLang != "None" && !defaultLang.isEmpty {
                let finalLang = tabCache.getTab(for: newKey)?.language ?? defaultLang
                self.tabCache.setTab(tabID: newKey, language: finalLang, lastHost: context.host)
                
                if currentOSSource != finalLang {
                    Task { @MainActor in
                        InputSourceManager.shared.switchLanguage(to: finalLang)
                        let trace = TraceFactory.create(event: .languageSwitch, result: .switched, reason: .newTabDefault, appName: bundleID)
                        DecisionTraceManager.shared.record(trace)
                    }
                }
                self.currentKey = newKey
                return
            }
        }

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
                Task { @MainActor in
                    InputSourceManager.shared.switchLanguage(to: node.language)
                    let trace = TraceFactory.create(event: .restore, result: .restored, reason: .browserTabRestore, appName: bundleID)
                    DecisionTraceManager.shared.record(trace)
                }
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
        let existingHost = tabCache.getTab(for: key)?.lastHost
        self.tabCache.setTab(tabID: key, language: currentSource, lastHost: existingHost)
    }

    private func generateTabKey(from context: TabContext, bundleID: String) -> String? {
        if let id = context.id { return "\(bundleID)_tab_\(id)" }
        if let url = context.url { return "\(bundleID)_url_\(url)" }
        return nil
    }
}
