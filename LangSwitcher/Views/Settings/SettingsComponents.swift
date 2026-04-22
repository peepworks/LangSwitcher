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

// 키보드 입력을 문자열로 예쁘게 포맷팅 해주는 공통 헬퍼 함수
func formatKeyEquivalent(modifierFlags: UInt, keyCode: UInt16) -> String {
    var parts: [String] = []
    let flags = NSEvent.ModifierFlags(rawValue: modifierFlags)

    if flags.contains(.control) { parts.append("⌃") }
    if flags.contains(.option)  { parts.append("⌥") }
    if flags.contains(.shift)   { parts.append("⇧") }
    if flags.contains(.command) { parts.append("⌘") }
    
    let modifierKeyCodes: Set<UInt16> = [54,55,56,60,58,61,59,62,57,63]
    if modifierKeyCodes.contains(keyCode) && modifierFlags == 0 {
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
    @State private var timeoutTask: DispatchWorkItem?

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
        // 🌟 이미 완벽한 순서 (차단 -> 타이머 -> 콜백)
        EventMonitor.shared.isPaused = true
        class RState { var m = Set<UInt16>(); var f: NSEvent.ModifierFlags = []; var r = false }
        let state = RState()

        timeoutTask?.cancel()
        let task = DispatchWorkItem {
            if self.isRecording { self.stopRecording() }
        }
        self.timeoutTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: task)

        EventMonitor.shared.shortcutRecordingCallback = { e in
            let code = e.keyCode
            let flags = e.modifierFlags.intersection(.deviceIndependentFlagsMask)

            if e.type == .flagsChanged {
                if code == 57 { DispatchQueue.main.async { self.registerShortcut(keyCode: 57, modifiers: 0, display: "⇪ Caps Lock") }; return }
                if !flags.isEmpty { state.m.insert(code); state.f.formUnion(flags); return }
                else if !state.r && !state.m.isEmpty {
                    if state.m.count == 1 {
                        let c = state.m.first!
                        let str = [54:"Right ⌘", 55:"Left ⌘", 56:"Left ⇧", 60:"Right ⇧", 58:"Left ⌥", 61:"Right ⌥", 59:"Left ⌃", 62:"Right ⌃", 63:"fn"][c] ?? "Mod(\(c))"
                        DispatchQueue.main.async { self.registerShortcut(keyCode: c, modifiers: 0, display: str) }
                    } else {
                        var str = ""
                        if state.f.contains(.control) { str += "⌃ " }
                        if state.f.contains(.option) { str += "⌥ " }
                        if state.f.contains(.shift) { str += "⇧ " }
                        if state.f.contains(.command) { str += "⌘ " }
                        DispatchQueue.main.async { self.registerShortcut(keyCode: 0, modifiers: UInt64(state.f.rawValue), display: str.trimmingCharacters(in: .whitespaces)) }
                    }
                    return
                }
                state.m.removeAll(); state.f = []; state.r = false; return
            } else if e.type == .keyDown {
                state.r = true
                var str = ""
                if flags.contains(.control) { str += "⌃ " }
                if flags.contains(.option) { str += "⌥ " }
                if flags.contains(.shift) { str += "⇧ " }
                if flags.contains(.command) { str += "⌘ " }

                if code == 49 { str += "Space" }
                else if let mapped = globalKeyMap[code] { str += mapped }
                else if let chars = e.charactersIgnoringModifiers?.uppercased(), !chars.isEmpty { str += chars }
                else { str += "Key(\(code))" }

                DispatchQueue.main.async { self.registerShortcut(keyCode: code, modifiers: UInt64(flags.rawValue), display: str) }
                return
            }
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
        timeoutTask?.cancel()
        EventMonitor.shared.shortcutRecordingCallback = nil
        EventMonitor.shared.isPaused = false
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
    @State private var timeoutTask: DispatchWorkItem?

    var body: some View {
        HStack(spacing: 8) {
            Button(action: {
                if isRecording { stopRecording() } else { startRecording() }
            }) {
                Text(isRecording ? String(localized: "Recording...") : (shortcut.displayString.isEmpty ? String(localized: "Record") : shortcut.displayString))
                    .frame(width: 90)
                    .foregroundColor(isRecording ? .red : .primary)
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
        // 🌟 [수정됨] 1. 가장 먼저 시스템 이벤트 개입 차단 (기존 누락됨)
        EventMonitor.shared.isPaused = true
        isRecording = true
        
        // 🌟 2. 타이머 설정
        timeoutTask?.cancel()
        let task = DispatchWorkItem { if self.isRecording { self.stopRecording() } }
        self.timeoutTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: task)

        // 🌟 3. 마지막으로 콜백 등록
        EventMonitor.shared.shortcutRecordingCallback = { event in
            let keyCode = event.keyCode
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let displayString = formatKeyEquivalent(modifierFlags: flags.rawValue, keyCode: keyCode)
            
            if !displayString.isEmpty {
                DispatchQueue.main.async {
                    if let index = settings.customShortcuts.firstIndex(where: { $0.id == self.shortcut.id }) {
                        settings.customShortcuts[index].keyCode = keyCode
                        settings.customShortcuts[index].modifierFlags = UInt64(flags.rawValue)
                        settings.customShortcuts[index].displayString = displayString
                    }
                }
            }
            self.stopRecording()
        }
    }

    private func stopRecording() {
        timeoutTask?.cancel() // 타이머 해제
        EventMonitor.shared.shortcutRecordingCallback = nil // 콜백 해제
        EventMonitor.shared.isPaused = false // 🌟 [수정됨] 이벤트 개입 차단 해제 (기존 누락됨)
        isRecording = false
    }
}

// MARK: - 3. AppLaunchShortcutRow (앱 실행 단축키 UI)
struct AppLaunchShortcutRow: View {
    @ObservedObject private var settings = SettingsManager.shared
    @Binding var shortcut: AppLaunchShortcut
    
    @State private var isRecording = false
    @State private var timeoutTask: DispatchWorkItem?
    
    @State private var appIcon: NSImage? = nil

    var body: some View {
        HStack(spacing: 8) {
            
            // 1. 앱 선택 및 아이콘 표시
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

            // 2. 단축키 기록 버튼
            Button(action: {
                if isRecording { stopRecording() } else { startRecording() }
            }) {
                Text(isRecording ? String(localized: "Recording...") : (shortcut.displayString.isEmpty ? String(localized: "Record") : shortcut.displayString))
                    .frame(width: 90)
                    .foregroundColor(isRecording ? .red : .primary)
            }
            .padding(.trailing, 5)

            // 3. 삭제 버튼
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
        .onAppear {
            loadIcon()
        }
        .onChange(of: shortcut.bundleIdentifier) { _ in
            loadIcon()
        }
    }

    private func loadIcon() {
        let bundleID = shortcut.bundleIdentifier
        guard !bundleID.isEmpty else { return }
        
        DispatchQueue.global(qos: .userInitiated).async {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            
            DispatchQueue.main.async {
                self.appIcon = icon
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
        // 🌟 [수정됨] 1. 가장 먼저 시스템 이벤트 개입 차단 (기존 누락됨)
        EventMonitor.shared.isPaused = true
        isRecording = true
        
        // 🌟 2. 타이머 설정
        timeoutTask?.cancel()
        let task = DispatchWorkItem { if self.isRecording { self.stopRecording() } }
        self.timeoutTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: task)

        // 🌟 3. 마지막으로 콜백 등록
        EventMonitor.shared.shortcutRecordingCallback = { event in
            let keyCode = event.keyCode
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let displayString = formatKeyEquivalent(modifierFlags: flags.rawValue, keyCode: keyCode)
            
            if !displayString.isEmpty {
                DispatchQueue.main.async {
                    if let index = settings.appLaunchShortcuts.firstIndex(where: { $0.id == self.shortcut.id }) {
                        settings.appLaunchShortcuts[index].keyCode = keyCode
                        settings.appLaunchShortcuts[index].modifierFlags = UInt64(flags.rawValue)
                        settings.appLaunchShortcuts[index].displayString = displayString
                    }
                }
            }
            self.stopRecording()
        }
    }

    private func stopRecording() {
        timeoutTask?.cancel() // 타이머 해제
        EventMonitor.shared.shortcutRecordingCallback = nil // 콜백 해제
        EventMonitor.shared.isPaused = false // 🌟 [수정됨] 이벤트 개입 차단 해제 (기존 누락됨)
        isRecording = false
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
