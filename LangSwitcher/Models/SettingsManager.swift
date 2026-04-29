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
    let isAutoTypoCorrectionOnEnterEnabled: Bool? // 🌟 [추가됨]
}

struct SettingsSnapshot {
    var isCtrlActive = false; var isCmdActive = false; var isOptActive = false
    var ctrlLang = ""; var cmdLang = ""; var optLang = ""
    var showVisualFeedback = true; var isTestMode = false
    var toggleKeyCode: UInt16 = 0; var toggleModifierFlags: UInt64 = 0; var toggleDisplayString = ""
    // 🌟 [추가됨] 오타 교정 범위(단어/문장) 상태를 스냅샷에 포함시킵니다.
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
    // 🌟 [추가됨] 앱별 지정 기능 상태를 스냅샷에 포함시킵니다.
    var isAppSpecificEnabled = true
    var isWindowMemoryEnabled = false
    var isWindowMemoryCleanupEnabled = true
    var isCursorHUDEnabled = true
    var isCloudSyncEnabled = false
    var isHapticFeedbackEnabled = false
    var isSoundFeedbackEnabled = false
    // 🌟 [추가] 스마트 자동 오타 감지
    var isAutoTypoCorrectionEnabled = false
    // 🌟 [추가] 노치 엣지 글로우 활성화 여부
    var isEdgeGlowEnabled = false
    var isAutoTypoCorrectionOnEnterEnabled = false // 🌟 [추가됨]
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
            // 🌟 [추가됨] AppStorage의 값을 스냅샷으로 복사해 줍니다.
            isAppSpecificEnabled: isAppSpecificEnabled,
            isWindowMemoryEnabled: isWindowMemoryEnabled,
            isWindowMemoryCleanupEnabled: isWindowMemoryCleanupEnabled,
            isCursorHUDEnabled: isCursorHUDEnabled,
            isCloudSyncEnabled: isCloudSyncEnabled,
            isHapticFeedbackEnabled: isHapticFeedbackEnabled,
            isSoundFeedbackEnabled: isSoundFeedbackEnabled,
            isAutoTypoCorrectionEnabled: isAutoTypoCorrectionEnabled, // 🌟 [추가]
            isEdgeGlowEnabled: isEdgeGlowEnabled, // 🌟 [추가]
            isAutoTypoCorrectionOnEnterEnabled: isAutoTypoCorrectionOnEnterEnabled // 🌟 [추가됨]
        )
        snapshotQueue.async(flags: .barrier) { self._snapshot = newSnapshot }
    }

    // ✅ 수정된 코드: 동기화 관리를 위한 전용 큐와 안전한 프로퍼티 래퍼 적용
    private let syncQueue = DispatchQueue(label: "com.peepworks.langswitcher.sync")
    private var _isBatchUpdating = false
        
    var isBatchUpdating: Bool {
        get { syncQueue.sync { _isBatchUpdating } }
        set { syncQueue.sync { self._isBatchUpdating = newValue } }
    }
    
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
    @AppStorage("isEdgeGlowEnabled") var isEdgeGlowEnabled: Bool = false { didSet { updateSnapshot(); syncToCloud() } }
    @AppStorage("isAutoTypoCorrectionOnEnterEnabled") var isAutoTypoCorrectionOnEnterEnabled: Bool = false { didSet { updateSnapshot(); syncToCloud() } } // 🌟 [추가됨]
    
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
            
            // 🌟 [핵심 방어 로직] defer를 사용하여 함수가 어떻게 종료되든 무조건 잠금을 풀도록 강제합니다.
            defer {
                self.isBatchUpdating = false
                self.saveAll()
                self.updateSnapshot()
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
            
            // defer 안에서 알아서 처리되므로 마지막에 있던 false 전환 코드는 삭제했습니다.
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
        // 🌟 [수정] 엣지 글로우도 클라우드에 저장하도록 추가합니다.
        icloudStore.set(isEdgeGlowEnabled, forKey: "isEdgeGlowEnabled")

        icloudStore.set(isAutoTypoCorrectionOnEnterEnabled, forKey: "isAutoTypoCorrectionOnEnterEnabled") // 🌟 [추가됨]
        
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
        
        // @AppStorage가 자동으로 처리하지 못하는 복잡한 배열(Array) 데이터들만 수동으로 인코딩하여 저장합니다.
        if let e = try? JSONEncoder().encode(customShortcuts) { d.set(e, forKey: "customShortcuts") }
        if let e = try? JSONEncoder().encode(customApps) { d.set(e, forKey: "customApps") }
        if let e = try? JSONEncoder().encode(appLaunchShortcuts) { d.set(e, forKey: "appLaunchShortcuts") }
        if let e = try? JSONEncoder().encode(excludedApps) { d.set(e, forKey: "excludedApps") }
        
        // 일반 변수(Bool, String, Int 등)는 @AppStorage가 자동 저장하므로 중복 코드를 제거했습니다.
    }
    
    func addLog(_ log: ActionLog) {
        DispatchQueue.main.async {
            self.recentLogs.insert(log, at: 0)
            
            while self.recentLogs.count > 50 {
                self.recentLogs.removeLast()
            }
        }
    }
    
    // MARK: - 안전한 백업 & 복원 (File I/O 최적화 및 Swift 6 호환)

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
                isAutoTypoCorrectionEnabled: isAutoTypoCorrectionEnabled, // 🌟 [수정] 이 줄이 빠져있었습니다!
                isEdgeGlowEnabled: isEdgeGlowEnabled,
                isAutoTypoCorrectionOnEnterEnabled: isAutoTypoCorrectionOnEnterEnabled // 🌟 [추가됨]
            )
            
            // 🌟 1. JSON 변환(초고속)은 메인 스레드에서 수행하여 Swift 6의 MainActor 에러를 해결합니다.
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(backup)
            
            // 🌟 2. 무거운 디스크 쓰기(File I/O)만 백그라운드로 보냅니다.
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try data.write(to: url)
                    DispatchQueue.main.async { completion(true, nil) } // 성공
                } catch {
                    DispatchQueue.main.async { completion(false, error) } // 실패
                }
            }
        } catch {
            completion(false, error) // 인코딩 실패 시
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
                        
                        // 🌟 [핵심 방어 로직] 여기서도 복원 중 오류가 나더라도 무조건 잠금을 풀도록 보장합니다.
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
                        
                        self.isExcludedAppsEnabled = backup.isExcludedAppsEnabled ?? true
                        
                        completion(true, nil) // 복원 성공
                    } catch {
                        // 에러가 나서 catch로 빠져도 defer가 발동하여 잠금이 안전하게 풀립니다!
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
}
