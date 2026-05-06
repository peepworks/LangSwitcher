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

import Foundation
import Combine
import SwiftUI

struct CustomShortcut: Identifiable, Codable { var id = UUID(); var keyCode: UInt16; var modifierFlags: UInt64; var displayString: String; var targetLanguage: String }
struct CustomApp: Identifiable, Codable { var id = UUID(); var bundleIdentifier: String; var appName: String; var targetLanguage: String }
struct AppLaunchShortcut: Identifiable, Codable { var id = UUID(); var keyCode: UInt16; var modifierFlags: UInt64; var displayString: String; var bundleIdentifier: String; var appName: String }
struct ExcludedApp: Identifiable, Codable { var id = UUID(); var bundleIdentifier: String; var appName: String }

enum LogResult: String, Codable { case success, failure }

enum FailureReason: String, Codable {
    case none = "None"
    case conditionMismatch = "Condition Mismatch"
    case excludedApp = "Excluded App"
    case permissionIssue = "Permission Issue"
    case unknown = "Unknown Error"
}

struct ActionLog: Identifiable, Codable {
    var id = UUID()
    let timestamp: Date
    let targetApp: String
    let appliedRule: String
    let finalInputSource: String
    let result: LogResult
    let failureReason: FailureReason
}

struct BackupData: Codable {
    let version: String?
    let isCtrlActive: Bool; let isCmdActive: Bool; let isOptActive: Bool
    let ctrlLang: String; let cmdLang: String; let optLang: String
    let showVisualFeedback: Bool; let isTestMode: Bool
    let toggleKeyCode: UInt16; let toggleModifierFlags: UInt64; let toggleDisplayString: String
    let customShortcuts: [CustomShortcut]; let customApps: [CustomApp]; let appLaunchShortcuts: [AppLaunchShortcut]
    let excludedApps: [ExcludedApp]?
    let isTypoCorrectionEnabled: Bool?
    let typoKeyCode: UInt16?
    let typoModifierFlags: UInt64?
    let typoDisplayString: String?
    let isSentenceMode: Bool?
    let isExcludedAppsEnabled: Bool?
    let isAutoTypoCorrectionEnabled: Bool?
    let isEdgeGlowEnabled: Bool?
    let isAutoTypoCorrectionOnEnterEnabled: Bool?
    
    let isBrowserTabMemoryEnabled: Bool?
    let isBrowserDomainModeEnabled: Bool?
    
    // 🌟 [추가] 백업 시 도메인 규칙 포함
    let domainRules: [DomainRule]?
}

struct SettingsSnapshot {
    var isCtrlActive = false; var isCmdActive = false; var isOptActive = false
    var ctrlLang = ""; var cmdLang = ""; var optLang = ""
    var showVisualFeedback = true; var isTestMode = false
    var toggleKeyCode: UInt16 = 0; var toggleModifierFlags: UInt64 = 0; var toggleDisplayString = ""
    var isSentenceMode = false
    var customShortcuts: [CustomShortcut] = []
    var customApps: [CustomApp] = []
    var appLaunchShortcuts: [AppLaunchShortcut] = []
    var excludedApps: [ExcludedApp] = []
    var isTypoCorrectionEnabled = false
    var typoKeyCode: UInt16 = 0; var typoModifierFlags: UInt64 = 0; var typoDisplayString = ""
    var isHyperKeyEnabled = false
    var isAppLaunchEnabled = true; var isCustomShortcutsEnabled = true
    var isExcludedAppsEnabled = true
    var isAppSpecificEnabled = true
    var isWindowMemoryEnabled = false
    var isWindowMemoryCleanupEnabled = true
    var isCursorHUDEnabled = true
    var isCloudSyncEnabled = false
    var isHapticFeedbackEnabled = false
    var isSoundFeedbackEnabled = false
    var isAutoTypoCorrectionEnabled = false
    var isEdgeGlowEnabled = false
    var isAutoTypoCorrectionOnEnterEnabled = false
    var isBrowserTabMemoryEnabled = false
    var isBrowserDomainModeEnabled = false
    var newTabDefaultLanguage = "None"
    
    // 🌟 [추가] 스냅샷에 도메인 규칙 배열 포함
    var domainRules: [DomainRule] = []
}

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    let currentSettingsVersion = "1.0.0"
    
    private let icloudStore = NSUbiquitousKeyValueStore.default
    
    private let snapshotQueue = DispatchQueue(label: "com.peepworks.settings.snapshot", attributes: .concurrent)
    private var _snapshot = SettingsSnapshot()
        
    var snapshot: SettingsSnapshot {
        snapshotQueue.sync { _snapshot }
    }
        
    func updateSnapshot() {
        let newSnapshot = SettingsSnapshot(
            isCtrlActive: isCtrlActive, isCmdActive: isCmdActive, isOptActive: isOptActive,
            ctrlLang: ctrlLang, cmdLang: cmdLang, optLang: optLang,
            showVisualFeedback: showVisualFeedback, isTestMode: isTestMode,
            toggleKeyCode: toggleKeyCode, toggleModifierFlags: toggleModifierFlags, toggleDisplayString: toggleDisplayString,
            isSentenceMode: isSentenceMode,
            customShortcuts: customShortcuts, customApps: customApps, appLaunchShortcuts: appLaunchShortcuts,
            excludedApps: excludedApps,
            isTypoCorrectionEnabled: isTypoCorrectionEnabled,
            typoKeyCode: typoKeyCode, typoModifierFlags: typoModifierFlags, typoDisplayString: typoDisplayString,
            isHyperKeyEnabled: isHyperKeyEnabled,
            isAppLaunchEnabled: isAppLaunchEnabled, isCustomShortcutsEnabled: isCustomShortcutsEnabled,
            isExcludedAppsEnabled: isExcludedAppsEnabled,
            isAppSpecificEnabled: isAppSpecificEnabled,
            isWindowMemoryEnabled: isWindowMemoryEnabled,
            isWindowMemoryCleanupEnabled: isWindowMemoryCleanupEnabled,
            isCursorHUDEnabled: isCursorHUDEnabled,
            isCloudSyncEnabled: isCloudSyncEnabled,
            isHapticFeedbackEnabled: isHapticFeedbackEnabled,
            isSoundFeedbackEnabled: isSoundFeedbackEnabled,
            isAutoTypoCorrectionEnabled: isAutoTypoCorrectionEnabled,
            isEdgeGlowEnabled: isEdgeGlowEnabled,
            isAutoTypoCorrectionOnEnterEnabled: isAutoTypoCorrectionOnEnterEnabled,
            isBrowserTabMemoryEnabled: isBrowserTabMemoryEnabled,
            isBrowserDomainModeEnabled: isBrowserDomainModeEnabled,
            newTabDefaultLanguage: newTabDefaultLanguage,
            domainRules: domainRules // 🌟 [추가]
        )
        snapshotQueue.async(flags: .barrier) { self._snapshot = newSnapshot }
    }

    // 🌟 [수정됨] NSLock을 제거하고 @MainActor를 사용하여 메인 스레드 격리를 보장합니다.
    @MainActor var isBatchUpdating: Bool = false
    
    @Published var isCtrlActive: Bool { didSet { save("isCtrlActive", isCtrlActive); updateSnapshot(); syncToCloud() } }
    @Published var isCmdActive: Bool { didSet { save("isCmdActive", isCmdActive); updateSnapshot(); syncToCloud() } }
    @Published var isOptActive: Bool { didSet { save("isOptActive", isOptActive); updateSnapshot(); syncToCloud() } }
    @Published var ctrlLang: String { didSet { save("ctrlLang", ctrlLang); updateSnapshot(); syncToCloud() } }
    @Published var cmdLang: String { didSet { save("cmdLang", cmdLang); updateSnapshot(); syncToCloud() } }
    @Published var optLang: String { didSet { save("optLang", optLang); updateSnapshot(); syncToCloud() } }
    
    @Published var showVisualFeedback: Bool { didSet { save("showVisualFeedback", showVisualFeedback); updateSnapshot(); syncToCloud() } }
    @Published var isTestMode: Bool { didSet { save("isTestMode", isTestMode); updateSnapshot() } }
    
    @Published var toggleKeyCode: UInt16 { didSet { save("toggleKeyCode", toggleKeyCode); updateSnapshot() } }
    @Published var toggleModifierFlags: UInt64 { didSet { save("toggleModifierFlags", toggleModifierFlags); updateSnapshot() } }
    @Published var toggleDisplayString: String { didSet { save("toggleDisplayString", toggleDisplayString); updateSnapshot() } }
    
    @Published var customShortcuts: [CustomShortcut] = [] { didSet { if let e = try? JSONEncoder().encode(customShortcuts) { save("customShortcuts", e); updateSnapshot(); syncToCloud() } } }
    @Published var customApps: [CustomApp] = [] { didSet { if let e = try? JSONEncoder().encode(customApps) { save("customApps", e); updateSnapshot(); syncToCloud() } } }
    @Published var appLaunchShortcuts: [AppLaunchShortcut] = [] { didSet { if let e = try? JSONEncoder().encode(appLaunchShortcuts) { save("appLaunchShortcuts", e); updateSnapshot(); syncToCloud() } } }
    @Published var excludedApps: [ExcludedApp] = [] { didSet { if let e = try? JSONEncoder().encode(excludedApps) { save("excludedApps", e); updateSnapshot(); syncToCloud() } } }
    
    // 🌟 [추가] 도메인 규칙 저장 및 DomainRuleManager 즉시 동기화
    @Published var domainRules: [DomainRule] = [] {
        didSet {
            if let e = try? JSONEncoder().encode(domainRules) {
                save("domainRules", e)
                updateSnapshot()
                syncToCloud()
                DomainRuleManager.shared.rules = domainRules
            }
        }
    }
    
    @Published var isTypoCorrectionEnabled: Bool { didSet { save("isTypoCorrectionEnabled", isTypoCorrectionEnabled); updateSnapshot(); syncToCloud() } }
    @Published var typoKeyCode: UInt16 { didSet { save("typoKeyCode", typoKeyCode); updateSnapshot() } }
    @Published var typoModifierFlags: UInt64 { didSet { save("typoModifierFlags", typoModifierFlags); updateSnapshot() } }
    @Published var typoDisplayString: String { didSet { save("typoDisplayString", typoDisplayString); updateSnapshot() } }
    @Published var isSentenceMode: Bool { didSet { save("isSentenceMode", isSentenceMode); updateSnapshot() } }
    
    @Published private(set) var recentLogs: [ActionLog] = []
    
    @AppStorage("isHyperKeyEnabled") var isHyperKeyEnabled: Bool = false {
        didSet { HyperKeyManager.shared.updateState(isEnabled: isHyperKeyEnabled); updateSnapshot(); syncToCloud() }
    }
    
    @AppStorage("isCustomShortcutsEnabled") var isCustomShortcutsEnabled: Bool = true { didSet { updateSnapshot() } }
    @AppStorage("isAppSpecificEnabled") var isAppSpecificEnabled: Bool = true { didSet { updateSnapshot() } }
    @AppStorage("isAppLaunchEnabled") var isAppLaunchEnabled: Bool = true { didSet { updateSnapshot() } }
    @AppStorage("isExcludedAppsEnabled") var isExcludedAppsEnabled: Bool = true { didSet { updateSnapshot() } }
    
    @AppStorage("isWindowMemoryEnabled") var isWindowMemoryEnabled: Bool = false { didSet { updateSnapshot(); syncToCloud() } }
    @AppStorage("isWindowMemoryCleanupEnabled") var isWindowMemoryCleanupEnabled: Bool = true { didSet { updateSnapshot(); syncToCloud() } }
    @AppStorage("isCursorHUDEnabled") var isCursorHUDEnabled: Bool = true { didSet { updateSnapshot(); syncToCloud() } }
    
    @AppStorage("isCloudSyncEnabled") var isCloudSyncEnabled: Bool = false {
        didSet {
            updateSnapshot()
            if isCloudSyncEnabled { syncToCloud() }
        }
    }
    @AppStorage("isHapticFeedbackEnabled") var isHapticFeedbackEnabled: Bool = false { didSet { updateSnapshot(); syncToCloud() } }
    @AppStorage("isSoundFeedbackEnabled") var isSoundFeedbackEnabled: Bool = false { didSet { updateSnapshot(); syncToCloud() } }
    @AppStorage("isAutoTypoCorrectionEnabled") var isAutoTypoCorrectionEnabled: Bool = false { didSet { updateSnapshot(); syncToCloud() } }
    @AppStorage("isEdgeGlowEnabled") var isEdgeGlowEnabled: Bool = false { didSet { updateSnapshot(); syncToCloud() } }
    @AppStorage("isAutoTypoCorrectionOnEnterEnabled") var isAutoTypoCorrectionOnEnterEnabled: Bool = false { didSet { updateSnapshot(); syncToCloud() } }
    
    @AppStorage("isBrowserTabMemoryEnabled") var isBrowserTabMemoryEnabled: Bool = false { didSet { updateSnapshot(); syncToCloud() } }
    @AppStorage("isBrowserDomainModeEnabled") var isBrowserDomainModeEnabled: Bool = false { didSet { updateSnapshot(); syncToCloud() } }
    @AppStorage("newTabDefaultLanguage") var newTabDefaultLanguage: String = "None" {
        didSet { updateSnapshot(); syncToCloud() }
    }
    
    private init() {
        let d = UserDefaults.standard
        isCtrlActive = d.bool(forKey: "isCtrlActive"); isCmdActive = d.bool(forKey: "isCmdActive"); isOptActive = d.bool(forKey: "isOptActive")
        showVisualFeedback = d.object(forKey: "showVisualFeedback") as? Bool ?? true; isTestMode = d.bool(forKey: "isTestMode")
        toggleKeyCode = UInt16(d.integer(forKey: "toggleKeyCode"))
        toggleModifierFlags = UInt64(d.integer(forKey: "toggleModifierFlags"))
        toggleDisplayString = d.string(forKey: "toggleDisplayString") ?? ""
        ctrlLang = d.string(forKey: "ctrlLang") ?? ""; cmdLang = d.string(forKey: "cmdLang") ?? ""; optLang = d.string(forKey: "optLang") ?? ""
        
        if let data = d.data(forKey: "customShortcuts"), let dec = try? JSONDecoder().decode([CustomShortcut].self, from: data) { customShortcuts = dec }
        if let data = d.data(forKey: "customApps"), let dec = try? JSONDecoder().decode([CustomApp].self, from: data) { customApps = dec }
        if let data = d.data(forKey: "appLaunchShortcuts"), let dec = try? JSONDecoder().decode([AppLaunchShortcut].self, from: data) { appLaunchShortcuts = dec }
        if let data = d.data(forKey: "excludedApps"), let dec = try? JSONDecoder().decode([ExcludedApp].self, from: data) { excludedApps = dec }
        
        // 🌟 [추가] 초기화 시 도메인 규칙을 불러오고 엔진에 즉시 주입
        if let data = d.data(forKey: "domainRules"), let dec = try? JSONDecoder().decode([DomainRule].self, from: data) {
            domainRules = dec
            DomainRuleManager.shared.rules = dec
        }
        
        isTypoCorrectionEnabled = d.object(forKey: "isTypoCorrectionEnabled") as? Bool ?? false
        typoKeyCode = UInt16(d.integer(forKey: "typoKeyCode"))
        typoModifierFlags = UInt64(d.integer(forKey: "typoModifierFlags"))
        typoDisplayString = d.string(forKey: "typoDisplayString") ?? ""
        isSentenceMode = d.object(forKey: "isSentenceMode") as? Bool ?? false
        
        updateSnapshot()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(icloudUpdateReceived(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: icloudStore
        )
        icloudStore.synchronize()
    }
    
    @objc private func icloudUpdateReceived(_ notification: Notification) {
        guard isCloudSyncEnabled else { return }
        
        // 🌟 [추가됨] [weak self]를 통해 메모리 누수를 완벽히 방지합니다.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 깃발을 올려 iCloud 역류를 방지합니다.
            self.isBatchUpdating = true
            
            defer {
                // 🌟 [핵심 수정] 순서를 바꿨습니다!
                // 깃발이 아직 올라가 있는 상태에서 안전하게 로컬 저장 및 스냅샷을 갱신합니다.
                self.saveAll()
                self.updateSnapshot()
                
                // 모든 작업이 완전히 끝난 후, 가장 마지막 순간에 깃발을 내립니다.
                self.isBatchUpdating = false
            }
            
            let dict = self.icloudStore.dictionaryRepresentation
            
            if let val = dict["showVisualFeedback"] as? Bool { self.showVisualFeedback = val }
            if let val = dict["isHyperKeyEnabled"] as? Bool { self.isHyperKeyEnabled = val }
            if let val = dict["isWindowMemoryEnabled"] as? Bool { self.isWindowMemoryEnabled = val }
            if let val = dict["isCursorHUDEnabled"] as? Bool { self.isCursorHUDEnabled = val }
            if let val = dict["isTypoCorrectionEnabled"] as? Bool { self.isTypoCorrectionEnabled = val }
            
            if let val = dict["isAutoTypoCorrectionEnabled"] as? Bool { self.isAutoTypoCorrectionEnabled = val }
            if let val = dict["isEdgeGlowEnabled"] as? Bool { self.isEdgeGlowEnabled = val }
            if let val = dict["isAutoTypoCorrectionOnEnterEnabled"] as? Bool { self.isAutoTypoCorrectionOnEnterEnabled = val }
            
            if let data = dict["excludedApps"] as? Data, let dec = try? JSONDecoder().decode([ExcludedApp].self, from: data) { self.excludedApps = dec }
            if let data = dict["customShortcuts"] as? Data, let dec = try? JSONDecoder().decode([CustomShortcut].self, from: data) { self.customShortcuts = dec }
            
            // 🌟 iCloud에서 도메인 규칙 수신 및 엔진 동기화
            if let data = dict["domainRules"] as? Data, let dec = try? JSONDecoder().decode([DomainRule].self, from: data) {
                self.domainRules = dec
                DomainRuleManager.shared.rules = dec
            }
            
            if let val = dict["isBrowserTabMemoryEnabled"] as? Bool { self.isBrowserTabMemoryEnabled = val }
            if let val = dict["isBrowserDomainModeEnabled"] as? Bool { self.isBrowserDomainModeEnabled = val }
        }
    }
    
    func syncToCloud() {
        guard isCloudSyncEnabled, !isBatchUpdating else { return }
        
        icloudStore.set(showVisualFeedback, forKey: "showVisualFeedback")
        icloudStore.set(isHyperKeyEnabled, forKey: "isHyperKeyEnabled")
        icloudStore.set(isWindowMemoryEnabled, forKey: "isWindowMemoryEnabled")
        icloudStore.set(isCursorHUDEnabled, forKey: "isCursorHUDEnabled")
        icloudStore.set(isTypoCorrectionEnabled, forKey: "isTypoCorrectionEnabled")
        icloudStore.set(isHapticFeedbackEnabled, forKey: "isHapticFeedbackEnabled")
        icloudStore.set(isSoundFeedbackEnabled, forKey: "isSoundFeedbackEnabled")
        icloudStore.set(isAutoTypoCorrectionEnabled, forKey: "isAutoTypoCorrectionEnabled")
        icloudStore.set(isEdgeGlowEnabled, forKey: "isEdgeGlowEnabled")
        icloudStore.set(isAutoTypoCorrectionOnEnterEnabled, forKey: "isAutoTypoCorrectionOnEnterEnabled")
        
        icloudStore.set(isBrowserTabMemoryEnabled, forKey: "isBrowserTabMemoryEnabled")
        icloudStore.set(isBrowserDomainModeEnabled, forKey: "isBrowserDomainModeEnabled")
        
        if let e = try? JSONEncoder().encode(excludedApps) { icloudStore.set(e, forKey: "excludedApps") }
        if let e = try? JSONEncoder().encode(customShortcuts) { icloudStore.set(e, forKey: "customShortcuts") }
        
        // 🌟 [추가] iCloud에 도메인 규칙 업로드
        if let e = try? JSONEncoder().encode(domainRules) { icloudStore.set(e, forKey: "domainRules") }
        
        icloudStore.synchronize()
    }
    
    private func save(_ key: String, _ value: Any) {
        guard !isBatchUpdating else { return }
        UserDefaults.standard.set(value, forKey: key)
    }
    
    private func saveAll() {
        let d = UserDefaults.standard
        if let e = try? JSONEncoder().encode(customShortcuts) { d.set(e, forKey: "customShortcuts") }
        if let e = try? JSONEncoder().encode(customApps) { d.set(e, forKey: "customApps") }
        if let e = try? JSONEncoder().encode(appLaunchShortcuts) { d.set(e, forKey: "appLaunchShortcuts") }
        if let e = try? JSONEncoder().encode(excludedApps) { d.set(e, forKey: "excludedApps") }
        
        // 🌟 [추가] 일괄 저장 시 도메인 규칙 포함
        if let e = try? JSONEncoder().encode(domainRules) { d.set(e, forKey: "domainRules") }
    }
    
    func addLog(_ log: ActionLog) {
        DispatchQueue.main.async {
            self.recentLogs.insert(log, at: 0)
            while self.recentLogs.count > 50 {
                self.recentLogs.removeLast()
            }
        }
    }
    
    func exportBackup(to url: URL, completion: @escaping (Bool, Error?) -> Void = { _, _ in }) {
        do {
            let backup = BackupData(
                version: currentSettingsVersion,
                isCtrlActive: isCtrlActive, isCmdActive: isCmdActive, isOptActive: isOptActive, ctrlLang: ctrlLang, cmdLang: cmdLang, optLang: optLang,
                showVisualFeedback: showVisualFeedback, isTestMode: isTestMode,
                toggleKeyCode: toggleKeyCode, toggleModifierFlags: toggleModifierFlags, toggleDisplayString: toggleDisplayString,
                customShortcuts: customShortcuts, customApps: customApps, appLaunchShortcuts: appLaunchShortcuts,
                excludedApps: excludedApps,
                isTypoCorrectionEnabled: isTypoCorrectionEnabled,
                typoKeyCode: typoKeyCode,
                typoModifierFlags: typoModifierFlags,
                typoDisplayString: typoDisplayString,
                isSentenceMode: isSentenceMode,
                isExcludedAppsEnabled: isExcludedAppsEnabled,
                isAutoTypoCorrectionEnabled: isAutoTypoCorrectionEnabled,
                isEdgeGlowEnabled: isEdgeGlowEnabled,
                isAutoTypoCorrectionOnEnterEnabled: isAutoTypoCorrectionOnEnterEnabled,
                isBrowserTabMemoryEnabled: isBrowserTabMemoryEnabled,
                isBrowserDomainModeEnabled: isBrowserDomainModeEnabled,
                domainRules: domainRules // 🌟 [추가]
            )
            
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(backup)
            
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try data.write(to: url)
                    DispatchQueue.main.async { completion(true, nil) }
                } catch {
                    DispatchQueue.main.async { completion(false, error) }
                }
            }
        } catch {
            completion(false, error)
        }
    }

    func importBackup(from url: URL, completion: @escaping (Bool, Error?) -> Void = { _, _ in }) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let data = try Data(contentsOf: url)
                
                DispatchQueue.main.async {
                    do {
                        let backup = try JSONDecoder().decode(BackupData.self, from: data)
                        
                        self.isBatchUpdating = true
                        
                        defer {
                            self.isBatchUpdating = false
                            self.saveAll()
                            self.updateSnapshot()
                        }
                        
                        self.isCtrlActive = backup.isCtrlActive; self.isCmdActive = backup.isCmdActive; self.isOptActive = backup.isOptActive
                        self.ctrlLang = backup.ctrlLang; self.cmdLang = backup.cmdLang; self.optLang = backup.optLang
                        self.showVisualFeedback = backup.showVisualFeedback

                        self.isTestMode = false
                        
                        self.toggleKeyCode = backup.toggleKeyCode; self.toggleModifierFlags = backup.toggleModifierFlags; self.toggleDisplayString = backup.toggleDisplayString
                        self.customShortcuts = backup.customShortcuts; self.customApps = backup.customApps; self.appLaunchShortcuts = backup.appLaunchShortcuts
                        self.excludedApps = backup.excludedApps ?? []
                        self.isTypoCorrectionEnabled = backup.isTypoCorrectionEnabled ?? false
                        self.typoKeyCode = backup.typoKeyCode ?? 0
                        self.typoModifierFlags = backup.typoModifierFlags ?? 0
                        self.typoDisplayString = backup.typoDisplayString ?? ""
                        self.isSentenceMode = backup.isSentenceMode ?? false
                        
                        self.isAutoTypoCorrectionEnabled = backup.isAutoTypoCorrectionEnabled ?? false
                        self.isEdgeGlowEnabled = backup.isEdgeGlowEnabled ?? false
                        self.isAutoTypoCorrectionOnEnterEnabled = backup.isAutoTypoCorrectionOnEnterEnabled ?? false
                        
                        self.isBrowserTabMemoryEnabled = backup.isBrowserTabMemoryEnabled ?? false
                        self.isBrowserDomainModeEnabled = backup.isBrowserDomainModeEnabled ?? false
                        
                        // 🌟 [추가] 백업에서 복원 시 도메인 규칙 적용 및 엔진 동기화
                        self.domainRules = backup.domainRules ?? []
                        DomainRuleManager.shared.rules = self.domainRules
                        
                        self.isExcludedAppsEnabled = backup.isExcludedAppsEnabled ?? true
                        
                        completion(true, nil)
                    } catch {
                        completion(false, error)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(false, error)
                }
            }
        }
    }
    // MARK: - Cache & Memory Management
    
    @MainActor
    func clearAllAppCaches() {
        // 1. 브라우저 탭별 언어 기억 초기화
        BrowserTabManager.shared.clearMemory()
        
        // 2. 일반 윈도우 창별 언어 기억 초기화
        WindowMonitor.shared.clearMemory()
        
        // 3. 타이핑 오타 교정을 위해 쌓아둔 임시 버퍼 문자열 비우기
        EventMonitor.shared.clearTypingBuffer()
        
        // 4. 사용자에게 시각적 피드백 제공 (HUD)
        let statusMessage = String(localized: "✨ All Memories Cleared")
        HUDManager.shared.showHUD(languageName: statusMessage)
        
        #if DEBUG
        print("LangSwitcher: All caches and memory records have been manually cleared.")
        #endif
    }
}
