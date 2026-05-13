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

struct DecisionTrace: Identifiable, Codable, Hashable {
    enum EventType: String, Codable {
        case languageSwitch = "languageSwitch"
        case snippetExpansion = "snippetExpansion"
        case shortcutIntent = "shortcutIntent"
        case skipped = "skipped"
        case restore = "restore"
    }

    enum ResultType: String, Codable {
        case switched = "switched"
        case kept = "kept"
        case skipped = "skipped"
        case expanded = "expanded"
        case blocked = "blocked"
        case restored = "restored"
        case failed = "failed"
    }

    let id: UUID
    let timestamp: Date
    let eventType: EventType
    let resultType: ResultType
    
    // 🌟 핵심: 분석용 코드와 표시용 메시지 분리
    let reasonCode: String
    let reasonMessage: String
    
    // 🌟 부가 정보 (프라이버시를 위해 최소한만 저장)
    let appBundleID: String?
    let appName: String?
    let windowTitlePreview: String?
    let domain: String?
    let triggerTextPreview: String?
    
    let matchedRuleID: UUID?
    let matchedRuleName: String?
    let ignoredRules: [IgnoredRuleTrace]
    let metadata: [String: String]
    
    // 초기화 편의성을 위한 init
    init(id: UUID = UUID(), timestamp: Date = Date(), eventType: EventType, resultType: ResultType, reasonCode: String, reasonMessage: String, appBundleID: String? = nil, appName: String? = nil, windowTitlePreview: String? = nil, domain: String? = nil, triggerTextPreview: String? = nil, matchedRuleID: UUID? = nil, matchedRuleName: String? = nil, ignoredRules: [IgnoredRuleTrace] = [], metadata: [String : String] = [:]) {
        self.id = id
        self.timestamp = timestamp
        self.eventType = eventType
        self.resultType = resultType
        self.reasonCode = reasonCode
        self.reasonMessage = reasonMessage
        self.appBundleID = appBundleID
        self.appName = appName
        self.windowTitlePreview = windowTitlePreview
        self.domain = domain
        self.triggerTextPreview = triggerTextPreview
        self.matchedRuleID = matchedRuleID
        self.matchedRuleName = matchedRuleName
        self.ignoredRules = ignoredRules
        self.metadata = metadata
    }
}

struct IgnoredRuleTrace: Codable, Hashable {
    let ruleID: UUID?
    let ruleName: String
    let ignoredReason: String
}
