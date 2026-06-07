//
//  AdvancedSettingsView.swift
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
import UniformTypeIdentifiers
import Carbon

struct AdvancedSettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared

    @State private var showAutomationAlert = false
    private let showICloudFeature = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                Text(String(localized: "Advanced Features"))
                    .font(.title2.bold())
                    .padding(.top, -5)

                hardwareKeyboardSection
                windowFocusSection
                browserTabSection
                
                // 🌟 [수정] 프로필 백업 및 복원 섹션으로 교체
                profileBackupRestoreSection
                
                if showICloudFeature {
                    cloudSyncSection
                }
                
                memoryManagementSection
                
                Spacer()
            }
            .padding(.horizontal, 30)
            .padding(.top, 15)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .alert(String(localized: "Automation Permission Required"), isPresented: $showAutomationAlert) {
            Button(String(localized: "Open Settings")) {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
            }
            Button(String(localized: "OK"), role: .cancel) { }
        } message: {
            Text(String(localized: "To remember tab languages, LangSwitcher needs Automation permission for your browsers. Please enable it in System Settings, or check the 'Info & Support' tab."))
        }
    }
    
    // MARK: - Subviews
    
    private var hardwareKeyboardSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 0) {
                SettingToggleRow(
                    title: String(localized: "Caps Lock to Hyper Key & Input Source Switcher"),
                    isOn: $settings.isHyperKeyEnabled
                )
                Text(String(localized: "Mapped instantly in the background. Short press toggles input source, long press acts as Hyper Key."))
                    .font(.caption).foregroundColor(.secondary).lineSpacing(2)
                    .padding(.horizontal, 15).padding(.bottom, 8).padding(.top, -2)
            }
        } label: {
            Text(String(localized: "Hardware Keyboard")).font(.headline)
        }
    }
    
    private var windowFocusSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 0) {
                SettingToggleRow(
                    title: String(localized: "Remember input source per window"),
                    isOn: $settings.isWindowMemoryEnabled
                )
                Text(String(localized: "Remembers the language state for each individual window and auto-restores it when focused."))
                    .font(.caption).foregroundColor(.secondary).lineSpacing(2)
                    .padding(.horizontal, 15).padding(.bottom, 8).padding(.top, -2)

                Divider().padding(.horizontal, 15)

                SettingToggleRow(
                    title: String(localized: "Clear window records when app exits"),
                    isOn: $settings.isWindowMemoryCleanupEnabled
                )
                Text(String(localized: "Automatically clears stored window language data when the application is closed to optimize memory."))
                    .font(.caption).foregroundColor(.secondary).lineSpacing(2)
                    .padding(.horizontal, 15).padding(.bottom, 8).padding(.top, -2)
            }
        } label: {
            Text(String(localized: "Window Focus Management")).font(.headline)
        }
    }
    
    private var browserTabSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 0) {
                SettingToggleRow(
                    title: String(localized: "Remember input source per browser tab (Beta)"),
                    isOn: $settings.isBrowserTabMemoryEnabled
                )
                .onChange(of: settings.isBrowserTabMemoryEnabled) { newValue in
                    if newValue {
                        AccessibilityManager.shared.checkAutomationPermissions(prompt: true)
                        self.showAutomationAlert = true
                    }
                }
                
                Text(String(localized: "Requires Automation permission on first use. Supports Chrome, Edge, Brave, and Safari. Restores language based on tab ID or domain."))
                    .font(.caption).foregroundColor(.secondary).lineSpacing(2)
                    .padding(.horizontal, 15).padding(.bottom, 8).padding(.top, -2)

                if settings.isBrowserTabMemoryEnabled {
                    Divider().padding(.horizontal, 15)

                    HStack {
                        Text(String(localized: "Default language for new tabs"))
                            .font(.body)
                        Spacer()
                        
                        Picker("", selection: $settings.newTabDefaultLanguage) {
                            Text(String(localized: "Keep Previous")).tag("None")
                            Divider()
                            ForEach(InputSourceManager.shared.availableKeyboards, id: \.id) { keyboard in
                                Text(keyboard.name).tag(keyboard.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 150)
                    }
                    .padding(.horizontal, 15)
                    .padding(.vertical, 6)
                    
                    Text(String(localized: "Automatically switches to this language when you open a new tab or window."))
                        .font(.caption).foregroundColor(.secondary)
                        .padding(.horizontal, 15).padding(.bottom, 8)
                }
            }
        } label: {
            Text(String(localized: "Browser Tab Management")).font(.headline)
        }
    }
    
    // 🌟 [수정] 프로필 시스템(v0.9.0)에 맞춰 텍스트와 UI 구조를 개선한 백업 섹션
    private var profileBackupRestoreSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 0) {
                Text(String(localized: "You can save all your current profile layouts, website rules, and replacement text presets to a JSON file, or restore them anytime."))
                    .font(.caption).foregroundColor(.secondary).lineSpacing(2)
                    .padding(.horizontal, 15).padding(.bottom, 12).padding(.top, 4)
                
                SettingButtonRow(title: String(localized: "Export Profiles"), buttonTitle: String(localized: "Export...")) {
                    exportSettings()
                }
                
                Divider().padding(.horizontal, 15)
                
                SettingButtonRow(title: String(localized: "Import Profiles"), buttonTitle: String(localized: "Import...")) {
                    importSettings()
                }
            }
        } label: {
            Text(String(localized: "Profile Backup & Restore")).font(.headline)
        }
    }
    
    private var cloudSyncSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 0) {
                SettingToggleRow(
                    title: String(localized: "Sync settings via iCloud"),
                    isOn: $settings.isCloudSyncEnabled
                )
                Text(String(localized: "Automatically synchronizes your shortcuts, excluded apps, and preferences across all your Mac devices using iCloud."))
                    .font(.caption).foregroundColor(.secondary).lineSpacing(2)
                    .padding(.horizontal, 15).padding(.bottom, 8).padding(.top, -2)
                
                if settings.isCloudSyncEnabled {
                    HStack {
                        Spacer()
                        Button(String(localized: "Sync Now")) {
                            SettingsManager.shared.syncToCloud()
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                        .padding(.trailing, 15)
                        .padding(.bottom, 8)
                    }
                }
            }
        } label: {
            Text(String(localized: "Cloud Sync")).font(.headline)
        }
    }
    
    private var memoryManagementSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "Clear App Memory"))
                            .font(.body)
                        Text(String(localized: "Instantly deletes all saved language states for windows and browser tabs. Use this if language switching gets tangled or to free up memory."))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    Spacer(minLength: 15)
                    
                    Button(action: {
                        settings.clearAllAppCaches()
                    }) {
                        Text(String(localized: "Clear Memory"))
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 8)
            }
        } label: {
            Text(String(localized: "Memory Management")).font(.headline)
        }
    }
    
    // MARK: - Actions
    
    private func exportSettings() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]

        if let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            panel.directoryURL = docsURL
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmm"
        panel.nameFieldStringValue = "LangSwitcher_Profiles_\(formatter.string(from: Date())).json"
        
        NSApp.activate(ignoringOtherApps: true)

        // 🌟 [수복] 설정 창 윈도우 주소를 안전하게 확보하여 시트를 올릴 앵커로 사용합니다.
        let targetWindow = NSApp.windows.first { $0.title.contains("LangSwitcher Settings") } ?? NSApp.keyWindow

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            
            // SettingsManager의 백그라운드 I/O 트랜잭션 가동
            settings.exportBackup(to: url) { success, error in
                guard success else {
                    if let error = error {
                        dprint("❌ Export failed: \(error.localizedDescription)")
                    }
                    return
                }
                
                // 🌟 [Swift 6 교정] 백그라운드에서 복귀 시 메인 액터 격리를 명시적으로 확약합니다.
                Task { @MainActor in
                    let alert = NSAlert()
                    alert.messageText = String(localized: "Profiles Backup Successful")
                    alert.informativeText = String(localized: "All profiles and associated settings have been exported successfully.")
                    alert.alertStyle = .informational
                    
                    if let appIcon = NSImage(named: NSImage.applicationIconName) {
                        alert.icon = appIcon
                    }
                    
                    for button in alert.buttons { button.focusRingType = .none }
                    
                    // 🌟 [우주 방어] runModal()을 폐기하고 스레드 무해한 비동기 시트 모달을 집행합니다.
                    if let window = targetWindow {
                        alert.beginSheetModal(for: window, completionHandler: nil)
                    } else {
                        alert.runModal() // Fallback 스레드가 메인 액터 안이므로 안전
                    }
                }
            }
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = String(localized: "Import Profiles Backup")

        NSApp.activate(ignoringOtherApps: true)
        
        let targetWindow = NSApp.windows.first { $0.title.contains("LangSwitcher Settings") } ?? NSApp.keyWindow

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            
            settings.importBackup(from: url) { success, error in
                // 🌟 [Swift 6 교정] UI 변경 및 알럿 개시는 무조건 메인 액터 요새 안에서 처리
                Task { @MainActor in
                    let alert = NSAlert()
                    
                    if let appIcon = NSImage(named: NSImage.applicationIconName) {
                        alert.icon = appIcon
                    }
                    for button in alert.buttons { button.focusRingType = .none }
                    
                    if success {
                        alert.messageText = String(localized: "Profiles Restore Successful")
                        alert.informativeText = String(localized: "Your profiles and settings have been imported successfully.")
                        alert.alertStyle = .informational
                    } else {
                        let errMsg = error?.localizedDescription ?? "Unknown context error."
                        dprint("❌ Import failed: \(errMsg)")
                        alert.messageText = String(localized: "Import Failed")
                        alert.informativeText = String(localized: "Failed to read the backup file. It might be corrupted or in an unsupported format.\n\nError: \(errMsg)")
                        alert.alertStyle = .critical
                    }
                    
                    // 🌟 [우주 방어] 중첩 블로킹 런루프 프리즈를 차단하는 비동기 시트 가동
                    if let window = targetWindow {
                        alert.beginSheetModal(for: window, completionHandler: nil)
                    } else {
                        alert.runModal()
                    }
                }
            }
        }
    }
}
