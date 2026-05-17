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

import AppIntents
import SwiftUI

// MARK: - 1. Set Input Source
struct SetInputSourceIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Input Source"
    static let description = IntentDescription("Change the macOS keyboard input source to a specific language.")
    
    @Parameter(title: "Input Source ID", requestValueDialog: "Enter the Input Source ID (e.g., com.apple.keylayout.US)")
    var inputSourceID: String
    
    static var parameterSummary: some ParameterSummary {
        Summary("Set input source to \(\.$inputSourceID)")
    }
    
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        // 기존에 잘 만들어두신 InputSourceManager를 그대로 재사용합니다!
        await MainActor.run {
            InputSourceManager.shared.switchLanguage(to: inputSourceID)
        }
        return .result(value: "Language switched to \(inputSourceID)")
    }
}

// MARK: - 2. Toggle Typo Correction
struct ToggleTypoCorrectionIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Typo Correction"
    static let description = IntentDescription("Enable, disable, or toggle the Typo Correction feature in LangSwitcher.")
    
    @Parameter(title: "State", default: .toggle)
    var state: FeatureToggleState
    
    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$state) Typo Correction")
    }
    
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let manager = SettingsManager.shared
        
        // 🌟 현재 활성화된 프로필 사본을 가져옵니다.
        var currentProfile = manager.activeProfile
        
        switch state {
        case .on:
            currentProfile.payload.isTypoCorrectionEnabled = true
        case .off:
            currentProfile.payload.isTypoCorrectionEnabled = false
        case .toggle:
            currentProfile.payload.isTypoCorrectionEnabled.toggle()
        }
        
        // 🌟 수정한 프로필 설정을 다시 manager에 반영합니다.
        // (이 시점에 didSet이 구동되면서 스냅샷과 엔진에 즉시 전파됩니다.)
        manager.activeProfile = currentProfile
        
        let currentState = currentProfile.payload.isTypoCorrectionEnabled ? "Enabled" : "Disabled"
        return .result(value: currentState)
    }
}

// MARK: - 3. Toggle Browser Tab Memory
struct ToggleBrowserTabMemoryIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Browser Tab Memory"
    static let description = IntentDescription("Enable, disable, or toggle the Browser Tab Memory feature.")
    
    @Parameter(title: "State", default: .toggle)
    var state: FeatureToggleState
    
    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$state) Browser Tab Memory")
    }
    
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let manager = SettingsManager.shared
        
        switch state {
        case .on: manager.isBrowserTabMemoryEnabled = true
        case .off: manager.isBrowserTabMemoryEnabled = false
        case .toggle: manager.isBrowserTabMemoryEnabled.toggle()
        }
        
        let currentState = manager.isBrowserTabMemoryEnabled ? "Enabled" : "Disabled"
        return .result(value: currentState)
    }
}

// MARK: - 4. Toggle Exception Apps Mode
struct ToggleExceptionAppsModeIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Exception Apps Mode"
    static let description = IntentDescription("Turn the Excluded Apps rule on or off.")
    
    @Parameter(title: "State", default: .toggle)
    var state: FeatureToggleState
    
    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$state) Exception Apps Mode")
    }
    
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let manager = SettingsManager.shared
        
        switch state {
        case .on: manager.isExcludedAppsEnabled = true
        case .off: manager.isExcludedAppsEnabled = false
        case .toggle: manager.isExcludedAppsEnabled.toggle()
        }
        
        let currentState = manager.isExcludedAppsEnabled ? "Enabled" : "Disabled"
        return .result(value: currentState)
    }
}
