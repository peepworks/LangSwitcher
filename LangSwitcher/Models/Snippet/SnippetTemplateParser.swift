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
    
    // 🌟 [수복 포인트] 기존 변수와 신형 달러 문법 플레이스홀더를 동시 포획하는 통합 정규식 패턴 리터럴 상주
    // 1번 캡처: {{...}} 변수군 | 2번 캡처: ${...} 플레이스홀더군
    private static let unifiedRegex = #/(?:\{\{(date|time|clipboard)(?::([^}]+))?\}\})|(?:\$\{(selection|selectedText|0|([1-9]\d*)(?::([^}]+))?)\})/#

    static func parse(template: String) -> [SnippetToken] {
        var tokens: [SnippetToken] = []
        var lastIndex = template.startIndex
        
        let matches = template.matches(of: unifiedRegex)
        
        for match in matches {
            let matchRange = match.range
            
            // 태그 진입 전 정적 일반 텍스트 분할 기입
            if matchRange.lowerBound > lastIndex {
                let staticText = String(template[lastIndex..<matchRange.lowerBound])
                tokens.append(.text(staticText))
            }
            
            let output = match.output
            
            // 분기 1: 레거시 {{...}} 중괄호 매크로 캡처 엔진 검문
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
                default:
                    tokens.append(.text(String(match.output.0)))
                }
            }
            // 분기 2: v0.9.5 신형 ${...} 달러 템플릿 오토마타 검문
            else if let advancedKeyword = output.3 {
                let keywordStr = String(advancedKeyword)
                
                if keywordStr == "selection" || keywordStr == "selectedText" {
                    tokens.append(.selection)
                } else if keywordStr == "0" {
                    tokens.append(.finalCaret)
                } else if let tabIndex = output.4 { // ${1:default} 또는 ${2} 파싱 라인
                    let idx = Int(tabIndex) ?? 1
                    let defaultValue = output.5.map { String($0) }
                    tokens.append(.tabStop(index: idx, defaultValue: defaultValue))
                }
            }
            
            lastIndex = matchRange.upperBound
        }
        
        // 후행 잔여문 정산
        if lastIndex < template.endIndex {
            tokens.append(.text(String(template[lastIndex..<template.endIndex])))
        }
        
        return tokens
    }
}
