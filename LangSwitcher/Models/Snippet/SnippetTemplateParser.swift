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
    
    // 🌟 [통합 정규식 확장] 새로운 사용자 입력형 및 제어형 기호 컴포넌트군을 단 한 줄로 완벽 포획합니다.
    private static let unifiedRegex = #/(?:\{\{(date|time|clipboard|cursor|input|textarea|select|optional)(?::([^\[\}]+))?(?:\[([^\]]+)\])?\}\})|(?:\$\{(selection|selectedText|0|([1-9]\d*)(?::([^\}]+))?)\})/#

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
                let mainParam = output.2.map { String($0) } ?? ""
                let optionParam = output.3.map { String($0) } ?? ""
                
                switch keywordStr {
                case "date":
                    tokens.append(.date(format: mainParam.isEmpty ? "yyyy-MM-dd" : mainParam))
                case "time":
                    tokens.append(.time(format: mainParam.isEmpty ? "HH:mm" : mainParam))
                case "clipboard":
                    tokens.append(.clipboard)
                case "cursor":
                    tokens.append(.finalCaret)
                    
                // 🌟 [신설] 동적 기호 정산 처리 체인 링크
                case "input":
                    let parts = mainParam.components(separatedBy: "|")
                    tokens.append(.input(name: parts[0], defaultValue: parts.count > 1 ? parts[1] : nil))
                case "textarea":
                    let parts = mainParam.components(separatedBy: "|")
                    tokens.append(.textarea(name: parts[0], defaultValue: parts.count > 1 ? parts[1] : nil))
                case "select":
                    let options = optionParam.components(separatedBy: ",")
                    tokens.append(.select(name: mainParam, options: options))
                case "optional":
                    tokens.append(.optionalBlock(name: mainParam, content: optionParam))
                    
                default:
                    tokens.append(.text(String(match.output.0)))
                }
            }
            else if let advancedKeyword = output.4 {
                let keywordStr = String(advancedKeyword)
                
                if keywordStr == "selection" || keywordStr == "selectedText" {
                    tokens.append(.selection)
                } else if keywordStr == "0" {
                    tokens.append(.finalCaret)
                } else if let tabIndex = output.5 {
                    let idx = Int(tabIndex) ?? 1
                    let defaultValue = output.6.map { String($0) }
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
