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
import ServiceManagement

struct SettingsView: View {
    @StateObject private var accManager = AccessibilityManager.shared
    @StateObject private var settings = SettingsManager.shared // ✅ 메모리 기반 매니저 연결
    
    @State private var isAutoLaunchEnabled: Bool = SMAppService.mainApp.status == .enabled

    // 🌟 앱 버전을 시스템 설정(TARGETS > General)에서 자동으로 불러옵니다.
    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 25) {
            Text("General").font(.title3.bold())

            Toggle("Launch at login", isOn: $isAutoLaunchEnabled)
                .toggleStyle(.checkbox)
                .onChange(of: isAutoLaunchEnabled) { newValue in
                    toggleLaunch(newValue)
                }

            Divider()
            Text("Shortcut Settings").font(.title3.bold())
            
            VStack(spacing: 18) {
                LanguageRow(title: "⌃ Control + Space", isActive: $settings.isCtrlActive, selection: $settings.ctrlLang)
                LanguageRow(title: "⌘ Command + Space", isActive: $settings.isCmdActive, selection: $settings.cmdLang)
                LanguageRow(title: "⌥ Option + Space", isActive: $settings.isOptActive, selection: $settings.optLang)
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 30)
            Divider()
            
            HStack {
                // 🌟 하드코딩되어 있던 v0.1.1을 지우고 자동 변수(appVersion)로 교체했습니다.
                Text("LangSwitcher v\(appVersion)").font(.footnote).foregroundColor(.secondary)
                Spacer()
                
                if accManager.isTrusted {
                    Label("Accessibility Granted", systemImage: "checkmark.shield.fill")
                        .font(.footnote).foregroundColor(.green)
                } else {
                    Button(action: {
                        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                        NSWorkspace.shared.open(url)
                    }) {
                        Label("Open Accessibility Settings", systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                    }.foregroundColor(.orange)
                }
            }
            .padding(.bottom, 10)
        }
        .padding(30)
        .frame(width: 500, height: 400)
        .onAppear {
            accManager.checkPermission()
        }
    }

    private func toggleLaunch(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled { try service.register() }
            else { try service.unregister() }
        } catch { print("자동 실행 설정 오류: \(error)") }
    }
}

struct LanguageRow: View {
    let title: String
    @Binding var isActive: Bool
    @Binding var selection: String

    var body: some View {
        HStack {
            Button(action: { isActive.toggle() }) {
                HStack(spacing: 12) {
                    Image(systemName: isActive ? "checkmark.square.fill" : "square")
                        .font(.title3).foregroundColor(isActive ? .blue : .secondary)
                    Text(title).font(.body)
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 40)
            
            if isActive {
                Picker("", selection: $selection) {
                    ForEach(SupportedLanguage.allCases) { lang in
                        Text(lang.rawValue).tag(lang.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 170)
                .padding(.trailing, 20)
            } else {
                Text("Disabled").font(.subheadline).foregroundColor(.secondary).padding(.trailing, 25)
            }
        }
    }
}
