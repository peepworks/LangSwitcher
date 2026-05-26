//
//  SnippetModels.swift
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

// 1. 파싱된 템플릿의 각 요소를 나타내는 토큰
enum SnippetToken: Equatable {
    case text(String)           // 일반 텍스트
    case date(format: String)   // {{date:yyyy-MM-dd}}
    case time(format: String)   // {{time:HH:mm}}
    case clipboard              // {{clipboard}}
    case cursor                 // {{cursor}}
}

// 2. 최종 렌더링 결과물
struct RenderedSnippet {
    let text: String
    /// 최종 문자열 시작점(0) 기준의 커서 위치 (없으면 nil, 즉 문자열 끝)
    let cursorOffsetFromStart: Int?
}
