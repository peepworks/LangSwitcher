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
import UniformTypeIdentifiers
import Carbon

struct AdvancedSettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared
    
    @State private var showBackupSuccess = false
    @State private var showRestoreSuccess = false
    @State private var showAutomationAlert = false
    
    private let showICloudFeature = false

    var body: some View {
        // 🌟 스크롤 인디케이터를 숨기고 컴팩트하게 정렬합니다.
        ScrollView(showsIndicators: false) {
            // 🌟 [핵심] 전체 섹션 간 간격을 25 -> 16으로 줄여 공간을 확보합니다.
            VStack(alignment: .leading, spacing: 16) {
                Text(String(localized: "Advanced Features"))
                    .font(.title2.bold())
                    .padding(.top, -5) // 타이틀을 살짝 위로 밀어올림

                hardwareKeyboardSection
                windowFocusSection
                browserTabSection
                backupRestoreSection
                
                if showICloudFeature {
                    cloudSyncSection
                }
                
                Spacer()
            }
            .padding(.horizontal, 30)
            .padding(.top, 15) // 상단 패딩 축소
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .alert(String(localized: "Backup Successful"), isPresented: $showBackupSuccess) {
            Button("OK", role: .cancel) { }
        }
        .alert(String(localized: "Restore Successful"), isPresented: $showRestoreSuccess) {
            Button("OK", role: .cancel) { }
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
                    // 🌟 텍스트 하단 여백 12 -> 8로 축소
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
                            ForEach(InputSourceManager.shared.allInputSources, id: \.id) { source in
                                Text(source.localizedName).tag(source.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 150)
                    }
                    .padding(.horizontal, 15)
                    .padding(.vertical, 6) // 🌟 Picker 상하 여백 8 -> 6으로 축소
                    
                    Text(String(localized: "Automatically switches to this language when you open a new tab or window."))
                        .font(.caption).foregroundColor(.secondary)
                        .padding(.horizontal, 15).padding(.bottom, 8)
                }
            }
        } label: {
            Text(String(localized: "Browser Tab Management")).font(.headline)
        }
    }
    
    private var backupRestoreSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 0) {
                SettingButtonRow(title: String(localized: "Export Settings"), buttonTitle: String(localized: "Export...")) {
                    exportSettings()
                }
                
                Divider().padding(.horizontal, 15)
                
                SettingButtonRow(title: String(localized: "Import Settings"), buttonTitle: String(localized: "Import...")) {
                    importSettings()
                }
            }
        } label: {
            Text(String(localized: "Backup & Restore")).font(.headline)
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
    
    // MARK: - Actions
    private func exportSettings() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmm"
        panel.nameFieldStringValue = "LangSwitcher_Backup_\(formatter.string(from: Date())).json"
        
        if panel.runModal() == .OK, let url = panel.url {
            settings.exportBackup(to: url) { success, error in
                if success {
                    self.showBackupSuccess = true
                } else if let error = error {
                    print("Export failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            settings.importBackup(from: url) { success, error in
                if success {
                    self.showRestoreSuccess = true
                } else if let error = error {
                    print("Import failed: \(error.localizedDescription)")
                }
            }
        }
    }
}

// MARK: - Input Source List Extension

struct InputSourceInfo: Identifiable, Hashable {
    let id: String
    let localizedName: String
} // 🌟 여기에 구조체를 닫는 괄호가 있어야 합니다!

extension InputSourceManager {
    /// 현재 Mac에 설치되고 선택 가능한 모든 키보드 입력 소스 목록을 반환합니다.
    var allInputSources: [InputSourceInfo] {
        var sources: [InputSourceInfo] = []
        
        // 키보드 입력 소스만 필터링
        let filter = [kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] else {
            return []
        }
        
        for source in list {
            // 🌟 [수정됨] 포인터(Ptr)가 비어있는지만 guard let으로 검사합니다.
            guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID),
                  let namePtr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) else {
                continue
            }
            
            // 🌟 [수정됨] CFString은 무조건 String이 되므로 물음표 없이 'as String'으로 확정합니다.
            let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
            let name = Unmanaged<CFString>.fromOpaque(namePtr).takeUnretainedValue() as String
            
            // 사용자가 실제로 선택할 수 있는(Select Capable) 소스인지 확인
            guard let selectablePtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable),
                  CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(selectablePtr).takeUnretainedValue()) else {
                continue
            }
            
            sources.append(InputSourceInfo(id: id, localizedName: name))
        }
        
        return sources
    }
}
