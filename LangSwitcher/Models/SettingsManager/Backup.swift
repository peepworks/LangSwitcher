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

extension SettingsManager {
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
                isAutoTypoCorrectionEnabled: isAutoTypoCorrectionEnabled,
                isEdgeGlowEnabled: isEdgeGlowEnabled,
                isAutoTypoCorrectionOnEnterEnabled: isAutoTypoCorrectionOnEnterEnabled,
                isBrowserTabMemoryEnabled: isBrowserTabMemoryEnabled,
                isBrowserDomainModeEnabled: isBrowserDomainModeEnabled,
                domainRules: domainRules,
                appDelays: appDelays // 🌟 추가 완료
            )
            
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(backup)
            
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

    func importBackup(from url: URL, completion: @escaping (Bool, Error?) -> Void = { _, _ in }) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let data = try Data(contentsOf: url)
                
                DispatchQueue.main.async {
                    do {
                        let backup = try JSONDecoder().decode(BackupData.self, from: data)
                        
                        self.isBatchUpdating = true
                        
                        defer {
                            self.saveAll()
                            self.updateSnapshot()
                            self.isBatchUpdating = false
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
                        
                        self.isBrowserTabMemoryEnabled = backup.isBrowserTabMemoryEnabled ?? false
                        self.isBrowserDomainModeEnabled = backup.isBrowserDomainModeEnabled ?? false
                        
                        self.domainRules = backup.domainRules ?? []
                        DomainRuleManager.shared.rules = self.domainRules
                        
                        self.appDelays = backup.appDelays ?? self.appDelays // 🌟 추가 완료
                        
                        self.isExcludedAppsEnabled = backup.isExcludedAppsEnabled ?? true
                        
                        completion(true, nil)
                    } catch {
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
