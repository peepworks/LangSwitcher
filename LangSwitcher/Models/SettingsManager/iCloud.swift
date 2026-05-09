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

extension SettingsManager {
    @objc func icloudUpdateReceived(_ notification: Notification) {
        guard isCloudSyncEnabled else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isBatchUpdating = true
            
            defer {
                self.saveAll()
                self.updateSnapshot()
                self.isBatchUpdating = false
            }
            
            let dict = self.icloudStore.dictionaryRepresentation
            
            if let val = dict["showVisualFeedback"] as? Bool { self.showVisualFeedback = val }
            if let val = dict["isHyperKeyEnabled"] as? Bool { self.isHyperKeyEnabled = val }
            if let val = dict["isWindowMemoryEnabled"] as? Bool { self.isWindowMemoryEnabled = val }
            if let val = dict["isCursorHUDEnabled"] as? Bool { self.isCursorHUDEnabled = val }
            if let val = dict["isTypoCorrectionEnabled"] as? Bool { self.isTypoCorrectionEnabled = val }
            if let val = dict["isAutoTypoCorrectionEnabled"] as? Bool { self.isAutoTypoCorrectionEnabled = val }
            if let val = dict["isEdgeGlowEnabled"] as? Bool { self.isEdgeGlowEnabled = val }
            if let val = dict["isAutoTypoCorrectionOnEnterEnabled"] as? Bool { self.isAutoTypoCorrectionOnEnterEnabled = val }
            
            if let data = dict["excludedApps"] as? Data, let dec = try? JSONDecoder().decode([ExcludedApp].self, from: data) { self.excludedApps = dec }
            if let data = dict["customShortcuts"] as? Data, let dec = try? JSONDecoder().decode([CustomShortcut].self, from: data) { self.customShortcuts = dec }
            if let data = dict["appDelays"] as? Data, let dec = try? JSONDecoder().decode([AppDelay].self, from: data) { self.appDelays = dec } // 🌟 추가
            
            if let data = dict["domainRules"] as? Data, let dec = try? JSONDecoder().decode([DomainRule].self, from: data) {
                self.domainRules = dec
                DomainRuleManager.shared.rules = dec
            }
            
            if let val = dict["isBrowserTabMemoryEnabled"] as? Bool { self.isBrowserTabMemoryEnabled = val }
            if let val = dict["isBrowserDomainModeEnabled"] as? Bool { self.isBrowserDomainModeEnabled = val }
        }
    }
    
    func syncToCloud() {
        guard isCloudSyncEnabled, !isBatchUpdating else { return }
        
        icloudStore.set(showVisualFeedback, forKey: "showVisualFeedback")
        icloudStore.set(isHyperKeyEnabled, forKey: "isHyperKeyEnabled")
        icloudStore.set(isWindowMemoryEnabled, forKey: "isWindowMemoryEnabled")
        icloudStore.set(isCursorHUDEnabled, forKey: "isCursorHUDEnabled")
        icloudStore.set(isTypoCorrectionEnabled, forKey: "isTypoCorrectionEnabled")
        icloudStore.set(isHapticFeedbackEnabled, forKey: "isHapticFeedbackEnabled")
        icloudStore.set(isSoundFeedbackEnabled, forKey: "isSoundFeedbackEnabled")
        icloudStore.set(isAutoTypoCorrectionEnabled, forKey: "isAutoTypoCorrectionEnabled")
        icloudStore.set(isEdgeGlowEnabled, forKey: "isEdgeGlowEnabled")
        icloudStore.set(isAutoTypoCorrectionOnEnterEnabled, forKey: "isAutoTypoCorrectionOnEnterEnabled")
        icloudStore.set(isBrowserTabMemoryEnabled, forKey: "isBrowserTabMemoryEnabled")
        icloudStore.set(isBrowserDomainModeEnabled, forKey: "isBrowserDomainModeEnabled")
        
        if let e = try? JSONEncoder().encode(excludedApps) { icloudStore.set(e, forKey: "excludedApps") }
        if let e = try? JSONEncoder().encode(customShortcuts) { icloudStore.set(e, forKey: "customShortcuts") }
        if let e = try? JSONEncoder().encode(domainRules) { icloudStore.set(e, forKey: "domainRules") }
        if let e = try? JSONEncoder().encode(appDelays) { icloudStore.set(e, forKey: "appDelays") } // 🌟 추가
        
        icloudStore.synchronize()
    }
}
