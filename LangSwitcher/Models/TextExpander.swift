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
import Foundation

class TextExpander {
    static let shared = TextExpander()
    private init() {}
    
    // 🌟 성능 최적화를 위한 공용 DateFormatter (딱 한 번만 생성됨)
    private static let sharedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        return formatter
    }()
    
    // 1. 버퍼에서 트리거 매칭 확인
    // 🌟 [수정] 파라미터로 스레드 세이프한 규칙 배열(rules)을 받도록 변경
    func findMatch(for buffer: String, rules: [TextExpansionRule]) -> TextExpansionRule? {
        // 외부에서 이미 정렬 및 필터링된 배열을 받으므로 즉시 순회합니다.
        for rule in rules {
            if buffer.hasSuffix(rule.trigger) {
                return rule
            }
        }
        return nil
    }
    
    // 🌟 [수정/추가] 기존 parseDynamicVariables를 대체하는 새로운 확장 진입점
    func expand(template: String) -> RenderedSnippet {
        let tokens = SnippetTemplateParser.parse(template: template)
        return SnippetVariableRenderer.render(tokens: tokens)
    }
}
