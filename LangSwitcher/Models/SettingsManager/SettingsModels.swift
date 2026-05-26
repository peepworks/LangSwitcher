//
//  SettingsModels.swift
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

import Cocoa

// 🌟 모든 설정 모델에 Sendable 추가
struct CustomShortcut: Identifiable, Codable, Sendable { var id = UUID(); var keyCode: UInt16; var modifierFlags: UInt64; var displayString: String; var targetLanguage: String }
struct CustomApp: Identifiable, Codable, Sendable { var id = UUID(); var bundleIdentifier: String; var appName: String; var targetLanguage: String }
struct AppLaunchShortcut: Identifiable, Codable, Sendable { var id = UUID(); var keyCode: UInt16; var modifierFlags: UInt64; var displayString: String; var bundleIdentifier: String; var appName: String }
struct ExcludedApp: Identifiable, Codable, Sendable { var id = UUID(); var bundleIdentifier: String; var appName: String }

enum LogResult: String, Codable, Sendable { case success, failure }

enum FailureReason: String, Codable, Sendable {
    case none = "None"
    case conditionMismatch = "Condition Mismatch"
    case excludedApp = "Excluded App"
    case permissionIssue = "Permission Issue"
    case unknown = "Unknown Error"
}

// 🌟 앱별 딜레이 저장 모델에 Sendable 추가
struct AppDelay: Identifiable, Codable, Sendable {
    var id = UUID()
    var bundleIdentifier: String
    var appName: String
    var delay: Double
}

enum ActionType: String, Codable, Sendable {
    case textExpansion = "Text Expansion"
    case typoCorrection = "Typo Correction"
    case systemRecovery = "System Recovery"
    case windowMemory = "Window Memory"
    case tabMemory = "Tab Memory"
}

struct ActionLog: Identifiable, Codable, Sendable {
    var id = UUID()
    let timestamp: Date
    let targetApp: String
    let appliedRule: String
    let finalInputSource: String
    let result: LogResult
    let failureReason: FailureReason
    var actionType: ActionType? = nil
}

// 🌟 통합 백업 구조체에 Sendable 추가
struct BackupData: Codable, Sendable {
    var version: String?
    var isCtrlActive: Bool?
    var isCmdActive: Bool?
    var isOptActive: Bool?
    var ctrlLang: String?
    var cmdLang: String?
    var optLang: String?
    var showVisualFeedback: Bool?
    var isTestMode: Bool?
    var toggleKeyCode: UInt16?
    var toggleModifierFlags: UInt?
    var toggleDisplayString: String?
    
    // 전역 환경 설정
    var isExcludedAppsEnabled: Bool?
    var isEdgeGlowEnabled: Bool?
    var isBrowserTabMemoryEnabled: Bool?
    
    // V2: 다중 프로필 시스템 데이터
    var profiles: [SettingsProfile]? = nil
    var activeProfileID: UUID? = nil
    
    // V1: 구버전 단일 프로필 데이터
    var customShortcuts: [CustomShortcut]? = nil
    var customApps: [CustomApp]? = nil
    var appLaunchShortcuts: [AppLaunchShortcut]? = nil
    var excludedApps: [ExcludedApp]? = nil
    var isTypoCorrectionEnabled: Bool? = nil
    var typoKeyCode: UInt16? = nil
    var typoModifierFlags: UInt? = nil
    var typoDisplayString: String? = nil
    var isSentenceMode: Bool? = nil
    var isAutoTypoCorrectionEnabled: Bool? = nil
    var isAutoTypoCorrectionOnEnterEnabled: Bool? = nil
    var isBrowserDomainModeEnabled: Bool? = nil
    var domainRules: [DomainRule]? = nil
    var appDelays: [AppDelay]? = nil
    var isTextExpansionEnabled: Bool? = nil
    var textExpansionRules: [TextExpansionRule]? = nil
}

// 🌟 엔진이 참조하는 가장 중요한 스냅샷에 Sendable 추가
struct SettingsSnapshot: Sendable {
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
    var enabledDomainRules: [DomainRule] = []
    var appDelays: [AppDelay] = []
    
    var isTextExpansionEnabled: Bool
    var textExpansionRules: [TextExpansionRule] = []
    
    var customShortcutCache: [UInt64: CustomShortcut] = [:]
    var appLaunchShortcutCache: [UInt64: AppLaunchShortcut] = [:]
    
    var textExpansionDict: [String: TextExpansionRule] = [:]
    var maxTriggerLength: Int = 0

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
        textExpansionDict.removeAll()
        maxTriggerLength = 0
        
        for rule in textExpansionRules where rule.isEnabled {
            textExpansionDict[rule.trigger] = rule
            if rule.trigger.count > maxTriggerLength {
                maxTriggerLength = rule.trigger.count
            }
        }
        self.enabledDomainRules = self.domainRules.filter { $0.isEnabled }
    }
}

// 🌟 캐시 키 구조체에 Sendable 추가
struct ShortcutKey: Hashable, Sendable {
    let keyCode: UInt16
    let modifiers: UInt64
}

// MARK: - Profile Management Models

// 🌟 프로필 컨텍스트 데이터 구조체들에 Sendable 추가
struct SettingsProfile: Identifiable, Codable, Sendable {
    var id: UUID
    var name: String
    var note: String
    var isDefault: Bool
    var createdAt: Date
    var updatedAt: Date
    var payload: ProfileSettingsPayload
}

struct ProfileSettingsPayload: Codable, Sendable {
    var customShortcuts: [CustomShortcut] = []
    var appLaunchShortcuts: [AppLaunchShortcut] = []
    var customApps: [CustomApp] = []
    var excludedApps: [ExcludedApp] = []
    var domainRules: [DomainRule] = []
    var appDelays: [AppDelay] = []
    
    // 2. 텍스트 대치
    var isTextExpansionEnabled: Bool = false
    var textExpansionRules: [TextExpansionRule] = []
    
    // 3. 오타 교정
    var isTypoCorrectionEnabled: Bool = false
    var typoKeyCode: UInt16 = 0
    var typoModifierFlags: UInt64 = 0
    var typoDisplayString: String = ""
    var isSentenceMode: Bool = false
    var isAutoTypoCorrectionEnabled: Bool = false
    var isAutoTypoCorrectionOnEnterEnabled: Bool = false
    
    // 4. 프로필 종속적인 일부 고급 설정 (선택적)
    var isAppSpecificEnabled: Bool = true
    var isBrowserDomainModeEnabled: Bool = false
}

// 🌟 글로벌 네비게이션 탭 열거형에 Sendable 추가
enum SettingsTab: Hashable, Sendable {
    case profiles
    case general
    case advanced
    case customShortcuts
    case appSpecific
    case domainRules
    case appLaunch
    case textExpansion
    case typoCorrection
    case excludedApps
    case stats
    case rulePriority
    case debugger
    case about
}
