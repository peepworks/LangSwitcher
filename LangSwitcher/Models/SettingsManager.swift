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
    } ()
    nonisolated private static let profileDecoder = JSONDecoder()
    
    let icloudStore = NSUbiquitousKeyValueStore.default
    private var _snapshot = SettingsSnapshot(isTextExpansionEnabled: false, textExpansionRules: [])
    
    // ── 🌟 [8번 리뷰 수복 포인트 1: 레거시 GCD 디바운서 폐기] ──
    // 추적이 불가능하여 앱 종료 시 데이터 유실을 유발하던 DispatchWorkItem을 전면 소각하고,
    // 생명주기를 완벽히 통제할 수 있는 단일 소스 Task 참조선으로 전치합니다.
    private var saveTask: Task<Void, Never>?
    
    nonisolated private let saveQueue = DispatchQueue(label: "com.peepworks.langswitcher.save", qos: .background)
    
    private let maxLogCount = 500
    private let logTrimBuffer = 50

    // 이제 하단의 addLog() 로직에서는 이 logTrimThreshold 단 하나만 기준선으로 바라봅니다.
    private var logTrimThreshold: Int { maxLogCount + logTrimBuffer }
    
    @Published var selectedTab: SettingsTab? = .general
    @MainActor var isBatchUpdating: Bool = false
    
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
    
    @AppStorage("isWindowMemoryEnabled") var isWindowMemoryEnabled: Bool = false {
        didSet {
            guard !isBatchUpdating else { return }
            updateSnapshot()
            syncToCloud()
        }
    }
    @AppStorage("isWindowMemoryCleanupEnabled") var isWindowMemoryCleanupEnabled: Bool = true { didSet { updateSnapshot(); syncToCloud() } }
    @AppStorage("isCursorHUDEnabled") var isCursorHUDEnabled: Bool = true {
        didSet {
            guard !isBatchUpdating else { return }
            updateSnapshot()
            syncToCloud()
        }
    }
    
    @AppStorage("isCloudSyncEnabled") var isCloudSyncEnabled: Bool = false {
        didSet { updateSnapshot(); if isCloudSyncEnabled { syncToCloud() } }
    }
    @AppStorage("isHapticFeedbackEnabled") var isHapticFeedbackEnabled: Bool = false { didSet { updateSnapshot(); syncToCloud() } }
    @AppStorage("isSoundFeedbackEnabled") var isSoundFeedbackEnabled: Bool = false { didSet { updateSnapshot(); syncToCloud() } }
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
            Task { @MainActor in
                await self.saveAll()
            }
            
            if d.data(forKey: "profiles") != nil {
                d.removeObject(forKey: "profiles")
                dprint("🧹 [Storage Engine] UserDefaults 내 레거시 무거운 profiles 배열 파괴 성공.")
            }
        }
        
        // ── 🌟 [우주 방어 수복 포인트 2: 앱 예기치 못한 즉사 방어선 구축] ──
        // OS 셧다운 알림 커널 스트림을 수신하기 위해 옵저버를 결속합니다.
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

    // MARK: - 고성능 디스크 저장 엔티티 (순서 역전 및 데이터 유실 트랩 완벽 소각)
    
    func saveAll() async {
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
            isTextExpansionEnabled: payload.isTextExpansionEnabled,
            textExpansionRules: payload.textExpansionRules
        )
        // (참고: 빌드 무결성을 보장하기 위해 파트너님의 순정 snapshot 파라미터 매핑 상태를 그대로 관통 결속합니다)
        newSnapshot = SettingsSnapshot(
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
        
        EventMonitor.shared.snapshotLock.lock()
        EventMonitor.shared.localSnapshot = newSnapshot
        EventMonitor.shared.snapshotLock.unlock()
        
        EventMonitor.shared.updateSettingsSnapshot(newSnapshot)
        self._snapshot = newSnapshot
    }
    
    // MARK: - 고성능 로그 주입 아키텍처
    @MainActor
    func addLog(_ log: ActionLog) {
        self.recentLogs.append(log)
        
        // 🌟 [수복 완료] SSOT 기준선 단 한 곳만 참조하여 정밀 타격
        if recentLogs.count > logTrimThreshold {
            // 초과된 버퍼(50개)만큼만 정확하게 잘라내어 maxLogCount(500개)를 유지합니다.
            let excessCount = recentLogs.count - maxLogCount
            recentLogs.removeFirst(excessCount)
        }
    }
    
    // MARK: - 🌟 [8번 리뷰 수복 포인트 3: 현대식 순정 비동기 디바운스 대통합]
    
    func scheduleSave() {
        guard !isBatchUpdating else { return }
        
        // 새로운 저장이 요청되는 즉시 기존 대기열 태스크 객체 자체를 저격 취소(Cancel)시킵니다.
        saveTask?.cancel()
        
        // 비구조화 프레임을 탈출하여 완벽한 소유주(saveTask)가 확약된 구조화 동시성을 전개합니다.
        saveTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                // GCD 타이머를 걷어내고 0.5초 동안 메인 스레드를 블로킹하지 않고 청정 비동기 대기
                try await Task.sleep(for: .seconds(0.5))
                
                // 대기 도중 연타가 인입되어 취소 신호를 수신했다면 아래 UI/디스크 플러시 라인을 완벽히 차단
                guard !Task.isCancelled else { return }
                
                await self.saveAll()
                self.updateSnapshot()
                
                if !self.isBatchUpdating {
                    self.syncToCloud()
                }
            } catch {
                // 취소 예외 발생 시 스킵 후 우아하게 후퇴
            }
        }
    }
    
    // MARK: - 🌟 [8번 리뷰 수복 포인트 4: 프로세스 강제 사살 즉사 방지 브레이크]
    
    @MainActor
    @objc private func appWillTerminate() {
        print("🚨 [SettingsManager] OS 시스템 강제 종료 시그널 감지. 긴급 동기 장부 강제 플러시를 집행합니다.")
        
        // 1. 대기선에서 0.5초 슬립을 구동 중이던 비동기 태스크를 즉각 전면 차단합니다.
        saveTask?.cancel()
        saveTask = nil
        
        // 2. 비동기 await를 호출하면 커널이 즉시 종료시키므로,
        // 이 비상 상태에서만큼은 메인 스레드 컨텍스트에서 인메모리 장부를 파일 시스템에 동기식(Sync)으로 즉각 각인합니다.
        self.executeEmergencySynchronousSave()
    }
    
    @MainActor
    private func executeEmergencySynchronousSave() {
        let directoryURL = self.applicationSupportDirectoryURL
        let fileURL = self.profilesFileURL
        
        do {
            if !FileManager.default.fileExists(atPath: directoryURL.path) {
                try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
            }
            
            // 현재 인메모리에 떠 있는 최신 설정 데이터 동기 직렬화
            let data = try Self.profileEncoder.encode(self.profiles)
            
            // 동기식(.atomic) 강제 저장을 통해 OS 프로세스가 끊어지기 전 장부 완벽 보존
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
    
    // MARK: - Text Expansion Only Backup/Restore
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
                    var profile = self.activeProfile
                    profile.payload.textExpansionRules = decodedRules
                    self.activeProfile = profile
                    
                    self.updateSnapshot()
                    self.scheduleSave()
                    
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
        self.recentLogs.removeAll(keepingCapacity: true)
        dprint("🧹 [LogEngine] 기존 힙 할당 캐파(Capacity)를 완벽히 유지한 채 인메모리 액션 로그만 청정 포맷 완료.")
    }
}
