//
//  SettingsManager.swift
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
import Combine
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AppIntents

extension Notification.Name {
    static let profileDidSwitch = Notification.Name("LangSwitcherProfileDidSwitch")
}

@MainActor
class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    let currentSettingsVersion = "1.0.0"
    
    let icloudStore = NSUbiquitousKeyValueStore.default
    private var _snapshot = SettingsSnapshot(isTextExpansionEnabled: false, textExpansionRules: [])
    private var saveWorkItem: DispatchWorkItem?
    
    private let maxLogCount = 500
    private var logBufferThreshold: Int { maxLogCount + 50 }
    
    @Published var selectedTab: SettingsTab? = .general
    @MainActor var isBatchUpdating: Bool = false
    
    // 🌟 [교정] 중복 선언되었던 recentLogs를 한 곳으로 깔끔하게 통합했습니다.
    @Published private(set) var recentLogs: [ActionLog] = []
    
    // 딕셔너리 캐시는 전역으로 관리하되, 활성 프로필 데이터를 굽습니다.
    private(set) var customShortcutCache: [ShortcutKey: CustomShortcut] = [:]
    private(set) var appLaunchShortcutCache: [ShortcutKey: AppLaunchShortcut] = [:]

    // MARK: - Global Settings (전역 설정)
    
    @Published var isCtrlActive: Bool {
        didSet {
            save("isCtrlActive", isCtrlActive)
            guard !isBatchUpdating else { return } // 🌟 방어벽
            scheduleSave()
        }
    }
    
    @Published var isCmdActive: Bool {
        didSet {
            save("isCmdActive", isCmdActive)
            guard !isBatchUpdating else { return } // 🌟 방어벽
            scheduleSave()
        }
    }
    @Published var isOptActive: Bool { didSet { save("isOptActive", isOptActive); scheduleSave() } }
    @Published var ctrlLang: String { didSet { save("ctrlLang", ctrlLang); scheduleSave() } }
    @Published var cmdLang: String { didSet { save("cmdLang", cmdLang); scheduleSave() } }
    @Published var optLang: String { didSet { save("optLang", optLang); scheduleSave() } }
        
    @Published var showVisualFeedback: Bool { didSet { save("showVisualFeedback", showVisualFeedback); scheduleSave() } }
    @Published var isTestMode: Bool { didSet { save("isTestMode", isTestMode); updateSnapshot() } }
    
    @Published var toggleKeyCode: UInt16 {
        didSet {
            save("toggleKeyCode", toggleKeyCode)
            guard !isBatchUpdating else { return } // 🌟 방어벽
            updateSnapshot()
        }
    }
    @Published var toggleModifierFlags: UInt64 { didSet { save("toggleModifierFlags", toggleModifierFlags); updateSnapshot() } }
    @Published var toggleDisplayString: String { didSet { save("toggleDisplayString", toggleDisplayString); updateSnapshot() } }

    @AppStorage("isHyperKeyEnabled") var isHyperKeyEnabled: Bool = false {
        didSet {
            HyperKeyManager.shared.updateState(isEnabled: isHyperKeyEnabled)
            guard !isBatchUpdating else { return } // 🌟 방어벽
            updateSnapshot()
            syncToCloud()
        }
    }
    
    @AppStorage("isCustomShortcutsEnabled") var isCustomShortcutsEnabled: Bool = true { didSet { updateSnapshot() } }
    @AppStorage("isAppLaunchEnabled") var isAppLaunchEnabled: Bool = true { didSet { updateSnapshot() } }
    @AppStorage("isExcludedAppsEnabled") var isExcludedAppsEnabled: Bool = true { didSet { updateSnapshot() } }
    
    @AppStorage("isWindowMemoryEnabled") var isWindowMemoryEnabled: Bool = false { didSet { updateSnapshot(); syncToCloud() } }
    @AppStorage("isWindowMemoryCleanupEnabled") var isWindowMemoryCleanupEnabled: Bool = true { didSet { updateSnapshot(); syncToCloud() } }
    @AppStorage("isCursorHUDEnabled") var isCursorHUDEnabled: Bool = true { didSet { updateSnapshot(); syncToCloud() } }
    
    @AppStorage("isCloudSyncEnabled") var isCloudSyncEnabled: Bool = false {
        didSet { updateSnapshot(); if isCloudSyncEnabled { syncToCloud() } }
    }
    @AppStorage("isHapticFeedbackEnabled") var isHapticFeedbackEnabled: Bool = false { didSet { updateSnapshot(); syncToCloud() } }
    @AppStorage("isSoundFeedbackEnabled") var isSoundFeedbackEnabled: Bool = false { didSet { updateSnapshot(); syncToCloud() } }
    @AppStorage("isEdgeGlowEnabled") var isEdgeGlowEnabled: Bool = false { didSet { updateSnapshot(); syncToCloud() } }
    @AppStorage("isBrowserTabMemoryEnabled") var isBrowserTabMemoryEnabled: Bool = false { didSet { updateSnapshot(); syncToCloud() } }
    @AppStorage("newTabDefaultLanguage") var newTabDefaultLanguage: String = "None" { didSet { updateSnapshot(); syncToCloud() } }
    

    // MARK: - Profile Management State (프로필 관리 상태)
    
    @Published var profiles: [SettingsProfile] = [] {
        didSet {
            if !isBatchUpdating { scheduleSave() }
        }
    }
    
    @Published var activeProfileID: UUID {
        didSet {
            guard oldValue != activeProfileID else { return }
            
            applyActiveProfile()
            NotificationCenter.default.post(name: .profileDidSwitch, object: nil)
            
            DispatchQueue.main.async {
                self.saveAll()
                self.syncToCloud()
                
                if #available(macOS 13.0, *) {
                    Task {
                        LangSwitcherShortcuts.updateAppShortcutParameters()
                    }
                }
            }
            
            dprint("🔄 [Profile Switched] Engine reloaded with profile: \(self.activeProfile.name)")
        }
    }
    
    var activeProfile: SettingsProfile {
        get {
            profiles.first(where: { $0.id == activeProfileID }) ?? profiles.first!
        }
        set {
            if let index = profiles.firstIndex(where: { $0.id == activeProfileID }) {
                profiles[index] = newValue
            }
        }
    }
    
    private init() {
        self.isBatchUpdating = true
        let d = UserDefaults.standard
        
        isCtrlActive = d.bool(forKey: "isCtrlActive"); isCmdActive = d.bool(forKey: "isCmdActive"); isOptActive = d.bool(forKey: "isOptActive")
        showVisualFeedback = d.object(forKey: "showVisualFeedback") as? Bool ?? true; isTestMode = d.bool(forKey: "isTestMode")
        toggleKeyCode = UInt16(d.integer(forKey: "toggleKeyCode"))
        toggleModifierFlags = UInt64(d.integer(forKey: "toggleModifierFlags"))
        toggleDisplayString = d.string(forKey: "toggleDisplayString") ?? ""
        ctrlLang = d.string(forKey: "ctrlLang") ?? ""; cmdLang = d.string(forKey: "cmdLang") ?? ""; optLang = d.string(forKey: "optLang") ?? ""
        
        var tempProfiles: [SettingsProfile] = []
        
        if let data = d.data(forKey: "profiles"), let dec = try? JSONDecoder().decode([SettingsProfile].self, from: data), !dec.isEmpty {
            tempProfiles = dec
        } else {
            var migratedPayload = ProfileSettingsPayload()
            
            if let data = d.data(forKey: "customShortcuts"), let dec = try? JSONDecoder().decode([CustomShortcut].self, from: data) { migratedPayload.customShortcuts = dec }
            if let data = d.data(forKey: "appLaunchShortcuts"), let dec = try? JSONDecoder().decode([AppLaunchShortcut].self, from: data) { migratedPayload.appLaunchShortcuts = dec }
            if let data = d.data(forKey: "customApps"), let dec = try? JSONDecoder().decode([CustomApp].self, from: data) { migratedPayload.customApps = dec }
            if let data = d.data(forKey: "excludedApps"), let dec = try? JSONDecoder().decode([ExcludedApp].self, from: data) { migratedPayload.excludedApps = dec }
            if let data = d.data(forKey: "domainRules"), let dec = try? JSONDecoder().decode([DomainRule].self, from: data) { migratedPayload.domainRules = dec }
            if let data = d.data(forKey: "appDelays"), let dec = try? JSONDecoder().decode([AppDelay].self, from: data) { migratedPayload.appDelays = dec }
            
            if let data = d.data(forKey: "textExpansionRules"), let dec = try? JSONDecoder().decode([TextExpansionRule].self, from: data) {
                migratedPayload.textExpansionRules = dec
            } else {
                migratedPayload.textExpansionRules = [
                    TextExpansionRule(id: UUID(), trigger: ";date", replacement: "{{date:yyyy-MM-dd}}", isEnabled: true),
                    TextExpansionRule(id: UUID(), trigger: ";time", replacement: "{{time:HH:mm}}", isEnabled: true),
                    TextExpansionRule(id: UUID(), trigger: ";clip", replacement: "{{clipboard}}", isEnabled: true),
                    TextExpansionRule(id: UUID(), trigger: ";info", replacement: "{{date:yyyy-MM-dd}} {{time:HH:mm}} | {{clipboard}}", isEnabled: true),
                    TextExpansionRule(id: UUID(), trigger: ";hello", replacement: "Hello {{cursor}} World", isEnabled: true)
                ]
            }
            
            migratedPayload.isTextExpansionEnabled = d.bool(forKey: "isTextExpansionEnabled")
            migratedPayload.isTypoCorrectionEnabled = d.object(forKey: "isTypoCorrectionEnabled") as? Bool ?? false
            migratedPayload.typoKeyCode = UInt16(d.integer(forKey: "typoKeyCode"))
            migratedPayload.typoModifierFlags = UInt64(d.integer(forKey: "typoModifierFlags"))
            migratedPayload.typoDisplayString = d.string(forKey: "typoDisplayString") ?? ""
            migratedPayload.isSentenceMode = d.object(forKey: "isSentenceMode") as? Bool ?? false
            migratedPayload.isAutoTypoCorrectionEnabled = d.bool(forKey: "isAutoTypoCorrectionEnabled")
            migratedPayload.isAutoTypoCorrectionOnEnterEnabled = d.bool(forKey: "isAutoTypoCorrectionOnEnterEnabled")
            migratedPayload.isAppSpecificEnabled = d.bool(forKey: "isAppSpecificEnabled")
            migratedPayload.isBrowserDomainModeEnabled = d.bool(forKey: "isBrowserDomainModeEnabled")
            
            let defaultProfile = SettingsProfile(
                id: UUID(), name: String(localized: "Default Profile"), note: String(localized: "Basic configuration"),
                isDefault: true, createdAt: Date(), updatedAt: Date(), payload: migratedPayload
            )
            tempProfiles = [defaultProfile]
        }
        
        var tempActiveID = tempProfiles.first!.id
        if let savedIDString = d.string(forKey: "activeProfileID"), let savedID = UUID(uuidString: savedIDString), tempProfiles.contains(where: { $0.id == savedID }) {
            tempActiveID = savedID
        }
        
        self.profiles = tempProfiles
        self.activeProfileID = tempActiveID
        
        applyActiveProfile()
        
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
        let profilesToSave = self.profiles
        DispatchQueue.global(qos: .background).async {
            if let e = try? JSONEncoder().encode(profilesToSave) {
                UserDefaults.standard.set(e, forKey: "profiles")
            }
        }
        dprint("SettingsManager: 프로필 데이터가 디스크에 저장되었습니다.")
    }
    
    func applyActiveProfile() {
        self.isBatchUpdating = true
        
        defer {
            self.isBatchUpdating = false
            self.updateSnapshot()
        }
        
        let payload = activeProfile.payload
        DomainRuleManager.shared.rules = payload.domainRules
        updateShortcutCaches()
        
        let log = ActionLog(timestamp: Date(), targetApp: "LangSwitcher", appliedRule: "Profile Switched", finalInputSource: "Active Profile: \(activeProfile.name)", result: .success, failureReason: .none)
        addLog(log)
            
        dprint("🔄 [Profile Switched] Engine reloaded with profile: \(self.activeProfile.name)")
    }
    
    var snapshot: SettingsSnapshot {
        _snapshot
    }
        
    @MainActor
    func updateSnapshot() {
        let payload = activeProfile.payload
        
        var newSnapshot = SettingsSnapshot(
            isCtrlActive: isCtrlActive, isCmdActive: isCmdActive, isOptActive: isOptActive,
            ctrlLang: ctrlLang, cmdLang: cmdLang, optLang: optLang,
            showVisualFeedback: showVisualFeedback, isTestMode: isTestMode,
            toggleKeyCode: toggleKeyCode, toggleModifierFlags: toggleModifierFlags, toggleDisplayString: toggleDisplayString,
            isSentenceMode: payload.isSentenceMode,
            isHyperKeyEnabled: isHyperKeyEnabled,
            isAppLaunchEnabled: isAppLaunchEnabled, isCustomShortcutsEnabled: isCustomShortcutsEnabled,
            isExcludedAppsEnabled: isExcludedAppsEnabled,
            isAppSpecificEnabled: payload.isAppSpecificEnabled,
            isWindowMemoryEnabled: isWindowMemoryEnabled,
            isWindowMemoryCleanupEnabled: isWindowMemoryCleanupEnabled,
            isCursorHUDEnabled: isCursorHUDEnabled,
            isCloudSyncEnabled: isCloudSyncEnabled,
            isHapticFeedbackEnabled: isHapticFeedbackEnabled,
            isSoundFeedbackEnabled: isSoundFeedbackEnabled,
            isAutoTypoCorrectionEnabled: payload.isAutoTypoCorrectionEnabled,
            isEdgeGlowEnabled: isEdgeGlowEnabled,
            isAutoTypoCorrectionOnEnterEnabled: payload.isAutoTypoCorrectionOnEnterEnabled,
            isBrowserTabMemoryEnabled: isBrowserTabMemoryEnabled,
            isBrowserDomainModeEnabled: payload.isBrowserDomainModeEnabled,
            newTabDefaultLanguage: newTabDefaultLanguage,
            isTypoCorrectionEnabled: payload.isTypoCorrectionEnabled,
            typoKeyCode: payload.typoKeyCode, typoModifierFlags: payload.typoModifierFlags, typoDisplayString: payload.typoDisplayString,
            customApps: payload.customApps,
            appLaunchShortcuts: payload.appLaunchShortcuts,
            excludedApps: payload.excludedApps,
            customShortcuts: payload.customShortcuts,
            domainRules: payload.domainRules,
            appDelays: payload.appDelays,
            isTextExpansionEnabled: payload.isTextExpansionEnabled,
            textExpansionRules: payload.textExpansionRules
        )
        
        newSnapshot.buildCaches()
        
        EventMonitor.shared.updateSettingsSnapshot(newSnapshot)
        self._snapshot = newSnapshot
    }
    
    // MARK: - 고성능 로그 주입 아키텍처
    func addLog(_ log: ActionLog) {
        // 1. 맨 뒤에 붙이기는 언제나 비용이 없는 O(1)
        self.recentLogs.append(log)
        
        // 2. 매번 지우지 않고 임계값(550개)에 도달했을 때만 50개를 일괄 청소
        if self.recentLogs.count > logBufferThreshold {
            let overflowCount = self.recentLogs.count - maxLogCount
            
            // 550번 타건할 때 딱 1번만 메모리 시프팅을 집행하므로,
            // 수학적 분할상환(Amortized) 성능은 완벽하게 O(1)에 수렴합니다.
            self.recentLogs.removeFirst(overflowCount)
        }
    }
    
    func scheduleSave() {
        saveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.saveAll()
            DispatchQueue.main.async {
                self.updateSnapshot()
                if !self.isBatchUpdating { self.syncToCloud() }
                
                if #available(macOS 13.0, *) {
                    Task {
                        LangSwitcherShortcuts.updateAppShortcutParameters()
                    }
                }
            }
        }
        saveWorkItem = workItem
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }
    
    private func updateShortcutCaches() {
        let payload = activeProfile.payload
        customShortcutCache.removeAll()
        for shortcut in payload.customShortcuts {
            customShortcutCache[ShortcutKey(keyCode: shortcut.keyCode, modifiers: shortcut.modifierFlags)] = shortcut
        }
        appLaunchShortcutCache.removeAll()
        for shortcut in payload.appLaunchShortcuts {
            appLaunchShortcutCache[ShortcutKey(keyCode: shortcut.keyCode, modifiers: shortcut.modifierFlags)] = shortcut
        }
    }
    
    @MainActor
    func restoreDefaultAppDelays() {
        var profile = activeProfile
        profile.payload.appDelays = [
            AppDelay(bundleIdentifier: "com.microsoft.VSCode", appName: "Visual Studio Code", delay: 0.7),
            AppDelay(bundleIdentifier: "com.tinyspeck.slackmacgap", appName: "Slack", delay: 0.6),
            AppDelay(bundleIdentifier: "com.hnc.Discord", appName: "Discord", delay: 0.6),
            AppDelay(bundleIdentifier: "notion.id", appName: "Notion", delay: 0.6),
            AppDelay(bundleIdentifier: "md.obsidian", appName: "Obsidian", delay: 0.5),
            AppDelay(bundleIdentifier: "com.google.Chrome", appName: "Google Chrome", delay: 0.4)
        ]
        activeProfile = profile
    }
    
    // MARK: - Text Expansion Only Backup/Restore
    func exportTextExpansionRules(to url: URL, completion: @escaping (Bool, Error?) -> Void = { _, _ in }) {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(activeProfile.payload.textExpansionRules)
            DispatchQueue.global(qos: .userInitiated).async {
                do { try data.write(to: url); DispatchQueue.main.async { completion(true, nil) } } catch { DispatchQueue.main.async { completion(false, error) } }
            }
        } catch { completion(false, error) }
    }

    func importTextExpansionRules(from url: URL, completion: @escaping (Bool, Error?) -> Void = { _, _ in }) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let data = try Data(contentsOf: url)
                DispatchQueue.main.async {
                    do {
                        let importedRules = try JSONDecoder().decode([TextExpansionRule].self, from: data)
                        var profile = self.activeProfile
                        for rule in importedRules {
                            if !profile.payload.textExpansionRules.contains(where: { $0.trigger == rule.trigger }) {
                                profile.payload.textExpansionRules.append(rule)
                            }
                        }
                        self.activeProfile = profile
                        completion(true, nil)
                    } catch { completion(false, error) }
                }
            } catch { DispatchQueue.main.async { completion(false, error) } }
        }
    }
    
    func exportProfiles() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        savePanel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        savePanel.nameFieldStringValue = "LangSwitcher_Profiles_Backup.json"
        savePanel.title = String(localized: "Export Profiles Backup")
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                do {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = .prettyPrinted
                    let data = try encoder.encode(self.profiles)
                    
                    try data.write(to: url)
                    dprint("✅ Profiles successfully exported to \(url.lastPathComponent)")
                } catch {
                    dprint("❌ Failed to export profiles: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func importProfiles() {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.json]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        openPanel.title = String(localized: "Import Profiles Backup")
        
        openPanel.begin { response in
            if response == .OK, let url = openPanel.url {
                do {
                    let data = try Data(contentsOf: url)
                    let decoder = JSONDecoder()
                    let importedProfiles = try decoder.decode([SettingsProfile].self, from: data)
                    
                    guard !importedProfiles.isEmpty else {
                        DispatchQueue.main.async {
                            let alert = NSAlert()
                            alert.messageText = String(localized: "Import Failed")
                            alert.informativeText = String(localized: "The selected backup file is empty or contains no valid profiles.")
                            alert.alertStyle = .warning
                            NSApp.activate(ignoringOtherApps: true)
                            alert.runModal()
                        }
                        return
                    }
                    
                    DispatchQueue.main.async {
                        self.profiles = importedProfiles
                        if let firstProfile = importedProfiles.first {
                            self.activeProfileID = firstProfile.id
                        }
                        
                        let alert = NSAlert()
                        alert.messageText = String(localized: "Profiles Restore Successful")
                        alert.informativeText = String(localized: "Your profiles and settings have been imported successfully.")
                        if let appIcon = NSImage(named: NSImage.applicationIconName) {
                            alert.icon = appIcon
                        }
                        NSApp.activate(ignoringOtherApps: true)
                        alert.runModal()
                    }
                    dprint("✅ Profiles successfully imported from \(url.lastPathComponent)")
                    
                } catch {
                    dprint("❌ Failed to import profiles: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        let alert = NSAlert()
                        alert.messageText = String(localized: "Import Failed")
                        alert.informativeText = String(localized: "Failed to read the backup file. It might be corrupted or in an unsupported format.\n\nError: \(error.localizedDescription)")
                        alert.alertStyle = .critical
                        NSApp.activate(ignoringOtherApps: true)
                        alert.runModal()
                    }
                }
            }
        }
    }
    
    func clearLogs() {
        self.recentLogs.removeAll(keepingCapacity: false)
    }
}
