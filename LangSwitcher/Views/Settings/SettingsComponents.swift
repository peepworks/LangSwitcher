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

// MARK: - Helper Functions

func getConflictMessage(keyCode: UInt16, modifiers: UInt64, ignoreID: UUID? = nil) -> String? {
    let settings = SettingsManager.shared
    
    if let conflict = settings.appLaunchShortcuts.first(where: {
        $0.id != ignoreID && $0.keyCode == keyCode && $0.modifierFlags == modifiers && !$0.displayString.isEmpty
    }) {
        return conflict.appName.isEmpty ? "App Launch" : conflict.appName
    }
    
    if let conflict = settings.customShortcuts.first(where: {
        $0.id != ignoreID && $0.keyCode == keyCode && $0.modifierFlags == modifiers && !$0.displayString.isEmpty
    }) {
        let langName = InputSourceManager.shared.availableKeyboards.first(where: { $0.id == conflict.targetLanguage })?.name ?? "Language"
        return langName
    }
    
    if ignoreID != nil {
        if settings.toggleKeyCode == keyCode && settings.toggleModifierFlags == modifiers && !settings.toggleDisplayString.isEmpty {
            return String(localized: "Toggle Key")
        }
    }
    
    if keyCode == 49 {
        if modifiers == NSEvent.ModifierFlags.control.rawValue { return "Control+Space" }
        if modifiers == NSEvent.ModifierFlags.command.rawValue { return "Command+Space" }
        if modifiers == NSEvent.ModifierFlags.option.rawValue { return "Option+Space" }
    }
    
    return nil
}

func makeKeyMap() -> [UInt16: String] {
    return [
        0:"A", 1:"S", 2:"D", 3:"F", 4:"H", 5:"G", 6:"Z", 7:"X", 8:"C", 9:"V",
        11:"B", 12:"Q", 13:"W", 14:"E", 15:"R", 16:"Y", 17:"T", 31:"O", 32:"U", 34:"I",
        35:"P", 37:"L", 38:"J", 40:"K", 45:"N", 46:"M",
        18:"1", 19:"2", 20:"3", 21:"4", 23:"5", 22:"6", 26:"7", 28:"8", 25:"9", 29:"0",
        27:"-", 24:"=", 33:"[", 30:"]", 42:"\\", 41:";", 39:"'", 43:",", 47:".", 44:"/",
        122:"F1", 120:"F2", 99:"F3", 118:"F4", 96:"F5", 97:"F6", 98:"F7", 100:"F8",
        101:"F9", 109:"F10", 103:"F11", 111:"F12", 105:"F13", 107:"F14", 113:"F15", 106:"F16",
        64:"F17", 79:"F18", 80:"F19", 90:"F20",
        53:"Esc", 48:"Tab", 36:"Return", 51:"Delete", 117:"Fwd Del", 115:"Home", 119:"End",
        116:"PgUp", 121:"PgDn", 123:"←", 124:"→", 125:"↓", 126:"↑"
    ]
}


// MARK: - Row Components

// 🌟 1. 전역 토글 키 (한/영 전환) 설정 행
struct ToggleShortcutRow: View {
    @StateObject private var settings = SettingsManager.shared
    @State private var isRecording = false
    @State private var showDuplicateWarning = false
    @State private var conflictMessage = ""
    
    private let keyMap = makeKeyMap()

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
            }) { Image(systemName: "trash").foregroundColor(.red) }.buttonStyle(.plain).padding(.leading, 10).help(String(localized: "Reset toggle key"))
        }.padding(.horizontal, 15).padding(.vertical, 10)
        .onDisappear { stopRecording() }
    }
    
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
                else if let mapped = keyMap[code] { str += mapped }
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
        EventMonitor.shared.shortcutRecordingCallback = nil
        EventMonitor.shared.isPaused = false
    }
}

// 🌟 2. 기본 시스템 언어 설정 행 (General 탭)
struct LanguageRow: View {
    let title: String
    @Binding var isActive: Bool
    @Binding var selection: String
    @StateObject private var inputManager = InputSourceManager.shared

    var body: some View {
        HStack {
            Toggle("", isOn: $isActive).toggleStyle(.checkbox).labelsHidden()
            Text(title).font(.body).padding(.leading, 5)
            Spacer(minLength: 20)
            
            ZStack(alignment: .trailing) {
                if isActive {
                    Picker("", selection: $selection) {
                        if selection.isEmpty { Text(String(localized: "Select Keyboard")).tag("") }
                        ForEach(inputManager.availableKeyboards) { kb in Text(kb.name).tag(kb.id) }
                    }.pickerStyle(.menu).labelsHidden()
                } else {
                    Text(String(localized: "Disabled")).font(.subheadline).foregroundColor(.secondary).padding(.trailing, 16)
                }
            }.frame(width: 130, alignment: .trailing).padding(.trailing, -3)
        }.padding(.horizontal, 15).padding(.vertical, 6)
    }
}

// 🌟 3. 특정 앱 실행 시 언어 자동 변경 행 (App-Specific 탭)
struct CustomAppRow: View {
    @Binding var customApp: CustomApp
    var onDelete: () -> Void
    @StateObject private var inputManager = InputSourceManager.shared

    var body: some View {
        HStack {
            Text(customApp.appName).frame(width: 140, alignment: .leading).lineLimit(1).padding(.vertical, 6).padding(.horizontal, 8).background(Color.green.opacity(0.15)).cornerRadius(6)
            Spacer()
            Picker("", selection: $customApp.targetLanguage) {
                if customApp.targetLanguage.isEmpty { Text(String(localized: "Select Keyboard")).tag("") }
                ForEach(inputManager.availableKeyboards) { kb in Text(kb.name).tag(kb.id) }
            }.pickerStyle(.menu).frame(width: 140)
            Button(role: .destructive, action: onDelete) { Image(systemName: "trash").foregroundColor(.red) }.buttonStyle(.plain).padding(.leading, 10)
        }
    }
}

// 🌟 4. 사용자 지정 단축키 설정 행 (Custom Shortcuts 탭) - 수정 완료!
struct CustomShortcutRow: View {
    @Binding var shortcut: CustomShortcut
    var onDelete: () -> Void
    
    @State private var isRecording = false
    @State private var showDuplicateWarning = false
    @State private var conflictMessage = ""
    @StateObject private var inputManager = InputSourceManager.shared
    private let keyMap = makeKeyMap()

    var body: some View {
        HStack {
            Button(action: {
                shortcut.displayString = ""; shortcut.keyCode = 0; shortcut.modifierFlags = 0
                showDuplicateWarning = false; isRecording = true
                startRecording()
            }) {
                Text(showDuplicateWarning ? conflictMessage : (isRecording ? String(localized: "Press any keys...") : (shortcut.displayString.isEmpty ? String(localized: "Click to Record") : shortcut.displayString)))
                    .frame(width: 140).padding(.vertical, 4).background(showDuplicateWarning ? Color.red.opacity(0.15) : (isRecording ? Color.blue.opacity(0.2) : Color.secondary.opacity(0.1))).foregroundColor(showDuplicateWarning ? .red : .primary).cornerRadius(6)
            }.buttonStyle(.plain)
            
            Spacer()
            Picker("", selection: $shortcut.targetLanguage) {
                if shortcut.targetLanguage.isEmpty { Text(String(localized: "Select Keyboard")).tag("") }
                ForEach(inputManager.availableKeyboards) { kb in Text(kb.name).tag(kb.id) }
            }.pickerStyle(.menu).frame(width: 140)
            
            Button(role: .destructive, action: onDelete) { Image(systemName: "trash").foregroundColor(.red) }.buttonStyle(.plain).padding(.leading, 10)
        }.onDisappear { stopRecording() }
    }
    
    private func startRecording() {
        EventMonitor.shared.isPaused = true
        class RState { var m = Set<UInt16>(); var f: NSEvent.ModifierFlags = []; var r = false }
        let state = RState()
        
        // 🌟 수정됨: EventMonitor.shared.shortcutRecordingCallback 사용
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
                else if let mapped = keyMap[code] { str += mapped }
                else if let chars = e.charactersIgnoringModifiers?.uppercased(), !chars.isEmpty { str += chars }
                else { str += "Key(\(code))" }
                
                DispatchQueue.main.async { self.registerShortcut(keyCode: code, modifiers: UInt64(flags.rawValue), display: str) }
                return
            }
        }
    }
    
    private func registerShortcut(keyCode: UInt16, modifiers: UInt64, display: String) {
        if let conflictName = getConflictMessage(keyCode: keyCode, modifiers: modifiers, ignoreID: shortcut.id) {
            NSSound.beep()
            conflictMessage = String(format: String(localized: "In use: %@"), conflictName)
            showDuplicateWarning = true; isRecording = false; stopRecording()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { showDuplicateWarning = false }
        } else {
            shortcut.keyCode = keyCode; shortcut.modifierFlags = modifiers; shortcut.displayString = display
            isRecording = false; stopRecording()
        }
    }
    
    private func stopRecording() {
        EventMonitor.shared.shortcutRecordingCallback = nil
        EventMonitor.shared.isPaused = false
    }
}

// 🌟 5. 앱 실행 단축키 설정 행 (App Launch 탭) - 수정 완료!
struct AppLaunchShortcutRow: View {
    @Binding var shortcut: AppLaunchShortcut
    var onDelete: () -> Void
    
    @State private var isRecording = false
    @State private var showDuplicateWarning = false
    @State private var conflictMessage = ""
    private let keyMap = makeKeyMap()

    var body: some View {
        HStack {
            Button(action: {
                shortcut.displayString = ""; shortcut.keyCode = 0; shortcut.modifierFlags = 0
                showDuplicateWarning = false; isRecording = true
                startRecording()
            }) {
                Text(showDuplicateWarning ? conflictMessage : (isRecording ? String(localized: "Press any keys...") : (shortcut.displayString.isEmpty ? String(localized: "Click to Record") : shortcut.displayString)))
                    .frame(width: 140).padding(.vertical, 4).background(showDuplicateWarning ? Color.red.opacity(0.15) : (isRecording ? Color.purple.opacity(0.2) : Color.secondary.opacity(0.1))).foregroundColor(showDuplicateWarning ? .red : .primary).cornerRadius(6)
            }.buttonStyle(.plain)
            
            Spacer()
            Button(action: selectApp) {
                Text(shortcut.appName.isEmpty ? String(localized: "Select App") : shortcut.appName)
                    .frame(width: 140).lineLimit(1).padding(.vertical, 4).background(shortcut.appName.isEmpty ? Color.secondary.opacity(0.1) : Color.green.opacity(0.15)).foregroundColor(shortcut.appName.isEmpty ? .secondary : .primary).cornerRadius(6)
            }.buttonStyle(.plain)
            
            Button(role: .destructive, action: onDelete) { Image(systemName: "trash").foregroundColor(.red) }.buttonStyle(.plain).padding(.leading, 10)
        }.onDisappear { stopRecording() }
    }
    
    private func selectApp() {
        let panel = NSOpenPanel(); panel.directoryURL = URL(fileURLWithPath: "/Applications"); panel.allowedContentTypes = [.application]; panel.canChooseFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            guard let bundle = Bundle(url: url), let bundleId = bundle.bundleIdentifier else { return }
            shortcut.appName = url.deletingPathExtension().lastPathComponent; shortcut.bundleIdentifier = bundleId
        }
    }
    
    private func startRecording() {
        EventMonitor.shared.isPaused = true
        class RState { var m = Set<UInt16>(); var f: NSEvent.ModifierFlags = []; var r = false }
        let state = RState()
        
        // 🌟 수정됨: EventMonitor.shared.shortcutRecordingCallback 사용
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
                else if let mapped = keyMap[code] { str += mapped }
                else if let chars = e.charactersIgnoringModifiers?.uppercased(), !chars.isEmpty { str += chars }
                else { str += "Key(\(code))" }
                
                DispatchQueue.main.async { self.registerShortcut(keyCode: code, modifiers: UInt64(flags.rawValue), display: str) }
                return
            }
        }
    }
    
    private func registerShortcut(keyCode: UInt16, modifiers: UInt64, display: String) {
        if let conflictName = getConflictMessage(keyCode: keyCode, modifiers: modifiers, ignoreID: shortcut.id) {
            NSSound.beep()
            conflictMessage = String(format: String(localized: "In use: %@"), conflictName)
            showDuplicateWarning = true; isRecording = false; stopRecording()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { showDuplicateWarning = false }
        } else {
            shortcut.keyCode = keyCode; shortcut.modifierFlags = modifiers; shortcut.displayString = display
            isRecording = false; stopRecording()
        }
    }
    
    private func stopRecording() {
        EventMonitor.shared.shortcutRecordingCallback = nil
        EventMonitor.shared.isPaused = false
    }
}
