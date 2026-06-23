//
//  SnippetTemplateParser.swift
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

struct SnippetTemplateParser {
    
    // 🌟 [수복 정산] {{cursor}} 문법을 안전하게 포획하도록 1번 캡처 그룹에 cursor 보초를 공식 매립했습니다.
    private static let unifiedRegex = #/(?:\{\{(date|time|clipboard|cursor)(?::([^}]+))?\}\})|(?:\$\{(selection|selectedText|0|([1-9]\d*)(?::([^}]+))?)\})/#

    static func parse(template: String) -> [SnippetToken] {
        var tokens: [SnippetToken] = []
        var lastIndex = template.startIndex
        
        let matches = template.matches(of: unifiedRegex)
        
        for match in matches {
            let matchRange = match.range
            
            if matchRange.lowerBound > lastIndex {
                let staticText = String(template[lastIndex..<matchRange.lowerBound])
                tokens.append(.text(staticText))
            }
            
            let output = match.output
            
            if let legacyKeyword = output.1 {
                let keywordStr = String(legacyKeyword)
                let customFormat = output.2.map { String($0) }
                
                switch keywordStr {
                case "date":
                    tokens.append(.date(format: customFormat ?? "yyyy-MM-dd"))
                case "time":
                    tokens.append(.time(format: customFormat ?? "HH:mm"))
                case "clipboard":
                    tokens.append(.clipboard)
                case "cursor":
                    // 🌟 {{cursor}} 기호가 감지되면 신형 ${0}과 동일하게 커서 최종 안착 장부로 완벽 마그네틱 결속합니다!
                    tokens.append(.finalCaret)
                default:
                    tokens.append(.text(String(match.output.0)))
                }
            }
            else if let advancedKeyword = output.3 {
                let keywordStr = String(advancedKeyword)
                
                if keywordStr == "selection" || keywordStr == "selectedText" {
                    tokens.append(.selection)
                } else if keywordStr == "0" {
                    tokens.append(.finalCaret)
                } else if let tabIndex = output.4 {
                    let idx = Int(tabIndex) ?? 1
                    let defaultValue = output.5.map { String($0) }
                    tokens.append(.tabStop(index: idx, defaultValue: defaultValue))
                }
            }
            
            lastIndex = matchRange.upperBound
        }
        
        if lastIndex < template.endIndex {
            tokens.append(.text(String(template[lastIndex..<template.endIndex])))
        }
        
        return tokens
    }
}
