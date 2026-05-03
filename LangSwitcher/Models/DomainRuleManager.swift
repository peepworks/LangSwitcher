//
//  HyperKeyManager.swift
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
        var stringToParse = urlOrDomain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // URLComponents가 host를 정확히 파싱하려면 스킴(http://)이 필요합니다.
        if !stringToParse.hasPrefix("http://") && !stringToParse.hasPrefix("https://") {
            stringToParse = "https://" + stringToParse
        }
        
        guard let components = URLComponents(string: stringToParse),
              let host = components.host else {
            return nil
        }
        
        // "www." 접두사가 있으면 제거하여 순수 도메인만 남깁니다.
        if host.hasPrefix("www.") {
            return String(host.dropFirst(4))
        }
        
        return host
    }
    
    // MARK: - 2. 규칙 매칭 엔진 (Matching Engine)
    /// 현재 브라우저의 URL을 받아, 등록된 규칙 중 가장 적합한 규칙을 찾아 반환합니다.
    func findMatchingRule(for urlString: String, browserBundleID: String) -> DomainRule? {
        // 1. 현재 브라우저의 URL을 순수 호스트로 정규화
        guard let currentHost = Self.normalize(urlOrDomain: urlString) else { return nil }
        
        // 2. 활성화된 규칙만 필터링
        let activeRules = rules.filter { $0.isEnabled }
        
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
