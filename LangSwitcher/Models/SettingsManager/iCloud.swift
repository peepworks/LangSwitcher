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
            
            defer {
                self.saveAll()
                self.updateSnapshot()
                self.isBatchUpdating = false
            }
            
            let dict = self.icloudStore.dictionaryRepresentation
            
            // 전역 설정 동기화
            if let val = dict["showVisualFeedback"] as? Bool { self.showVisualFeedback = val }
            if let val = dict["isHyperKeyEnabled"] as? Bool { self.isHyperKeyEnabled = val }
            if let val = dict["isWindowMemoryEnabled"] as? Bool { self.isWindowMemoryEnabled = val }
            if let val = dict["isCursorHUDEnabled"] as? Bool { self.isCursorHUDEnabled = val }
            if let val = dict["isEdgeGlowEnabled"] as? Bool { self.isEdgeGlowEnabled = val }
            if let val = dict["isBrowserTabMemoryEnabled"] as? Bool { self.isBrowserTabMemoryEnabled = val }
            
            // 🌟 [핵심 수정] 다중 프로필 전체 배열 동기화 처리
            if let data = dict["profiles"] as? Data, let decodedProfiles = try? JSONDecoder().decode([SettingsProfile].self, from: data) {
                if !decodedProfiles.isEmpty {
                    self.profiles = decodedProfiles
                }
            }
            
            // 활성 프로필 ID 동기화
            if let activeIDString = dict["activeProfileID"] as? String, let activeID = UUID(uuidString: activeIDString) {
                // 가져온 프로필 목록 중에 해당 ID가 존재하는지 안전장치 확인 후 전환
                if self.profiles.contains(where: { $0.id == activeID }) {
                    self.activeProfileID = activeID
                }
            }
            
            // 싱글톤 매니저 강제 갱신
            DomainRuleManager.shared.rules = self.activeProfile.payload.domainRules
        }
    }

    func syncToCloud() {
        guard isCloudSyncEnabled, !isBatchUpdating else { return }
        
        // 전역 설정 업로드
        icloudStore.set(showVisualFeedback, forKey: "showVisualFeedback")
        icloudStore.set(isHyperKeyEnabled, forKey: "isHyperKeyEnabled")
        icloudStore.set(isWindowMemoryEnabled, forKey: "isWindowMemoryEnabled")
        icloudStore.set(isCursorHUDEnabled, forKey: "isCursorHUDEnabled")
        icloudStore.set(isHapticFeedbackEnabled, forKey: "isHapticFeedbackEnabled")
        icloudStore.set(isSoundFeedbackEnabled, forKey: "isSoundFeedbackEnabled")
        icloudStore.set(isEdgeGlowEnabled, forKey: "isEdgeGlowEnabled")
        icloudStore.set(isBrowserTabMemoryEnabled, forKey: "isBrowserTabMemoryEnabled")
        
        // 🌟 [핵심 수정] 파편화된 payload 대신 프로필 배열 전체와 활성 ID를 업로드
        if let encodedProfiles = try? JSONEncoder().encode(self.profiles) {
            icloudStore.set(encodedProfiles, forKey: "profiles")
        }
        icloudStore.set(self.activeProfileID.uuidString, forKey: "activeProfileID")
        
        icloudStore.synchronize()
    }
}
