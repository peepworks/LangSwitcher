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
    
    // 🌟 [정규식 최종 진화] 이름, 대괄호 옵션란, 파이프 기본값의 경계를 완벽하게 격리 가로채는 마스터 패턴
    // 2번 캡처: 필드명 / 3번 캡처: [옵션배열] / 4번 캡처: |기본값 또는 포맷문자열
    private static let unifiedRegex = #/(?:\{\{(date|time|clipboard|cursor|input|textarea|select|optional|checkbox|radio|datepicker)(?::([^\[\}|]+))?(?:\[([^\]]+)\])?(?:\|([^}]+))?\}\})|(?:\$\{(selection|selectedText|0|([1-9]\d*)(?::([^\}]+))?)\})/#

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
                
                // 🌟 정규식이 미리 컴포넌트별로 정밀 가공해 준 순정 파라미터 획득
                let nameParam = output.2.map { String($0) } ?? ""
                let arrayParam = output.3.map { String($0) } ?? ""
                let defaultParam = output.4.map { String($0) } ?? ""
                
                switch keywordStr {
                case "date":
                    tokens.append(.date(format: nameParam.isEmpty ? "yyyy-MM-dd" : nameParam))
                case "time":
                    tokens.append(.time(format: nameParam.isEmpty ? "HH:mm" : nameParam))
                case "clipboard":
                    tokens.append(.clipboard)
                case "cursor":
                    tokens.append(.finalCaret)
                    
                case "input":
                    tokens.append(.input(name: nameParam, defaultValue: defaultParam.isEmpty ? nil : defaultParam))
                case "textarea":
                    tokens.append(.textarea(name: nameParam, defaultValue: defaultParam.isEmpty ? nil : defaultParam))
                case "select":
                    let options = arrayParam.components(separatedBy: ",")
                    tokens.append(.select(name: nameParam, options: options, defaultValue: defaultParam.isEmpty ? nil : defaultParam))
                    
                case "checkbox":
                    let isChecked = defaultParam.isEmpty ? true : (defaultParam.lowercased() == "true")
                    tokens.append(.checkbox(name: nameParam, content: arrayParam, isCheckedByDefault: isChecked))
                case "radio":
                    let options = arrayParam.components(separatedBy: ",")
                    tokens.append(.radio(name: nameParam, options: options, defaultValue: defaultParam.isEmpty ? nil : defaultParam))
                case "datepicker":
                    // 🌟 파이프 뒤의 포맷(yyyy/MM/dd)을 완벽하게 인식 보장합니다.
                    tokens.append(.datePicker(name: nameParam, format: defaultParam.isEmpty ? "yyyy-MM-dd" : defaultParam))
                    
                case "optional":
                    tokens.append(.optionalBlock(name: nameParam, content: arrayParam))
                    
                default:
                    tokens.append(.text(String(match.output.0)))
                }
            }
            else if let advancedKeyword = output.5 {
                let keywordStr = String(advancedKeyword)
                
                if keywordStr == "selection" || keywordStr == "selectedText" {
                    tokens.append(.selection)
                } else if keywordStr == "0" {
                    tokens.append(.finalCaret)
                } else if let tabIndex = output.6 {
                    let idx = Int(tabIndex) ?? 1
                    let defaultValue = output.7.map { String($0) }
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
