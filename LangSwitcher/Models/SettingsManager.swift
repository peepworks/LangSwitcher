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
}

struct SettingsSnapshot {
    var isCtrlActive = false; var isCmdActive = false; var isOptActive = false
    var ctrlLang = ""; var cmdLang = ""; var optLang = ""
    var showVisualFeedback = true; var isTestMode = false
    var toggleKeyCode: UInt16 = 0; var toggleModifierFlags: UInt64 = 0; var toggleDisplayString = ""
    var customShortcuts: [CustomShortcut] = []
    var customApps: [CustomApp] = []
    var appLaunchShortcuts: [AppLaunchShortcut] = []
    var excludedApps: [ExcludedApp] = []
    var isTypoCorrectionEnabled = false
    var typoKeyCode: UInt16 = 0; var typoModifierFlags: UInt64 = 0; var typoDisplayString = ""
    var isHyperKeyEnabled = false
    var isAppLaunchEnabled = true; var isCustomShortcutsEnabled = true
    var isExcludedAppsEnabled = true
    var isWindowMemoryEnabled = false
    var isWindowMemoryCleanupEnabled = true
    var isCursorHUDEnabled = true
    var isCloudSyncEnabled = false
    var isHapticFeedbackEnabled = false
    var isSoundFeedbackEnabled = false
    // 🌟 [추가] 스마트 자동 오타 감지
    var isAutoTypoCorrectionEnabled = false
}

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    let currentSettingsVersion = "1.0.0"
    
    // 🌟 iCloud 저장소 접근 객체
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
            customShortcuts: customShortcuts, customApps: customApps, appLaunchShortcuts: appLaunchShortcuts,
            excludedApps: excludedApps,
            isTypoCorrectionEnabled: isTypoCorrectionEnabled,
            typoKeyCode: typoKeyCode, typoModifierFlags: typoModifierFlags, typoDisplayString: typoDisplayString,
            isHyperKeyEnabled: isHyperKeyEnabled,
            isAppLaunchEnabled: isAppLaunchEnabled, isCustomShortcutsEnabled: isCustomShortcutsEnabled,
            isExcludedAppsEnabled: isExcludedAppsEnabled,
            isWindowMemoryEnabled: isWindowMemoryEnabled,
            isWindowMemoryCleanupEnabled: isWindowMemoryCleanupEnabled,
            isCursorHUDEnabled: isCursorHUDEnabled,
            isCloudSyncEnabled: isCloudSyncEnabled,
            isHapticFeedbackEnabled: isHapticFeedbackEnabled,
            isSoundFeedbackEnabled: isSoundFeedbackEnabled,
            isAutoTypoCorrectionEnabled: isAutoTypoCorrectionEnabled // 🌟 [추가]
        )
        snapshotQueue.async(flags: .barrier) { self._snapshot = newSnapshot }
    }

    private var isBatchUpdating = false
    
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
    
    @Published var isTypoCorrectionEnabled: Bool { didSet { save("isTypoCorrectionEnabled", isTypoCorrectionEnabled); updateSnapshot(); syncToCloud() } }
    @Published var typoKeyCode: UInt16 { didSet { save("typoKeyCode", typoKeyCode); updateSnapshot() } }
    @Published var typoModifierFlags: UInt64 { didSet { save("typoModifierFlags", typoModifierFlags); updateSnapshot() } }
    @Published var typoDisplayString: String { didSet { save("typoDisplayString", typoDisplayString); updateSnapshot() } }
    @Published var isSentenceMode: Bool { didSet { save("isSentenceMode", isSentenceMode); updateSnapshot() } }
    
    @Published var recentLogs: [ActionLog] = []
    
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
    
    // 🌟 동기화 켜기/끄기 설정
    @AppStorage("isCloudSyncEnabled") var isCloudSyncEnabled: Bool = false {
        didSet {
            updateSnapshot()
            if isCloudSyncEnabled { syncToCloud() }
        }
    }
    @AppStorage("isHapticFeedbackEnabled") var isHapticFeedbackEnabled: Bool = false { didSet { updateSnapshot(); syncToCloud() } }
    @AppStorage("isSoundFeedbackEnabled") var isSoundFeedbackEnabled: Bool = false { didSet { updateSnapshot(); syncToCloud() } }
    @AppStorage("isAutoTypoCorrectionEnabled") var isAutoTypoCorrectionEnabled: Bool = false { didSet { updateSnapshot(); syncToCloud() } }
    
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
        
        isTypoCorrectionEnabled = d.object(forKey: "isTypoCorrectionEnabled") as? Bool ?? false
        typoKeyCode = UInt16(d.integer(forKey: "typoKeyCode"))
        typoModifierFlags = UInt64(d.integer(forKey: "typoModifierFlags"))
        typoDisplayString = d.string(forKey: "typoDisplayString") ?? ""
        isSentenceMode = d.object(forKey: "isSentenceMode") as? Bool ?? false
        
        updateSnapshot()
        
        // 🌟 iCloud 외부 변경 알림 구독 (다른 Mac에서 설정이 바뀌면 감지)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(icloudUpdateReceived(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: icloudStore
        )
        icloudStore.synchronize()
    }
    
    // 🌟 다른 기기에서 설정이 변경되어 iCloud를 통해 전달받았을 때
    @objc private func icloudUpdateReceived(_ notification: Notification) {
        guard isCloudSyncEnabled else { return }
        
        DispatchQueue.main.async {
            self.isBatchUpdating = true
            
            let dict = self.icloudStore.dictionaryRepresentation
            
            if let val = dict["showVisualFeedback"] as? Bool { self.showVisualFeedback = val }
            if let val = dict["isHyperKeyEnabled"] as? Bool { self.isHyperKeyEnabled = val }
            if let val = dict["isWindowMemoryEnabled"] as? Bool { self.isWindowMemoryEnabled = val }
            if let val = dict["isCursorHUDEnabled"] as? Bool { self.isCursorHUDEnabled = val }
            if let val = dict["isTypoCorrectionEnabled"] as? Bool { self.isTypoCorrectionEnabled = val }
            
            if let data = dict["excludedApps"] as? Data, let dec = try? JSONDecoder().decode([ExcludedApp].self, from: data) { self.excludedApps = dec }
            if let data = dict["customShortcuts"] as? Data, let dec = try? JSONDecoder().decode([CustomShortcut].self, from: data) { self.customShortcuts = dec }
            
            self.isBatchUpdating = false
            self.saveAll()
            self.updateSnapshot()
        }
    }
    
    // 🌟 현재 기기의 설정을 iCloud로 밀어넣기
    func syncToCloud() {
        guard isCloudSyncEnabled, !isBatchUpdating else { return }
        
        icloudStore.set(showVisualFeedback, forKey: "showVisualFeedback")
        icloudStore.set(isHyperKeyEnabled, forKey: "isHyperKeyEnabled")
        icloudStore.set(isWindowMemoryEnabled, forKey: "isWindowMemoryEnabled")
        icloudStore.set(isCursorHUDEnabled, forKey: "isCursorHUDEnabled")
        icloudStore.set(isTypoCorrectionEnabled, forKey: "isTypoCorrectionEnabled")
        icloudStore.set(isHapticFeedbackEnabled, forKey: "isHapticFeedbackEnabled")
        icloudStore.set(isSoundFeedbackEnabled, forKey: "isSoundFeedbackEnabled")
        icloudStore.set(isAutoTypoCorrectionEnabled, forKey: "isAutoTypoCorrectionEnabled") // 🌟 [추가]
        
        if let e = try? JSONEncoder().encode(excludedApps) { icloudStore.set(e, forKey: "excludedApps") }
        if let e = try? JSONEncoder().encode(customShortcuts) { icloudStore.set(e, forKey: "customShortcuts") }
        
        icloudStore.synchronize()
    }
    
    private func save(_ key: String, _ value: Any) {
        guard !isBatchUpdating else { return }
        UserDefaults.standard.set(value, forKey: key)
    }
    
    private func saveAll() {
        let d = UserDefaults.standard
        d.set(isCtrlActive, forKey: "isCtrlActive")
        d.set(isCmdActive, forKey: "isCmdActive")
        d.set(isOptActive, forKey: "isOptActive")
        d.set(ctrlLang, forKey: "ctrlLang")
        d.set(cmdLang, forKey: "cmdLang")
        d.set(optLang, forKey: "optLang")
        d.set(showVisualFeedback, forKey: "showVisualFeedback")
        d.set(isTestMode, forKey: "isTestMode")
        d.set(toggleKeyCode, forKey: "toggleKeyCode")
        d.set(toggleModifierFlags, forKey: "toggleModifierFlags")
        d.set(toggleDisplayString, forKey: "toggleDisplayString")
        if let e = try? JSONEncoder().encode(customShortcuts) { d.set(e, forKey: "customShortcuts") }
        if let e = try? JSONEncoder().encode(customApps) { d.set(e, forKey: "customApps") }
        if let e = try? JSONEncoder().encode(appLaunchShortcuts) { d.set(e, forKey: "appLaunchShortcuts") }
        if let e = try? JSONEncoder().encode(excludedApps) { d.set(e, forKey: "excludedApps") }
        d.set(isTypoCorrectionEnabled, forKey: "isTypoCorrectionEnabled")
        d.set(typoKeyCode, forKey: "typoKeyCode")
        d.set(typoModifierFlags, forKey: "typoModifierFlags")
        d.set(typoDisplayString, forKey: "typoDisplayString")
        d.set(isSentenceMode, forKey: "isSentenceMode")
    }
    
    func addLog(_ log: ActionLog) {
        DispatchQueue.main.async {
            self.recentLogs.insert(log, at: 0)
            
            while self.recentLogs.count > 50 {
                self.recentLogs.removeLast()
            }
        }
    }
    
    func exportBackup(to url: URL) throws {
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
            isExcludedAppsEnabled: isExcludedAppsEnabled
        )
        let encoder = JSONEncoder(); encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(backup); try data.write(to: url)
    }
    
    func importBackup(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let backup = try JSONDecoder().decode(BackupData.self, from: data)
        
        DispatchQueue.main.async {
            self.isBatchUpdating = true
            
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
            
            self.isExcludedAppsEnabled = backup.isExcludedAppsEnabled ?? true
            
            self.isBatchUpdating = false
            self.saveAll()
            self.updateSnapshot()
        }
    }
}
