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
            // 🌟 현재 활성화된 프로필의 페이로드를 가져옵니다.
            let payload = activeProfile.payload
            
            let backup = BackupData(
                version: currentSettingsVersion,
                isCtrlActive: isCtrlActive, isCmdActive: isCmdActive, isOptActive: isOptActive,
                ctrlLang: ctrlLang, cmdLang: cmdLang, optLang: optLang,
                showVisualFeedback: showVisualFeedback, isTestMode: isTestMode,
                toggleKeyCode: toggleKeyCode, toggleModifierFlags: toggleModifierFlags, toggleDisplayString: toggleDisplayString,
                
                // 🌟 [수정] 프로필 페이로드 내부의 값들을 안전하게 매핑합니다.
                customShortcuts: payload.customShortcuts,
                customApps: payload.customApps,
                appLaunchShortcuts: payload.appLaunchShortcuts,
                excludedApps: payload.excludedApps,
                isTypoCorrectionEnabled: payload.isTypoCorrectionEnabled,
                typoKeyCode: payload.typoKeyCode,
                typoModifierFlags: payload.typoModifierFlags,
                typoDisplayString: payload.typoDisplayString,
                isSentenceMode: payload.isSentenceMode,
                isExcludedAppsEnabled: isExcludedAppsEnabled, // 전역 설정
                isAutoTypoCorrectionEnabled: payload.isAutoTypoCorrectionEnabled,
                isEdgeGlowEnabled: isEdgeGlowEnabled, // 전역 설정
                isAutoTypoCorrectionOnEnterEnabled: payload.isAutoTypoCorrectionOnEnterEnabled,
                isBrowserTabMemoryEnabled: isBrowserTabMemoryEnabled, // 전역 설정
                isBrowserDomainModeEnabled: payload.isBrowserDomainModeEnabled,
                domainRules: payload.domainRules,
                appDelays: payload.appDelays,
                isTextExpansionEnabled: payload.isTextExpansionEnabled,
                textExpansionRules: payload.textExpansionRules
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
                        
                        // 1. 전역 변수 복원
                        self.isCtrlActive = backup.isCtrlActive; self.isCmdActive = backup.isCmdActive; self.isOptActive = backup.isOptActive
                        self.ctrlLang = backup.ctrlLang; self.cmdLang = backup.cmdLang; self.optLang = backup.optLang
                        self.showVisualFeedback = backup.showVisualFeedback
                        self.isTestMode = false
                        self.toggleKeyCode = backup.toggleKeyCode; self.toggleModifierFlags = backup.toggleModifierFlags; self.toggleDisplayString = backup.toggleDisplayString
                        self.isExcludedAppsEnabled = backup.isExcludedAppsEnabled ?? true
                        self.isEdgeGlowEnabled = backup.isEdgeGlowEnabled ?? false
                        self.isBrowserTabMemoryEnabled = backup.isBrowserTabMemoryEnabled ?? false
                        
                        // 2. 🌟 프로필 데이터 복원 구조로 교체
                        // 백업 파일의 내용을 현재 활성화된 프로필의 payload에 채워 넣습니다.
                        var currentProfile = self.activeProfile
                        
                        currentProfile.payload.customShortcuts = backup.customShortcuts
                        currentProfile.payload.customApps = backup.customApps
                        currentProfile.payload.appLaunchShortcuts = backup.appLaunchShortcuts
                        currentProfile.payload.excludedApps = backup.excludedApps ?? []
                        currentProfile.payload.isTypoCorrectionEnabled = backup.isTypoCorrectionEnabled ?? false
                        currentProfile.payload.typoKeyCode = backup.typoKeyCode ?? 0
                        currentProfile.payload.typoModifierFlags = backup.typoModifierFlags ?? 0
                        currentProfile.payload.typoDisplayString = backup.typoDisplayString ?? ""
                        currentProfile.payload.isSentenceMode = backup.isSentenceMode ?? false
                        currentProfile.payload.isAutoTypoCorrectionEnabled = backup.isAutoTypoCorrectionEnabled ?? false
                        currentProfile.payload.isAutoTypoCorrectionOnEnterEnabled = backup.isAutoTypoCorrectionOnEnterEnabled ?? false
                        currentProfile.payload.isBrowserDomainModeEnabled = backup.isBrowserDomainModeEnabled ?? false
                        currentProfile.payload.domainRules = backup.domainRules ?? []
                        currentProfile.payload.appDelays = backup.appDelays ?? currentProfile.payload.appDelays
                        currentProfile.payload.isTextExpansionEnabled = backup.isTextExpansionEnabled ?? false
                        currentProfile.payload.textExpansionRules = backup.textExpansionRules ?? []
                        
                        // 변경된 프로필 저장 (세터 구동 -> 자동으로 캐시 세팅 및 스냅샷 전파)
                        self.activeProfile = currentProfile
                        
                        // 별도 동기화가 필요한 싱글톤 컴포넌트 갱신
                        DomainRuleManager.shared.rules = currentProfile.payload.domainRules
                        
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
