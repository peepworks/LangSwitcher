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

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    let currentSettingsVersion = "1.0.0"
    
    let icloudStore = NSUbiquitousKeyValueStore.default
    private let snapshotQueue = DispatchQueue(label: "com.peepworks.settings.snapshot", attributes: .concurrent)
    private var _snapshot = SettingsSnapshot()
    private var saveWorkItem: DispatchWorkItem?
    
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
    
    @Published var customShortcuts: [CustomShortcut] = [] { didSet { scheduleSave() } }
    @Published var customApps: [CustomApp] = [] { didSet { scheduleSave() } }
    @Published var appLaunchShortcuts: [AppLaunchShortcut] = [] { didSet { scheduleSave() } }
    @Published var excludedApps: [ExcludedApp] = [] { didSet { scheduleSave() } }
    
    // 🌟 앱 딜레이 배열 (추가 완료)
    @Published var appDelays: [AppDelay] = [] { didSet { scheduleSave() } }
    
    @Published var domainRules: [DomainRule] = [] {
        didSet {
            scheduleSave()
            DomainRuleManager.shared.rules = domainRules
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
    @AppStorage("newTabDefaultLanguage") var newTabDefaultLanguage: String = "None" { didSet { updateSnapshot(); syncToCloud() } }
    
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
        
        if let data = d.data(forKey: "domainRules"), let dec = try? JSONDecoder().decode([DomainRule].self, from: data) {
            domainRules = dec
            DomainRuleManager.shared.rules = dec
        }
        
        // 🌟 앱 딜레이 기본값 할당 (추가 완료)
        if let data = d.data(forKey: "appDelays"), let dec = try? JSONDecoder().decode([AppDelay].self, from: data) {
            appDelays = dec
        } else {
            appDelays = [
                AppDelay(bundleIdentifier: "com.microsoft.VSCode", appName: "Visual Studio Code", delay: 0.7),
                AppDelay(bundleIdentifier: "com.tinyspeck.slackmacgap", appName: "Slack", delay: 0.6),
                AppDelay(bundleIdentifier: "com.hnc.Discord", appName: "Discord", delay: 0.6),
                AppDelay(bundleIdentifier: "notion.id", appName: "Notion", delay: 0.6),
                AppDelay(bundleIdentifier: "md.obsidian", appName: "Obsidian", delay: 0.5),
                AppDelay(bundleIdentifier: "com.google.Chrome", appName: "Google Chrome", delay: 0.4)
            ]
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
    
    
    
    private func save(_ key: String, _ value: Any) {
        UserDefaults.standard.set(value, forKey: key)
    }
    
    func saveAll() {
        let d = UserDefaults.standard
        if let e = try? JSONEncoder().encode(customShortcuts) { d.set(e, forKey: "customShortcuts") }
        if let e = try? JSONEncoder().encode(customApps) { d.set(e, forKey: "customApps") }
        if let e = try? JSONEncoder().encode(appLaunchShortcuts) { d.set(e, forKey: "appLaunchShortcuts") }
        if let e = try? JSONEncoder().encode(excludedApps) { d.set(e, forKey: "excludedApps") }
        if let e = try? JSONEncoder().encode(domainRules) { d.set(e, forKey: "domainRules") }
        if let e = try? JSONEncoder().encode(appDelays) { d.set(e, forKey: "appDelays") } // 🌟 추가
    }
    
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
            isTypoCorrectionEnabled: isTypoCorrectionEnabled,
            typoKeyCode: typoKeyCode, typoModifierFlags: typoModifierFlags, typoDisplayString: typoDisplayString,
            customApps: customApps,
            appLaunchShortcuts: appLaunchShortcuts,
            excludedApps: excludedApps,
            customShortcuts: customShortcuts,
            domainRules: domainRules,
            appDelays: appDelays // 🌟 추가 완료
        )
        
        EventMonitor.shared.updateSettingsSnapshot(newSnapshot)
        snapshotQueue.async(flags: .barrier) { self._snapshot = newSnapshot }
    }
    
    func addLog(_ log: ActionLog) {
        DispatchQueue.main.async {
            self.recentLogs.insert(log, at: 0)
            while self.recentLogs.count > 50 {
                self.recentLogs.removeLast()
            }
        }
    }
    
    private func scheduleSave() {
        saveWorkItem?.cancel()
        
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.performActualSave()
            DispatchQueue.main.async {
                self.updateSnapshot()
                if !self.isBatchUpdating { self.syncToCloud() }
            }
        }
        
        saveWorkItem = workItem
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }
    
    private func performActualSave() {
        self.saveAll()
        #if DEBUG
        print("SettingsManager: 배열 데이터들이 디바운스 처리되어 한 번에 디스크에 저장되었습니다.")
        #endif
    }
    
    // MARK: - Cache & Memory Management    
    // SettingsManager.swift 클래스 내부에 추가
    
    // 🌟 [추가됨] 앱별 딜레이 기본값 복원 함수
    @MainActor
    func restoreDefaultAppDelays() {
        self.appDelays = [
            AppDelay(bundleIdentifier: "com.microsoft.VSCode", appName: "Visual Studio Code", delay: 0.7),
            AppDelay(bundleIdentifier: "com.tinyspeck.slackmacgap", appName: "Slack", delay: 0.6),
            AppDelay(bundleIdentifier: "com.hnc.Discord", appName: "Discord", delay: 0.6),
            AppDelay(bundleIdentifier: "notion.id", appName: "Notion", delay: 0.6),
            AppDelay(bundleIdentifier: "md.obsidian", appName: "Obsidian", delay: 0.5),
            AppDelay(bundleIdentifier: "com.google.Chrome", appName: "Google Chrome", delay: 0.4)
        ]
        
        #if DEBUG
        print("SettingsManager: App delays restored to defaults.")
        #endif
    }
}
