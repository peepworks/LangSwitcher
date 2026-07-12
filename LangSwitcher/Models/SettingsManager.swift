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
    
    nonisolated private static let profileEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        return encoder
    } ()
    nonisolated private static let profileDecoder = JSONDecoder()
    
    let icloudStore = NSUbiquitousKeyValueStore.default
    private var _snapshot = SettingsSnapshot(isTextExpansionEnabled: false, textExpansionRules: [])
    
    private var saveTask: Task<Void, Never>?
    nonisolated private let saveQueue = DispatchQueue(label: "com.peepworks.langswitcher.save", qos: .background)
    
    private let maxLogCount = 500
    private let logTrimBuffer = 50

    private var logTrimThreshold: Int { maxLogCount + logTrimBuffer }
    
    @Published var selectedTab: SettingsTab? = .general
    @MainActor var isBatchUpdating: Bool = false
    
    @Published private(set) var recentLogs: [ActionLog] = []
    
    private(set) var customShortcutCache: [ShortcutKey: CustomShortcut] = [:]
    private(set) var appLaunchShortcutCache: [ShortcutKey: AppLaunchShortcut] = [:]
 
    private var applicationSupportDirectoryURL: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("LangSwitcher", isDirectory: true)
    }

    private var profilesFileURL: URL {
        return applicationSupportDirectoryURL.appendingPathComponent("profiles.json")
    }

    // MARK: - Global Settings
    
    @Published var isCtrlActive: Bool {
        didSet {
            save("isCtrlActive", isCtrlActive)
            guard !isBatchUpdating else { return }
            scheduleSave()
        }
    }
    
    @Published var isCmdActive: Bool {
        didSet {
            save("isCmdActive", isCmdActive)
            guard !isBatchUpdating else { return }
            scheduleSave()
        }
    }
    @Published var isOptActive: Bool {
        didSet {
            save("isOptActive", isOptActive)
            guard !isBatchUpdating else { return }
            scheduleSave()
        }
    }
    
    @Published var ctrlLang: String {
        didSet {
            save("ctrlLang", ctrlLang)
            guard !isBatchUpdating else { return }
            scheduleSave()
        }
    }
    
    @Published var cmdLang: String {
        didSet {
            save("cmdLang", cmdLang)
            guard !isBatchUpdating else { return }
            scheduleSave()
        }
    }
    
    @Published var optLang: String {
        didSet {
            save("optLang", optLang)
            guard !isBatchUpdating else { return }
            scheduleSave()
        }
    }
        
    @Published var showVisualFeedback: Bool {
        didSet {
            save("showVisualFeedback", showVisualFeedback)
            guard !isBatchUpdating else { return }
            scheduleSave()
        }
    }
    
    @Published var isTestMode: Bool {
        didSet {
            save("isTestMode", isTestMode)
            guard !isBatchUpdating else { return }
            updateSnapshot()
        }
    }
    
    @Published var toggleKeyCode: UInt16 {
        didSet {
            save("toggleKeyCode", toggleKeyCode)
            guard !isBatchUpdating else { return }
            updateSnapshot()
        }
    }
    @Published var toggleModifierFlags: UInt64 {
        didSet {
            save("toggleModifierFlags", toggleModifierFlags)
            guard !isBatchUpdating else { return }
            updateSnapshot()
        }
    }
    
    @Published var toggleDisplayString: String {
        didSet {
            save("toggleDisplayString", toggleDisplayString)
            guard !isBatchUpdating else { return }
            updateSnapshot()
        }
    }

    @AppStorage("isHyperKeyEnabled") var isHyperKeyEnabled: Bool = false {
        didSet {
            HyperKeyManager.shared.updateState(isEnabled: isHyperKeyEnabled)
            guard !isBatchUpdating else { return }
            updateSnapshot()
            syncToCloud()
        }
    }
    
    @AppStorage("isCustomShortcutsEnabled") var isCustomShortcutsEnabled: Bool = true {
        didSet {
            guard !isBatchUpdating else { return }
            updateSnapshot()
        }
    }
    @AppStorage("isAppLaunchEnabled") var isAppLaunchEnabled: Bool = true {
        didSet {
            guard !isBatchUpdating else { return }
            updateSnapshot()
        }
    }
    @AppStorage("isExcludedAppsEnabled") var isExcludedAppsEnabled: Bool = true {
        didSet {
            guard !isBatchUpdating else { return }
            updateSnapshot()
        }
    }
    
    @AppStorage("isWindowMemoryEnabled") var isWindowMemoryEnabled: Bool = false {
        didSet {
            guard !isBatchUpdating else { return }
            updateSnapshot()
            syncToCloud()
        }
    }
    @AppStorage("isWindowMemoryCleanupEnabled") var isWindowMemoryCleanupEnabled: Bool = true {
        didSet {
            guard !isBatchUpdating else { return }
            updateSnapshot()
            syncToCloud()
        }
    }
    @AppStorage("isCursorHUDEnabled") var isCursorHUDEnabled: Bool = true {
        didSet {
            guard !isBatchUpdating else { return }
            updateSnapshot()
            syncToCloud()
        }
    }
    
    @AppStorage("isCloudSyncEnabled") var isCloudSyncEnabled: Bool = false {
        didSet {
            guard !isBatchUpdating else { return }
            updateSnapshot()
            if isCloudSyncEnabled { syncToCloud() }
        }
    }
    @AppStorage("isHapticFeedbackEnabled") var isHapticFeedbackEnabled: Bool = false {
        didSet {
            guard !isBatchUpdating else { return }
            updateSnapshot()
            syncToCloud()
        }
    }
    @AppStorage("isSoundFeedbackEnabled") var isSoundFeedbackEnabled: Bool = false {
        didSet {
            guard !isBatchUpdating else { return }
            updateSnapshot()
            syncToCloud()
        }
    }
    @AppStorage("isEdgeGlowEnabled") var isEdgeGlowEnabled: Bool = false {
        didSet {
            guard !isBatchUpdating else { return }
            updateSnapshot()
            syncToCloud()
        }
    }
    @AppStorage("isBrowserTabMemoryEnabled") var isBrowserTabMemoryEnabled: Bool = false {
        didSet {
            guard !isBatchUpdating else { return }
            updateSnapshot()
            syncToCloud()
        }
    }
    @AppStorage("newTabDefaultLanguage") var newTabDefaultLanguage: String = "None" {
        didSet {
            guard !isBatchUpdating else { return }
            updateSnapshot()
            syncToCloud()
        }
    }

    // MARK: - Profile Management State
    
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

            Task { @MainActor in
                await self.saveAll()
                self.syncToCloud()
                
                if #available(macOS 13.0, *) {
                    LangSwitcherShortcuts.updateAppShortcutParameters()
                }
            }
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
        let fileManager = FileManager.default
        
        isCtrlActive = d.bool(forKey: "isCtrlActive")
        isCmdActive = d.bool(forKey: "isCmdActive")
        isOptActive = d.bool(forKey: "isOptActive")
        showVisualFeedback = d.object(forKey: "showVisualFeedback") as? Bool ?? true
        isTestMode = d.bool(forKey: "isTestMode")
        toggleKeyCode = UInt16(d.integer(forKey: "toggleKeyCode"))
        toggleModifierFlags = UInt64(d.integer(forKey: "toggleModifierFlags"))
        toggleDisplayString = d.string(forKey: "toggleDisplayString") ?? ""
        ctrlLang = d.string(forKey: "ctrlLang") ?? ""
        cmdLang = d.string(forKey: "cmdLang") ?? ""
        optLang = d.string(forKey: "optLang") ?? ""
        
        let appSupportPaths = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let localProfilesFileURL = appSupportPaths[0]
            .appendingPathComponent("LangSwitcher", isDirectory: true)
            .appendingPathComponent("profiles.json")
        
        var needsMigration = false
        var tempProfiles: [SettingsProfile] = []
        
        if fileManager.fileExists(atPath: localProfilesFileURL.path),
           let data = try? Data(contentsOf: localProfilesFileURL),
           let dec = try? JSONDecoder().decode([SettingsProfile].self, from: data), !dec.isEmpty {
            tempProfiles = dec
        } else if let legacyData = d.data(forKey: "profiles"),
                  let dec = try? JSONDecoder().decode([SettingsProfile].self, from: legacyData), !dec.isEmpty {
            tempProfiles = dec
            needsMigration = true
        } else {
            var migratedPayload = ProfileSettingsPayload()
            
            if let data = d.data(forKey: "customShortcuts"), let dec = try? JSONDecoder().decode([CustomShortcut].self, from: data) { migratedPayload.customShortcuts = dec }
            if let data = d.data(forKey: "appLaunchShortcuts"), let dec = try? JSONDecoder().decode([AppLaunchShortcut].self, from: data) { migratedPayload.appLaunchShortcuts = dec }
            if let data = d.data(forKey: "customApps"), let dec = try? JSONDecoder().decode([CustomApp].self, from: data) { migratedPayload.customApps = dec }
            if let data = d.data(forKey: "excludedApps"), let dec = try? JSONDecoder().decode([ExcludedApp].self, from: data) { migratedPayload.excludedApps = dec }
            if let data = d.data(forKey: "domainRules"), let dec = try? JSONDecoder().decode([DomainRule].self, from: data) { migratedPayload.domainRules = dec }
            if let data = d.data(forKey: "appDelays"), let dec = try? JSONDecoder().decode([AppDelay].self, from: data) { migratedPayload.appDelays = dec }
            
            migratedPayload.textExpansionRules = [
                TextExpansionRule(id: UUID(), trigger: ";date", replacement: "{{date:yyyy-MM-dd}}", isEnabled: true),
                TextExpansionRule(id: UUID(), trigger: ";time", replacement: "{{time:HH:mm}}", isEnabled: true),
                TextExpansionRule(id: UUID(), trigger: ";clip", replacement: "{{clipboard}}", isEnabled: true),
                TextExpansionRule(id: UUID(), trigger: ";info", replacement: "{{date:yyyy-MM-dd}} {{time:HH:mm}} | {{clipboard}}", isEnabled: true),
                TextExpansionRule(id: UUID(), trigger: ";hello", replacement: "Hello {{cursor}} World", isEnabled: true)
            ]
            
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

            // 🌟 이 위치에서 구조체 생성이 모호해지지 않도록 명확히 파라미터 매핑을 확약합니다.
            migratedPayload.typoExcludedWords = TypoExceptionManager.shared.excludedWords

            let defaultProfile = SettingsProfile(
                id: UUID(),
                name: String(localized: "Default Profile"),
                note: String(localized: "Basic configuration"),
                isDefault: true,
                createdAt: Date(),
                updatedAt: Date(),
                payload: migratedPayload // 🌟 모델의 Payload와 일대일 매칭 보장
            )
            tempProfiles = [defaultProfile]
            needsMigration = true
        }
        
        var tempActiveID = tempProfiles.first!.id
        if let savedIDString = d.string(forKey: "activeProfileID"),
           let savedID = UUID(uuidString: savedIDString),
           tempProfiles.contains(where: { $0.id == savedID }) {
            tempActiveID = savedID
        }
        
        self.profiles = tempProfiles
        self.activeProfileID = tempActiveID
        
        self.applyActiveProfile()
        
        if needsMigration {
            Task { @MainActor in
                await self.saveAll()
            }
            
            if d.data(forKey: "profiles") != nil {
                d.removeObject(forKey: "profiles")
                dprint("🧹 [Storage Engine] UserDefaults 내 레거시 무거운 profiles 배열 파괴 성공.")
            }
        }
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
        
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

    func saveAll() async {
        // 🌟 저장 직전 실시간 메모리상의 제외 단어 목록을 액티브 프로필 데이터 홀더와 강제 동기화(Sync)합니다.
        if let index = self.profiles.firstIndex(where: { $0.id == self.activeProfileID }) {
            self.profiles[index].payload.typoExcludedWords = TypoExceptionManager.shared.excludedWords
        }
        
        let profilesToSave = self.profiles
        let directoryURL = self.applicationSupportDirectoryURL
        let fileURL = self.profilesFileURL
        
        await withCheckedContinuation { continuation in
            saveQueue.async {
                do {
                    if !FileManager.default.fileExists(atPath: directoryURL.path) {
                        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
                    }
                    let data = try Self.profileEncoder.encode(profilesToSave)
                    try data.write(to: fileURL, options: .atomic)

                    dprint("✅ [Storage Engine] 직렬화 큐 통과 — profiles.json 원자적 저장 무결성 확약.")
                } catch {
                    dprint("❌ [Storage Engine] 직렬화 큐 디스크 저장 실패: \(error.localizedDescription)")
                }
                continuation.resume()
            }
        }
    }
    
    private func applyActiveProfile() {
        self.isBatchUpdating = true
        
        defer {
            self.isBatchUpdating = false
            self.updateSnapshot()
        }
        
        let payload = activeProfile.payload
        DomainRuleManager.shared.rules = payload.domainRules
        updateShortcutCaches()
        
        // 🌟 [수복 2 구역: 프로필 교체 시 예외 단어 관리자 하이드레이션]
        // 불러온 프로필에 저장된 고유 예외 단어가 있다면 UI 컴포넌트 실시간 배열로 롤백시킵니다.
        if !payload.typoExcludedWords.isEmpty {
            TypoExceptionManager.shared.excludedWords = payload.typoExcludedWords
        }
        
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
        
        // 실시간 예외 단어를 매니저 레이어로부터 캡처하여 동기화
        let activeExcludedWords = TypoExceptionManager.shared.excludedWords
        
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
        
        // 🌟 [수복 3 구역: 변환 엔진용 고속 조회 스냅샷 데이터 주입]
        newSnapshot.typoExcludedWords = activeExcludedWords
        
        newSnapshot.buildCaches()
        InputShortcutEngine.shared.syncEngineCache(newSnapshot)
        
        EventMonitor.shared.snapshotLock.lock()
        EventMonitor.shared.localSnapshot = newSnapshot
        EventMonitor.shared.snapshotLock.unlock()
        
        EventMonitor.shared.updateSettingsSnapshot(newSnapshot)
        self._snapshot = newSnapshot
    }
    
    @MainActor
    func addLog(_ log: ActionLog) {
        self.recentLogs.append(log)
        if recentLogs.count > logTrimThreshold {
            let excessCount = recentLogs.count - maxLogCount
            recentLogs.removeFirst(excessCount)
        }
    }
    
    func scheduleSave() {
        guard !isBatchUpdating else { return }
        
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                try await Task.sleep(for: .seconds(0.5))
                guard !Task.isCancelled else { return }
                
                await self.saveAll()
                self.updateSnapshot()
                
                if !self.isBatchUpdating {
                    self.syncToCloud()
                }
            } catch {
                // 우아하게 후퇴
            }
        }
    }
    
    @MainActor
    @objc private func appWillTerminate() {
        print("🚨 [SettingsManager] OS 시스템 강제 종료 시그널 감지. 긴급 동기 장부 강제 플러시를 집행합니다.")
        saveTask?.cancel()
        saveTask = nil
        self.executeEmergencySynchronousSave()
    }
    
    @MainActor
    private func executeEmergencySynchronousSave() {
        if let index = self.profiles.firstIndex(where: { $0.id == self.activeProfileID }) {
            self.profiles[index].payload.typoExcludedWords = TypoExceptionManager.shared.excludedWords
        }
        
        let directoryURL = self.applicationSupportDirectoryURL
        let fileURL = self.profilesFileURL
        
        do {
            if !FileManager.default.fileExists(atPath: directoryURL.path) {
                try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
            }
            let data = try Self.profileEncoder.encode(self.profiles)
            try data.write(to: fileURL, options: .atomic)
            print("✨ [SettingsManager] Emergency Sync Save 대성공 — profiles.json 무결성 보존 완결.")
        } catch {
            print("❌ [SettingsManager] 비상 동기화 디스크 저장 대패: \(error.localizedDescription)")
        }
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
    
    func exportTextExpansionRules(to url: URL, completion: @escaping @MainActor (Bool, Error?) -> Void = { _, _ in }) {
        let rulesToExport = activeProfile.payload.textExpansionRules
        do {
            let data = try Self.profileEncoder.encode(rulesToExport)
            Task.detached(priority: .userInitiated) {
                do {
                    try data.write(to: url)
                    await completion(true, nil)
                } catch {
                    await completion(false, error)
                }
            }
        } catch {
            completion(false, error)
        }
    }

    @MainActor
    func importTextExpansionRules(from url: URL, completion: @escaping @MainActor (Bool, Error?) -> Void = { _, _ in }) {
        Task.detached(priority: .userInitiated) {
            do {
                let data = try Data(contentsOf: url)
                let decodedRules = try JSONDecoder().decode([TextExpansionRule].self, from: data)
                
                await MainActor.run {
                    self.isBatchUpdating = true
                    defer {
                        self.isBatchUpdating = false
                        self.updateSnapshot()
                        self.scheduleSave()
                    }
                    
                    var profile = self.activeProfile
                    profile.payload.textExpansionRules = decodedRules
                    self.activeProfile = profile
                    
                    let log = ActionLog(
                        timestamp: Date(), targetApp: "LangSwitcher", appliedRule: "Text Expansion Import",
                        finalInputSource: "Successfully imported \(decodedRules.count) rules", result: .success,
                        failureReason: .none
                    )
                    self.addLog(log)
                    HUDManager.shared.showHUD(languageName: String(localized: "Import Successful"))
                    completion(true, nil)
                }
            } catch {
                await MainActor.run {
                    dprint("❌ [SettingsManager] 텍스트 대치 규칙 임포트 실패: \(error.localizedDescription)")
                    let log = ActionLog(
                        timestamp: Date(), targetApp: "LangSwitcher", appliedRule: "Text Expansion Import",
                        finalInputSource: "Failed to import rules: \(error.localizedDescription)", result: .failure,
                        failureReason: .unknown
                    )
                    self.addLog(log)
                    HUDManager.shared.showHUD(languageName: String(localized: "Import Failed"))
                    completion(false, error)
                }
            }
        }
    }
    
    func exportProfiles() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        savePanel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        savePanel.nameFieldStringValue = "LangSwitcher_Profiles_Backup.json"
        savePanel.title = String(localized: "Export Profiles Backup")
        
        // 백업 JSON 생성 전 실시간 상태 반영 강제 확약
        if let index = self.profiles.firstIndex(where: { $0.id == self.activeProfileID }) {
            self.profiles[index].payload.typoExcludedWords = TypoExceptionManager.shared.excludedWords
        }
        
        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }
            do {
                let data = try Self.profileEncoder.encode(self.profiles)
                Task.detached(priority: .userInitiated) {
                    do {
                        try data.write(to: url)
                        dprint("✅ Profiles successfully exported to \(url.lastPathComponent)")
                    } catch {
                        dprint("❌ Failed to export profiles: \(error.localizedDescription)")
                    }
                }
            } catch {
                dprint("❌ Failed to encode profiles: \(error.localizedDescription)")
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
            guard response == .OK, let url = openPanel.url else { return }
            let localDecoder = Self.profileDecoder
            
            Task.detached(priority: .userInitiated) {
                do {
                    let data = try Data(contentsOf: url)
                    let importedProfiles = try localDecoder.decode([SettingsProfile].self, from: data)
                    
                    await MainActor.run {
                        guard !importedProfiles.isEmpty else {
                            let alert = NSAlert()
                            alert.messageText = String(localized: "Import Failed")
                            alert.informativeText = String(localized: "The selected backup file is empty or contains no valid profiles.")
                            alert.alertStyle = .warning
                            NSApp.activate(ignoringOtherApps: true)
                            alert.runModal()
                            return
                        }
                        
                        self.isBatchUpdating = true
                        defer {
                            self.isBatchUpdating = false
                            self.updateSnapshot()
                            self.scheduleSave()
                        }
                        
                        self.profiles = importedProfiles
                        if let firstProfile = importedProfiles.first {
                            self.activeProfileID = firstProfile.id
                            
                            // 🌟 복원 직후 복원된 액티브 프로필의 예외 단어를 실시간 매니저로 완벽 하이드레이션(동기화)
                            TypoExceptionManager.shared.excludedWords = firstProfile.payload.typoExcludedWords
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
                    await MainActor.run {
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
    
    @MainActor
    func clearLogs() {
        self.recentLogs.removeAll(keepingCapacity: true)
        dprint("🧹 [LogEngine] 기존 힙 할당 캐파(Capacity)를 완벽히 유지한 채 인메모리 액션 로그만 청정 포맷 완료.")
    }
}
