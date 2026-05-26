//
//  SettingsView.swift
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

import SwiftUI

struct SettingsView: View {
    @ObservedObject private var accManager = AccessibilityManager.shared
    @ObservedObject private var settings = SettingsManager.shared

    private var isKoreanUser: Bool {
        Locale.preferredLanguages.contains { $0.hasPrefix("ko") }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $settings.selectedTab) {
                Section(header: Text(String(localized: "Profile Management"))) {
                    Label(String(localized: "Profiles"), systemImage: "person.crop.circle")
                        .tag(SettingsTab.profiles)
                }
                
                Section(header: Text(String(localized: "Settings"))) {
                    Label(String(localized: "General"), systemImage: "gearshape").tag(SettingsTab.general)
                    Label(String(localized: "Advanced"), systemImage: "gearshape.2").tag(SettingsTab.advanced)
                    Label(String(localized: "Custom Shortcuts"), systemImage: "keyboard").tag(SettingsTab.customShortcuts)
                    Label(String(localized: "App-Specific Keyboards"), systemImage: "macwindow").tag(SettingsTab.appSpecific)
                    Label(String(localized: "Website Keyboards"), systemImage: "globe").tag(SettingsTab.domainRules)
                    Label(String(localized: "App Launch Shortcuts"), systemImage: "square.grid.2x2").tag(SettingsTab.appLaunch)
                    Label(String(localized: "Text Expansion"), systemImage: "text.badge.plus").tag(SettingsTab.textExpansion)
                    if isKoreanUser {
                        Label(String(localized: "Typo Correction"), systemImage: "text.cursor").tag(SettingsTab.typoCorrection)
                    }
                    Label(String(localized: "Excluded Apps"), systemImage: "nosign").tag(SettingsTab.excludedApps)
                }
                Section(header: Text(String(localized: "System"))) {
                    Label(String(localized: "Statistics"), systemImage: "chart.bar.xaxis").tag(SettingsTab.stats)
                    Label(String(localized: "Rule Priority"), systemImage: "list.number").tag(SettingsTab.rulePriority)
                    Label(String(localized: "Rule Debugger"), systemImage: "ladybug").tag(SettingsTab.debugger)
                    Label(String(localized: "About & Support"), systemImage: "info.circle").tag(SettingsTab.about)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 250)
        } detail: {
            Group {
                switch settings.selectedTab {
                case .profiles: ProfileManagementView()
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
                case .debugger: DebuggerSettingsView()
                case .about: AboutSettingsView()
                case nil: Text(String(localized: "Select a menu item.")).foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(NSColor.controlBackgroundColor))
            // 🌟 [핵심] 여기에 타이틀을 추가해야 상단 윈도우 바에 제목이 나타납니다.
            .navigationTitle(String(localized: "LangSwitcher Settings"))
        }
        .frame(minWidth: 780, idealWidth: 800, minHeight: 750, idealHeight: 850)
        .onAppear {
            accManager.checkPermission()
            if !isKoreanUser && settings.selectedTab == .typoCorrection {
                settings.selectedTab = .general
            }
        }
    }
}
