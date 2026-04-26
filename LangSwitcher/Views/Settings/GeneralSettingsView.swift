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
import UniformTypeIdentifiers // 에러 해결: .json 타입을 사용하기 위해 필수 추가

struct GeneralSettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var updateManager = UpdateManager.shared
    @State private var isAutoLaunchEnabled: Bool = SMAppService.mainApp.status == .enabled
    @State private var showBackupSuccess = false
    @State private var showRestoreSuccess = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "General")).font(.title2.bold())
                
                // 1. 시작 및 옵션 섹션
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Startup & Options")).font(.headline)
                    VStack(spacing: 0) {
                        // 로그인 시 자동 실행
                        SettingToggleRow(title: String(localized: "Launch at login"), isOn: $isAutoLaunchEnabled)
                            .onChange(of: isAutoLaunchEnabled) { newValue in
                                do {
                                    if newValue { try SMAppService.mainApp.register() }
                                    else { try SMAppService.mainApp.unregister() }
                                } catch { print("Auto-launch error: \(error)") }
                            }
                        
                        Divider().padding(.horizontal, 15)
                        
                        // 자동 업데이트 확인
                        SettingToggleRow(title: String(localized: "Automatically check for updates"), isOn: $updateManager.isAutoUpdateEnabled)
                        
                        Divider().padding(.horizontal, 15)
                        
                        // 시각적 피드백 (HUD)
                        SettingToggleRow(title: String(localized: "Show visual feedback"), isOn: $settings.showVisualFeedback)
                        
                        // 시각 피드백이 켜져 있을 때만 미니 플래그 옵션 표시
                        if settings.showVisualFeedback {
                            SettingToggleRow(
                                title: String(localized: "Show mini flag near text cursor"),
                                isOn: $settings.isCursorHUDEnabled
                            )
                            .padding(.leading, 20) // 하위 옵션 느낌을 주기 위한 들여쓰기
                        }
                            
                        Text(String(localized: "Displays a brief overlay indicating the new language."))
                            .font(.caption).foregroundColor(.secondary).lineSpacing(2)
                            .padding(.horizontal, 15).padding(.bottom, 12).padding(.top, -2)
                        
                        // 🌟 [추가됨] 사운드 및 햅틱 피드백 토글 스위치 (구분선 Divider 포함)
                        Divider().padding(.horizontal, 15)
                        
                        SettingToggleRow(title: String(localized: "Play sound on switch"), isOn: $settings.isSoundFeedbackEnabled)
                        
                        Divider().padding(.horizontal, 15)
                        
                        SettingToggleRow(title: String(localized: "Haptic feedback on switch"), isOn: $settings.isHapticFeedbackEnabled)
                        
                        Divider().padding(.horizontal, 15)
                        
                        // 규칙 테스트 모드
                        SettingToggleRow(title: String(localized: "Rule Test"), isOn: $settings.isTestMode)
                    }
                    .background(Color(NSColor.textBackgroundColor)).cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                }
                
                // 2. 입력 소스 전환 키 섹션
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Input Source Toggle Key")).font(.headline)
                    VStack(spacing: 0) {
                        ToggleShortcutRow()
                    }
                    .background(Color(NSColor.textBackgroundColor)).cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                }
                
                // 3. 백업 및 복구 섹션
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Backup & Restore")).font(.headline)
                    VStack(spacing: 0) {
                        SettingButtonRow(title: String(localized: "Export Settings"), buttonTitle: String(localized: "Export...")) {
                            exportSettings()
                        }
                        
                        Divider().padding(.horizontal, 15)
                        
                        SettingButtonRow(title: String(localized: "Import Settings"), buttonTitle: String(localized: "Import...")) {
                            importSettings()
                        }
                    }
                    .background(Color(NSColor.textBackgroundColor)).cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                }
                
                // 4. 기본 단축키 섹션
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Default Shortcuts")).font(.headline)
                    VStack(spacing: 0) {
                        LanguageRow(title: "⌃ Control + Space", isActive: $settings.isCtrlActive, selection: $settings.ctrlLang)
                        Divider().padding(.horizontal, 15)
                        LanguageRow(title: "⌘ Command + Space", isActive: $settings.isCmdActive, selection: $settings.cmdLang)
                        Divider().padding(.horizontal, 15)
                        LanguageRow(title: "⌥ Option + Space", isActive: $settings.isOptActive, selection: $settings.optLang)
                    }
                    .background(Color(NSColor.textBackgroundColor)).cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                }
                
            }
            .padding(.horizontal, 25)
            .padding(.vertical, 12)
            .alert(String(localized: "Backup Successful"), isPresented: $showBackupSuccess) {
                Button("OK", role: .cancel) { }
            }
            .alert(String(localized: "Restore Successful"), isPresented: $showRestoreSuccess) {
                Button("OK", role: .cancel) { }
            }
        }
    }
    
    // MARK: - Actions
    // ... (exportSettings, importBackup 함수 유지) ...
    private func exportSettings() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmm"
        panel.nameFieldStringValue = "LangSwitcher_Backup_\(formatter.string(from: Date())).json"
        
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try settings.exportBackup(to: url)
                showBackupSuccess = true
            } catch {
                print("Export failed: \(error)")
            }
        }
    }
    
    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try settings.importBackup(from: url)
                showRestoreSuccess = true
            } catch {
                print("Import failed: \(error)")
            }
        }
    }
}

// 🌟 에러 해결: 올려주신 소스코드 하단에 LanguageRow 컴포넌트가 누락되어 있어 다시 추가했습니다.
struct LanguageRow: View {
    let title: String
    @Binding var isActive: Bool
    @Binding var selection: String
    @ObservedObject private var inputManager = InputSourceManager.shared

    var body: some View {
        HStack {
            Toggle("", isOn: $isActive)
                .toggleStyle(.checkbox) // 네모난 체크박스 스타일
                .labelsHidden()
            
            Text(title).font(.body).padding(.leading, 5)
            Spacer(minLength: 20)

            ZStack(alignment: .trailing) {
                if isActive {
                    Picker("", selection: $selection) {
                        if selection.isEmpty { Text(String(localized: "Select Keyboard")).tag("") }
                        ForEach(inputManager.availableKeyboards) { kb in Text(kb.name).tag(kb.id) }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                } else {
                    Text(String(localized: "Disabled")).font(.subheadline).foregroundColor(.secondary).padding(.trailing, 16)
                }
            }
            .frame(width: 130, alignment: .trailing)
            .padding(.trailing, -3)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 6)
    }
}
