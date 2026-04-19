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

struct TypoCorrectionSettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared
    @State private var isRecording = false
    @State private var conflictMessage = ""
    @State private var showDuplicateWarning = false
    
    // 🌟 [수정 1] 문제가 되었던 private let keyMap = ... 부분은 완전히 삭제했습니다.

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(String(localized: "Auto-Typo Correction")).font(.title2.bold())
                    Text(String(localized: "Automatically fixes English/Korean typing errors (e.g., dkssud → 안녕) using a global shortcut."))
                        .font(.subheadline).foregroundColor(.secondary)
                }
                
                VStack(spacing: 0) {
                    ToggleRow(
                        title: String(localized: "Enable Typo Correction"),
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
            .padding(.horizontal, 25).padding(.vertical, 15)
            .onDisappear { stopRecording() }
        }
    }
    
    // MARK: - Shortcut Recording Logic
    
    private func startRecording() {
        EventMonitor.shared.isPaused = true
        class RState { var m = Set<UInt16>(); var f: NSEvent.ModifierFlags = []; var r = false }
        let state = RState()

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
                // 🌟 [수정 2] keyMap 대신 globalKeyMap을 직접 참조하도록 변경했습니다.
                else if let mapped = globalKeyMap[code] { str += mapped }
                else if let chars = e.charactersIgnoringModifiers?.uppercased(), !chars.isEmpty { str += chars }
                else { str += "Key(\(code))" }
                
                DispatchQueue.main.async { self.registerShortcut(keyCode: code, modifiers: UInt64(flags.rawValue), display: str) }
                return
            }
        }
    }
    
    private func registerShortcut(keyCode: UInt16, modifiers: UInt64, display: String) {
        // 🌟 [수정 3] 함수 호출 이름(매개변수 라벨)을 일치시키고 없는 ignoreID는 제거했습니다.
        if let conflictName = getConflictMessage(keyCode: keyCode, modifierFlags: modifiers) {
            NSSound.beep()
            conflictMessage = String(format: String(localized: "In use: %@"), conflictName)
            showDuplicateWarning = true; isRecording = false; stopRecording()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { showDuplicateWarning = false }
        } else {
            settings.typoKeyCode = keyCode
            settings.typoModifierFlags = modifiers
            settings.typoDisplayString = display
            isRecording = false
            stopRecording()
        }
    }
    
    private func stopRecording() {
        EventMonitor.shared.shortcutRecordingCallback = nil
        EventMonitor.shared.isPaused = false
    }
    
    // 🌟 단축키 중복을 검사하는 함수
    private func getConflictMessage(keyCode: UInt16, modifierFlags: UInt64) -> String? {
        let settings = SettingsManager.shared
            
        // 1. 한/영 전환 단축키와 겹치는지 확인
        if settings.toggleKeyCode == keyCode && settings.toggleModifierFlags == modifierFlags {
            return String(localized: "This shortcut is already used for Toggle Shortcut.")
        }

        // 2. 다른 사용자 지정 단축키와 겹치는지 확인
        if settings.customShortcuts.contains(where: { $0.keyCode == keyCode && $0.modifierFlags == modifierFlags }) {
            return String(localized: "This shortcut is already used for a Custom Shortcut.")
        }
            
        // 3. 앱 실행 단축키와 겹치는지 확인
        if settings.appLaunchShortcuts.contains(where: { $0.keyCode == keyCode && $0.modifierFlags == modifierFlags }) {
            return String(localized: "This shortcut is already used for an App Launch Shortcut.")
        }

        // 겹치지 않으면 nil 반환 (에러 없음)
        return nil
    }
}

// MARK: - Reusable UI Component
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
            Spacer()
            Toggle("", isOn: $isOn).toggleStyle(.switch).labelsHidden()
        }.padding(15)
    }
}
