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
    
    // 🌟 딕셔너리(dict)를 받아 O(1) 속도로 탐색하는 함수
    func findMatch(for buffer: String, dict: [String: TextExpansionRule], maxLength: Int) -> TextExpansionRule? {
        // 버퍼가 비어있거나 찾을 길이가 없으면 즉시 종료
        guard !buffer.isEmpty, maxLength > 0 else { return nil }
        
        let checkLength = min(buffer.count, maxLength)
        
        // 🌟 [핵심 개선] 거대한 원본 buffer 대신, 끝에서부터 필요한 만큼만
        // 메모리를 공유하는 투명한 창문(Substring)을 딱 한 번만 만듭니다. (비용 0)
        let tail = buffer.suffix(checkLength)
        
        for length in stride(from: checkLength, through: 1, by: -1) {
            // 이미 짧아진 tail 안에서 자르므로 CPU와 메모리 소모가 거의 없습니다.
            let suffix = String(tail.suffix(length))
            
            // 🌟 [추가됨] 딕셔너리에서 규칙을 찾고, 그 규칙이 '켜져 있을 때(isEnabled)'만 반환합니다.
            if let rule = dict[suffix], rule.isEnabled {
                return rule
            }
        }
        
        return nil
    }
}
