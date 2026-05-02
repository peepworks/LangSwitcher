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

struct AdvancedSettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared
    
    @State private var showBackupSuccess = false
    @State private var showRestoreSuccess = false
    
    // 🌟 [추가됨] 자동화 권한 안내 알림 상태
    @State private var showAutomationAlert = false
    
    private let showICloudFeature = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                Text(String(localized: "Advanced Features")).font(.title2.bold())

                // 1. 하드웨어 키보드 제어 (Hyper Key)
                GroupBox {
                    VStack(alignment: .leading, spacing: 0) {
                        SettingToggleRow(
                            title: String(localized: "Caps Lock to Hyper Key & Input Source Switcher"),
                            isOn: $settings.isHyperKeyEnabled
                        )
                        Text(String(localized: "Mapped instantly in the background. Short press toggles input source, long press acts as Hyper Key."))
                            .font(.caption).foregroundColor(.secondary).lineSpacing(2)
                            .padding(.horizontal, 15).padding(.bottom, 12).padding(.top, -2)
                    }
                } label: {
                    Text(String(localized: "Hardware Keyboard")).font(.headline)
                }

                // 2. 창(Window) 단위 메모리 관리
                GroupBox {
                    VStack(alignment: .leading, spacing: 0) {
                        SettingToggleRow(
                            title: String(localized: "Remember input source per window"),
                            isOn: $settings.isWindowMemoryEnabled
                        )
                        Text(String(localized: "Remembers the language state for each individual window and auto-restores it when focused."))
                            .font(.caption).foregroundColor(.secondary).lineSpacing(2)
                            .padding(.horizontal, 15).padding(.bottom, 12).padding(.top, -2)

                        Divider().padding(.horizontal, 15)

                        SettingToggleRow(
                            title: String(localized: "Clear window records when app exits"),
                            isOn: $settings.isWindowMemoryCleanupEnabled
                        )
                        Text(String(localized: "Automatically clears stored window language data when the application is closed to optimize memory."))
                            .font(.caption).foregroundColor(.secondary).lineSpacing(2)
                            .padding(.horizontal, 15).padding(.bottom, 12).padding(.top, -2)
                    }
                } label: {
                    Text(String(localized: "Window Focus Management")).font(.headline)
                }
                
                // 3. 브라우저 탭 단위 메모리 관리
                GroupBox {
                    VStack(alignment: .leading, spacing: 0) {
                        SettingToggleRow(
                            title: String(localized: "Remember input source per browser tab (Beta)"),
                            isOn: $settings.isBrowserTabMemoryEnabled
                        )
                        .onChange(of: settings.isBrowserTabMemoryEnabled) { newValue in
                            if newValue {
                                // 시스템 권한 요청도 시도하고, 우리 자체 알림창도 띄웁니다.
                                AccessibilityManager.shared.checkAutomationPermissions(prompt: true)
                                self.showAutomationAlert = true // 🌟 [핵심] 팝업 띄우기
                            }
                        }
                        
                        Text(String(localized: "Requires Automation permission on first use. Supports Chrome, Edge, Brave, and Safari. Restores language based on tab ID or domain."))
                            .font(.caption).foregroundColor(.secondary).lineSpacing(2)
                            .padding(.horizontal, 15).padding(.bottom, 12).padding(.top, -2)
                    }
                } label: {
                    Text(String(localized: "Browser Tab Management")).font(.headline)
                }
                
                // 4. 백업 및 복구 섹션
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
                
                // 5. iCloud 동기화 섹션
                if showICloudFeature {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 0) {
                            SettingToggleRow(
                                title: String(localized: "Sync settings via iCloud"),
                                isOn: $settings.isCloudSyncEnabled
                            )
                            Text(String(localized: "Automatically synchronizes your shortcuts, excluded apps, and preferences across all your Mac devices using iCloud."))
                                .font(.caption).foregroundColor(.secondary).lineSpacing(2)
                                .padding(.horizontal, 15).padding(.bottom, 12).padding(.top, -2)
                            
                            if settings.isCloudSyncEnabled {
                                HStack {
                                    Spacer()
                                    Button(String(localized: "Sync Now")) {
                                        SettingsManager.shared.syncToCloud()
                                    }
                                    .buttonStyle(.link)
                                    .font(.caption)
                                    .padding(.trailing, 15)
                                    .padding(.bottom, 10)
                                }
                            }
                        }
                    } label: {
                        Text(String(localized: "Cloud Sync")).font(.headline)
                    }
                }
                
                Spacer()
            }
            .padding()
            .alert(String(localized: "Backup Successful"), isPresented: $showBackupSuccess) {
                Button("OK", role: .cancel) { }
            }
            .alert(String(localized: "Restore Successful"), isPresented: $showRestoreSuccess) {
                Button("OK", role: .cancel) { }
            }
            // 🌟 [추가됨] 권한 설정 안내 알림창 (설정 열기 버튼 포함)
            .alert(String(localized: "Automation Permission Required"), isPresented: $showAutomationAlert) {
                Button(String(localized: "Open Settings")) {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
                }
                Button("OK", role: .cancel) { }
            } message: {
                Text(String(localized: "To remember tab languages, LangSwitcher needs Automation permission for your browsers. Please enable it in System Settings, or check the 'Info & Support' tab."))
            }
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
