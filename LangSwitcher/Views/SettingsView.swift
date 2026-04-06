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

struct SettingsView: View {
    @StateObject private var accManager = AccessibilityManager.shared
    @StateObject private var settings = SettingsManager.shared
    
    @State private var isAutoLaunchEnabled: Bool = SMAppService.mainApp.status == .enabled

    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }
    
    // 🌟 방어 로직: 단축키가 비어있거나, 언어가 선택되지 않은("") 항목이 있으면 true 반환
    var hasIncompleteShortcut: Bool {
        settings.customShortcuts.contains { $0.displayString.isEmpty || $0.targetLanguage.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("General").font(.title3.bold())

            Toggle("Launch at login", isOn: $isAutoLaunchEnabled)
                .toggleStyle(.checkbox)
                .onChange(of: isAutoLaunchEnabled) { newValue in
                    toggleLaunch(newValue)
                }

            Divider()
            
            Text("Default Shortcuts").font(.title3.bold())
            
            VStack(spacing: 12) {
                LanguageRow(title: "⌃ Control + Space", isActive: $settings.isCtrlActive, selection: $settings.ctrlLang)
                LanguageRow(title: "⌘ Command + Space", isActive: $settings.isCmdActive, selection: $settings.cmdLang)
                LanguageRow(title: "⌥ Option + Space", isActive: $settings.isOptActive, selection: $settings.optLang)
            }
            .padding(.horizontal, 10)

            Divider()

            HStack {
                Text("Custom Shortcuts").font(.title3.bold())
                Spacer()
                
                Button(action: {
                    if !hasIncompleteShortcut {
                        // 🌟 빈 문자열("")로 초기화하여 '언어 선택'을 유도합니다.
                        let newShortcut = CustomShortcut(keyCode: 0, modifierFlags: 0, displayString: "", targetLanguage: "")
                        settings.customShortcuts.append(newShortcut)
                    }
                }) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(hasIncompleteShortcut ? .secondary.opacity(0.5) : .blue)
                    Text("Add")
                        .foregroundColor(hasIncompleteShortcut ? .secondary.opacity(0.5) : .primary)
                }
                .buttonStyle(.plain)
                .disabled(hasIncompleteShortcut)
            }
            
            ScrollView {
                VStack(spacing: 10) {
                    ForEach($settings.customShortcuts) { $shortcut in
                        CustomShortcutRow(shortcut: $shortcut) {
                            settings.customShortcuts.removeAll { $0.id == shortcut.id }
                        }
                    }
                }
                .padding(15)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .frame(height: 160)
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
            .padding(.bottom, 5)

            Divider()
            
            HStack {
                Text("LangSwitcher v\(appVersion)").font(.footnote).foregroundColor(.secondary)
                Spacer()

                if accManager.isTrusted {
                    Label("Accessibility Granted", systemImage: "checkmark.shield.fill")
                        .font(.footnote).foregroundColor(.green)
                } else {
                    Button(action: {
                        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                        NSWorkspace.shared.open(url)
                    }) {
                        Label("Open Accessibility Settings", systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                    }.foregroundColor(.orange)
                }
            }
            .padding(.top, 2)
        }
        .padding(30)
        .frame(width: 500)
        .onAppear {
            accManager.checkPermission()
        }
    }

    private func toggleLaunch(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled { try service.register() }
            else { try service.unregister() }
        } catch { print("자동 실행 설정 오류: \(error)") }
    }
}

// 고정 단축키용 Row
struct LanguageRow: View {
    let title: String
    @Binding var isActive: Bool
    @Binding var selection: String
    
    @StateObject private var inputManager = InputSourceManager.shared // 🌟 시스템 키보드 연동

    var body: some View {
        HStack {
            Button(action: { isActive.toggle() }) {
                HStack(spacing: 12) {
                    Image(systemName: isActive ? "checkmark.square.fill" : "square")
                        .font(.title3).foregroundColor(isActive ? .blue : .secondary)
                    Text(title).font(.body)
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 40)
            
            if isActive {
                Picker("", selection: $selection) {
                    // 🌟 선택값이 비어있으면 Placeholder 표시
                    if selection.isEmpty {
                        Text(String(localized: "Select Keyboard")).tag("")
                    }
                    // 🌟 맥 시스템에 설치된 키보드 목록 표시
                    ForEach(inputManager.availableKeyboards) { kb in
                        Text(kb.name).tag(kb.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 170)
                .padding(.trailing, 20)
            } else {
                Text("Disabled").font(.subheadline).foregroundColor(.secondary).padding(.trailing, 25)
            }
        }
    }
}

// 커스텀 단축키 녹화용 Row
struct CustomShortcutRow: View {
    @Binding var shortcut: CustomShortcut
    var onDelete: () -> Void
    
    @State private var isRecording = false
    @State private var showDuplicateWarning = false
    @State private var monitor: Any?
    @StateObject private var inputManager = InputSourceManager.shared // 🌟 시스템 키보드 연동
    
    private let QWERTYKeyMap: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U",
        34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
        27: "-", 24: "=", 33: "[", 30: "]", 42: "\\", 41: ";", 39: "'", 43: ",", 47: ".", 44: "/"
    ]

    var body: some View {
        HStack {
            Button(action: {
                // 클릭 시 데이터 즉시 초기화하여 'Add' 버튼 비활성화 유도
                shortcut.displayString = ""
                shortcut.keyCode = 0
                shortcut.modifierFlags = 0
                showDuplicateWarning = false
                
                isRecording = true
                startRecording()
            }) {
                let displayText = showDuplicateWarning ? String(localized: "Already in use!") :
                                  isRecording ? String(localized: "Press any keys...") :
                                  (shortcut.displayString.isEmpty ? String(localized: "Click to Record") : shortcut.displayString)
                
                Text(displayText)
                    .frame(width: 140)
                    .padding(.vertical, 4)
                    .background(showDuplicateWarning ? Color.red.opacity(0.15) : (isRecording ? Color.blue.opacity(0.2) : Color.secondary.opacity(0.1)))
                    .foregroundColor(showDuplicateWarning ? .red : .primary)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            Picker("", selection: $shortcut.targetLanguage) {
                // 🌟 선택값이 비어있으면 Placeholder 표시
                if shortcut.targetLanguage.isEmpty {
                    Text(String(localized: "Select Keyboard")).tag("")
                }
                // 🌟 맥 시스템에 설치된 키보드 목록 표시
                ForEach(inputManager.availableKeyboards) { kb in
                    Text(kb.name).tag(kb.id)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 140)
            
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash").foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .padding(.leading, 10)
        }
        .onDisappear { stopRecording() }
    }
    
    private func startRecording() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let keyCode = event.keyCode
            let newModifierFlags = UInt64(flags.rawValue)
            
            // 🌟 중복 검사
            let isDuplicate = SettingsManager.shared.customShortcuts.contains { existing in
                existing.id != shortcut.id &&
                existing.keyCode == keyCode &&
                existing.modifierFlags == newModifierFlags &&
                !existing.displayString.isEmpty
            }
            
            if isDuplicate {
                NSSound.beep() // 에러음
                showDuplicateWarning = true
                isRecording = false
                stopRecording()
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    if showDuplicateWarning { showDuplicateWarning = false }
                }
                return nil
            }
            
            var str = ""
            if flags.contains(.control) { str += "⌃ " }
            if flags.contains(.option) { str += "⌥ " }
            if flags.contains(.shift) { str += "⇧ " }
            if flags.contains(.command) { str += "⌘ " }
            
            if keyCode == 49 {
                str += "Space"
            } else if let mappedChar = QWERTYKeyMap[keyCode] {
                str += mappedChar
            } else if let chars = event.charactersIgnoringModifiers?.uppercased(), !chars.isEmpty {
                str += chars
            } else {
                str += "Key(\(keyCode))"
            }
            
            shortcut.keyCode = keyCode
            shortcut.modifierFlags = newModifierFlags
            shortcut.displayString = str
            
            isRecording = false
            stopRecording()
            return nil
        }
    }
    
    private func stopRecording() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
