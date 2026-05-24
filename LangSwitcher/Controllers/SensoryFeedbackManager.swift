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

@MainActor // 🌟 오디오 레이어 제어 및 전역 스냅샷 접근 안전성을 위해 메인 액터 격리 적용
class SensoryFeedbackManager {
    static let shared = SensoryFeedbackManager()

    // 원본 사운드는 이니셜라이즈 시점에 메모리에 딱 한 번만 올려두고 그대로 재사용합니다.
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
            let isKorean = id.lowercased().contains("ko") || id.contains("Hangul") || id.contains("두벌식") || id.contains("세벌식")
            let baseSound = isKorean ? self.soundKorean : self.soundEnglish

            // 🌟 [리뷰 반영 리팩토링 완료]
            // 무거운 .copy()를 완전히 도려내고, 기존 사운드를 즉시 멈춘 후 재시작하여
            // 메모리 할당(Alloc) 부하를 완전한 0% 고성능 상태로 고정합니다.
            if let sound = baseSound {
                sound.stop() // 진행 중인 소리가 있다면 즉시 자르고 플레이헤드 리셋
                sound.play() // 0초부터 깔끔하게 재시작
            } else {
                dprint("⚠️ [SensoryFeedbackManager] 사운드 재생 실패: baseSound 파일 자원을 찾을 수 없습니다.")
            }
        }
    }
}
