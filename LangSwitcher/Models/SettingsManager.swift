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
import Combine

struct CustomShortcut: Identifiable, Codable {
    var id = UUID()
    var keyCode: UInt16
    var modifierFlags: UInt64
    var displayString: String
    var targetLanguage: String
}

// 🌟 사용자 지정 앱 저장을 위한 구조체 추가
struct CustomApp: Identifiable, Codable {
    var id = UUID()
    var bundleIdentifier: String
    var appName: String
    var targetLanguage: String
}

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    @Published var isCtrlActive: Bool { didSet { save("isCtrlActive", isCtrlActive) } }
    @Published var isCmdActive: Bool { didSet { save("isCmdActive", isCmdActive) } }
    @Published var isOptActive: Bool { didSet { save("isOptActive", isOptActive) } }

    @Published var ctrlLang: String { didSet { save("ctrlLang", ctrlLang) } }
    @Published var cmdLang: String { didSet { save("cmdLang", cmdLang) } }
    @Published var optLang: String { didSet { save("optLang", optLang) } }
    
    @Published var customShortcuts: [CustomShortcut] = [] {
        didSet {
            if let encoded = try? JSONEncoder().encode(customShortcuts) {
                save("customShortcuts", encoded)
            }
        }
    }
    
    // 🌟 사용자 지정 앱 배열 추가
    @Published var customApps: [CustomApp] = [] {
        didSet {
            if let encoded = try? JSONEncoder().encode(customApps) {
                save("customApps", encoded)
            }
        }
    }
    
    private init() {
        let d = UserDefaults.standard
        isCtrlActive = d.bool(forKey: "isCtrlActive")
        isCmdActive = d.bool(forKey: "isCmdActive")
        isOptActive = d.bool(forKey: "isOptActive")
        
        ctrlLang = d.string(forKey: "ctrlLang") ?? ""
        cmdLang = d.string(forKey: "cmdLang") ?? ""
        optLang = d.string(forKey: "optLang") ?? ""
        
        if let data = d.data(forKey: "customShortcuts"),
           let decoded = try? JSONDecoder().decode([CustomShortcut].self, from: data) {
            customShortcuts = decoded
        }
        
        // 🌟 사용자 지정 앱 데이터 로드
        if let data = d.data(forKey: "customApps"),
           let decoded = try? JSONDecoder().decode([CustomApp].self, from: data) {
            customApps = decoded
        }
    }
    
    private func save(_ key: String, _ value: Any) {
        UserDefaults.standard.set(value, forKey: key)
    }
}
