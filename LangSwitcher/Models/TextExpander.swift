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

class TextExpander {
    static let shared = TextExpander()
    private init() {}
    
    // 1. 버퍼에서 트리거 매칭 확인
    func findMatch(in buffer: String, activeAppID: String, rules: [TextExpansionRule]) -> TextExpansionRule? {
        // 긴 트리거부터 매칭하기 위해 길이순 정렬
        let activeRules = rules.filter { $0.isEnabled }
            .sorted { $0.trigger.count > $1.trigger.count }
        
        for rule in activeRules {
            // 앱별 범위 필터링 (심층 리서치: 특정 앱 활성화 로직)
            if rule.isExcludeMode && rule.targetAppBundleIDs.contains(activeAppID) { continue }
            if !rule.isExcludeMode && !rule.targetAppBundleIDs.contains(activeAppID) { continue }
            
            // 버퍼가 트리거로 끝나는지 확인 (대소문자 구분 옵션에 따라 .lowercased() 사용 가능)
            if buffer.hasSuffix(rule.trigger) {
                return rule
            }
        }
        return nil
    }
    
    // 2. 동적 스니펫 파싱 (심층 리서치: 날짜/시간 동적 삽입 구현)
    func parseDynamicVariables(text: String) -> String {
        var parsedText = text
        let now = Date()
        
        // {date} -> 2026-05-11
        if parsedText.contains("{date}") {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            parsedText = parsedText.replacingOccurrences(of: "{date}", with: formatter.string(from: now))
        }
        
        // {time} -> 11:04
        if parsedText.contains("{time}") {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            parsedText = parsedText.replacingOccurrences(of: "{time}", with: formatter.string(from: now))
        }
        
        // {clip} -> 현재 클립보드 텍스트
        if parsedText.contains("{clip}") {
            let pasteboardString = NSPasteboard.general.string(forType: .string) ?? ""
            parsedText = parsedText.replacingOccurrences(of: "{clip}", with: pasteboardString)
        }
        
        return parsedText
    }
}
