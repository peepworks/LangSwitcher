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

import AppKit

/// 🌟 [4번 리뷰 완결 종결: 순정 햅틱 피드백 엔진]
/// 존재하지 않는 HapticManager 오염선들을 전부 소각하고,
/// macOS 표준 AppKit 자산인 NSHapticFeedbackManager로 직결 정산합니다.
final class SensoryFeedbackManager: Sendable {
    static let shared = SensoryFeedbackManager()
    
    private init() {} // 싱글톤 보호

    func playFeedback(for text: String) {
        // 우리가 뚫어놓은 단일 기준선(InputLanguage)을 통해 언어를 완벽하게 격리 인식합니다.
        let language = InputLanguage.determine(from: text)
        
        switch language {
        case .korean:
            // 🇰🇷 한국어 자판 전환 시: 탁 걸리는 명확한 경계 진동 (.alignment)
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            
        case .english:
            // 🇺🇸 영어 자판 전환 시: 가볍게 팅기는 진동 (.levelChange)
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            
        case .unknown:
            // 그 외 일반 전환 시: 표준 순정 햅틱 (.generic)
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
    }
}
