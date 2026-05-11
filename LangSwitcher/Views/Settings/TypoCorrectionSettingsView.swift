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
import UniformTypeIdentifiers // 🌟 이 줄을 추가해 주세요.

@MainActor
struct TypoCorrectionSettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared
    @State private var isRecording = false
    @State private var conflictMessage = ""
    @State private var showDuplicateWarning = false
    
    private var isKoreanUser: Bool {
        return Locale.preferredLanguages.first?.hasPrefix("ko") == true
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                
                VStack(alignment: .leading, spacing: 5) {
                    Text(String(localized: "Typo Correction")).font(.title2.bold())
                    Text(String(localized: "Fix typing errors when you type in the wrong keyboard layout."))
                        .font(.subheadline).foregroundColor(.secondary)
                }
                
                // 1. 스마트 자동 오타 감지 (한국어 사용자에게만 노출)
                if isKoreanUser {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "Smart Automation")).font(.headline)
                        
                        VStack(spacing: 0) {
                            ToggleRow(
                                title: String(localized: "Smart Auto-Correction (English → Korean)"),
                                description: String(localized: "Automatically detects when you type Korean words in English layout (e.g., 'dkssud' → '안녕') and converts them instantly upon pressing Space."),
                                isOn: $settings.isAutoTypoCorrectionEnabled
                            )
                            
                            // 🌟 [추가됨] 엔터 키 옵션 (메인 기능이 켜져 있을 때만 노출)
                            if settings.isAutoTypoCorrectionEnabled {
                                Divider().padding(.horizontal, 15)
                                ToggleRow(
                                    title: String(localized: "Trigger on Enter Key"),
                                    description: String(localized: "Also attempt to correct typos when pressing the Enter key. (May cause false positives for short commands like 'cle' in Terminal)"),
                                    isOn: $settings.isAutoTypoCorrectionOnEnterEnabled
                                )
                            }
                        }
                        .background(Color(NSColor.textBackgroundColor)).cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                    }
                }
                
                // 2. 수동 오타 교정 (단축키 방식)
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Manual Correction")).font(.headline)
                    
                    VStack(spacing: 0) {
                        ToggleRow(
                            title: String(localized: "Enable Manual Typo Correction"),
                            description: String(localized: "Convert the currently selected text when the shortcut is pressed."),
                            isOn: $settings.isTypoCorrectionEnabled
                        )
                        
                        if settings.isTypoCorrectionEnabled {
                            Divider().padding(.horizontal, 15)
                            
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(String(localized: "Correction Scope")).font(.body)
                                    Text(String(localized: "Choose whether to convert just the current word or the entire line.")).font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Picker("", selection: $settings.isSentenceMode) {
                                    Text(String(localized: "Current Word")).tag(false)
                                    Text(String(localized: "Entire Line")).tag(true)
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 180)
                            }.padding(15)
                            
                            Divider().padding(.horizontal, 15)
                            
                            HStack {
                                Text(String(localized: "Correction Shortcut")).font(.body).foregroundColor(.secondary)
                                Spacer()
                                Button(action: {
                                    settings.typoDisplayString = ""; settings.typoKeyCode = 0; settings.typoModifierFlags = 0
                                    showDuplicateWarning = false; isRecording = true
                                    startRecording()
                                }) {
                                    Text(showDuplicateWarning ? conflictMessage : (isRecording ? String(localized: "Press any keys...") : (settings.typoDisplayString.isEmpty ? String(localized: "Click to Record") : settings.typoDisplayString)))
                                        .frame(width: 140).padding(.vertical, 4)
                                        .background(showDuplicateWarning ? Color.red.opacity(0.15) : (isRecording ? Color.blue.opacity(0.2) : Color.secondary.opacity(0.1)))
                                        .foregroundColor(showDuplicateWarning ? .red : .primary).cornerRadius(6)
                                }.buttonStyle(.plain)
                                
                                Button(role: .destructive, action: {
                                    settings.typoDisplayString = ""; settings.typoKeyCode = 0; settings.typoModifierFlags = 0
                                }) { Image(systemName: "trash").foregroundColor(.red) }.buttonStyle(.plain).padding(.leading, 10)
                            }.padding(15)
                        }
                    }
                    .background(Color(NSColor.textBackgroundColor)).cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                    
                    Text(String(localized: "Note: This feature simulates selecting the text and replacing it. It may not work perfectly in all applications depending on their text selection behavior."))
                        .font(.caption).foregroundColor(.secondary).padding(.leading, 5)
                }
                // 3. 앱별 적응형 딜레이 설정 (고급)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(String(localized: "App-Specific Delays (Advanced)")).font(.headline)
                        Spacer()
                        Button(action: addDelayApp) {
                            Image(systemName: "plus.circle.fill").foregroundColor(.blue)
                            Text(String(localized: "Add App"))
                        }.buttonStyle(.plain)
                    }
                    Text(String(localized: "Increase the delay if typo correction fails or overlaps in heavy applications like IDEs or Electron apps."))
                        .font(.caption).foregroundColor(.secondary)
                    
                    VStack(spacing: 0) {
                        if settings.appDelays.isEmpty {
                            Text(String(localized: "No app-specific delays configured."))
                                .font(.subheadline).foregroundColor(.secondary).padding(.vertical, 20)
                                .frame(maxWidth: .infinity, alignment: .center)
                        } else {
                            ForEach($settings.appDelays) { $appDelay in
                                AppDelayRow(appDelay: $appDelay)
                                if appDelay.id != settings.appDelays.last?.id {
                                    Divider().padding(.horizontal, 15)
                                }
                            }
                        }
                    }
                    .background(Color(NSColor.textBackgroundColor)).cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                    
                    // 🌟 [새로 추가된 부분] 리스트 하단 우측 정렬된 기본값 복원 버튼
                    HStack {
                        Spacer()
                        Button(action: {
                            settings.restoreDefaultAppDelays()
                        }) {
                            Image(systemName: "arrow.counterclockwise")
                            Text(String(localized: "Restore Defaults"))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                        .font(.caption)
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, 25).padding(.vertical, 15)
            .onDisappear { stopRecording() }
        }
    }
    
    private func startRecording() {
        ShortcutRecorder.shared.startRecording(
            completion: { keyCode, modifiers, display in
                self.registerShortcut(keyCode: keyCode, modifiers: modifiers, display: display)
            },
            onTimeout: {
                self.isRecording = false
                self.showDuplicateWarning = false
            }
        )
    }
    
    private func registerShortcut(keyCode: UInt16, modifiers: UInt64, display: String) {
        if let conflictName = getConflictMessage(keyCode: keyCode, modifierFlags: modifiers) {
            NSSound.beep()
            conflictMessage = String(format: String(localized: "In use: %@"), conflictName)
            showDuplicateWarning = true
            isRecording = false
            stopRecording()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { self.showDuplicateWarning = false }
        } else {
            settings.typoKeyCode = keyCode
            settings.typoModifierFlags = modifiers
            settings.typoDisplayString = display
            isRecording = false
            stopRecording()
        }
    }
    
    private func stopRecording() {
        ShortcutRecorder.shared.stopRecording()
    }
    
    private func getConflictMessage(keyCode: UInt16, modifierFlags: UInt64) -> String? {
        let settings = SettingsManager.shared
        if settings.toggleKeyCode == keyCode && settings.toggleModifierFlags == modifierFlags { return String(localized: "This shortcut is already used for Toggle Shortcut.") }
        if settings.customShortcuts.contains(where: { $0.keyCode == keyCode && $0.modifierFlags == modifierFlags }) { return String(localized: "This shortcut is already used for a Custom Shortcut.") }
        if settings.appLaunchShortcuts.contains(where: { $0.keyCode == keyCode && $0.modifierFlags == modifierFlags }) { return String(localized: "This shortcut is already used for an App Launch Shortcut.") }
        return nil
    }
    
    // TypoCorrectionSettingsView 내부에 함수 추가
    private func addDelayApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        
        if panel.runModal() == .OK, let url = panel.url {
            guard let bundle = Bundle(url: url), let bundleId = bundle.bundleIdentifier else { return }
            let appName = url.deletingPathExtension().lastPathComponent
            
            // 중복 방지 후 0.5초를 기본값으로 앱 추가
            if !settings.appDelays.contains(where: { $0.bundleIdentifier == bundleId }) {
                settings.appDelays.append(AppDelay(bundleIdentifier: bundleId, appName: appName, delay: 0.5))
            }
        }
    }
}

struct ToggleRow: View {
    let title: String
    let description: String
    @Binding var isOn: Bool
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                Text(description).font(.caption).foregroundColor(.secondary)
            }
            Spacer(minLength: 20)
            Toggle("", isOn: $isOn).toggleStyle(.switch).labelsHidden().controlSize(.small)
        }.padding(15)
    }
}

struct AppDelayRow: View {
    @Binding var appDelay: AppDelay
    @ObservedObject private var settings = SettingsManager.shared
    @State private var appIcon: NSImage? = nil

    var body: some View {
        HStack(spacing: 12) {
            // 앱 아이콘 및 이름
            if let icon = appIcon {
                Image(nsImage: icon).resizable().frame(width: 20, height: 20)
            } else {
                Image(systemName: "app.dashed").resizable().frame(width: 20, height: 20).foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(appDelay.appName).lineLimit(1)
                Text(String(format: "%.2f sec", appDelay.delay)).font(.caption).foregroundColor(.secondary)
            }
            .frame(width: 120, alignment: .leading)
            
            // 🌟 딜레이 조절 슬라이더 (0.1초 ~ 1.5초 범위, 0.05초 단위)
            Slider(value: $appDelay.delay, in: 0.1...1.5, step: 0.05)
                .labelsHidden()
            
            // 삭제 버튼
            Button(action: {
                settings.appDelays.removeAll { $0.id == appDelay.id }
            }) {
                Image(systemName: "trash").foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .padding(.leading, 5)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .onAppear { loadIcon() }
    }
    
    private func loadIcon() {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appDelay.bundleIdentifier) else { return }
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            DispatchQueue.main.async { self.appIcon = icon }
        }
    }
}
