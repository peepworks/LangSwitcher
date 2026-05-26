//
//  Backup.swift
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

import Foundation

extension SettingsManager {
    func exportBackup(to url: URL, completion: @escaping (Bool, Error?) -> Void = { _, _ in }) {
        do {
            let backup = BackupData(
                version: currentSettingsVersion,
                isCtrlActive: isCtrlActive,
                isCmdActive: isCmdActive,
                isOptActive: isOptActive,
                ctrlLang: ctrlLang,
                cmdLang: cmdLang,
                optLang: optLang,
                showVisualFeedback: showVisualFeedback,
                isTestMode: isTestMode,
                toggleKeyCode: toggleKeyCode,
                toggleModifierFlags: UInt(toggleModifierFlags),
                toggleDisplayString: toggleDisplayString,
                
                isExcludedAppsEnabled: isExcludedAppsEnabled,
                isEdgeGlowEnabled: isEdgeGlowEnabled,
                isBrowserTabMemoryEnabled: isBrowserTabMemoryEnabled,
                
                profiles: self.profiles,
                activeProfileID: self.activeProfileID
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
                        
                        // 전역 변수 복원
                        self.isCtrlActive = backup.isCtrlActive ?? self.isCtrlActive
                        self.isCmdActive = backup.isCmdActive ?? self.isCmdActive
                        self.isOptActive = backup.isOptActive ?? self.isOptActive
                        self.ctrlLang = backup.ctrlLang ?? self.ctrlLang
                        self.cmdLang = backup.cmdLang ?? self.cmdLang
                        self.optLang = backup.optLang ?? self.optLang
                        self.showVisualFeedback = backup.showVisualFeedback ?? self.showVisualFeedback
                        self.isTestMode = false
                        
                        self.toggleKeyCode = backup.toggleKeyCode ?? self.toggleKeyCode
                        if let flags = backup.toggleModifierFlags {
                            self.toggleModifierFlags = UInt64(flags)
                        }
                        self.toggleDisplayString = backup.toggleDisplayString ?? self.toggleDisplayString
                        
                        self.isExcludedAppsEnabled = backup.isExcludedAppsEnabled ?? self.isExcludedAppsEnabled
                        self.isEdgeGlowEnabled = backup.isEdgeGlowEnabled ?? self.isEdgeGlowEnabled
                        self.isBrowserTabMemoryEnabled = backup.isBrowserTabMemoryEnabled ?? self.isBrowserTabMemoryEnabled
                        
                        // 프로필 데이터 복원 분기 처리
                        if let importedProfiles = backup.profiles, !importedProfiles.isEmpty {
                            self.profiles = importedProfiles
                            if let activeID = backup.activeProfileID {
                                self.activeProfileID = activeID
                            } else {
                                self.activeProfileID = importedProfiles[0].id
                            }
                        } else {
                            var currentProfile = self.activeProfile
                            
                            currentProfile.payload.customShortcuts = backup.customShortcuts ?? []
                            currentProfile.payload.customApps = backup.customApps ?? []
                            currentProfile.payload.appLaunchShortcuts = backup.appLaunchShortcuts ?? []
                            currentProfile.payload.excludedApps = backup.excludedApps ?? []
                            currentProfile.payload.isTypoCorrectionEnabled = backup.isTypoCorrectionEnabled ?? false
                            currentProfile.payload.typoKeyCode = backup.typoKeyCode ?? 0
                            
                            // 🌟 [핵심 수정] 여기서 UInt64로 캐스팅해줍니다!
                            currentProfile.payload.typoModifierFlags = UInt64(backup.typoModifierFlags ?? 0)
                            
                            currentProfile.payload.typoDisplayString = backup.typoDisplayString ?? ""
                            currentProfile.payload.isSentenceMode = backup.isSentenceMode ?? false
                            currentProfile.payload.isAutoTypoCorrectionEnabled = backup.isAutoTypoCorrectionEnabled ?? false
                            currentProfile.payload.isAutoTypoCorrectionOnEnterEnabled = backup.isAutoTypoCorrectionOnEnterEnabled ?? false
                            currentProfile.payload.isBrowserDomainModeEnabled = backup.isBrowserDomainModeEnabled ?? false
                            currentProfile.payload.domainRules = backup.domainRules ?? []
                            currentProfile.payload.appDelays = backup.appDelays ?? []
                            currentProfile.payload.isTextExpansionEnabled = backup.isTextExpansionEnabled ?? false
                            currentProfile.payload.textExpansionRules = backup.textExpansionRules ?? []
                            
                            if let index = self.profiles.firstIndex(where: { $0.id == currentProfile.id }) {
                                self.profiles[index] = currentProfile
                            }
                            self.activeProfileID = currentProfile.id
                        }
                        
                        DomainRuleManager.shared.rules = self.activeProfile.payload.domainRules
                        
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
