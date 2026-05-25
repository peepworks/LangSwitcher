//
//  SensoryFeedbackManager.swift
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

import Cocoa

@MainActor // 🌟 Swift 6 가드: 오디오 하드웨어 제어 및 스냅샷 조회를 메인 액터로 격리
class SensoryFeedbackManager {
    static let shared = SensoryFeedbackManager()

    // 원본 사운드는 초기화 시점에 런타임에 딱 한 번만 메모리에 상주
    private let soundKorean = NSSound(named: "ClickHigh") ?? NSSound(named: "Tink")
    private let soundEnglish = NSSound(named: "ClickLow") ?? NSSound(named: "Pop")

    // 🌟 [리뷰 반영] 현재 재생 중인 사운드의 인스턴스 주소를 추적할 평생 단 하나의 슬롯
    private var activeSound: NSSound? = nil

    private init() {}

    func playFeedback(forLanguageID id: String) {
        let snapshot = SettingsManager.shared.snapshot

        // 1. 햅틱(진동) 피드백 처리
        if snapshot.isHapticFeedbackEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }

        // 2. 효과음(사운드) 피드백 처리
        guard snapshot.isSoundFeedbackEnabled else { return }
        
        let isKorean = id.lowercased().contains("ko") || id.contains("Hangul") || id.contains("두벌식") || id.contains("세벌식")
        let baseSound = isKorean ? self.soundKorean : self.soundEnglish
        guard let sound = baseSound else { return }

        // 🌟 [완벽한 아키텍처 개편]
        // 1. 이전 언어의 잔재 소리가 아직 흐르고 있다면 물리적으로 즉시 전원을 차단(인터럽트)
        self.activeSound?.stop()
        
        // 2. 새로운 사운드로 슬롯 포인터 스위칭 (카피 없음, 비용 0)
        self.activeSound = sound
        
        // 3. 동기식 즉시 시작 가드 실행
        sound.stop()
        sound.play()
    }
}
