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
    
    // 1. 버퍼에서 트리거 매칭 확인
    func findMatch(in buffer: String, activeAppID: String, rules: [TextExpansionRule]) -> TextExpansionRule? {
        // 긴 트리거부터 매칭하기 위해 길이순 정렬
        let activeRules = rules.filter { $0.isEnabled }
            .sorted { $0.trigger.count > $1.trigger.count }
        
        for rule in activeRules {
            // 앱별 범위 필터링 (사용자님이 추가하신 훌륭한 기능 유지)
            // (주의: TextExpansionRule 모델에 해당 변수들이 선언되어 있어야 합니다)
            /*
            if rule.isExcludeMode && rule.targetAppBundleIDs.contains(activeAppID) { continue }
            if !rule.isExcludeMode && !rule.targetAppBundleIDs.contains(activeAppID) { continue }
            */
            
            // 버퍼가 트리거로 끝나는지 확인
            if buffer.hasSuffix(rule.trigger) {
                return rule
            }
        }
        return nil
    }
    
    // 2. 동적 스니펫 파싱 (정규식 엔진 + 고정 토큰 통합)
    func parseDynamicVariables(text: String, now: Date = Date()) -> String {
        var result = text as NSString
        
        // --- A. 고급 동적 날짜 파싱: {{date:yyyy-MM-dd}} ---
        let pattern = #"\{\{date:([^}]+)\}\}"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let matches = regex.matches(in: result as String, range: NSRange(location: 0, length: result.length))
            
            // 문자열 치환 시 인덱스 꼬임을 방지하기 위해 뒤에서부터(reversed) 처리
            for match in matches.reversed() {
                let fullRange = match.range(at: 0)
                let formatRange = match.range(at: 1)
                
                let format = result.substring(with: formatRange)
                
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = format
                
                let replacement = formatter.string(from: now)
                result = result.replacingCharacters(in: fullRange, with: replacement) as NSString
            }
        }
        
        var parsedText = result as String
        
        // --- B. 클립보드 파싱: {{clip}} 또는 {clip} ---
        if parsedText.contains("{clip}") || parsedText.contains("{{clip}}") {
            let pasteboardString = NSPasteboard.general.string(forType: .string) ?? ""
            parsedText = parsedText.replacingOccurrences(of: "{{clip}}", with: pasteboardString)
            parsedText = parsedText.replacingOccurrences(of: "{clip}", with: pasteboardString)
        }
        
        // --- C. 단순 날짜/시간 하위 호환성: {date}, {time} ---
        if parsedText.contains("{date}") {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            parsedText = parsedText.replacingOccurrences(of: "{date}", with: formatter.string(from: now))
        }
        
        if parsedText.contains("{time}") {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            parsedText = parsedText.replacingOccurrences(of: "{time}", with: formatter.string(from: now))
        }
        
        return parsedText
    }
}
