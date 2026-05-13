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
    case advanced
    case customShortcuts
    case appSpecific
    case domainRules
    case appLaunch
    case textExpansion
    case typoCorrection
    case excludedApps
    case stats
    case rulePriority
    case debugger // 🌟 1. 규칙 디버거 탭 식별자 추가
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
                    
                    Label(String(localized: "Advanced"), systemImage: "gearshape.2")
                        .tag(SettingsTab.advanced)
                    
                    Label(String(localized: "Custom Shortcuts"), systemImage: "keyboard")
                        .tag(SettingsTab.customShortcuts)
                        
                    Label(String(localized: "App-Specific Keyboards"), systemImage: "macwindow")
                        .tag(SettingsTab.appSpecific)
                        
                    Label(String(localized: "Website Keyboards"), systemImage: "globe")
                        .tag(SettingsTab.domainRules)
                        
                    Label(String(localized: "App Launch Shortcuts"), systemImage: "square.grid.2x2")
                        .tag(SettingsTab.appLaunch)
                    
                    Label(String(localized: "Text Expansion"), systemImage: "text.badge.plus")
                        .tag(SettingsTab.textExpansion)
                    
                    if isKoreanUser {
                        Label(String(localized: "Typo Correction"), systemImage: "text.cursor")
                            .tag(SettingsTab.typoCorrection)
                    }
                    
                    Label(String(localized: "Excluded Apps"), systemImage: "nosign")
                        .tag(SettingsTab.excludedApps)
                }
                Section(header: Text(String(localized: "System"))) {
                    Label(String(localized: "Statistics"), systemImage: "chart.bar.xaxis")
                        .tag(SettingsTab.stats)
                    
                    Label(String(localized: "Rule Priority"), systemImage: "list.number")
                        .tag(SettingsTab.rulePriority)
                    
                    // 🌟 2. 사이드바 메뉴에 규칙 디버거 버튼 추가 (아이콘은 벌레 모양의 ladybug 사용)
                    Label(String(localized: "Rule Debugger"), systemImage: "ladybug")
                        .tag(SettingsTab.debugger)
                    
                    Label(String(localized: "About & Support"), systemImage: "info.circle")
                        .tag(SettingsTab.about)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 250)
        } detail: {
            Group {
                switch selectedTab {
                case .general: GeneralSettingsView()
                case .advanced: AdvancedSettingsView()
                case .customShortcuts: CustomShortcutsSettingsView()
                case .appSpecific: AppSpecificSettingsView()
                case .domainRules: DomainRuleSettingsView()
                case .appLaunch: AppLaunchSettingsView()
                case .textExpansion: TextExpansionSettingsView()
                case .typoCorrection:
                    if isKoreanUser { TypoCorrectionSettingsView() }
                case .excludedApps: ExcludedAppsSettingsView()
                case .stats: StatsSettingsView()
                case .rulePriority: RulePrioritySettingsView()
                case .debugger: DebuggerSettingsView() // 🌟 3. 화면 연결
                case .about: AboutSettingsView()
                case nil: Text(String(localized: "Select a menu item.")).foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(minWidth: 750, idealWidth: 750, minHeight: 750, idealHeight: 850)
        .onAppear {
            accManager.checkPermission()
            
            if !isKoreanUser && selectedTab == .typoCorrection {
                selectedTab = .general
            }
        }
    }
}
