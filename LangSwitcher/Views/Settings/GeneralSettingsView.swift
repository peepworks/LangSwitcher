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
import UniformTypeIdentifiers

struct GeneralSettingsView: View {
    @StateObject private var settings = SettingsManager.shared
    @StateObject private var updateManager = UpdateManager.shared
    @State private var isAutoLaunchEnabled: Bool = SMAppService.mainApp.status == .enabled
    @State private var showBackupSuccess = false
    @State private var showRestoreSuccess = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                Text(String(localized: "General")).font(.title2.bold())
                
                // 1. Startup & Updates
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Startup & Updates")).font(.headline)
                    VStack(spacing: 0) {
                        HStack { Text(String(localized: "Launch at login")); Spacer(); Toggle("", isOn: $isAutoLaunchEnabled).toggleStyle(.switch).labelsHidden().controlSize(.small).onChange(of: isAutoLaunchEnabled) { newValue in do { if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch {} } }.padding(.horizontal, 15).padding(.vertical, 6)
                        Divider().padding(.horizontal, 15)
                        HStack { Text(String(localized: "Automatically check for updates")); Spacer(); Toggle("", isOn: $updateManager.isAutoUpdateEnabled).toggleStyle(.switch).labelsHidden().controlSize(.small) }.padding(.horizontal, 15).padding(.vertical, 6)
                        Divider().padding(.horizontal, 15)
                        HStack { Text(String(localized: "Show visual feedback")); Spacer(); Toggle("", isOn: $settings.showVisualFeedback).toggleStyle(.switch).labelsHidden().controlSize(.small) }.padding(.horizontal, 15).padding(.vertical, 6)
                        Divider().padding(.horizontal, 15)
                        HStack { Text(String(localized: "Rule Test")); Spacer(); Toggle("", isOn: $settings.isTestMode).toggleStyle(.switch).labelsHidden().controlSize(.small) }.padding(.horizontal, 15).padding(.vertical, 6)
                    }
                    .background(Color(NSColor.textBackgroundColor)).cornerRadius(8).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                }
                
                // 2. 🌟 입력 소스 전환 키 영역
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Input Source Toggle Key")).font(.headline) // 섹션 제목
                    VStack(spacing: 0) {
                        ToggleShortcutRow()
                    }
                    .background(Color(NSColor.textBackgroundColor)).cornerRadius(8).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                    
                    // 🌟 도움말 텍스트 변경
                    Text(String(localized: "Set the key to switch input sources."))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 5)
                }
                
                // 3. Backup & Restore (버튼 텍스트 변경)
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Backup & Restore")).font(.headline)
                    VStack(spacing: 0) {
                        HStack { Text(String(localized: "Export Settings")); Spacer(); Button(String(localized: "Export Settings...")) { exportSettings() }.padding(.trailing, -2) }.padding(.horizontal, 15).padding(.vertical, 6)
                        Divider().padding(.horizontal, 15)
                        HStack { Text(String(localized: "Import Settings")); Spacer(); Button(String(localized: "Import Settings...")) { importSettings() }.padding(.trailing, -2) }.padding(.horizontal, 15).padding(.vertical, 6)
                    }
                    .background(Color(NSColor.textBackgroundColor)).cornerRadius(8).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                }
                
                // 4. Default Shortcuts
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Default Shortcuts")).font(.headline)
                    VStack(spacing: 0) {
                        LanguageRow(title: "⌃ Control + Space", isActive: $settings.isCtrlActive, selection: $settings.ctrlLang)
                        Divider().padding(.horizontal, 15)
                        LanguageRow(title: "⌘ Command + Space", isActive: $settings.isCmdActive, selection: $settings.cmdLang)
                        Divider().padding(.horizontal, 15)
                        LanguageRow(title: "⌥ Option + Space", isActive: $settings.isOptActive, selection: $settings.optLang)
                    }
                    .background(Color(NSColor.textBackgroundColor)).cornerRadius(8).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                }
            }.padding(.horizontal, 25).padding(.vertical, 15)
            .alert(String(localized: "Backup Successful"), isPresented: $showBackupSuccess) { Button("OK", role: .cancel) { } }
            .alert(String(localized: "Restore Successful"), isPresented: $showRestoreSuccess) { Button("OK", role: .cancel) { } }
        }
    }
    
    private func exportSettings() { let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; let f = DateFormatter(); f.dateFormat = "yyyyMMdd_HHmm"; panel.nameFieldStringValue = "LangSwitcher_Backup_\(f.string(from: Date())).json"; panel.prompt = String(localized: "Export Settings"); if panel.runModal() == .OK, let url = panel.url { do { try settings.exportBackup(to: url); showBackupSuccess = true } catch {} } }
    private func importSettings() { let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.prompt = String(localized: "Import Settings"); if panel.runModal() == .OK, let url = panel.url { do { try settings.importBackup(from: url); showRestoreSuccess = true } catch {} } }
}
