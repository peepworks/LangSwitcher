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
import AppKit // 🌟 아이콘을 불러오기 위해 추가
import UniformTypeIdentifiers

struct AppSpecificSettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared
    var hasIncomplete: Bool { settings.customApps.contains { $0.targetLanguage.isEmpty } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(String(localized: "App-Specific Keyboards")).font(.title2.bold())
                Spacer()
                Button(action: selectApp) {
                    Image(systemName: "plus.app.fill").foregroundColor(hasIncomplete ? .secondary.opacity(0.5) : .green)
                    Text(String(localized: "Add App")).foregroundColor(hasIncomplete ? .secondary.opacity(0.5) : .primary)
                }.buttonStyle(.plain).disabled(hasIncomplete)
            }.padding(.horizontal, 30).padding(.top, 30).padding(.bottom, 15)
            
            ScrollView {
                VStack(spacing: 4) {
                    if settings.customApps.isEmpty {
                        Text(String(localized: "No apps configured.")).font(.subheadline).foregroundColor(.secondary).padding(.vertical, 20)
                    }
                    
                    // 🌟 꼬리표 삭제 로직을 제거하고 깔끔하게 호출합니다.
                    ForEach($settings.customApps) { $app in
                        CustomAppRow(customApp: $app)
                    }
                }.padding(15).frame(maxWidth: .infinity, alignment: .top)
            }
            .background(Color(NSColor.textBackgroundColor)).cornerRadius(8).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
            .padding(.horizontal, 30).padding(.bottom, 30)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    
    private func selectApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.canChooseFiles = true
        
        if panel.runModal() == .OK, let url = panel.url {
            guard let bundle = Bundle(url: url), let bundleId = bundle.bundleIdentifier else { return }
            if !settings.customApps.contains(where: { $0.bundleIdentifier == bundleId }) {
                settings.customApps.append(CustomApp(bundleIdentifier: bundleId, appName: url.deletingPathExtension().lastPathComponent, targetLanguage: ""))
            }
        }
    }
}

// CustomAppRow 컴포넌트 수정
struct CustomAppRow: View {
    @Binding var customApp: CustomApp
    @ObservedObject private var settings = SettingsManager.shared

    var body: some View {
        HStack(spacing: 8) {
            
            HStack(spacing: 8) {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: customApp.bundleIdentifier) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable()
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: "app.dashed")
                        .resizable()
                        .frame(width: 20, height: 20)
                        .foregroundColor(.secondary)
                }
                Text(customApp.appName).lineLimit(1)
            }
            
            Spacer()
            
            Picker("", selection: $customApp.targetLanguage) {
                Text(String(localized: "Select Language...")).tag("")
                ForEach(InputSourceManager.shared.availableKeyboards) { keyboard in
                    Text(keyboard.name).tag(keyboard.id)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 140)
            
            Button(action: {
                settings.customApps.removeAll { $0.id == customApp.id }
            }) {
                Image(systemName: "trash").foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .padding(.leading, 5)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 2) // 🌟 상하 여백 최소화
    }
}
