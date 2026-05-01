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
    case advanced // 🌟 [추가됨] 고급 설정 탭
    case customShortcuts
    case appSpecific
    case appLaunch
    case typoCorrection
    case excludedApps
    case stats // 🌟 [추가됨]
    case about
}

struct SettingsView: View {
    @ObservedObject private var accManager = AccessibilityManager.shared
    @State private var selectedTab: SettingsTab? = .general

    // 한국어 사용자 여부 확인 (OS 선호 언어 목록에 한국어가 있는지 체크)
    private var isKoreanUser: Bool {
        Locale.preferredLanguages.contains { $0.hasPrefix("ko") }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                Section(header: Text(String(localized: "Settings"))) {
                    Label(String(localized: "General"), systemImage: "gearshape")
                        .tag(SettingsTab.general)
                    
                    // 🌟 [추가됨] 톱니바퀴 두 개 아이콘을 사용한 고급 메뉴
                    Label(String(localized: "Advanced"), systemImage: "gearshape.2")
                        .tag(SettingsTab.advanced)
                    
                    Label(String(localized: "Custom Shortcuts"), systemImage: "keyboard")
                        .tag(SettingsTab.customShortcuts)
                    Label(String(localized: "App-Specific Keyboards"), systemImage: "macwindow")
                        .tag(SettingsTab.appSpecific)
                    Label(String(localized: "App Launch Shortcuts"), systemImage: "square.grid.2x2")
                        .tag(SettingsTab.appLaunch)
                    
                    // 한국어 사용자일 때만 '한/영 오타 변환' 메뉴를 사이드바에 표시
                    if isKoreanUser {
                        Label(String(localized: "Typo Correction"), systemImage: "text.cursor")
                            .tag(SettingsTab.typoCorrection)
                    }
                    
                    Label(String(localized: "Excluded Apps"), systemImage: "nosign")
                        .tag(SettingsTab.excludedApps)
                }
                Section(header: Text(String(localized: "System"))) {
                    // 🌟 통계 탭 UI 추가
                    Label(String(localized: "Statistics"), systemImage: "chart.bar.xaxis")
                            .tag(SettingsTab.stats)
                    Label(String(localized: "About & Support"), systemImage: "info.circle")
                        .tag(SettingsTab.about)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 250)
        } detail: {
            Group {
                switch selectedTab {
                case .general: GeneralSettingsView()
                case .advanced: AdvancedSettingsView() // 🌟 [추가됨] 선택 시 렌더링할 뷰
                case .customShortcuts: CustomShortcutsSettingsView()
                case .appSpecific: AppSpecificSettingsView()
                case .appLaunch: AppLaunchSettingsView()
                case .typoCorrection:
                    if isKoreanUser { TypoCorrectionSettingsView() }
                case .excludedApps: ExcludedAppsSettingsView()
                case .stats: StatsSettingsView() // 🌟 통계 뷰 렌더링 추가
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
            
            if !isKoreanUser && selectedTab == .typoCorrection {
                selectedTab = .general
            }
        }
    }
}
