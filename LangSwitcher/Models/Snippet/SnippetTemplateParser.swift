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
    
    // 컴파일러 경고도 없이 런타임 진단 장부를 오염시키던 try! 패턴을 전면 소각하고,
    // 오타 발생 시 명확한 추적 단서를 남기는 자가 진단형 클로저 초기화 방식을 도입합니다.
    private static let snippetRegex: NSRegularExpression = {
        let pattern = "\\{(.+?)\\}"
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            // 향후 플레이스홀더 문법 규칙 확장을 위해 정규식을 수정하다가 휴먼 에러를 내더라도
            // 디버그 콘솔 및 터미널 로그에 정확한 원인 주소와 파일 도메인이 문자열로 기록됩니다.
            fatalError("🚨 [Programmer Error] SnippetTemplateParser: Invalid regex pattern '\(pattern)'. Please check your regular expression syntax.")
        }
        return regex
    }()
    
    static func parse(template: String) -> [SnippetToken] {
        var tokens: [SnippetToken] = []
        
        let nsTemplate = template as NSString
        let fullRange = NSRange(location: 0, length: nsTemplate.length)
        
        // 🌟 [핵심 수정] 매번 새로 만들지 않고, 위에 만들어둔 snippetRegex를 재사용합니다.
        let matches = snippetRegex.matches(in: template, options: [], range: fullRange)
       
        var lastIndex = 0
        
        // 🌟 변수명 수정: results -> matches
        for match in matches {
            let matchRange = match.range
            
            // 1. 태그 이전의 일반 텍스트 추가
            if matchRange.location > lastIndex {
                // 🌟 변수명 수정: nsString -> nsTemplate
                let textStr = nsTemplate.substring(with: NSRange(location: lastIndex, length: matchRange.location - lastIndex))
                tokens.append(.text(textStr))
            }
            
            // 2. 캡처된 내용(태그 내부) 분석
            let contentRange = match.range(at: 1)
            // 🌟 변수명 수정: nsString -> nsTemplate
            let content = nsTemplate.substring(with: contentRange).trimmingCharacters(in: .whitespaces)
            
            if content.hasPrefix("date:") {
                let format = String(content.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                tokens.append(.date(format: format))
            } else if content.hasPrefix("time:") {
                let format = String(content.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                tokens.append(.time(format: format))
            } else if content == "clipboard" {
                tokens.append(.clipboard)
            } else if content == "cursor" {
                tokens.append(.cursor)
            } else {
                // 알 수 없는 태그는 원본 텍스트 그대로 유지
                tokens.append(.text("{{\(content)}}"))
            }
            
            lastIndex = matchRange.location + matchRange.length
        }
        
        // 3. 마지막 태그 이후의 남은 텍스트 추가
        // 🌟 변수명 수정: nsString -> nsTemplate
        if lastIndex < nsTemplate.length {
            let textStr = nsTemplate.substring(from: lastIndex)
            tokens.append(.text(textStr))
        }
        
        return tokens
    }
}
