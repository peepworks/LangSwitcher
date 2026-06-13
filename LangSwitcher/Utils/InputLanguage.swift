//
//  InputLanguage.swift
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

/// 🌟 [4번 리뷰 수복 포인트: 전역 공용 언어 판별 엔진]
/// 입력 소스의 localizedName 또는 ID 문자열을 단 하나의 중앙 집중식 기준으로 평가하여 토큰화합니다.
enum InputLanguage: String, Sendable {
    case korean
    case english
    case unknown

    /// 문자열 이름을 기반으로 정확한 언어 카테고리를 판정합니다. (모든 매니저 공용 기준선)
    static func determine(from text: String) -> InputLanguage {
        let lower = text.lowercased()
        
        // 1. 영어 계열 통합 판정
        if lower.contains("u.s.") || lower.contains("abc") || lower.contains("english") || lower.contains("en-") {
            return .english
        }
        
        // 2. 한국어 계열 통합 판정
        if lower.contains("ko") || lower.contains("한국어") || lower.contains("korean") || lower.contains("2-set") || lower.contains("3-set") {
            return .korean
        }
        
        return .unknown
    }

    /// HUD나 UI 레이어에 뿌려줄 표준화된 1글자 심볼을 반환합니다.
    func shortLabel(fallbackText: String) -> String {
        switch self {
        case .korean: return "한"
        case .english: return "A"
        case .unknown: return String(fallbackText.prefix(1).uppercased())
        }
    }
}
