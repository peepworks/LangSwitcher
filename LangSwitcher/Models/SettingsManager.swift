//
//  LangSwitcher
//  Copyright (C) 2026 peepboy
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//

import Foundation
import Combine

struct CustomShortcut: Identifiable, Codable {
    var id = UUID()
    var keyCode: UInt16
    var modifierFlags: UInt64
    var displayString: String
    var targetLanguage: String
}

struct CustomApp: Identifiable, Codable {
    var id = UUID()
    var bundleIdentifier: String
    var appName: String
    var targetLanguage: String
}

struct AppLaunchShortcut: Identifiable, Codable {
    var id = UUID()
    var keyCode: UInt16
    var modifierFlags: UInt64
    var displayString: String
    var bundleIdentifier: String
    var appName: String
}

struct BackupData: Codable {
    let isCtrlActive: Bool
    let isCmdActive: Bool
    let isOptActive: Bool
    let ctrlLang: String
    let cmdLang: String
    let optLang: String
    let showVisualFeedback: Bool
    let isTestMode: Bool
    let customShortcuts: [CustomShortcut]
    let customApps: [CustomApp]
    let appLaunchShortcuts: [AppLaunchShortcut]
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
    
    @Published var customShortcuts: [CustomShortcut] = [] {
        didSet { if let encoded = try? JSONEncoder().encode(customShortcuts) { save("customShortcuts", encoded) } }
    }
    @Published var customApps: [CustomApp] = [] {
        didSet { if let encoded = try? JSONEncoder().encode(customApps) { save("customApps", encoded) } }
    }
    @Published var appLaunchShortcuts: [AppLaunchShortcut] = [] {
        didSet { if let encoded = try? JSONEncoder().encode(appLaunchShortcuts) { save("appLaunchShortcuts", encoded) } }
    }
    
    private init() {
        let d = UserDefaults.standard
        isCtrlActive = d.bool(forKey: "isCtrlActive")
        isCmdActive = d.bool(forKey: "isCmdActive")
        isOptActive = d.bool(forKey: "isOptActive")
        showVisualFeedback = d.object(forKey: "showVisualFeedback") as? Bool ?? true
        isTestMode = d.bool(forKey: "isTestMode")
        
        ctrlLang = d.string(forKey: "ctrlLang") ?? ""
        cmdLang = d.string(forKey: "cmdLang") ?? ""
        optLang = d.string(forKey: "optLang") ?? ""
        
        if let data = d.data(forKey: "customShortcuts"), let decoded = try? JSONDecoder().decode([CustomShortcut].self, from: data) { customShortcuts = decoded }
        if let data = d.data(forKey: "customApps"), let decoded = try? JSONDecoder().decode([CustomApp].self, from: data) { customApps = decoded }
        if let data = d.data(forKey: "appLaunchShortcuts"), let decoded = try? JSONDecoder().decode([AppLaunchShortcut].self, from: data) { appLaunchShortcuts = decoded }
    }
    
    private func save(_ key: String, _ value: Any) { UserDefaults.standard.set(value, forKey: key) }
    
    func exportBackup(to url: URL) throws {
        let backup = BackupData(
            isCtrlActive: isCtrlActive, isCmdActive: isCmdActive, isOptActive: isOptActive,
            ctrlLang: ctrlLang, cmdLang: cmdLang, optLang: optLang,
            showVisualFeedback: showVisualFeedback, isTestMode: isTestMode,
            customShortcuts: customShortcuts, customApps: customApps, appLaunchShortcuts: appLaunchShortcuts
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(backup)
        try data.write(to: url)
    }
    
    func importBackup(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let backup = try JSONDecoder().decode(BackupData.self, from: data)
        DispatchQueue.main.async {
            self.isCtrlActive = backup.isCtrlActive
            self.isCmdActive = backup.isCmdActive
            self.isOptActive = backup.isOptActive
            self.ctrlLang = backup.ctrlLang
            self.cmdLang = backup.cmdLang
            self.optLang = backup.optLang
            self.showVisualFeedback = backup.showVisualFeedback
            self.isTestMode = backup.isTestMode
            self.customShortcuts = backup.customShortcuts
            self.customApps = backup.customApps
            self.appLaunchShortcuts = backup.appLaunchShortcuts
        }
    }
}
