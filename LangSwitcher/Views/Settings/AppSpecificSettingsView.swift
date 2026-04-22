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
import AppKit
import UniformTypeIdentifiers

struct AppSpecificSettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared
    var hasIncomplete: Bool { settings.customApps.contains { $0.targetLanguage.isEmpty } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 🌟 1. 마스터 스위치 영역
            HStack {
                Text(String(localized: "App-Specific Keyboards")).font(.title2.bold())
                Spacer()
                Toggle("", isOn: $settings.isAppSpecificEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small) // 🌟 일반 설정과 동일한 아담한 크기로 변경
            }.padding(.horizontal, 30).padding(.top, 30).padding(.bottom, 10)

            // 🌟 2. 스위치 상태에 따라 활성/비활성되는 영역
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Text(String(localized: "Automatically switch to a specific language when an app becomes active."))
                        .font(.subheadline).foregroundColor(.secondary)
                    Spacer()
                    Button(action: selectApp) {
                        Image(systemName: "plus.app.fill").foregroundColor(hasIncomplete ? .secondary.opacity(0.5) : .green)
                        Text(String(localized: "Add App")).foregroundColor(hasIncomplete ? .secondary.opacity(0.5) : .primary)
                    }.buttonStyle(.plain).disabled(hasIncomplete)
                }

                ScrollView {
                    VStack(spacing: 4) {
                        if settings.customApps.isEmpty {
                            Text(String(localized: "No apps configured.")).font(.subheadline).foregroundColor(.secondary).padding(.vertical, 20)
                        }

                        ForEach($settings.customApps) { $app in
                            CustomAppRow(customApp: $app)
                        }
                    }.padding(15).frame(maxWidth: .infinity, alignment: .top)
                }
                .background(Color(NSColor.textBackgroundColor)).cornerRadius(8).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
            }
            .padding(.horizontal, 30).padding(.bottom, 30)
            .opacity(settings.isAppSpecificEnabled ? 1.0 : 0.5) // 끄면 반투명
            .disabled(!settings.isAppSpecificEnabled) // 끄면 클릭 차단
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

// CustomAppRow 코드는 기존과 동일하게 이 아래에 두시면 됩니다!
struct CustomAppRow: View {
    @Binding var customApp: CustomApp
    @ObservedObject private var settings = SettingsManager.shared
    @State private var appIcon: NSImage? = nil

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                if let icon = appIcon {
                    Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                } else {
                    Image(systemName: "app.dashed").resizable().frame(width: 20, height: 20).foregroundColor(.secondary)
                }
                Text(customApp.appName).lineLimit(1)
            }
            Spacer()
            Picker("", selection: $customApp.targetLanguage) {
                Text(String(localized: "Select Language...")).tag("")
                ForEach(InputSourceManager.shared.availableKeyboards) { keyboard in Text(keyboard.name).tag(keyboard.id) }
            }.pickerStyle(.menu).labelsHidden().frame(width: 140)
            Button(action: { settings.customApps.removeAll { $0.id == customApp.id } }) { Image(systemName: "trash").foregroundColor(.red) }
            .buttonStyle(.plain).padding(.leading, 5)
        }
        .padding(.horizontal, 10).padding(.vertical, 2)
        .onAppear { loadIcon() }
        .onChange(of: customApp.bundleIdentifier) { _ in loadIcon() }
    }

    private func loadIcon() {
        let bundleID = customApp.bundleIdentifier
        guard !bundleID.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            DispatchQueue.main.async { self.appIcon = icon }
        }
    }
}
