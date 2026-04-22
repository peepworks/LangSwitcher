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
}

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    let currentSettingsVersion = "1.0.0"
    
    // 🌟 [리뷰 반영] 일괄 업데이트(Batch Update) 상태를 추적하는 플래그
    private var isBatchUpdating = false
    
    @Published var isCtrlActive: Bool { didSet { save("isCtrlActive", isCtrlActive) } }
    @Published var isCmdActive: Bool { didSet { save("isCmdActive", isCmdActive) } }
    @Published var isOptActive: Bool { didSet { save("isOptActive", isOptActive) } }
    @Published var ctrlLang: String { didSet { save("ctrlLang", ctrlLang) } }
    @Published var cmdLang: String { didSet { save("cmdLang", cmdLang) } }
    @Published var optLang: String { didSet { save("optLang", optLang) } }
    
    @Published var showVisualFeedback: Bool { didSet { save("showVisualFeedback", showVisualFeedback) } }
    @Published var isTestMode: Bool { didSet { save("isTestMode", isTestMode) } }
    
    @Published var toggleKeyCode: UInt16 { didSet { save("toggleKeyCode", toggleKeyCode) } }
    @Published var toggleModifierFlags: UInt64 { didSet { save("toggleModifierFlags", toggleModifierFlags) } }
    @Published var toggleDisplayString: String { didSet { save("toggleDisplayString", toggleDisplayString) } }
    
    @Published var customShortcuts: [CustomShortcut] = [] { didSet { if let e = try? JSONEncoder().encode(customShortcuts) { save("customShortcuts", e) } } }
    @Published var customApps: [CustomApp] = [] { didSet { if let e = try? JSONEncoder().encode(customApps) { save("customApps", e) } } }
    @Published var appLaunchShortcuts: [AppLaunchShortcut] = [] { didSet { if let e = try? JSONEncoder().encode(appLaunchShortcuts) { save("appLaunchShortcuts", e) } } }
    @Published var excludedApps: [ExcludedApp] = [] { didSet { if let e = try? JSONEncoder().encode(excludedApps) { save("excludedApps", e) } } }
    
    @Published var isTypoCorrectionEnabled: Bool { didSet { save("isTypoCorrectionEnabled", isTypoCorrectionEnabled) } }
    @Published var typoKeyCode: UInt16 { didSet { save("typoKeyCode", typoKeyCode) } }
    @Published var typoModifierFlags: UInt64 { didSet { save("typoModifierFlags", typoModifierFlags) } }
    @Published var typoDisplayString: String { didSet { save("typoDisplayString", typoDisplayString) } }
    @Published var isSentenceMode: Bool { didSet { save("isSentenceMode", isSentenceMode) } }
    
    @Published var recentLogs: [ActionLog] = []
    
    @AppStorage("isHyperKeyEnabled") var isHyperKeyEnabled: Bool = false {
        didSet { HyperKeyManager.shared.updateState(isEnabled: isHyperKeyEnabled) }
    }
    
    @AppStorage("isCustomShortcutsEnabled") var isCustomShortcutsEnabled: Bool = true
    @AppStorage("isAppSpecificEnabled") var isAppSpecificEnabled: Bool = true
    @AppStorage("isAppLaunchEnabled") var isAppLaunchEnabled: Bool = true
    
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
    }
    
    // 🌟 [리뷰 반영] 일괄 업데이트 중일 때는 저장을 무시하여 I/O 과부하 방지
    private func save(_ key: String, _ value: Any) {
        guard !isBatchUpdating else { return }
        UserDefaults.standard.set(value, forKey: key)
    }
    
    // 🌟 [리뷰 반영] 한 번에 모든 데이터를 디스크에 저장하는 함수
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
    
    // 🌟 [리뷰 반영] ActionLog 추가 및 크기 상한선 방어 로직
    func addLog(_ log: ActionLog) {
        DispatchQueue.main.async {
            self.recentLogs.insert(log, at: 0)
            
            // 🌟 50개를 초과할 경우, 몇 개가 초과되었든 확실하게 앞의 50개만 남깁니다.
            if self.recentLogs.count > 50 {
                self.recentLogs = Array(self.recentLogs.prefix(50))
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
            isSentenceMode: isSentenceMode
        )
        let encoder = JSONEncoder(); encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(backup); try data.write(to: url)
    }
    
    func importBackup(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let backup = try JSONDecoder().decode(BackupData.self, from: data)
        
        DispatchQueue.main.async {
            // 🌟 [리뷰 반영] 업데이트 시작: 디스크 쓰기 중단
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
            
            // 🌟 [리뷰 반영] 업데이트 종료: 한 번에 디스크에 저장
            self.isBatchUpdating = false
            self.saveAll()
        }
    }
}
