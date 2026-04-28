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
    
    // 🌟 [핵심 최적화] 사운드 객체를 매번 하드디스크에서 찾지 않고, 메모리에 딱 한 번만 올려두고 평생 재사용합니다.
    private let soundKorean = NSSound(named: "ClickHigh") ?? NSSound(named: "Tink")
    private let soundEnglish = NSSound(named: "ClickLow") ?? NSSound(named: "Pop")
    
    private init() {}

    func playFeedback(forLanguageID id: String) {
        let snapshot = SettingsManager.shared.snapshot
        
        // 1. 햅틱(진동) 피드백 (트랙패드에서 '달칵' 하는 느낌)
        // NSHapticFeedbackManager는 내부적으로 스레드 안전하게 처리되므로 그대로 둡니다.
        if snapshot.isHapticFeedbackEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        
        // 2. 효과음(사운드) 피드백 (기계식 키보드 소리)
        if snapshot.isSoundFeedbackEnabled {
            // AppKit 규칙에 따라 재생은 메인 스레드에서 안전하게 실행합니다.
            DispatchQueue.main.async {
                let isKorean = id.lowercased().contains("ko") || id.contains("Hangul") || id.contains("두벌식") || id.contains("세벌식")
                
                // 🌟 [핵심 수정] 매번 객체를 생성하지 않고, 미리 준비해 둔 객체의 재생 버튼만 누릅니다!
                let soundToPlay = isKorean ? self.soundKorean : self.soundEnglish
                soundToPlay?.play()
            }
        }
    }
}
