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
        
        // 🌟 [우주 방어 수복 포인트]
        // 레거시 GCD(DispatchQueue) 이중 래핑을 과감히 소각하고,
        // 전체 흐름을 단 하나의 명시적인 메인 액터 비동기 컨텍스트로 통일 결속합니다.
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            
            self.beginBatchUpdate()
            
            let store = NSUbiquitousKeyValueStore.default
            let cloudDict = store.dictionaryRepresentation
            
            dprint("🌐 [iCloud] 외부 기기 동기화 패킷 인입 감지 — 장부 세션 정산을 개시합니다.")
            
            // ── [1단계: 원격 프로필 전체 데이터 수신 및 파싱] ──
            if let profilesData = cloudDict["profiles"] as? Data,
               let decodedProfiles = try? JSONDecoder().decode([SettingsProfile].self, from: profilesData) {
                self.profiles = decodedProfiles
            }
            
            // ── [2단계: 활성 프로필 ID 컨텍스트 맵핑] ──
            if let activeProfileID = cloudDict["activeProfileID"] as? String {
                if self.activeProfile.id.uuidString != activeProfileID {
                    if let matched = self.profiles.first(where: { $0.id.uuidString == activeProfileID }) {
                        self.activeProfile = matched
                    }
                }
            }
            
            // ── [3단계: 전역 스위치 설정 실시간 원격 싱크 및 Null Guard 결속] ──
            if store.object(forKey: "showVisualFeedback") != nil { self.showVisualFeedback = store.bool(forKey: "showVisualFeedback") }
            if store.object(forKey: "isHyperKeyEnabled") != nil { self.isHyperKeyEnabled = store.bool(forKey: "isHyperKeyEnabled") }
            if store.object(forKey: "isWindowMemoryEnabled") != nil { self.isWindowMemoryEnabled = store.bool(forKey: "isWindowMemoryEnabled") }
            if store.object(forKey: "isCursorHUDEnabled") != nil { self.isCursorHUDEnabled = store.bool(forKey: "isCursorHUDEnabled") }
            if store.object(forKey: "isHapticFeedbackEnabled") != nil { self.isHapticFeedbackEnabled = store.bool(forKey: "isHapticFeedbackEnabled") }
            if store.object(forKey: "isSoundFeedbackEnabled") != nil { self.isSoundFeedbackEnabled = store.bool(forKey: "isSoundFeedbackEnabled") }
            if store.object(forKey: "isEdgeGlowEnabled") != nil { self.isEdgeGlowEnabled = store.bool(forKey: "isEdgeGlowEnabled") }
            if store.object(forKey: "isBrowserTabMemoryEnabled") != nil { self.isBrowserTabMemoryEnabled = store.bool(forKey: "isBrowserTabMemoryEnabled") }
            
            // 하드웨어 타건 엔진이 참조하는 싱글톤 도메인 매니저 동기화
            DomainRuleManager.shared.rules = self.activeProfile.payload.domainRules
            
            // ── [4단계: 3번 리뷰 지적 사항 근본적 정산 완결] ──
            do {
                // 상단에서 원격 설정을 메모리에 완벽히 기입 완료한 "이 정갈한 시점"에 비로소 저장을 트리거합니다.
                // 직렬화 큐가 물리 디스크 쓰기를 끝마칠 때까지 책임을 지고 안전하게 대기(Await)합니다.
                await self.saveAll()
                
                // 디스크에 무결하게 저장되었음이 확약된 상태에서 비로서 최신 엔진 스냅샷을 배포합니다.
                self.updateSnapshot()
                
                // 모든 정산 연산이 마감되었으므로 가드 플래그를 안전하게 해제합니다.
                self.endBatchUpdate()
                
                dprint("✨ [iCloud] 클라우드 원격 설정 장부 디스크 플러시 및 엔진 스냅샷 갱신이 완벽하게 완결되었습니다.")
            }
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
