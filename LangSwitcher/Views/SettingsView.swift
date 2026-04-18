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
    case typoCorrection
    case excludedApps
    case about
}

struct SettingsView: View {
    @StateObject private var accManager = AccessibilityManager.shared
    @State private var selectedTab: SettingsTab? = .general

    // 🌟 한국어 사용자 여부 확인 (OS 선호 언어 목록에 한국어가 있는지 체크)
    private var isKoreanUser: Bool {
        Locale.preferredLanguages.contains { $0.hasPrefix("ko") }
    }

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
                    
                    // 🌟 한국어 사용자일 때만 '한/영 오타 변환' 메뉴를 사이드바에 표시합니다.
                    if isKoreanUser {
                        Label(String(localized: "Typo Correction"), systemImage: "text.cursor")
                            .tag(SettingsTab.typoCorrection)
                    }
                    
                    Label(String(localized: "Excluded Apps"), systemImage: "nosign")
                        .tag(SettingsTab.excludedApps)
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
                case .typoCorrection:
                    // 🌟 화면 접근 시에도 안전하게 한 번 더 체크합니다.
                    if isKoreanUser { TypoCorrectionSettingsView() }
                case .excludedApps: ExcludedAppsSettingsView()
                case .about: AboutSettingsView()
                case nil: Text(String(localized: "Select a menu item.")).foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(minWidth: 750, minHeight: 650)
        .onAppear {
            accManager.checkPermission()
            
            // 만약 한국어 사용자가 아닌데 초기 탭이 오타 변환으로 꼬여있을 경우 General로 초기화
            if !isKoreanUser && selectedTab == .typoCorrection {
                selectedTab = .general
            }
        }
    }
}
