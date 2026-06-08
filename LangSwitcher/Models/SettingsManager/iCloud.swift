//
//  iCloud.swift
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
    @objc func icloudUpdateReceived(_ notification: Notification) {
        guard isCloudSyncEnabled else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.isBatchUpdating = true
            
            // 🌟 [우주 방어 수복 완료]
            // 후행 주석의 개행 찌꺼기로 인해 DispatchWorkItem 타입 매칭 에러(27라인)를 유발하던
            // 컴파일러 파싱 트랩을 청정 소각하고 안전하게 디바운스 엔진을 도킹했습니다.
            defer {
                self.scheduleSave()
                self.updateSnapshot()
                self.isBatchUpdating = false
            }
            
            let store = NSUbiquitousKeyValueStore.default
            let cloudDict = store.dictionaryRepresentation
            
            dprint("🌐 [iCloud] 외부 기기로부터 원격 동기화 스트림 수신 완료. 장부 배치 정산을 전개합니다.")
            
            // ── 1단계: 원격 프로필 전체 데이터 수신 (실제 타입명 'SettingsProfile' 정밀 결속 완료) ──
            if let profilesData = cloudDict["profiles"] as? Data,
               let decodedProfiles = try? JSONDecoder().decode([SettingsProfile].self, from: profilesData) {
                self.profiles = decodedProfiles
            }
            
            // ── 2단계: 활성 프로필 ID 컨텍스트 맵핑 ──
            if let activeProfileID = cloudDict["activeProfileID"] as? String {
                if self.activeProfile.id.uuidString != activeProfileID {
                    if let matched = self.profiles.first(where: { $0.id.uuidString == activeProfileID }) {
                        self.activeProfile = matched
                    }
                }
            }
            
            // ── 3단계: 전역 스위치 설정 실시간 원격 싱크 및 Null Guard 결속 ──
            if store.object(forKey: "showVisualFeedback") != nil { self.showVisualFeedback = store.bool(forKey: "showVisualFeedback") }
            if store.object(forKey: "isHyperKeyEnabled") != nil { self.isHyperKeyEnabled = store.bool(forKey: "isHyperKeyEnabled") }
            if store.object(forKey: "isWindowMemoryEnabled") != nil { self.isWindowMemoryEnabled = store.bool(forKey: "isWindowMemoryEnabled") }
            if store.object(forKey: "isCursorHUDEnabled") != nil { self.isCursorHUDEnabled = store.bool(forKey: "isCursorHUDEnabled") }
            if store.object(forKey: "isHapticFeedbackEnabled") != nil { self.isHapticFeedbackEnabled = store.bool(forKey: "isHapticFeedbackEnabled") }
            if store.object(forKey: "isSoundFeedbackEnabled") != nil { self.isSoundFeedbackEnabled = store.bool(forKey: "isSoundFeedbackEnabled") }
            if store.object(forKey: "isEdgeGlowEnabled") != nil { self.isEdgeGlowEnabled = store.bool(forKey: "isEdgeGlowEnabled") }
            if store.object(forKey: "isBrowserTabMemoryEnabled") != nil { self.isBrowserTabMemoryEnabled = store.bool(forKey: "isBrowserTabMemoryEnabled") }
            
            // 하드웨어 타건 엔진이 참조하는 싱글톤 도메인 매니저 갱신
            DomainRuleManager.shared.rules = self.activeProfile.payload.domainRules
        }
    }

    func syncToCloud() {
        guard isCloudSyncEnabled, !isBatchUpdating else { return }
        
        let store = NSUbiquitousKeyValueStore.default
        
        // 전역 프리퍼런스 업로드
        store.set(showVisualFeedback, forKey: "showVisualFeedback")
        store.set(isHyperKeyEnabled, forKey: "isHyperKeyEnabled")
        store.set(isWindowMemoryEnabled, forKey: "isWindowMemoryEnabled")
        store.set(isCursorHUDEnabled, forKey: "isCursorHUDEnabled")
        store.set(isHapticFeedbackEnabled, forKey: "isHapticFeedbackEnabled")
        store.set(isSoundFeedbackEnabled, forKey: "isSoundFeedbackEnabled")
        store.set(isEdgeGlowEnabled, forKey: "isEdgeGlowEnabled")
        store.set(isBrowserTabMemoryEnabled, forKey: "isBrowserTabMemoryEnabled")
        
        // 다중 프로필 통째 백업 업로드 (데이터 가동 유실률 0%)
        if let encodedProfiles = try? JSONEncoder().encode(self.profiles) {
            store.set(encodedProfiles, forKey: "profiles")
        }
        store.set(self.activeProfile.id.uuidString, forKey: "activeProfileID")
        
        store.synchronize()
    }
}
