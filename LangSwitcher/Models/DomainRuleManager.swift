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

class DomainRuleManager {
    static let shared = DomainRuleManager()
    
    // 임시 저장소 (추후 SettingsManager의 UserDefaults와 연동 예정)
    var rules: [DomainRule] = []
    
    private init() {}
    
    // MARK: - 1. 도메인 정규화 (Normalization)
    /// 어떤 형태의 URL이나 도메인이 들어와도 순수한 호스트(Host) 문자열로 변환합니다.
    /// 예: "https://www.naver.com/search" -> "naver.com"
    /// 예: "www.github.com" -> "github.com"
    static func normalize(urlOrDomain: String) -> String? {
        // 1. 앞뒤 공백 제거 및 소문자 변환
        var stringToParse = urlOrDomain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // 2. 스킴(http:// 또는 https://)이 없다면 강제로 붙여줌
        // (이렇게 해야 URLComponents가 슬래시(/) 뒤의 문자열을 경로(path)로 올바르게 분리하고 host를 찾아냄)
        if !stringToParse.hasPrefix("http://") && !stringToParse.hasPrefix("https://") {
            stringToParse = "https://" + stringToParse
        }
        
        // 3. 파싱 및 host 추출
        guard let components = URLComponents(string: stringToParse),
              var host = components.host, !host.isEmpty else {
            return nil
        }
        
        // 4. (선택 사항) 사용자가 "www.github.com"이라고 쳤을 때 "github.com"으로 통일하고 싶다면
        if host.hasPrefix("www.") {
            host = String(host.dropFirst(4))
        }
        
        return host
    }
    
    // MARK: - 2. 규칙 매칭 엔진 (Matching Engine)
    /// 현재 브라우저의 URL을 받아, 등록된 규칙 중 가장 적합한 규칙을 찾아 반환합니다.
    func findMatchingRule(for urlString: String, browserBundleID: String) -> DomainRule? {
        // 1. 현재 브라우저의 URL을 순수 호스트로 정규화
        guard let currentHost = Self.normalize(urlOrDomain: urlString) else { return nil }
        
        // 🌟 [핵심 개선] 매번 filter 배열을 생성하지 않고, 스냅샷이 이미 구워둔 활성화 규칙 캐시를 그대로 가져옵니다.
        let activeRules = SettingsManager.shared.snapshot.enabledDomainRules
        
        for rule in activeRules {
            // 브라우저 제한이 걸려있는데 현재 브라우저와 다르면 패스
            if let ruleBrowser = rule.browserBundleID, ruleBrowser != browserBundleID {
                continue
            }
            
            if rule.includeSubdomains {
                // 서브도메인 포함: 정확히 일치하거나, ".도메인"으로 끝나는 경우 매칭 (예: gist.github.com)
                if currentHost == rule.domain || currentHost.hasSuffix(".\(rule.domain)") {
                    return rule
                }
            } else {
                // 정확 일치 (Exact Match)
                if currentHost == rule.domain {
                    return rule
                }
            }
        }
        
        return nil
    }
}
