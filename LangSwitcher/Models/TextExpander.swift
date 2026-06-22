//
//  TextExpander.swift
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
import Foundation

@MainActor
class TextExpander {
    static let shared = TextExpander()
    private init() {}

    /// 🌟 [v0.9.5 전면 진화] 선택 텍스트 컨텍스트를 흡수하여 동적 변수와 탭스톱 장부를 통합 방출합니다.
    func expand(template: String, selectedText: String? = nil) -> RenderedSnippet {
        let tokens = SnippetTemplateParser.parse(template: template)
        return SnippetVariableRenderer.render(tokens: tokens, selectedText: selectedText)
    }

    func findMatch(for buffer: String, dict: [String: TextExpansionRule], maxLength: Int) -> TextExpansionRule? {
        guard !buffer.isEmpty, maxLength > 0 else { return nil }

        let checkLength = min(buffer.count, maxLength)
        let tail = buffer.suffix(checkLength)

        for length in stride(from: checkLength, through: 1, by: -1) {
            let suffix = String(tail.suffix(length))
            if let rule = dict[suffix], rule.isEnabled {
                return rule
            }
        }
        return nil
    }
}
