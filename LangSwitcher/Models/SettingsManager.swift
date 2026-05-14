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

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    let currentSettingsVersion = "1.0.0"
    
    let icloudStore = NSUbiquitousKeyValueStore.default
    private let snapshotQueue = DispatchQueue(label: "com.peepworks.settings.snapshot", attributes: .concurrent)
    private var _snapshot = SettingsSnapshot(isTextExpansionEnabled: false, textExpansionRules: [])
    private var saveWorkItem: DispatchWorkItem?
    
    @MainActor var isBatchUpdating: Bool = false
    
    @Published var isCtrlActive: Bool { didSet { save("isCtrlActive", isCtrlActive); scheduleSave() } }
    @Published var isCmdActive: Bool { didSet { save("isCmdActive", isCmdActive); scheduleSave() } }
    @Published var isOptActive: Bool { didSet { save("isOptActive", isOptActive); scheduleSave() } }
    @Published var ctrlLang: String { didSet { save("ctrlLang", ctrlLang); scheduleSave() } }
    @Published var cmdLang: String { didSet { save("cmdLang", cmdLang); scheduleSave() } }
    @Published var optLang: String { didSet { save("optLang", optLang); scheduleSave() } }
        
    @Published var showVisualFeedback: Bool { didSet { save("showVisualFeedback", showVisualFeedback); scheduleSave() } }
    @Published var isTestMode: Bool { didSet { save("isTestMode", isTestMode); updateSnapshot() } }
    
    @Published var toggleKeyCode: UInt16 { didSet { save("toggleKeyCode", toggleKeyCode); updateSnapshot() } }
    @Published var toggleModifierFlags: UInt64 { didSet { save("toggleModifierFlags", toggleModifierFlags); updateSnapshot() } }
    @Published var toggleDisplayString: String { didSet { save("toggleDisplayString", toggleDisplayString); updateSnapshot() } }
    
    // 🌟 중복 선언 제거 및 통합 완료 (캐시 업데이트 연결)
    @Published var customShortcuts: [CustomShortcut] = [] { didSet { scheduleSave(); updateShortcutCaches() } }
    @Published var appLaunchShortcuts: [AppLaunchShortcut] = [] { didSet { scheduleSave(); updateShortcutCaches() } }
    
    @Published var customApps: [CustomApp] = [] { didSet { scheduleSave() } }
    @Published var excludedApps: [ExcludedApp] = [] { didSet { scheduleSave() } }
    
    // 🌟 앱 딜레이 배열
    @Published var appDelays: [AppDelay] = [] { didSet { scheduleSave() } }
    
    @Published var domainRules: [DomainRule] = [] {
        didSet {
            scheduleSave()
            DomainRuleManager.shared.rules = domainRules
        }
    }
    
    @Published var isTypoCorrectionEnabled: Bool { didSet { save("isTypoCorrectionEnabled", isTypoCorrectionEnabled); updateSnapshot(); syncToCloud() } }
    @Published var typoKeyCode: UInt16 { didSet { save("typoKeyCode", typoKeyCode); updateSnapshot() } }
    @Published var typoModifierFlags: UInt64 { didSet { save("typoModifierFlags", typoModifierFlags); updateSnapshot() } }
    @Published var typoDisplayString: String { didSet { save("typoDisplayString", typoDisplayString); updateSnapshot() } }
    @Published var isSentenceMode: Bool { didSet { save("isSentenceMode", isSentenceMode); updateSnapshot() } }
    
    @Published private(set) var recentLogs: [ActionLog] = []
    
    // 🌟 [추가] 미리 필터링 및 정렬된 텍스트 대치 규칙 캐시
    @Published private(set) var cachedActiveTextExpansionRules: [TextExpansionRule] = []

    @Published var textExpansionRules: [TextExpansionRule] = [] {
        didSet {
            scheduleSave()
            updateTextExpansionCache() // 🌟 저장될 때마다 캐시 업데이트
        }
    }
    
    // 🌟 [추가] 빛의 속도로 검색하기 위한 딕셔너리 캐시
    private(set) var customShortcutCache: [ShortcutKey: CustomShortcut] = [:]
    private(set) var appLaunchShortcutCache: [ShortcutKey: AppLaunchShortcut] = [:]

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
    @AppStorage("isAutoTypoCorrectionOnEnterEnabled") var isAutoTypoCorrectionOnEnterEnabled: Bool = false { didSet { updateSnapshot(); syncToCloud() } }
    
    @AppStorage("isBrowserTabMemoryEnabled") var isBrowserTabMemoryEnabled: Bool = false { didSet { updateSnapshot(); syncToCloud() } }
    @AppStorage("isBrowserDomainModeEnabled") var isBrowserDomainModeEnabled: Bool = false { didSet { updateSnapshot(); syncToCloud() } }
    @AppStorage("newTabDefaultLanguage") var newTabDefaultLanguage: String = "None" { didSet { updateSnapshot(); syncToCloud() } }
    
    // 🌟 [추가됨] 텍스트 대치 기능 전체 활성화/비활성화 토글
    @AppStorage("isTextExpansionEnabled") var isTextExpansionEnabled: Bool = false { didSet { updateSnapshot(); syncToCloud() } }

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
        
        // 🌟 텍스트 대치 규칙 불러오기 및 기본 프리셋 제공
        if let data = d.data(forKey: "textExpansionRules"), let dec = try? JSONDecoder().decode([TextExpansionRule].self, from: data) {
            textExpansionRules = dec
        } else {
            textExpansionRules = [
                TextExpansionRule(id: UUID(), trigger: ";date", replacement: "{{date:yyyy-MM-dd}}", isEnabled: true),
                TextExpansionRule(id: UUID(), trigger: ";time", replacement: "{{date:HH:mm}}", isEnabled: true),
                TextExpansionRule(id: UUID(), trigger: ";now", replacement: "{{date:yyyy-MM-dd HH:mm}}", isEnabled: true),
                TextExpansionRule(id: UUID(), trigger: ";day", replacement: "{{date:EEEE}}", isEnabled: true),
                TextExpansionRule(id: UUID(), trigger: ";clip", replacement: "{{clipboard}}", isEnabled: true)
            ]
        }
        
        if let data = d.data(forKey: "domainRules"), let dec = try? JSONDecoder().decode([DomainRule].self, from: data) {
            domainRules = dec
            DomainRuleManager.shared.rules = dec
        }
        
        if let data = d.data(forKey: "appDelays"), let dec = try? JSONDecoder().decode([AppDelay].self, from: data) {
            appDelays = dec
        } else {
            appDelays = [
                AppDelay(bundleIdentifier: "com.microsoft.VSCode", appName: "Visual Studio Code", delay: 0.7),
                AppDelay(bundleIdentifier: "com.tinyspeck.slackmacgap", appName: "Slack", delay: 0.6),
                AppDelay(bundleIdentifier: "com.hnc.Discord", appName: "Discord", delay: 0.6),
                AppDelay(bundleIdentifier: "notion.id", appName: "Notion", delay: 0.6),
                AppDelay(bundleIdentifier: "md.obsidian", appName: "Obsidian", delay: 0.5),
                AppDelay(bundleIdentifier: "com.google.Chrome", appName: "Google Chrome", delay: 0.4)
            ]
        }
        
        isTypoCorrectionEnabled = d.object(forKey: "isTypoCorrectionEnabled") as? Bool ?? false
        typoKeyCode = UInt16(d.integer(forKey: "typoKeyCode"))
        typoModifierFlags = UInt64(d.integer(forKey: "typoModifierFlags"))
        typoDisplayString = d.string(forKey: "typoDisplayString") ?? ""
        isSentenceMode = d.object(forKey: "isSentenceMode") as? Bool ?? false
        
        updateSnapshot()
        // 앱 실행 시 최초 1회 캐시 빌드 (초기화 단계에서 didSet이 작동하지 않을 수 있으므로)
        updateShortcutCaches()
        updateTextExpansionCache()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(icloudUpdateReceived(_:)), // iCloud 연동 함수가 있다면
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: icloudStore
        )
        icloudStore.synchronize()
    }

    private func save(_ key: String, _ value: Any) {
        UserDefaults.standard.set(value, forKey: key)
    }
    
    func saveAll() {
        let d = UserDefaults.standard
        if let e = try? JSONEncoder().encode(customShortcuts) { d.set(e, forKey: "customShortcuts") }
        if let e = try? JSONEncoder().encode(customApps) { d.set(e, forKey: "customApps") }
        if let e = try? JSONEncoder().encode(appLaunchShortcuts) { d.set(e, forKey: "appLaunchShortcuts") }
        if let e = try? JSONEncoder().encode(excludedApps) { d.set(e, forKey: "excludedApps") }
        if let e = try? JSONEncoder().encode(domainRules) { d.set(e, forKey: "domainRules") }
        if let e = try? JSONEncoder().encode(appDelays) { d.set(e, forKey: "appDelays") }
        if let e = try? JSONEncoder().encode(textExpansionRules) { d.set(e, forKey: "textExpansionRules") }
    }
    
    var snapshot: SettingsSnapshot {
        snapshotQueue.sync { _snapshot }
    }
        
    func updateSnapshot() {
        var newSnapshot = SettingsSnapshot(
            isCtrlActive: isCtrlActive, isCmdActive: isCmdActive, isOptActive: isOptActive,
            ctrlLang: ctrlLang, cmdLang: cmdLang, optLang: optLang,
            showVisualFeedback: showVisualFeedback, isTestMode: isTestMode,
            toggleKeyCode: toggleKeyCode, toggleModifierFlags: toggleModifierFlags, toggleDisplayString: toggleDisplayString,
            isSentenceMode: isSentenceMode,
            isHyperKeyEnabled: isHyperKeyEnabled,
            isAppLaunchEnabled: isAppLaunchEnabled, isCustomShortcutsEnabled: isCustomShortcutsEnabled,
            isExcludedAppsEnabled: isExcludedAppsEnabled,
            isAppSpecificEnabled: isAppSpecificEnabled,
            isWindowMemoryEnabled: isWindowMemoryEnabled,
            isWindowMemoryCleanupEnabled: isWindowMemoryCleanupEnabled,
            isCursorHUDEnabled: isCursorHUDEnabled,
            isCloudSyncEnabled: isCloudSyncEnabled,
            isHapticFeedbackEnabled: isHapticFeedbackEnabled,
            isSoundFeedbackEnabled: isSoundFeedbackEnabled,
            isAutoTypoCorrectionEnabled: isAutoTypoCorrectionEnabled,
            isEdgeGlowEnabled: isEdgeGlowEnabled,
            isAutoTypoCorrectionOnEnterEnabled: isAutoTypoCorrectionOnEnterEnabled,
            isBrowserTabMemoryEnabled: isBrowserTabMemoryEnabled,
            isBrowserDomainModeEnabled: isBrowserDomainModeEnabled,
            newTabDefaultLanguage: newTabDefaultLanguage,
            isTypoCorrectionEnabled: isTypoCorrectionEnabled,
            typoKeyCode: typoKeyCode, typoModifierFlags: typoModifierFlags, typoDisplayString: typoDisplayString,
            customApps: customApps,
            appLaunchShortcuts: appLaunchShortcuts,
            excludedApps: excludedApps,
            customShortcuts: customShortcuts,
            domainRules: domainRules,
            appDelays: appDelays,
            isTextExpansionEnabled: isTextExpansionEnabled,
            textExpansionRules: textExpansionRules
        )
        
        // 🌟 스냅샷에 딕셔너리 캐시 미리 구워두기
        newSnapshot.buildCaches()
        
        EventMonitor.shared.updateSettingsSnapshot(newSnapshot)
        snapshotQueue.async(flags: .barrier) {
            self._snapshot = newSnapshot
        }
    }
    
    func addLog(_ log: ActionLog) {
        DispatchQueue.main.async {
            self.recentLogs.insert(log, at: 0)
            while self.recentLogs.count > 50 {
                self.recentLogs.removeLast()
            }
        }
    }
    
    private func scheduleSave() {
        saveWorkItem?.cancel()
        
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            
            self.performActualSave()
            
            DispatchQueue.main.async {
                self.updateSnapshot()
                if !self.isBatchUpdating { self.syncToCloud() }
            }
        }
        
        saveWorkItem = workItem
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }
    
    private func performActualSave() {
        self.saveAll()
        #if DEBUG
        print("SettingsManager: 배열 데이터들이 디스크에 저장되었습니다.")
        #endif
    }
    
    // 🌟 [추가] 캐시 업데이트 함수 (isEnabled를 확인하여 필터링)
    private func updateTextExpansionCache() {
        cachedActiveTextExpansionRules = textExpansionRules
            .filter { $0.isEnabled } // 🌟 isActive를 isEnabled로 수정완료
            .sorted { $0.trigger.count > $1.trigger.count }
    }
    
    // 🌟 [추가] 딕셔너리 업데이트 함수
    private func updateShortcutCaches() {
        customShortcutCache.removeAll()
        for shortcut in customShortcuts {
            let key = ShortcutKey(keyCode: shortcut.keyCode, modifiers: shortcut.modifierFlags)
            customShortcutCache[key] = shortcut
        }
        
        appLaunchShortcutCache.removeAll()
        for shortcut in appLaunchShortcuts {
            let key = ShortcutKey(keyCode: shortcut.keyCode, modifiers: shortcut.modifierFlags)
            appLaunchShortcutCache[key] = shortcut
        }
    }
    
    // MARK: - Cache & Memory Management
    @MainActor
    func restoreDefaultAppDelays() {
        self.appDelays = [
            AppDelay(bundleIdentifier: "com.microsoft.VSCode", appName: "Visual Studio Code", delay: 0.7),
            AppDelay(bundleIdentifier: "com.tinyspeck.slackmacgap", appName: "Slack", delay: 0.6),
            AppDelay(bundleIdentifier: "com.hnc.Discord", appName: "Discord", delay: 0.6),
            AppDelay(bundleIdentifier: "notion.id", appName: "Notion", delay: 0.6),
            AppDelay(bundleIdentifier: "md.obsidian", appName: "Obsidian", delay: 0.5),
            AppDelay(bundleIdentifier: "com.google.Chrome", appName: "Google Chrome", delay: 0.4)
        ]
    }
    
    // MARK: - Text Expansion Only Backup/Restore
    func exportTextExpansionRules(to url: URL, completion: @escaping (Bool, Error?) -> Void = { _, _ in }) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(textExpansionRules)
            
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try data.write(to: url)
                    DispatchQueue.main.async { completion(true, nil) }
                } catch {
                    DispatchQueue.main.async { completion(false, error) }
                }
            }
        } catch {
            completion(false, error)
        }
    }

    func importTextExpansionRules(from url: URL, completion: @escaping (Bool, Error?) -> Void = { _, _ in }) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let data = try Data(contentsOf: url)
                DispatchQueue.main.async {
                    do {
                        let importedRules = try JSONDecoder().decode([TextExpansionRule].self, from: data)
                        
                        for rule in importedRules {
                            if !self.textExpansionRules.contains(where: { $0.trigger == rule.trigger }) {
                                self.textExpansionRules.append(rule)
                            }
                        }
                        
                        self.saveAll()
                        completion(true, nil)
                    } catch {
                        completion(false, error)
                    }
                }
            } catch {
                DispatchQueue.main.async { completion(false, error) }
            }
        }
    }
}
