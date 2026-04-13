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

struct CustomShortcut: Identifiable, Codable { var id = UUID(); var keyCode: UInt16; var modifierFlags: UInt64; var displayString: String; var targetLanguage: String }
struct CustomApp: Identifiable, Codable { var id = UUID(); var bundleIdentifier: String; var appName: String; var targetLanguage: String }
struct AppLaunchShortcut: Identifiable, Codable { var id = UUID(); var keyCode: UInt16; var modifierFlags: UInt64; var displayString: String; var bundleIdentifier: String; var appName: String }

// 🌟 1. 실행 로그 구조체 및 실패 항목 정의
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

// 🌟 2. 백업 파일에 버전 필드 추가
struct BackupData: Codable {
    let version: String? // 구버전 백업 파일과의 호환성을 위해 Optional(?)로 선언
    let isCtrlActive: Bool; let isCmdActive: Bool; let isOptActive: Bool
    let ctrlLang: String; let cmdLang: String; let optLang: String
    let showVisualFeedback: Bool; let isTestMode: Bool
    let toggleKeyCode: UInt16; let toggleModifierFlags: UInt64; let toggleDisplayString: String
    let customShortcuts: [CustomShortcut]; let customApps: [CustomApp]; let appLaunchShortcuts: [AppLaunchShortcut]
}

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    // 🌟 현재 앱의 설정 버전 (업데이트 시 변경 가능)
    let currentSettingsVersion = "1.0.0"
    
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
    
    // 🌟 3. 최근 로그 50개를 저장하는 배열 (메모리 부담 최소화)
    @Published var recentLogs: [ActionLog] = []
    
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
    }
    
    private func save(_ key: String, _ value: Any) { UserDefaults.standard.set(value, forKey: key) }
    
    // 🌟 4. 로그 추가 헬퍼 함수
    func addLog(_ log: ActionLog) {
        DispatchQueue.main.async {
            self.recentLogs.insert(log, at: 0)
            if self.recentLogs.count > 50 { self.recentLogs.removeLast() } // 50개 유지
            
            // 개발자 디버깅용 콘솔 출력
            #if DEBUG
            print("[\(log.result == .success ? "✅" : "❌")] App: \(log.targetApp) | Rule: \(log.appliedRule) | Source: \(log.finalInputSource) | Reason: \(log.failureReason.rawValue)")
            #endif
        }
    }
    
    func exportBackup(to url: URL) throws {
        let backup = BackupData(
            version: currentSettingsVersion, // 🌟 백업 시 버전 명시
            isCtrlActive: isCtrlActive, isCmdActive: isCmdActive, isOptActive: isOptActive, ctrlLang: ctrlLang, cmdLang: cmdLang, optLang: optLang,
            showVisualFeedback: showVisualFeedback, isTestMode: isTestMode,
            toggleKeyCode: toggleKeyCode, toggleModifierFlags: toggleModifierFlags, toggleDisplayString: toggleDisplayString,
            customShortcuts: customShortcuts, customApps: customApps, appLaunchShortcuts: appLaunchShortcuts
        )
        let encoder = JSONEncoder(); encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(backup); try data.write(to: url)
    }
    
    func importBackup(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let backup = try JSONDecoder().decode(BackupData.self, from: data)
        
        // 🌟 향후 버전별 마이그레이션이 필요하다면 여기서 분기 처리 가능
        // print("Importing settings version: \(backup.version ?? "Legacy")")
        
        DispatchQueue.main.async {
            self.isCtrlActive = backup.isCtrlActive; self.isCmdActive = backup.isCmdActive; self.isOptActive = backup.isOptActive
            self.ctrlLang = backup.ctrlLang; self.cmdLang = backup.cmdLang; self.optLang = backup.optLang
            self.showVisualFeedback = backup.showVisualFeedback; self.isTestMode = backup.isTestMode
            self.toggleKeyCode = backup.toggleKeyCode; self.toggleModifierFlags = backup.toggleModifierFlags; self.toggleDisplayString = backup.toggleDisplayString
            self.customShortcuts = backup.customShortcuts; self.customApps = backup.customApps; self.appLaunchShortcuts = backup.appLaunchShortcuts
        }
    }
}
