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
    
    // 컴파일 타임 문법 정적 검증이 확약된 순정 Modern Swift Regex 리터럴 상주 고정
    private static let snippetRegex = #/\{\{(date|time|clipboard|cursor)(?::([^}]+))?\}\}/#
    
    static func parse(template: String) -> [SnippetToken] {
        var tokens: [SnippetToken] = []
        
        // Swift 고유의 String.Index 추적선 수립
        var lastIndex = template.startIndex
        
        let matches = template.matches(of: snippetRegex)
       
        for match in matches {
            // 강력한 타입 추론이 완료된 튜플 출력부 직결 인출
            let coreKeyword = String(match.output.1)               // "date", "time", "clipboard", "cursor"
            let customFormat = match.output.2.map { String($0) }    // 콜론 뒤의 포맷 문자열만 청정 추출
            let matchRange = match.range                           // Range<String.Index>
            
            // 1. 태그 이전의 일반 텍스트 구간 분할 추가
            if matchRange.lowerBound > lastIndex {
                let textStr = String(template[lastIndex..<matchRange.lowerBound])
                tokens.append(.text(textStr))
            }
            
            // 2. 글로벌 레지스트리에 이미 선언된 SnippetToken enum 자산과 직결 매핑
            switch coreKeyword {
            case "date":
                let format = customFormat?.trimmingCharacters(in: .whitespaces) ?? "yyyy-MM-dd"
                tokens.append(.date(format: format))
                
            case "time":
                let format = customFormat?.trimmingCharacters(in: .whitespaces) ?? "HH:mm"
                tokens.append(.time(format: format))
                
            case "clipboard":
                tokens.append(.clipboard)
                
            case "cursor":
                tokens.append(.cursor)
                
            default:
                tokens.append(.text(String(match.output.0)))
            }
            
            // 마감 인덱스를 매칭 범위의 끝단(upperBound)으로 갱신
            lastIndex = matchRange.upperBound
        }
        
        // 3. 마지막 태그 이후의 남은 텍스트 정산
        if lastIndex < template.endIndex {
            let textStr = String(template[lastIndex..<template.endIndex])
            tokens.append(.text(textStr))
        }
        
        return tokens
    }
}
