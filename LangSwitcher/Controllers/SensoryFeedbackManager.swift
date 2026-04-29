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
                // 이렇게 하면 빠르게 연타해도 소리가 뚝뚝 끊기지 않고 자연스럽게 겹쳐서(Overlapping) 들립니다.
                if let soundClone = baseSound?.copy() as? NSSound {
                    soundClone.play()
                }
            }
        }
    }
}
