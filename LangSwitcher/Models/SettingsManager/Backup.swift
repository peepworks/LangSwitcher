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
    
    func exportBackup(to url: URL, completion: @escaping @MainActor @Sendable (Bool, Error?) -> Void = { _, _ in }) {
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
            
            Task.detached(priority: .userInitiated) {
                do {
                    try data.write(to: url, options: .atomic)
                    await completion(true, nil)
                } catch {
                    await completion(false, error)
                }
            }
        } catch {
            completion(false, error)
        }
    }

    // MARK: - 시스템 백업 데이터 인메모리 수복 및 물리 장부 복원 엔진
        
    func importBackup(from url: URL, completion: @escaping @MainActor @Sendable (Bool, Error?) -> Void = { _, _ in }) {
        
        Task { @MainActor in
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    return try Data(contentsOf: url)
                } .value
                
                let backup = try JSONDecoder().decode(BackupData.self, from: data)
                
                // 🌟 [수복] 접근 제한 문제를 피하기 위해 setter 대신 메서드 사용
                self.beginBatchUpdate()
                
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
                
                if let importedProfiles = backup.profiles, !importedProfiles.isEmpty {
                    self.profiles = importedProfiles
                    let activeID = backup.activeProfileID ?? importedProfiles[0].id
                    self.activeProfileID = activeID
                    
                    // 🌟 [수복] 싱글톤 동기화 정밀 정산
                    // 1. 기존 싱글톤의 잔재를 완전히 플러시(Flush)합니다.
                    TypoExceptionManager.shared.excludedWords.removeAll()
                    
                    // 2. 복원된 페이로드의 데이터를 싱글톤에 주입합니다.
                    if let activeProfile = self.profiles.first(where: { $0.id == activeID }) {
                        TypoExceptionManager.shared.excludedWords = activeProfile.payload.typoExcludedWords
                    }
                } else {
                    var currentProfile = self.activeProfile
                    
                    currentProfile.payload.customShortcuts = backup.customShortcuts ?? []
                    currentProfile.payload.customApps = backup.customApps ?? []
                    currentProfile.payload.appLaunchShortcuts = backup.appLaunchShortcuts ?? []
                    currentProfile.payload.excludedApps = backup.excludedApps ?? []
                    currentProfile.payload.isTypoCorrectionEnabled = backup.isTypoCorrectionEnabled ?? false
                    currentProfile.payload.typoKeyCode = backup.typoKeyCode ?? 0
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
                
                await self.saveAll()
                self.updateSnapshot()
                
                // 🌟 [수복] setter 대신 메서드 사용
                self.endBatchUpdate()
                
                completion(true, nil)
                
            } catch {
                // 🌟 [수복] 에러 발생 시에도 안전하게 배치 업데이트 종료
                self.endBatchUpdate()
                completion(false, error)
            }
        }
    }
}
