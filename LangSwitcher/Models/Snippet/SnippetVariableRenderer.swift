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

struct SnippetVariableRenderer {
    // 다중 날짜/시간 포맷 호출 시 성능 최적화를 위한 DateFormatter 캐시
    private static var dateFormatterCache: [String: DateFormatter] = [:]
    
    /// 파싱된 토큰 배열을 순회하며 최종 문자열과 커서 삽입 위치를 계산합니다.
    static func render(tokens: [SnippetToken]) -> RenderedSnippet {
        var resultText = ""
        var cursorOffset: Int? = nil
        
        let currentDate = Date()
        
        for token in tokens {
            switch token {
            case .text(let text):
                resultText += text
                
            case .date(let format), .time(let format):
                let formatter = getFormatter(for: format)
                resultText += formatter.string(from: currentDate)
                
            case .clipboard:
                // 1차 정책: 클립보드에 문자열이 없으면 빈 문자열 취급하여 렌더링 계속 진행
                if let clipboardText = ClipboardProvider.getString() {
                    resultText += clipboardText
                }
                
            case .cursor:
                // 정책: 첫 번째 {{cursor}}만 유효하며, 결과 문자열에는 남기지 않음
                if cursorOffset == nil {
                    // 현재까지 조립된 문자열의 길이를 커서 복귀 목표 지점으로 기록
                    // (1차 기준: Swift 기본 String.count 사용. 추후 이모지/조합문자 이슈 시 utf16.count 등으로 변경)
                    cursorOffset = resultText.count
                }
            }
        }
        
        return RenderedSnippet(text: resultText, cursorOffsetFromStart: cursorOffset)
    }
    
    /// 지정된 포맷의 DateFormatter를 반환하거나 새로 생성하여 캐싱합니다.
    private static func getFormatter(for format: String) -> DateFormatter {
        if let cached = dateFormatterCache[format] {
            return cached
        }
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.locale = Locale.current // 사용자의 현재 지역 설정 반영
        dateFormatterCache[format] = formatter
        return formatter
    }
}
