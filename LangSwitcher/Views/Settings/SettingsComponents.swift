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
import Dispatch
import AppKit
import UniformTypeIdentifiers

// 🌟 앱 실행 시 딱 한 번만 메모리에 상주하는 전역 키맵
let globalKeyMap: [UInt16: String] = [
    0:"A", 1:"S", 2:"D", 3:"F", 4:"H", 5:"G", 6:"Z", 7:"X", 8:"C", 9:"V",
    11:"B", 12:"Q", 13:"W", 14:"E", 15:"R", 16:"Y", 17:"T", 31:"O", 32:"U", 34:"I",
    35:"P", 37:"L", 38:"J", 40:"K", 45:"N", 46:"M",
    18:"1", 19:"2", 20:"3", 21:"4", 23:"5", 22:"6", 26:"7", 28:"8", 25:"9", 29:"0",
    27:"-", 24:"=", 33:"[", 30:"]", 42:"\\", 41:";", 39:"'", 43:",", 47:".", 44:"/",
    122:"F1", 120:"F2", 99:"F3", 118:"F4", 96:"F5", 97:"F6", 98:"F7", 100:"F8",
    101:"F9", 109:"F10", 103:"F11", 111:"F12", 105:"F13", 107:"F14", 113:"F15", 106:"F16",
    64:"F17", 79:"F18", 80:"F19", 90:"F20",
    53:"Esc", 48:"Tab", 36:"Return", 51:"Delete", 117:"Fwd Del", 115:"Home", 119:"End",
    116:"PgUp", 121:"PgDn", 123:"←", 124:"→", 125:"↓", 126:"↑",
    54:"R-Cmd", 55:"L-Cmd", 56:"L-Shift", 60:"R-Shift", 58:"L-Opt", 61:"R-Opt", 59:"L-Ctrl", 62:"R-Ctrl",
    57:"Caps Lock", 63:"Fn"
]

// 🌟 앱 전체에서 사용하는 수식어 키코드 모음
let globalModifierKeyCodes: Set<UInt16> = [54, 55, 56, 60, 58, 61, 59, 62, 57, 63]

// 키보드 입력을 문자열로 예쁘게 포맷팅 해주는 공통 헬퍼 함수
// 키보드 입력을 문자열로 예쁘게 포맷팅 해주는 공통 헬퍼 함수
func formatKeyEquivalent(modifierFlags: UInt, keyCode: UInt16) -> String {
    var parts: [String] = []
    let flags = NSEvent.ModifierFlags(rawValue: modifierFlags)

    if flags.contains(.control) { parts.append("⌃") }
    if flags.contains(.option)  { parts.append("⌥") }
    if flags.contains(.shift)   { parts.append("⇧") }
    if flags.contains(.command) { parts.append("⌘") }
    
    // 🌟 [수정됨] 함수 내부에 있던 배열을 지우고, 방금 만든 전역 상수(globalModifierKeyCodes)를 사용합니다.
    if globalModifierKeyCodes.contains(keyCode) && modifierFlags == 0 {
        return globalKeyMap[keyCode] ?? "Unknown"
    }
    
    if keyCode != 0 || (keyCode == 0 && globalKeyMap[keyCode] != nil && modifierFlags == 0) {
        if let keyString = globalKeyMap[keyCode] {
            parts.append(keyString)
        }
    }
    return parts.joined(separator: "")
}

// MARK: - 1. ToggleShortcutRow (한/영 전환 단축키 UI)
struct ToggleShortcutRow: View {
    @ObservedObject private var settings = SettingsManager.shared
    @State private var isRecording = false
    @State private var showDuplicateWarning = false
    @State private var conflictMessage = ""
    // 🗑️ timeoutTask 삭제됨

    var body: some View {
        HStack {
            Text(String(localized: "Toggle Key")).font(.body).foregroundColor(.secondary)
            Spacer()

            Button(action: {
                settings.toggleDisplayString = ""; settings.toggleKeyCode = 0; settings.toggleModifierFlags = 0
                showDuplicateWarning = false; isRecording = true
                startRecording()
            }) {
                Text(showDuplicateWarning ? conflictMessage : (isRecording ? String(localized: "Press any keys...") : (settings.toggleDisplayString.isEmpty ? String(localized: "Change...") : settings.toggleDisplayString)))
                    .frame(width: 140).padding(.vertical, 4)
                    .background(showDuplicateWarning ? Color.red.opacity(0.15) : (isRecording ? Color.orange.opacity(0.2) : Color.secondary.opacity(0.1)))
                    .foregroundColor(showDuplicateWarning ? .red : .primary).cornerRadius(6)
            }.buttonStyle(.plain)

            Button(role: .destructive, action: {
                settings.toggleDisplayString = ""; settings.toggleKeyCode = 0; settings.toggleModifierFlags = 0
            }) { Image(systemName: "trash").foregroundColor(.red) }
            .buttonStyle(.plain)
            .padding(.leading, 10)
            .help(String(localized: "Reset toggle key"))
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 10)
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        isRecording = true
        showDuplicateWarning = false
            
        ShortcutRecorder.shared.startRecording { code, mods, display in
            self.registerShortcut(keyCode: code, modifiers: mods, display: display)
        } onTimeout: {
            self.isRecording = false
        }
    }

    private func registerShortcut(keyCode: UInt16, modifiers: UInt64, display: String) {
        if let conflictName = getConflictMessage(keyCode: keyCode, modifiers: modifiers, ignoreID: nil) {
            NSSound.beep()
            conflictMessage = String(format: String(localized: "In use: %@"), conflictName)
            showDuplicateWarning = true; isRecording = false; stopRecording()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { showDuplicateWarning = false }
        } else {
            settings.toggleKeyCode = keyCode; settings.toggleModifierFlags = modifiers; settings.toggleDisplayString = display
            isRecording = false; stopRecording()
        }
    }

    private func stopRecording() {
        // 🌟 [수정됨] 공용 매니저를 통해 정지하도록 통일
        ShortcutRecorder.shared.stopRecording()
        isRecording = false
    }

    private func getConflictMessage(keyCode: UInt16, modifiers: UInt64, ignoreID: UUID?) -> String? {
        if settings.customShortcuts.contains(where: { $0.keyCode == keyCode && $0.modifierFlags == modifiers }) {
            return String(localized: "Custom Shortcut")
        }
        if settings.appLaunchShortcuts.contains(where: { $0.keyCode == keyCode && $0.modifierFlags == modifiers }) {
            return String(localized: "App Launch Shortcut")
        }
        if settings.isTypoCorrectionEnabled && settings.typoKeyCode == keyCode && settings.typoModifierFlags == modifiers {
            return String(localized: "Typo Correction")
        }
        return nil
    }
}

// MARK: - 2. CustomShortcutRow (사용자 지정 단축키 UI)
struct CustomShortcutRow: View {
    @ObservedObject private var settings = SettingsManager.shared
    @Binding var shortcut: CustomShortcut
    
    @State private var isRecording = false
    // 🗑️ timeoutTask 삭제됨
    
    @State private var showDuplicateWarning = false
    @State private var conflictMessage = ""

    var body: some View {
        HStack(spacing: 8) {
            Button(action: {
                if isRecording { stopRecording() } else { startRecording() }
            }) {
                Text(showDuplicateWarning ? conflictMessage : (isRecording ? String(localized: "Recording...") : (shortcut.displayString.isEmpty ? String(localized: "Record") : shortcut.displayString)))
                    .frame(width: 90)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8) // 글자가 길면 살짝 줄여줌
                    .foregroundColor(showDuplicateWarning ? .red : (isRecording ? .red : .primary))
            }
            
            Spacer()

            Picker("", selection: $shortcut.targetLanguage) {
                Text(String(localized: "Select Language...")).tag("")
                ForEach(InputSourceManager.shared.availableKeyboards) { keyboard in
                    Text(keyboard.name).tag(keyboard.id)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 140)
            
            Button(action: {
                settings.customShortcuts.removeAll { $0.id == shortcut.id }
            }) {
                Image(systemName: "trash").foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .padding(.leading, 5)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        isRecording = true
        showDuplicateWarning = false
            
        ShortcutRecorder.shared.startRecording { code, mods, display in
            self.saveShortcut(keyCode: code, modifiers: mods, displayString: display)
        } onTimeout: {
            self.isRecording = false
        }
    }
    
    private func saveShortcut(keyCode: UInt16, modifiers: UInt64, displayString: String) {
        if let conflict = getConflictMessage(keyCode: keyCode, modifiers: modifiers) {
            NSSound.beep() // 에러 소리 재생
            conflictMessage = String(format: String(localized: "In use: %@"), conflict)
            showDuplicateWarning = true
            stopRecording()
            
            // 2초 뒤 경고 메시지 해제
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                showDuplicateWarning = false
            }
        } else {
            if let index = settings.customShortcuts.firstIndex(where: { $0.id == self.shortcut.id }) {
                settings.customShortcuts[index].keyCode = keyCode
                settings.customShortcuts[index].modifierFlags = modifiers
                settings.customShortcuts[index].displayString = displayString
            }
            stopRecording()
        }
    }

    private func stopRecording() {
        // 🌟 [수정됨] 공용 매니저를 통해 정지하도록 통일
        ShortcutRecorder.shared.stopRecording()
        isRecording = false
    }
    
    private func getConflictMessage(keyCode: UInt16, modifiers: UInt64) -> String? {
        if settings.toggleKeyCode == keyCode && settings.toggleModifierFlags == modifiers { return String(localized: "Toggle Key") }
        if settings.isTypoCorrectionEnabled && settings.typoKeyCode == keyCode && settings.typoModifierFlags == modifiers { return String(localized: "Typo Correction") }
        if settings.appLaunchShortcuts.contains(where: { $0.keyCode == keyCode && $0.modifierFlags == modifiers }) { return String(localized: "App Launch Shortcut") }
        // 자기 자신을 제외한 다른 Custom Shortcut과 중복되는지 체크
        if settings.customShortcuts.contains(where: { $0.id != self.shortcut.id && $0.keyCode == keyCode && $0.modifierFlags == modifiers }) { return String(localized: "Custom Shortcut") }
        
        return nil
    }
}

// MARK: - 3. AppLaunchShortcutRow (앱 실행 단축키 UI)
struct AppLaunchShortcutRow: View {
    @ObservedObject private var settings = SettingsManager.shared
    @Binding var shortcut: AppLaunchShortcut
    
    @State private var isRecording = false
    // 🗑️ timeoutTask 삭제됨
    
    @State private var appIcon: NSImage? = nil
    @State private var currentIconLoadID = UUID()
    
    @State private var showDuplicateWarning = false
    @State private var conflictMessage = ""

    var body: some View {
        HStack(spacing: 8) {
            
            if shortcut.bundleIdentifier.isEmpty {
                Button(String(localized: "Select App...")) {
                    selectApp()
                }
            } else {
                HStack(spacing: 8) {
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
                    Text(shortcut.appName).lineLimit(1)
                }
            }

            Spacer()

            Button(action: {
                if isRecording { stopRecording() } else { startRecording() }
            }) {
                Text(showDuplicateWarning ? conflictMessage : (isRecording ? String(localized: "Recording...") : (shortcut.displayString.isEmpty ? String(localized: "Record") : shortcut.displayString)))
                    .frame(width: 90)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundColor(showDuplicateWarning ? .red : (isRecording ? .red : .primary))
            }
            .padding(.trailing, 5)

            Button(action: {
                settings.appLaunchShortcuts.removeAll { $0.id == shortcut.id }
            }) {
                Image(systemName: "trash").foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
        .onDisappear { stopRecording() }
        .onAppear { loadIcon() }
        .onChange(of: shortcut.bundleIdentifier) { _ in loadIcon() }
    }

    private func loadIcon() {
        let bundleID = shortcut.bundleIdentifier
        guard !bundleID.isEmpty else { return }
        let loadID = UUID()
        self.currentIconLoadID = loadID
        
        DispatchQueue.global(qos: .userInitiated).async {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            DispatchQueue.main.async {
                if self.currentIconLoadID == loadID {
                    self.appIcon = icon
                }
            }
        }
    }

    private func selectApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.canChooseFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            guard let bundle = Bundle(url: url), let bundleId = bundle.bundleIdentifier else { return }
            let appName = url.deletingPathExtension().lastPathComponent
            if let index = settings.appLaunchShortcuts.firstIndex(where: { $0.id == shortcut.id }) {
                settings.appLaunchShortcuts[index].bundleIdentifier = bundleId
                settings.appLaunchShortcuts[index].appName = appName
            }
        }
    }

    private func startRecording() {
        isRecording = true
        showDuplicateWarning = false
            
        ShortcutRecorder.shared.startRecording { code, mods, display in
            self.saveShortcut(keyCode: code, modifiers: mods, displayString: display)
        } onTimeout: {
            self.isRecording = false
        }
    }
    
    private func saveShortcut(keyCode: UInt16, modifiers: UInt64, displayString: String) {
        if let conflict = getConflictMessage(keyCode: keyCode, modifiers: modifiers) {
            NSSound.beep() // 에러 소리 재생
            conflictMessage = String(format: String(localized: "In use: %@"), conflict)
            showDuplicateWarning = true
            stopRecording()
            
            // 2초 뒤 경고 메시지 해제
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                showDuplicateWarning = false
            }
        } else {
            if let index = settings.appLaunchShortcuts.firstIndex(where: { $0.id == self.shortcut.id }) {
                settings.appLaunchShortcuts[index].keyCode = keyCode
                settings.appLaunchShortcuts[index].modifierFlags = modifiers
                settings.appLaunchShortcuts[index].displayString = displayString
            }
            stopRecording()
        }
    }

    private func stopRecording() {
        // 🌟 [수정됨] 공용 매니저를 통해 정지하도록 통일
        ShortcutRecorder.shared.stopRecording()
        isRecording = false
    }
    
    private func getConflictMessage(keyCode: UInt16, modifiers: UInt64) -> String? {
        if settings.toggleKeyCode == keyCode && settings.toggleModifierFlags == modifiers { return String(localized: "Toggle Key") }
        if settings.isTypoCorrectionEnabled && settings.typoKeyCode == keyCode && settings.typoModifierFlags == modifiers { return String(localized: "Typo Correction") }
        if settings.customShortcuts.contains(where: { $0.keyCode == keyCode && $0.modifierFlags == modifiers }) { return String(localized: "Custom Shortcut") }
        // 자기 자신을 제외한 다른 App Launch Shortcut과 중복되는지 체크
        if settings.appLaunchShortcuts.contains(where: { $0.id != self.shortcut.id && $0.keyCode == keyCode && $0.modifierFlags == modifiers }) { return String(localized: "App Launch Shortcut") }
        
        return nil
    }
}

// MARK: - 기타 컴포넌트들
struct SettingToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(title).font(.body)
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 7)
    }
}

struct SettingButtonRow: View {
    let title: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        HStack {
            Text(title).font(.body)
            Spacer()
            Button(buttonTitle) {
                action()
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 6)
    }
}
