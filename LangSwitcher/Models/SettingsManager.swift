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

struct BackupData: Codable {
    let isCtrlActive: Bool; let isCmdActive: Bool; let isOptActive: Bool
    let ctrlLang: String; let cmdLang: String; let optLang: String
    let showVisualFeedback: Bool; let isTestMode: Bool
    let toggleKeyCode: UInt16; let toggleModifierFlags: UInt64; let toggleDisplayString: String // 🌟 백업 추가
    let customShortcuts: [CustomShortcut]; let customApps: [CustomApp]; let appLaunchShortcuts: [AppLaunchShortcut]
}

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    @Published var isCtrlActive: Bool { didSet { save("isCtrlActive", isCtrlActive) } }
    @Published var isCmdActive: Bool { didSet { save("isCmdActive", isCmdActive) } }
    @Published var isOptActive: Bool { didSet { save("isOptActive", isOptActive) } }
    @Published var ctrlLang: String { didSet { save("ctrlLang", ctrlLang) } }
    @Published var cmdLang: String { didSet { save("cmdLang", cmdLang) } }
    @Published var optLang: String { didSet { save("optLang", optLang) } }
    
    @Published var showVisualFeedback: Bool { didSet { save("showVisualFeedback", showVisualFeedback) } }
    @Published var isTestMode: Bool { didSet { save("isTestMode", isTestMode) } }
    
    // 🌟 전역 토글 키 (한/영 변환키)
    @Published var toggleKeyCode: UInt16 { didSet { save("toggleKeyCode", toggleKeyCode) } }
    @Published var toggleModifierFlags: UInt64 { didSet { save("toggleModifierFlags", toggleModifierFlags) } }
    @Published var toggleDisplayString: String { didSet { save("toggleDisplayString", toggleDisplayString) } }
    
    @Published var customShortcuts: [CustomShortcut] = [] { didSet { if let e = try? JSONEncoder().encode(customShortcuts) { save("customShortcuts", e) } } }
    @Published var customApps: [CustomApp] = [] { didSet { if let e = try? JSONEncoder().encode(customApps) { save("customApps", e) } } }
    @Published var appLaunchShortcuts: [AppLaunchShortcut] = [] { didSet { if let e = try? JSONEncoder().encode(appLaunchShortcuts) { save("appLaunchShortcuts", e) } } }
    
    private init() {
        let d = UserDefaults.standard
        isCtrlActive = d.bool(forKey: "isCtrlActive"); isCmdActive = d.bool(forKey: "isCmdActive"); isOptActive = d.bool(forKey: "isOptActive")
        showVisualFeedback = d.object(forKey: "showVisualFeedback") as? Bool ?? true; isTestMode = d.bool(forKey: "isTestMode")
        
        // 🌟 토글 키 로드
        toggleKeyCode = UInt16(d.integer(forKey: "toggleKeyCode"))
        toggleModifierFlags = UInt64(d.integer(forKey: "toggleModifierFlags"))
        toggleDisplayString = d.string(forKey: "toggleDisplayString") ?? ""
        
        ctrlLang = d.string(forKey: "ctrlLang") ?? ""; cmdLang = d.string(forKey: "cmdLang") ?? ""; optLang = d.string(forKey: "optLang") ?? ""
        if let data = d.data(forKey: "customShortcuts"), let dec = try? JSONDecoder().decode([CustomShortcut].self, from: data) { customShortcuts = dec }
        if let data = d.data(forKey: "customApps"), let dec = try? JSONDecoder().decode([CustomApp].self, from: data) { customApps = dec }
        if let data = d.data(forKey: "appLaunchShortcuts"), let dec = try? JSONDecoder().decode([AppLaunchShortcut].self, from: data) { appLaunchShortcuts = dec }
    }
    
    private func save(_ key: String, _ value: Any) { UserDefaults.standard.set(value, forKey: key) }
    
    func exportBackup(to url: URL) throws {
        let backup = BackupData(
            isCtrlActive: isCtrlActive, isCmdActive: isCmdActive, isOptActive: isOptActive, ctrlLang: ctrlLang, cmdLang: cmdLang, optLang: optLang,
            showVisualFeedback: showVisualFeedback, isTestMode: isTestMode,
            toggleKeyCode: toggleKeyCode, toggleModifierFlags: toggleModifierFlags, toggleDisplayString: toggleDisplayString, // 🌟 백업 추가
            customShortcuts: customShortcuts, customApps: customApps, appLaunchShortcuts: appLaunchShortcuts
        )
        let encoder = JSONEncoder(); encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(backup); try data.write(to: url)
    }
    
    func importBackup(from url: URL) throws {
        let data = try Data(contentsOf: url); let backup = try JSONDecoder().decode(BackupData.self, from: data)
        DispatchQueue.main.async {
            self.isCtrlActive = backup.isCtrlActive; self.isCmdActive = backup.isCmdActive; self.isOptActive = backup.isOptActive
            self.ctrlLang = backup.ctrlLang; self.cmdLang = backup.cmdLang; self.optLang = backup.optLang
            self.showVisualFeedback = backup.showVisualFeedback; self.isTestMode = backup.isTestMode
            self.toggleKeyCode = backup.toggleKeyCode; self.toggleModifierFlags = backup.toggleModifierFlags; self.toggleDisplayString = backup.toggleDisplayString // 🌟 복원 추가
            self.customShortcuts = backup.customShortcuts; self.customApps = backup.customApps; self.appLaunchShortcuts = backup.appLaunchShortcuts
        }
    }
}
