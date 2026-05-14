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
    func findMatch(for buffer: String) -> TextExpansionRule? {
        // 미리 정렬된 캐시 배열을 즉시 가져옵니다. (속도 대폭 향상)
        let activeRules = SettingsManager.shared.cachedActiveTextExpansionRules
        
        for rule in activeRules {
            if buffer.hasSuffix(rule.trigger) {
                return rule
            }
        }
        return nil
    }
    
    // 2. 동적 스니펫 파싱 (정규식 엔진 + 고정 토큰 통합)
    func parseDynamicVariables(text: String, now: Date = Date()) -> String {
        var result = text as NSString
        let sharedFormatter = TextExpander.sharedDateFormatter // 공용 포매터 가져오기 (이름 충돌 방지를 위해 sharedFormatter로 명명)
        
        // --- A. 고급 동적 날짜 파싱: {{date:yyyy-MM-dd}} ---
        let pattern = #"\{\{date:([^}]+)\}\}"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let matches = regex.matches(in: result as String, range: NSRange(location: 0, length: result.length))
            
            // 문자열 치환 시 인덱스 꼬임을 방지하기 위해 뒤에서부터(reversed) 처리
            for match in matches.reversed() {
                let fullRange = match.range(at: 0)
                let formatRange = match.range(at: 1)
                let format = result.substring(with: formatRange)
                
                // 🌟 수정됨: 새 DateFormatter를 만들지 않고 공용 포매터를 재사용합니다.
                sharedFormatter.locale = Locale(identifier: "en_US_POSIX")
                sharedFormatter.dateFormat = format
                
                let replacement = sharedFormatter.string(from: now)
                result = result.replacingCharacters(in: fullRange, with: replacement) as NSString
            }
        }
        
        var parsedText = result as String
        
        // --- B. 클립보드 파싱: {{clipboard}}, {{clip}} 또는 {clip} ---
        if parsedText.contains("{{clipboard}}") || parsedText.contains("{{clip}}") || parsedText.contains("{clip}") {
            let pasteboardString = NSPasteboard.general.string(forType: .string) ?? ""
            parsedText = parsedText.replacingOccurrences(of: "{{clipboard}}", with: pasteboardString)
            parsedText = parsedText.replacingOccurrences(of: "{{clip}}", with: pasteboardString)
            parsedText = parsedText.replacingOccurrences(of: "{clip}", with: pasteboardString)
        }
        
        // --- C. 단순 날짜/시간 하위 호환성: {date}, {time} ---
        if parsedText.contains("{date}") {
            // 🌟 수정됨: 공용 포매터 재사용 (A에서 변경되었을 수 있으므로 locale을 복구)
            sharedFormatter.locale = Locale.current
            sharedFormatter.dateFormat = "yyyy-MM-dd"
            parsedText = parsedText.replacingOccurrences(of: "{date}", with: sharedFormatter.string(from: now))
        }
        
        if parsedText.contains("{time}") {
            // 🌟 수정됨: 공용 포매터 재사용
            sharedFormatter.locale = Locale.current
            sharedFormatter.dateFormat = "HH:mm"
            parsedText = parsedText.replacingOccurrences(of: "{time}", with: sharedFormatter.string(from: now))
        }
        
        return parsedText
    }
}
