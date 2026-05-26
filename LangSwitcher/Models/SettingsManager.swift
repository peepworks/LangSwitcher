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
 
    // 🌟 [추가] Application Support 내 앱 전용 안전 폴더 경로 확보
    private var applicationSupportDirectoryURL: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        // ~/Library/Application Support/LangSwitcher 폴더 지정
        return paths[0].appendingPathComponent("LangSwitcher", isDirectory: true)
    }

    // 🌟 [추가] 최종 프로필 JSON 파일의 절대 경로
    private var profilesFileURL: URL {
        return applicationSupportDirectoryURL.appendingPathComponent("profiles.json")
    }

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
        // 1. 연쇄 업데이트 방어막 활성화
        self.isBatchUpdating = true
        let d = UserDefaults.standard
        let fileManager = FileManager.default
        
        // 2. 일반 저장 프로퍼티들 선제 초기화
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
        
        // 3. self 가 완전히 초기화되기 전이므로, 파일 경로를 안전한 '지역 변수'로 계산합니다.
        let appSupportPaths = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let localProfilesFileURL = appSupportPaths[0]
            .appendingPathComponent("LangSwitcher", isDirectory: true)
            .appendingPathComponent("profiles.json")
        
        // 마이그레이션이 실행되어야 하는지 추적할 플래그
        var needsMigration = false
        var tempProfiles: [SettingsProfile] = []
        
        // 4. 독립된 지역 변수 풀 안에서 프로필 데이터 정산 집행
        if fileManager.fileExists(atPath: localProfilesFileURL.path),
           let data = try? Data(contentsOf: localProfilesFileURL),
           let dec = try? JSONDecoder().decode([SettingsProfile].self, from: data), !dec.isEmpty {
            
            // [케이스 A] Application Support에 정식 파일이 이미 상주 중인 경우
            tempProfiles = dec
            
        } else if let legacyData = d.data(forKey: "profiles"),
                  let dec = try? JSONDecoder().decode([SettingsProfile].self, from: legacyData), !dec.isEmpty {
            
            // [케이스 B] 구버전 UserDefaults 데이터가 남아있는 경우 (마이그레이션 대상)
            tempProfiles = dec
            needsMigration = true
            
        } else {
            // [케이스 C] 설정이 전혀 없는 완전 순정 최초 실행 유저
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
            needsMigration = true // 최초 유저도 파일 공간 확보를 위해 즉시 저장 플래그를 켭니다.
        }
        
        // 활성 프로필 ID 가 계산될 임시 변수 확보
        var tempActiveID = tempProfiles.first!.id
        if let savedIDString = d.string(forKey: "activeProfileID"),
           let savedID = UUID(uuidString: savedIDString),
           tempProfiles.contains(where: { $0.id == savedID }) {
            tempActiveID = savedID
        }
        
        // 🌟 [핵심 수복 지점]
        // 1단계(Phase 1) 초기화 완료! 모든 핵심 저장 프로퍼티의 장부를 완전히 채웁니다.
        self.profiles = tempProfiles
        self.activeProfileID = tempActiveID
        
        // ── 여기서부터 2단계(Phase 2) 영역 진입: 이제 'self' 메서드를 호출해도 100% 안전합니다 ──
        
        self.applyActiveProfile()
        
        // 마이그레이션 대상이거나 신규 파일 생성이 필요한 경우 후속 안전지대에서 청소 실행
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
        
        // 백그라운드 스레드에서 무거운 파일 쓰기를 처리하여 UI 스레드를 완벽하게 보호합니다.
        DispatchQueue.global(qos: .background).async {
            do {
                // 1. Application Support 내부에 앱 전용 폴더가 없다면 선제 생성
                if !FileManager.default.fileExists(atPath: directoryURL.path) {
                    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
                }
                
                // 2. 인코딩 집행
                let data = try JSONEncoder().encode(profilesToSave)
                
                // 3. .atomic 옵션을 주어 임시 파일을 만든 뒤 쓰기가 성공하면
                // 원래 파일과 교체하는 방식을 취하므로, 저장 도중 앱이 꺼져도 파일 무결성이 깨지지 않습니다.
                try data.write(to: fileURL, options: .atomic)
                
                #if DEBUG
                dprint("✅ [Storage Engine] 프로필 데이터가 Application Support 폴더에 안전하게 저장되었습니다.")
                #endif
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
        // 1. 맨 뒤에 붙이기는 언제나 비용이 없는 완벽한 O(1)
        self.recentLogs.append(log)
        
        // 2. 매번 지우지 않고 임계값(550개)에 도달했을 때만 50개를 일괄 배치 청소
        if self.recentLogs.count > logBufferThreshold {
            let overflowCount = self.recentLogs.count - maxLogCount
            
            // 🌟 [리뷰어 지적 완벽 종결]
            // Array(suffix)처럼 새 메모리 공간을 파서 500개를 전량 복사하는 낭비 없이,
            // 순정 배열 내부에서 앞전의 50개 찌꺼기만 단 1번의 메모리 이동으로 칼같이 잘라냅니다.
            // 550번의 키 타건 중 딱 1번만 이사가 실행되므로 고속 타이핑 시 CPU 지연이 0%로 통제됩니다.
            self.recentLogs.removeFirst(overflowCount)
            
            #if DEBUG
            dprint("🧹 [LogEngine] 버퍼 한도 초과로 오래된 로그 \(overflowCount)건을 일괄 배치 트리밍했습니다. (현재 카운트: \(self.recentLogs.count)건)")
            #endif
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
    // 호출자가 내부 스레드 전환 구조를 신경 쓰지 않고 무조건 메인 스레드에서 안전하게 UI를 받도록 규격화합니다.
    func exportTextExpansionRules(to url: URL, completion: @escaping @MainActor (Bool, Error?) -> Void = { _, _ in }) {
        let rulesToExport = activeProfile.payload.textExpansionRules
        
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(rulesToExport)
            
            // 디스크 쓰기(I/O)만 백그라운드로 철저히 격리
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try data.write(to: url)
                    // ✅ 성공 경로: 메인 스레드 정렬
                    DispatchQueue.main.async { completion(true, nil) }
                } catch {
                    // 🌟 [리뷰 반영 수복] 디스크 쓰기 실패 시에도 백그라운드에서 터지지 않고,
                    // 반드시 메인 스레드로 컨텍스트를 이관한 뒤 실패 콜백을 호출합니다.
                    DispatchQueue.main.async { completion(false, error) }
                }
            }
        } catch {
            // ✅ 인코딩 실패 경로: 이미 메인 스레드 위이므로 즉시 안전하게 호출
            completion(false, error)
        }
    }

    func importTextExpansionRules(from url: URL, completion: @escaping @MainActor (Bool, Error?) -> Void = { _, _ in }) {
        // 백그라운드에서는 순수 디스크 데이터 읽기와 JSON 파싱만 독점 집행하여 UI 프리징을 막습니다.
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let data = try Data(contentsOf: url)
                let importedRules = try JSONDecoder().decode([TextExpansionRule].self, from: data)
                
                // 🌟 [수복 핵심] 가공된 결과물 장부를 원본 프로필에 주입할 때는
                // 반드시 메인 액터 런타임 안으로 안전하게 진입하여 동기화 처리를 수행합니다.
                DispatchQueue.main.async {
                    var profile = self.activeProfile
                    for rule in importedRules {
                        if !profile.payload.textExpansionRules.contains(where: { $0.trigger == rule.trigger }) {
                            profile.payload.textExpansionRules.append(rule)
                        }
                    }
                    self.activeProfile = profile
                    completion(true, nil)
                }
            } catch {
                DispatchQueue.main.async { completion(false, error) }
            }
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
    
    @MainActor
    func clearLogs() {
        self.recentLogs.removeAll(keepingCapacity: false)
        #if DEBUG
        dprint("🧹 [SettingsManager] 메인 액터 보호막 안에서 안전하게 전체 로그를 소각했습니다.")
        #endif
    }
}
