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

struct TraceFactory {
    
    enum Reason {
        case domainRule(domain: String)
        case appRule(appName: String)
        case windowRestore
        case browserTabRestore
        case manualOverride
        case excludedApp
        case secureInput
        case snippetExpanded(trigger: String)
        case snippetBlocked
        case shortcutIntent
        case noMatchingRule
        case newTabDefault
        
        var code: String {
            switch self {
            case .domainRule: return "domain_rule_applied"
            case .appRule: return "app_rule_applied"
            case .windowRestore: return "window_restore_applied"
            case .browserTabRestore: return "browser_tab_restore_applied"
            case .manualOverride: return "manual_override_kept"
            case .excludedApp: return "excluded_app_skipped"
            case .secureInput: return "secure_input_blocked"
            case .snippetExpanded: return "snippet_expanded"
            case .snippetBlocked: return "snippet_blocked"
            case .shortcutIntent: return "shortcut_intent_executed"
            case .noMatchingRule: return "no_matching_rule"
            case .newTabDefault: return "new_tab_default_applied"
            }
        }
        
        var message: String {
            switch self {
            case .domainRule(let domain): return String(localized: "Language changed due to \(domain) rule")
            case .appRule(let appName): return String(localized: "Language changed due to \(appName) app rule")
            case .windowRestore: return String(localized: "Restored previous language by window memory")
            case .browserTabRestore: return String(localized: "Restored previous language by browser tab memory")
            case .manualOverride: return String(localized: "Manual switch prioritized over automatic rules")
            case .excludedApp: return String(localized: "Skipped automatic switch due to excluded app settings")
            case .secureInput: return String(localized: "Skipped due to secure input (e.g., password field)")
            case .snippetExpanded(let trigger): return String(localized: "'\(trigger)' snippet expanded successfully")
            case .snippetBlocked: return String(localized: "Snippet expansion skipped due to current app settings")
            case .shortcutIntent: return String(localized: "Language changed by Shortcuts request")
            case .noMatchingRule: return String(localized: "Maintained current state as no matching rule applies")
            case .newTabDefault: return String(localized: "Applied default language for the new tab")
            }
        }
    }
    
    static func create(
        event: DecisionTrace.EventType,
        result: DecisionTrace.ResultType,
        reason: Reason,
        appName: String? = nil,
        domain: String? = nil,
        trigger: String? = nil
    ) -> DecisionTrace {
        return DecisionTrace(
            eventType: event,
            resultType: result,
            reasonCode: reason.code,
            reasonMessage: reason.message,
            appName: appName,
            domain: domain,
            triggerTextPreview: trigger
        )
    }
}
