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

import Foundation

struct SnippetTemplateParser {
    /// 템플릿 문자열을 분석하여 토큰 배열로 변환합니다.
    static func parse(template: String) -> [SnippetToken] {
        var tokens: [SnippetToken] = []
        
        // 정규식: {{ 와 }} 사이의 내용을 캡처 (최소 일치 탐색)
        let pattern = "\\{\\{(.*?)\\}\\}"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return [.text(template)]
        }
        
        let nsString = template as NSString
        let results = regex.matches(in: template, options: [], range: NSRange(location: 0, length: nsString.length))
        
        var lastIndex = 0
        
        for match in results {
            let matchRange = match.range
            
            // 1. 태그 이전의 일반 텍스트 추가
            if matchRange.location > lastIndex {
                let textStr = nsString.substring(with: NSRange(location: lastIndex, length: matchRange.location - lastIndex))
                tokens.append(.text(textStr))
            }
            
            // 2. 캡처된 내용(태그 내부) 분석
            let contentRange = match.range(at: 1)
            let content = nsString.substring(with: contentRange).trimmingCharacters(in: .whitespaces)
            
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
        if lastIndex < nsString.length {
            let textStr = nsString.substring(from: lastIndex)
            tokens.append(.text(textStr))
        }
        
        return tokens
    }
}
