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

import SwiftUI

enum SettingsTab: Hashable {
    case general
    case customShortcuts
    case appSpecific
    case appLaunch
    case about
}

struct SettingsView: View {
    @StateObject private var accManager = AccessibilityManager.shared
    @State private var selectedTab: SettingsTab? = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                Section(header: Text(String(localized: "Settings"))) {
                    Label(String(localized: "General"), systemImage: "gearshape")
                        .tag(SettingsTab.general)
                    Label(String(localized: "Custom Shortcuts"), systemImage: "keyboard")
                        .tag(SettingsTab.customShortcuts)
                    Label(String(localized: "App-Specific Keyboards"), systemImage: "macwindow")
                        .tag(SettingsTab.appSpecific)
                    Label(String(localized: "App Launch Shortcuts"), systemImage: "square.grid.2x2")
                        .tag(SettingsTab.appLaunch)
                }
                Section(header: Text(String(localized: "System"))) {
                    Label(String(localized: "About & Support"), systemImage: "info.circle")
                        .tag(SettingsTab.about)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 250)
        } detail: {
            Group {
                switch selectedTab {
                case .general: GeneralSettingsView()
                case .customShortcuts: CustomShortcutsSettingsView()
                case .appSpecific: AppSpecificSettingsView()
                case .appLaunch: AppLaunchSettingsView()
                case .about: AboutSettingsView()
                case nil: Text(String(localized: "Select a menu item.")).foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(NSColor.controlBackgroundColor))
        }
        // 🌟 이 부분을 추가하여 설정 창의 최소 크기를 여유 있게 키웁니다. (스크롤바 제거)
        .frame(minWidth: 750, minHeight: 650)
        .onAppear {
            accManager.checkPermission()
        }
    }
}
