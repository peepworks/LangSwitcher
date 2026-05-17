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

struct ExcludedAppsSettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared

    private var payload: Binding<ProfileSettingsPayload> {
        Binding(
            get: { settings.activeProfile.payload },
            set: { settings.activeProfile.payload = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProfileHeaderView() // 🌟 헤더 추가
            
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    HStack(alignment: .center) {
                        Text(String(localized: "Excluded Apps")).font(.title2.bold())
                        Spacer()
                        Toggle("", isOn: $settings.isExcludedAppsEnabled) // 🌟 전역 변수 유지
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .controlSize(.small)
                    }

                    Text(String(localized: "LangSwitcher will be completely disabled while using these apps. Useful for games or heavy software to prevent shortcut conflicts and input lag."))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 10)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(String(localized: "Active Exclusions")).font(.headline)
                            Spacer()
                            Button(action: addExcludedApp) {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus.circle.fill").foregroundColor(.blue)
                                    Text(String(localized: "Add App")).font(.body)
                                }.foregroundColor(.primary)
                            }
                            .buttonStyle(.plain)
                            .help(String(localized: "Add Application"))
                            .disabled(!settings.isExcludedAppsEnabled)
                        }

                        VStack(spacing: 0) {
                            if settings.activeProfile.payload.excludedApps.isEmpty {
                                Text(String(localized: "No apps excluded. LangSwitcher is active everywhere."))
                                    .font(.subheadline).foregroundColor(.secondary).padding(.vertical, 20)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            } else {
                                ForEach(payload.excludedApps) { $app in
                                    ExcludedAppRow(excludedApp: $app)
                                    if app.id != settings.activeProfile.payload.excludedApps.last?.id {
                                        Divider().padding(.horizontal, 15).padding(.vertical, 4)
                                    }
                                }
                            }
                        }
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                    }
                    .opacity(settings.isExcludedAppsEnabled ? 1.0 : 0.5)
                    Spacer()
                }
                .padding(.horizontal, 25)
                .padding(.vertical, 15)
            }
        }
    }

    private func addExcludedApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.prompt = String(localized: "Exclude")

        if panel.runModal() == .OK, let url = panel.url {
            guard let bundle = Bundle(url: url), let bundleId = bundle.bundleIdentifier else { return }
            let appName = url.deletingPathExtension().lastPathComponent
            if !settings.activeProfile.payload.excludedApps.contains(where: { $0.bundleIdentifier == bundleId }) {
                settings.activeProfile.payload.excludedApps.append(ExcludedApp(bundleIdentifier: bundleId, appName: appName))
            }
        }
    }
}

struct ExcludedAppRow: View {
    @Binding var excludedApp: ExcludedApp
    @ObservedObject private var settings = SettingsManager.shared
    @State private var appIcon: NSImage? = nil
    @State private var currentIconLoadID = UUID()

    var body: some View {
        HStack(spacing: 8) {
            if let icon = appIcon {
                Image(nsImage: icon).resizable().frame(width: 20, height: 20)
            } else {
                Image(systemName: "app.dashed").resizable().frame(width: 20, height: 20).foregroundColor(.secondary)
            }
            Text(excludedApp.appName).lineLimit(1)
            Spacer()
            Button(action: { settings.activeProfile.payload.excludedApps.removeAll { $0.id == excludedApp.id } }) {
                Image(systemName: "trash").foregroundColor(.red)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .onAppear { loadIcon() }
        .onChange(of: excludedApp.bundleIdentifier) { _ in loadIcon() }
    }

    private func loadIcon() {
        let bundleID = excludedApp.bundleIdentifier
        guard !bundleID.isEmpty else { return }
        let loadID = UUID()
        self.currentIconLoadID = loadID
        DispatchQueue.global(qos: .userInitiated).async {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            DispatchQueue.main.async { if self.currentIconLoadID == loadID { self.appIcon = icon } }
        }
    }
}
