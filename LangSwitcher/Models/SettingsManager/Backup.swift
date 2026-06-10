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
    
    // 🌟 [8번 리뷰 수복 포인트: Swift 6 Concurrency 패러다임 전면 통일]
    // 후행 콜백 장부에 @MainActor 및 @Sendable 속성을 강제 결속하여 스레드 간 데이터 전송 무결성을 확보합니다.
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
            let data = try encoder.encode(backup) // Data 구조체는 안전한 Sendable 자산입니다.
            
            // 레거시 DispatchQueue.global을 소각하고 무거운 디스크 쓰기 연산(I/O)을 독립 백그라운드 태스크로 격리합니다.
            Task.detached(priority: .userInitiated) {
                do {
                    // 원자적(.atomic) 쓰기 옵션을 부여하여 저장 중 기습 종료 시 파일 파괴 리스크를 차단합니다.
                    try data.write(to: url, options: .atomic)
                    
                    // DispatchQueue.main.async 호출 엇박자를 제거하고 메인 액터 컨텍스트 복귀 호출을 확약(await)받습니다.
                    await completion(true, nil)
                } catch {
                    await completion(false, error)
                }
            }
        } catch {
            // 현재 스코프는 SettingsManager(@MainActor) 내부이므로 동일 액터 영역인 completion을 await 없이 즉시 동기 호출합니다.
            completion(false, error)
        }
    }

    // MARK: - 시스템 백업 데이터 인메모리 수복 및 물리 장부 복원 엔진
        
    func importBackup(from url: URL, completion: @escaping @MainActor @Sendable (Bool, Error?) -> Void = { _, _ in }) {
        
        Task { @MainActor in
            do {
                // 🌟 [우주 방어 수복 포인트 1: 스레드 분리 정산]
                // 스레드를 블로킹하는 범인인 '디스크 파일 로드(I/O)'만 백그라운드로 격리 추출합니다.
                let data = try await Task.detached(priority: .userInitiated) {
                    return try Data(contentsOf: url)
                } .value
                
                // 🌟 [우주 방어 수복 포인트 2: 격리 무혈 입성]
                // 인메모리 바이트를 DTO로 구워내는 디코딩 연산은 @MainActor 컨텍스트 본위로 복귀하여 집행합니다.
                let backup = try JSONDecoder().decode(BackupData.self, from: data)
                
                // 3. 파싱이 무결하게 성공했으므로 메인 액터 장치에 데이터 수복 개시
                self.isBatchUpdating = true
                
                // 전역 프리퍼런스 변수 복원
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
                
                // 전체 프로필 스택 또는 단일 활성 프로필 샌드박스 대입 분기 안정화
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
                
                // 하드웨어 입력 코어가 스캔하는 도메인 규칙 싱글톤 동기화
                DomainRuleManager.shared.rules = self.activeProfile.payload.domainRules
                
                // 로컬 디스크 직렬 write 및 스냅샷 정산 직렬 확약
                await self.saveAll()
                self.updateSnapshot()
                self.isBatchUpdating = false
                
                // 수복 성공 알림 뷰 후행 콜백 발동
                completion(true, nil)
                
            } catch {
                self.isBatchUpdating = false
                completion(false, error)
            }
        }
    }
}
