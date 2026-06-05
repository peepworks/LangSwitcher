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
        encoder.outputFormatting = .prettyPrinted // 줄바꿈/들여쓰기 포맷 사양 고정
        return encoder
    }()
    nonisolated private static let profileDecoder = JSONDecoder()
    
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
 
    // Application Support 내 앱 전용 안전 폴더 경로 확보
    private var applicationSupportDirectoryURL: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("LangSwitcher", isDirectory: true)
    }

    // 최종 프로필 JSON 파일의 절대 경로
    private var profilesFileURL: URL {
        return applicationSupportDirectoryURL.appendingPathComponent("profiles.json")
    }

    // MARK: - Global Settings (전역 설정)
    
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
    @Published var isTestMode: Bool { didSet { save("isTestMode", isTestMode); updateSnapshot() } }
    
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

            Task { @MainActor in
                self.saveAll()
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
            
            let defaultProfile = SettingsProfile(
                id: UUID(), name: String(localized: "Default Profile"), note: String(localized: "Basic configuration"),
                isDefault: true, createdAt: Date(), updatedAt: Date(), payload: migratedPayload
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
            self.saveAll()
            if d.data(forKey: "profiles") != nil {
                d.removeObject(forKey: "profiles")
                dprint("🧹 [Storage Engine] UserDefaults 내 레거시 무거운 profiles 배열 파괴 성공.")
            }
        }
        
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
        let directoryURL = self.applicationSupportDirectoryURL
        let fileURL = self.profilesFileURL
        
        // 🌟 [수복 완료] 레거시 GCD 대신 Swift 6 최적화 규격인 Task.detached 사양으로 디스크 저장 처리 통합
        Task.detached(priority: .background) {
            do {
                if !FileManager.default.fileExists(atPath: directoryURL.path) {
                    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
                }
                let data = try Self.profileEncoder.encode(profilesToSave)
                try data.write(to: fileURL, options: .atomic)
                dprint("✅ [Storage Engine] 프로필 데이터가 Application Support 폴더에 안전하게 저장되었습니다.")
            } catch {
                dprint("❌ [Storage Engine] 프로필 디스크 저장 실패: \(error.localizedDescription)")
            }
        }
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
    @MainActor
    func addLog(_ log: ActionLog) {
        // 1. 뒤에 붙이기는 언제나 비용이 없는 완벽한 O(1)
        self.recentLogs.append(log)
        
        // 2. 🌟 [최종 최적화 수복]
        // 550개 임계치 도달 시, 완전히 새로운 배열을 힙에 할당하는 Array(suffix)를 버리고
        // 기존 메모리 버퍼 내부에서 memmove 기반으로 앞의 50개만 즉시 밀어버립니다. (힙 할당 오버헤드 0%)
        if self.recentLogs.count > maxLogCount + 50 {
            self.recentLogs.removeFirst(50)
            
            dprint("🧹 [LogEngine] 메모리 재할당 없이 기존 버퍼 내에서 50건의 로그를 제자리(In-place) 트리밍했습니다.")
        }
    }
    
    // MARK: - 고성능 디바운스 저장 엔진 (@MainActor 격리 완전 준수)
    func scheduleSave() {
        saveWorkItem?.cancel()
        
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            
            self.saveAll()
            self.updateSnapshot()
            
            if !self.isBatchUpdating {
                self.syncToCloud()
            }
            dprint("📝 [SettingsManager] 메인 액터 격리를 준수하며 안전하게 설정을 통합 보존했습니다.")
        }
        
        self.saveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
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
    func exportTextExpansionRules(to url: URL, completion: @escaping @MainActor (Bool, Error?) -> Void = { _, _ in }) {
        let rulesToExport = activeProfile.payload.textExpansionRules
        
        do {
            let data = try Self.profileEncoder.encode(rulesToExport)
            
            // 🌟 [수복 완료] 레거시 GCD 대신 리뷰어 9번의 권고에 맞춰 전역 Task.detached 독립 스레드로 격리 통합
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
        // 독립된 백그라운드 작업동(Task.detached)으로 파일 I/O 및 대량 파싱 연산을 완벽히 위임합니다.
        Task.detached(priority: .userInitiated) {
            do {
                let data = try Data(contentsOf: url)
                let decodedRules = try JSONDecoder().decode([TextExpansionRule].self, from: data)
                
                // 1. 샌드박스 파싱이 완벽히 끝난 시점에 메인 액터의 진짜 장부(activeProfile)에 원자적 대입을 집행합니다.
                await MainActor.run {
                    var profile = self.activeProfile
                    profile.payload.textExpansionRules = decodedRules
                    self.activeProfile = profile
                    
                    // 수동 메모리 스냅샷 정산 및 디스크 커널 백업 트리거 호출
                    self.updateSnapshot()
                    self.scheduleSave()
                    
                    let log = ActionLog(
                        timestamp: Date(), targetApp: "LangSwitcher", appliedRule: "Text Expansion Import",
                        finalInputSource: "Successfully imported \(decodedRules.count) rules", result: .success,
                        failureReason: .none
                    )
                    self.addLog(log)
                    HUDManager.shared.showHUD(languageName: String(localized: "Import Successful"))
                    
                    // 🌟 [수복 완료] 성공 시 뷰(View)가 등록해둔 후행 콜백을 깨워 정산 완료를 알립니다.
                    completion(true, nil)
                }
            } catch {
                // 2. 예외 상황 발생 시 오염된 decodedRules 접근을 원천 차단하고 청정하게 에러 상태 장부만 보고합니다.
                await MainActor.run {
                    dprint("❌ [SettingsManager] 텍스트 대치 규칙 임포트 실패: \(error.localizedDescription)")
                    
                    let log = ActionLog(
                        timestamp: Date(), targetApp: "LangSwitcher", appliedRule: "Text Expansion Import",
                        finalInputSource: "Failed to import rules: \(error.localizedDescription)", result: .failure,
                        failureReason: .unknown
                    )
                    self.addLog(log)
                    HUDManager.shared.showHUD(languageName: String(localized: "Import Failed"))
                    
                    // 🌟 [수복 완료] 실패 시에도 뷰(View)에 실패 원인 에러 객체를 안전하게 배달합니다.
                    completion(false, error)
                }
            }
        }
    }
    
    // MARK: - 프로필 내보내기/가져오기 고성능 스레드 격리 수복 버전
    func exportProfiles() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        savePanel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        savePanel.nameFieldStringValue = "LangSwitcher_Profiles_Backup.json"
        savePanel.title = String(localized: "Export Profiles Backup")
        
        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }
            
            do {
                let data = try Self.profileEncoder.encode(self.profiles)
                
                // 🌟 [수복 완료] 리뷰어 9번 의견 적용: 익스포트 디스크 I/O 역시 무결한 Task.detached 시스템으로 전환
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
            
            // 🌟 [수복 완료] 리뷰어 9번 의견 적극 반영: 대량의 전체 프로필 임포트 구역까지 완벽한 Task.detached 사양으로 통일 완성!
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
        self.recentLogs.removeAll(keepingCapacity: false)
        dprint("🧹 [SettingsManager] 메인 액터 보호막 안에서 안전하게 전체 로그를 소각했습니다.")
    }
}
