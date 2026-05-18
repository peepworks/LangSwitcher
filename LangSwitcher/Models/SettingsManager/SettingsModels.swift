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

// 🌟 V1(구버전)과 V2(신버전: 프로필 시스템) 백업 파일을 모두 호환하기 위한 통합 구조체
struct BackupData: Codable {
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
    
    // 🌟 [신규 추가] V2: 다중 프로필 시스템 데이터
    var profiles: [SettingsProfile]? = nil
    var activeProfileID: UUID? = nil
    
    // 🌟 [수정] V1: 구버전 단일 프로필 데이터 (생략 가능하도록 모두 '= nil' 기본값 할당)
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
    
    var cachedActiveTextExpansionRules: [TextExpansionRule] = []

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
        self.cachedActiveTextExpansionRules = textExpansionRules
            .filter { $0.isEnabled }
            .sorted { $0.trigger.count > $1.trigger.count }
    }
}

// 🌟 [추가] 딕셔너리의 열쇠로 쓸 구조체
struct ShortcutKey: Hashable {
    let keyCode: UInt16
    let modifiers: UInt64
}

// MARK: - Profile Management Models

/// 프로필 자체의 메타데이터와 실제 설정값(Payload)을 담는 구조체
struct SettingsProfile: Identifiable, Codable { // 🌟 Hashable 제거
    var id: UUID
    var name: String
    var note: String
    var isDefault: Bool
    var createdAt: Date
    var updatedAt: Date
    var payload: ProfileSettingsPayload
}

struct ProfileSettingsPayload: Codable { // 🌟 Hashable, Equatable 제거
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

// 🌟 탭 열거형을 전역 모델로 독립 (앱 내의 모든 파일에서 접근 가능해집니다)
enum SettingsTab: Hashable {
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
