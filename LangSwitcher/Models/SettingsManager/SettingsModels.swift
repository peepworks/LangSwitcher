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

import Cocoa

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

// 🌟 앱별 딜레이 저장 모델
struct AppDelay: Identifiable, Codable {
    var id = UUID()
    var bundleIdentifier: String
    var appName: String
    var delay: Double
}

enum ActionType: String, Codable {
    case textExpansion = "Text Expansion"
    case typoCorrection = "Typo Correction"
    case systemRecovery = "System Recovery"
    case windowMemory = "Window Memory"
    case tabMemory = "Tab Memory"
}

struct ActionLog: Identifiable, Codable {
    var id = UUID()
    let timestamp: Date
    let targetApp: String
    let appliedRule: String
    let finalInputSource: String
    let result: LogResult
    let failureReason: FailureReason
    var actionType: ActionType? = nil
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
    
    let domainRules: [DomainRule]?
    let appDelays: [AppDelay]? // 🌟 백업용 앱 딜레이
    
    let isTextExpansionEnabled: Bool?
    let textExpansionRules: [TextExpansionRule]?
}

struct SettingsSnapshot {
    var isCtrlActive = false; var isCmdActive = false; var isOptActive = false
    var ctrlLang = ""; var cmdLang = ""; var optLang = ""
    var showVisualFeedback = true; var isTestMode = false
    var toggleKeyCode: UInt16 = 0; var toggleModifierFlags: UInt64 = 0; var toggleDisplayString = ""
    var isSentenceMode = false
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
    var isTypoCorrectionEnabled = false
    var typoKeyCode: UInt16 = 0; var typoModifierFlags: UInt64 = 0; var typoDisplayString = ""
    
    var customApps: [CustomApp] = []
    var appLaunchShortcuts: [AppLaunchShortcut] = []
    var excludedApps: [ExcludedApp] = []
    var customShortcuts: [CustomShortcut] = []
    var domainRules: [DomainRule] = []
    var appDelays: [AppDelay] = [] // 🌟 스냅샷용 앱 딜레이
    
    var isTextExpansionEnabled: Bool
    var textExpansionRules: [TextExpansionRule] = []
    // 🌟 1. O(1) 검색을 위한 딕셔너리 변수 2개를 선언합니다. (기본값 빈 딕셔너리)
    var customShortcutCache: [UInt64: CustomShortcut] = [:]
    var appLaunchShortcutCache: [UInt64: AppLaunchShortcut] = [:]

    // 🌟 2. 스냅샷이 생성될 때 기존 배열(Array)을 딕셔너리(Dictionary)로 1번만 구워두는 함수입니다.
    mutating func buildCaches() {
        var tempCustom: [UInt64: CustomShortcut] = [:]
        for shortcut in customShortcuts {
            let maskedMods = UInt64(NSEvent.ModifierFlags(rawValue: UInt(shortcut.modifierFlags)).intersection([.command, .control, .option, .shift]).rawValue)
            let key = (UInt64(shortcut.keyCode) << 32) | maskedMods
            tempCustom[key] = shortcut
        }
        self.customShortcutCache = tempCustom

        var tempAppLaunch: [UInt64: AppLaunchShortcut] = [:]
        for appLaunch in appLaunchShortcuts {
            let maskedMods = UInt64(NSEvent.ModifierFlags(rawValue: UInt(appLaunch.modifierFlags)).intersection([.command, .control, .option, .shift]).rawValue)
            let key = (UInt64(appLaunch.keyCode) << 32) | maskedMods
            tempAppLaunch[key] = appLaunch
        }
        self.appLaunchShortcutCache = tempAppLaunch
    }
}

// 🌟 [추가] 딕셔너리의 열쇠로 쓸 구조체
struct ShortcutKey: Hashable {
    let keyCode: UInt16
    let modifiers: UInt64
}
