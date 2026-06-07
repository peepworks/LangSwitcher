//
//  TypoCorrectionSettingsView.swift
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

    private var payload: Binding<ProfileSettingsPayload> {
        Binding(
            get: { settings.activeProfile.payload },
            set: { newValue in
                // 🌟 [도킹 2] 유저가 스위치를 바꾸는 순간, 활성 프로필 장부에 대입함과 동시에
                // 백엔드 타건 스레드의 로컬 캐시 스냅샷까지 한 프레임의 오차도 없이 즉시 갱신합니다.
                settings.activeProfile.payload = newValue
                
                guard !settings.isBatchUpdating else { return }
                settings.updateSnapshot()
                settings.scheduleSave()
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProfileHeaderView() // 🌟 헤더 추가
            
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {

                    VStack(alignment: .leading, spacing: 5) {
                        Text(String(localized: "Typo Correction")).font(.title2.bold())
                        Text(String(localized: "Fix typing errors when you type in the wrong keyboard layout."))
                            .font(.subheadline).foregroundColor(.secondary)
                    }

                    if isKoreanUser {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(String(localized: "Smart Automation")).font(.headline)

                            VStack(spacing: 0) {
                                ToggleRow(
                                    title: String(localized: "Smart Auto-Correction (English → Korean)"),
                                    description: String(localized: "Automatically detects when you type Korean words in English layout (e.g., 'dkssud' → '안녕') and converts them instantly upon pressing Space."),
                                    isOn: payload.isAutoTypoCorrectionEnabled
                                )

                                if settings.activeProfile.payload.isAutoTypoCorrectionEnabled {
                                    Divider().padding(.horizontal, 15)
                                    ToggleRow(
                                        title: String(localized: "Trigger on Enter Key"),
                                        description: String(localized: "Also attempt to correct typos when pressing the Enter key. (May cause false positives for short commands like 'cle' in Terminal)"),
                                        isOn: payload.isAutoTypoCorrectionOnEnterEnabled
                                    )
                                }
                            }
                            .background(Color(NSColor.textBackgroundColor)).cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "Manual Correction")).font(.headline)

                        VStack(spacing: 0) {
                            ToggleRow(
                                title: String(localized: "Enable Manual Typo Correction"),
                                description: String(localized: "Convert the currently selected text when the shortcut is pressed."),
                                isOn: payload.isTypoCorrectionEnabled
                            )

                            if settings.activeProfile.payload.isTypoCorrectionEnabled {
                                Divider().padding(.horizontal, 15)

                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(String(localized: "Correction Scope")).font(.body)
                                        Text(String(localized: "Choose whether to convert just the current word or the entire line.")).font(.caption).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Picker("", selection: payload.isSentenceMode) {
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
                                        settings.activeProfile.payload.typoDisplayString = ""
                                        settings.activeProfile.payload.typoKeyCode = 0
                                        settings.activeProfile.payload.typoModifierFlags = 0
                                        showDuplicateWarning = false
                                        isRecording = true
                                        startRecording()
                                    }) {
                                        let display = settings.activeProfile.payload.typoDisplayString
                                        Text(showDuplicateWarning ? conflictMessage : (isRecording ? String(localized: "Press any keys...") : (display.isEmpty ? String(localized: "Click to Record") : display)))
                                            .frame(width: 140).padding(.vertical, 4)
                                            .background(showDuplicateWarning ? Color.red.opacity(0.15) : (isRecording ? Color.blue.opacity(0.2) : Color.secondary.opacity(0.1)))
                                            .foregroundColor(showDuplicateWarning ? .red : .primary).cornerRadius(6)
                                    }.buttonStyle(.plain)

                                    Button(role: .destructive, action: {
                                        settings.activeProfile.payload.typoDisplayString = ""
                                        settings.activeProfile.payload.typoKeyCode = 0
                                        settings.activeProfile.payload.typoModifierFlags = 0
                                    }) { Image(systemName: "trash").foregroundColor(.red) }.buttonStyle(.plain).padding(.leading, 10)
                                }.padding(15)
                            }
                        }
                        .background(Color(NSColor.textBackgroundColor)).cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))

                        Text(String(localized: "Note: This feature simulates selecting the text and replacing it. It may not work perfectly in all applications depending on their text selection behavior."))
                            .font(.caption).foregroundColor(.secondary).padding(.leading, 5)
                    }

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
                            if settings.activeProfile.payload.appDelays.isEmpty {
                                Text(String(localized: "No app-specific delays configured."))
                                    .font(.subheadline).foregroundColor(.secondary).padding(.vertical, 20)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            } else {
                                ForEach(payload.appDelays) { $appDelay in
                                    AppDelayRow(appDelay: $appDelay)
                                    if appDelay.id != settings.activeProfile.payload.appDelays.last?.id {
                                        Divider().padding(.horizontal, 15)
                                    }
                                }
                            }
                        }
                        .background(Color(NSColor.textBackgroundColor)).cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))

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
            settings.activeProfile.payload.typoKeyCode = keyCode
            settings.activeProfile.payload.typoModifierFlags = modifiers
            settings.activeProfile.payload.typoDisplayString = display
            isRecording = false
            stopRecording()
        }
    }

    private func stopRecording() { ShortcutRecorder.shared.stopRecording() }

    private func getConflictMessage(keyCode: UInt16, modifierFlags: UInt64) -> String? {
        let payload = settings.activeProfile.payload
        if settings.toggleKeyCode == keyCode && settings.toggleModifierFlags == modifierFlags { return String(localized: "This shortcut is already used for Toggle Shortcut.") }
        if payload.customShortcuts.contains(where: { $0.keyCode == keyCode && $0.modifierFlags == modifierFlags }) { return String(localized: "This shortcut is already used for a Custom Shortcut.") }
        if payload.appLaunchShortcuts.contains(where: { $0.keyCode == keyCode && $0.modifierFlags == modifierFlags }) { return String(localized: "This shortcut is already used for an App Launch Shortcut.") }
        return nil
    }

    private func addDelayApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            guard let bundle = Bundle(url: url), let bundleId = bundle.bundleIdentifier else { return }
            let appName = url.deletingPathExtension().lastPathComponent

            if !settings.activeProfile.payload.appDelays.contains(where: { $0.bundleIdentifier == bundleId }) {
                settings.activeProfile.payload.appDelays.append(AppDelay(bundleIdentifier: bundleId, appName: appName, delay: 0.5))
            }
        }
    }
}

// AppDelayRow 도 바인딩 수정
struct AppDelayRow: View {
    @Binding var appDelay: AppDelay
    @ObservedObject private var settings = SettingsManager.shared
    @State private var appIcon: NSImage? = nil
    // 🌟 [추가] 빠른 스크롤 시 아이콘 뒤섞임 방지를 위한 로드 트래킹 ID
    @State private var currentIconLoadID = UUID()

    var body: some View {
        HStack(spacing: 12) {
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "app.dashed")
                    .resizable()
                    .frame(width: 20, height: 20)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(appDelay.appName).lineLimit(1)
                Text(String(format: "%.2f sec", appDelay.delay))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(width: 120, alignment: .leading)

            Slider(value: $appDelay.delay, in: 0.1...1.5, step: 0.05)
                .labelsHidden()

            Button(action: {
                settings.activeProfile.payload.appDelays.removeAll { $0.id == appDelay.id }
            }) {
                Image(systemName: "trash").foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .padding(.leading, 5)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .onAppear {
            loadIcon()
        }
        // 🌟 [핵심 추가] 행 전체가 화면에서 사라질 때(스크롤 아웃, 창 닫힘)
        // 무거운 고해상도 앱 아이콘 메모리(NSImage)를 완벽하게 방출합니다!
        .onDisappear {
            self.appIcon = nil
        }
    }

    private func loadIcon() {
        let bundleID = appDelay.bundleIdentifier
        guard !bundleID.isEmpty else { return }
        
        // 🌟 고유 로드 ID 생성 및 할당
        let loadID = UUID()
        self.currentIconLoadID = loadID
        
        DispatchQueue.global(qos: .userInitiated).async {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            
            DispatchQueue.main.async {
                // 🌟 백그라운드 작업이 끝난 시점에 내가 여전히 이 셀의 주인인지 검사
                if self.currentIconLoadID == loadID {
                    self.appIcon = icon
                }
            }
        }
    }
}

// 🌟 TypoCorrectionSettingsView.swift 맨 아래에 추가
struct ToggleRow: View {
    var title: String
    var description: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 15)
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 10)
    }
}
