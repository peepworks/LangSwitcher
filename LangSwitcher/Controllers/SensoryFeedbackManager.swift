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
    
    private init() {}

    func playFeedback(forLanguageID id: String) {
        let snapshot = SettingsManager.shared.snapshot
        
        // 1. 햅틱(진동) 피드백 (트랙패드에서 '달칵' 하는 느낌)
        if snapshot.isHapticFeedbackEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        
        // 2. 효과음(사운드) 피드백 (기계식 키보드 소리)
        if snapshot.isSoundFeedbackEnabled {
            DispatchQueue.global(qos: .userInitiated).async {
                // 한글인지 영문인지 판별 (간단한 매핑)
                let isKorean = id.lowercased().contains("ko") || id.contains("Hangul") || id.contains("두벌식") || id.contains("세벌식")
                
                if isKorean {
                    // 한글 전환 시: 높은 톤 (🌟 [ClickHigh] 파일 사용)
                    if let customSound = NSSound(named: "ClickHigh") {
                        customSound.play()
                    } else {
                        // 파일이 없을 경우 macOS 기본음 Tink로 우회(Fallback)
                        NSSound(named: "Tink")?.play()
                    }
                } else {
                    // 영문 전환 시: 낮은 톤 (🌟 [ClickLow] 파일 사용)
                    if let customSound = NSSound(named: "ClickLow") {
                        customSound.play()
                    } else {
                        // 파일이 없을 경우 macOS 기본음 Pop으로 우회(Fallback)
                        NSSound(named: "Pop")?.play()
                    }
                }
            }
        }
    }
}
