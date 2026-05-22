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

import Cocoa

class SensoryFeedbackManager {
    static let shared = SensoryFeedbackManager()
    
    // 🌟 원본 사운드는 메모리에 딱 한 번만 올려두고 '틀(Template)'로만 사용합니다.
    private let soundKorean = NSSound(named: "ClickHigh") ?? NSSound(named: "Tink")
    private let soundEnglish = NSSound(named: "ClickLow") ?? NSSound(named: "Pop")
    
    private init() {}

    func playFeedback(forLanguageID id: String) {
        let snapshot = SettingsManager.shared.snapshot
        
        // 1. 햅틱(진동) 피드백
        if snapshot.isHapticFeedbackEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        
        // 2. 효과음(사운드) 피드백
        if snapshot.isSoundFeedbackEnabled {
            DispatchQueue.main.async {
                let isKorean = id.lowercased().contains("ko") || id.contains("Hangul") || id.contains("두벌식") || id.contains("세벌식")
                
                let baseSound = isKorean ? self.soundKorean : self.soundEnglish
                
                // 🌟 [핵심 수정] 원본을 멈추지 않고 복제본(clone)을 생성하여 재생합니다.
                // 1순위: 복사본을 만든다. (빠르게 연타해도 소리가 겹치도록)
                // 2순위: 시스템 리소스 부족 등으로 복사에 실패하면(??), 원본(baseSound)을 대신 쓴다.
                let soundToPlay = (baseSound?.copy() as? NSSound) ?? baseSound
                
                // 찾아낸 소리(복사본 혹은 원본)를 재생한다.
                soundToPlay?.play()
                
                // 만약 baseSound 자체가 아예 없다면(파일 유실 등) 디버그 로그 출력
                if soundToPlay == nil {
                    dprint("⚠️ [SensoryFeedbackManager] 사운드 재생 실패: baseSound 파일 자체를 찾을 수 없습니다.")
                }
            }
        }
    }
}
