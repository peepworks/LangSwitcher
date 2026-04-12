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
import UniformTypeIdentifiers

// 사이드바 메뉴 탭 정의
enum SettingsTab: Hashable {
    case general
    case customShortcuts
    case appSpecific
    case about
}

struct SettingsView: View {
    @StateObject private var accManager = AccessibilityManager.shared
    @State private var selectedTab: SettingsTab? = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                Section(header: Text(String(localized: "Settings"))) {
                    Label(String(localized: "General"), systemImage: "gearshape")
                        .tag(SettingsTab.general)
                    Label(String(localized: "Custom Shortcuts"), systemImage: "keyboard")
                        .tag(SettingsTab.customShortcuts)
                    Label(String(localized: "App-Specific Keyboards"), systemImage: "macwindow")
                        .tag(SettingsTab.appSpecific)
                }
                
                Section(header: Text(String(localized: "System"))) {
                    Label(String(localized: "About & Support"), systemImage: "info.circle")
                        .tag(SettingsTab.about)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 250)
        } detail: {
            Group {
                switch selectedTab {
                case .general:
                    GeneralSettingsView()
                case .customShortcuts:
                    CustomShortcutsSettingsView()
                case .appSpecific:
                    AppSpecificSettingsView()
                case .about:
                    AboutSettingsView()
                case nil:
                    Text(String(localized: "Select a menu item."))
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .onAppear {
            accManager.checkPermission()
        }
    }
}

// MARK: - 1. General Settings View
struct GeneralSettingsView: View {
    @StateObject private var settings = SettingsManager.shared
    @StateObject private var updateManager = UpdateManager.shared // 🌟 업데이트 매니저 연결
    @State private var isAutoLaunchEnabled: Bool = SMAppService.mainApp.status == .enabled

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                Text(String(localized: "General")).font(.title2.bold())
                
                VStack(alignment: .leading, spacing: 10) {
                    Text(String(localized: "Startup")).font(.headline)
                    
                    Toggle(String(localized: "Launch at login"), isOn: $isAutoLaunchEnabled)
                        .toggleStyle(.checkbox)
                        .onChange(of: isAutoLaunchEnabled) { newValue in
                            let service = SMAppService.mainApp
                            do {
                                if newValue { try service.register() } else { try service.unregister() }
                            } catch { print("Launch setting error: \(error)") }
                        }
                    
                    // 🌟 자동 업데이트 토글 추가
                    Toggle(String(localized: "Automatically check for updates"), isOn: $updateManager.isAutoUpdateEnabled)
                        .toggleStyle(.checkbox)
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 15) {
                    Text(String(localized: "Default Shortcuts")).font(.headline)
                    VStack(spacing: 12) {
                        LanguageRow(title: "⌃ Control + Space", isActive: $settings.isCtrlActive, selection: $settings.ctrlLang)
                        LanguageRow(title: "⌘ Command + Space", isActive: $settings.isCmdActive, selection: $settings.cmdLang)
                        LanguageRow(title: "⌥ Option + Space", isActive: $settings.isOptActive, selection: $settings.optLang)
                    }
                    .padding(.leading, 5)
                }
            }
            .padding(30)
        }
    }
}

// MARK: - 2. Custom Shortcuts View
struct CustomShortcutsSettingsView: View {
    @StateObject private var settings = SettingsManager.shared
    var hasIncompleteShortcut: Bool {
        settings.customShortcuts.contains { $0.displayString.isEmpty || $0.targetLanguage.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(String(localized: "Custom Shortcuts")).font(.title2.bold())
                Spacer()
                Button(action: {
                    if !hasIncompleteShortcut {
                        settings.customShortcuts.append(CustomShortcut(keyCode: 0, modifierFlags: 0, displayString: "", targetLanguage: ""))
                    }
                }) {
                    Image(systemName: "plus.circle.fill").foregroundColor(hasIncompleteShortcut ? .secondary.opacity(0.5) : .blue)
                    Text(String(localized: "Add")).foregroundColor(hasIncompleteShortcut ? .secondary.opacity(0.5) : .primary)
                }
                .buttonStyle(.plain)
                .disabled(hasIncompleteShortcut)
            }
            .padding(.horizontal, 30)
            .padding(.top, 30)
            .padding(.bottom, 15)
            
            ScrollView {
                VStack(spacing: 10) {
                    if settings.customShortcuts.isEmpty {
                        Text(String(localized: "No custom shortcuts added."))
                            .font(.subheadline).foregroundColor(.secondary).padding(.vertical, 20)
                    }
                    ForEach($settings.customShortcuts) { $shortcut in
                        CustomShortcutRow(shortcut: $shortcut) {
                            settings.customShortcuts.removeAll { $0.id == shortcut.id }
                        }
                    }
                }
                .padding(15)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
            .padding(.horizontal, 30)
            .padding(.bottom, 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - 3. App-Specific View
struct AppSpecificSettingsView: View {
    @StateObject private var settings = SettingsManager.shared
    var hasIncompleteApp: Bool {
        settings.customApps.contains { $0.targetLanguage.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(String(localized: "App-Specific Keyboards")).font(.title2.bold())
                Spacer()
                Button(action: selectApp) {
                    Image(systemName: "plus.app.fill").foregroundColor(hasIncompleteApp ? .secondary.opacity(0.5) : .green)
                    Text(String(localized: "Add App")).foregroundColor(hasIncompleteApp ? .secondary.opacity(0.5) : .primary)
                }
                .buttonStyle(.plain)
                .disabled(hasIncompleteApp)
            }
            .padding(.horizontal, 30)
            .padding(.top, 30)
            .padding(.bottom, 15)
            
            ScrollView {
                VStack(spacing: 10) {
                    if settings.customApps.isEmpty {
                        Text(String(localized: "No apps configured."))
                            .font(.subheadline).foregroundColor(.secondary).padding(.vertical, 20)
                    }
                    ForEach($settings.customApps) { $app in
                        CustomAppRow(customApp: $app) {
                            settings.customApps.removeAll { $0.id == app.id }
                        }
                    }
                }
                .padding(15)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
            .padding(.horizontal, 30)
            .padding(.bottom, 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    
    private func selectApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = String(localized: "Select App")
        
        if panel.runModal() == .OK, let url = panel.url {
            guard let bundle = Bundle(url: url), let bundleId = bundle.bundleIdentifier else { return }
            let appName = url.deletingPathExtension().lastPathComponent
            
            if !settings.customApps.contains(where: { $0.bundleIdentifier == bundleId }) {
                settings.customApps.append(CustomApp(bundleIdentifier: bundleId, appName: appName, targetLanguage: ""))
            }
        }
    }
}

// MARK: - 4. About & Support View
struct AboutSettingsView: View {
    @StateObject private var accManager = AccessibilityManager.shared
    @StateObject private var updateManager = UpdateManager.shared // 🌟 업데이트 매니저 연결
    
    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                Text(String(localized: "About & Support")).font(.title2.bold())
                
                VStack(alignment: .center, spacing: 10) {
                    if let appIcon = NSImage(named: NSImage.applicationIconName) {
                        Image(nsImage: appIcon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 80, height: 80)
                            .padding(.bottom, 10)
                            .shadow(color: Color.black.opacity(0.2), radius: 5, x: 0, y: 3)
                    } else {
                        Image(systemName: "keyboard.macwindow")
                            .font(.system(size: 50))
                            .foregroundColor(.blue)
                            .padding(.bottom, 10)
                    }
                    
                    Text("LangSwitcher").font(.title.bold())
                    Text("Version \(appVersion)").font(.subheadline).foregroundColor(.secondary)
                    
                    // 🌟 업데이트 확인 버튼
                    Button(action: {
                        updateManager.checkForUpdates()
                    }) {
                        if updateManager.isChecking {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 100)
                        } else {
                            Text(String(localized: "Check for Updates..."))
                                .frame(width: 130)
                        }
                    }
                    .padding(.top, 5)
                    // 🌟 업데이트가 있을 때 표시되는 알림창
                    .alert(Text(String(localized: "Update Available")), isPresented: $updateManager.showUpdateAlert) {
                        Button(String(localized: "Download"), role: .none) {
                            if let url = updateManager.releaseURL {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        Button(String(localized: "Later"), role: .cancel) { }
                    } message: {
                        Text(String(localized: "A new version (\(updateManager.latestVersion)) of LangSwitcher is available!"))
                    }
                    // 🌟 최신 버전일 때 표시되는 알림창
                    .alert(Text(String(localized: "Up to Date")), isPresented: $updateManager.showUpToDateAlert) {
                        Button("OK", role: .cancel) { }
                    } message: {
                        Text(String(localized: "You are running the latest version of LangSwitcher."))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(12)
                
                VStack(alignment: .leading, spacing: 15) {
                    Text(String(localized: "Permissions")).font(.headline)
                    HStack {
                        if accManager.isTrusted {
                            Label(String(localized: "Accessibility Granted"), systemImage: "checkmark.shield.fill")
                                .foregroundColor(.green)
                        } else {
                            Label(String(localized: "Accessibility Required"), systemImage: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                        }
                        Spacer()
                        Button(String(localized: "Open System Settings")) {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)
                }
            }
            .padding(30)
        }
    }
}

// MARK: - Shared Row Components

struct CustomAppRow: View {
    @Binding var customApp: CustomApp
    var onDelete: () -> Void
    @StateObject private var inputManager = InputSourceManager.shared

    var body: some View {
        HStack {
            Text(customApp.appName)
                .frame(width: 140, alignment: .leading)
                .lineLimit(1)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(Color.green.opacity(0.15))
                .cornerRadius(6)
            Spacer()
            Picker("", selection: $customApp.targetLanguage) {
                if customApp.targetLanguage.isEmpty { Text(String(localized: "Select Keyboard")).tag("") }
                ForEach(inputManager.availableKeyboards) { kb in Text(kb.name).tag(kb.id) }
            }.pickerStyle(.menu).frame(width: 140)
            Button(role: .destructive, action: onDelete) { Image(systemName: "trash").foregroundColor(.red) }
            .buttonStyle(.plain).padding(.leading, 10)
        }
    }
}

struct LanguageRow: View {
    let title: String
    @Binding var isActive: Bool
    @Binding var selection: String
    @StateObject private var inputManager = InputSourceManager.shared

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
                    if selection.isEmpty { Text(String(localized: "Select Keyboard")).tag("") }
                    ForEach(inputManager.availableKeyboards) { kb in Text(kb.name).tag(kb.id) }
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

struct CustomShortcutRow: View {
    @Binding var shortcut: CustomShortcut
    var onDelete: () -> Void
    @State private var isRecording = false
    @State private var showDuplicateWarning = false
    @State private var monitor: Any?
    @StateObject private var inputManager = InputSourceManager.shared
    
    // 일반 문자 매핑
    private let QWERTYKeyMap: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U",
        34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
        27: "-", 24: "=", 33: "[", 30: "]", 42: "\\", 41: ";", 39: "'", 43: ",", 47: ".", 44: "/"
    ]
    
    // 🌟 펑션키 및 특수키 매핑 추가 (F1~F20, 화살표, ESC, Return, Tab, Delete 등)
    private let SpecialKeyMap: [UInt16: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5",
        97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
        103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
        106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
        53: "Esc", 48: "Tab", 36: "Return", 51: "Delete", 117: "Fwd Del",
        115: "Home", 119: "End", 116: "PgUp", 121: "PgDn",
        123: "←", 124: "→", 125: "↓", 126: "↑"
    ]

    var body: some View {
        HStack {
            Button(action: {
                shortcut.displayString = ""; shortcut.keyCode = 0; shortcut.modifierFlags = 0
                showDuplicateWarning = false; isRecording = true; startRecording()
            }) {
                let displayText = showDuplicateWarning ? String(localized: "Already in use!") :
                                  isRecording ? String(localized: "Press any keys...") :
                                  (shortcut.displayString.isEmpty ? String(localized: "Click to Record") : shortcut.displayString)
                Text(displayText)
                    .frame(width: 140).padding(.vertical, 4)
                    .background(showDuplicateWarning ? Color.red.opacity(0.15) : (isRecording ? Color.blue.opacity(0.2) : Color.secondary.opacity(0.1)))
                    .foregroundColor(showDuplicateWarning ? .red : .primary).cornerRadius(6)
            }.buttonStyle(.plain)
            Spacer()
            Picker("", selection: $shortcut.targetLanguage) {
                if shortcut.targetLanguage.isEmpty { Text(String(localized: "Select Keyboard")).tag("") }
                ForEach(inputManager.availableKeyboards) { kb in Text(kb.name).tag(kb.id) }
            }.pickerStyle(.menu).frame(width: 140)
            Button(role: .destructive, action: onDelete) { Image(systemName: "trash").foregroundColor(.red) }
            .buttonStyle(.plain).padding(.leading, 10)
        }.onDisappear { stopRecording() }
    }
    
    private func startRecording() {
        class RecordingState { var pressedModifiers = Set<UInt16>(); var maxFlags: NSEvent.ModifierFlags = []; var didPressRegularKey = false }
        let state = RecordingState()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            let keyCode = event.keyCode
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if event.type == .flagsChanged {
                if keyCode == 57 { DispatchQueue.main.async { self.registerShortcut(keyCode: 57, modifiers: 0, display: "⇪ Caps Lock") }; return nil }
                if !flags.isEmpty { state.pressedModifiers.insert(keyCode); state.maxFlags.formUnion(flags); return nil }
                else {
                    if !state.didPressRegularKey && !state.pressedModifiers.isEmpty {
                        if state.pressedModifiers.count == 1 {
                            let modCode = state.pressedModifiers.first!
                            var str = ""
                            switch modCode {
                            case 54: str = "Right ⌘"; case 55: str = "Left ⌘"; case 56: str = "Left ⇧"; case 60: str = "Right ⇧"
                            case 58: str = "Left ⌥"; case 61: str = "Right ⌥"; case 59: str = "Left ⌃"; case 62: str = "Right ⌃"
                            case 63: str = "fn"; default: str = "Mod(\(modCode))"
                            }
                            DispatchQueue.main.async { self.registerShortcut(keyCode: modCode, modifiers: 0, display: str) }
                        } else {
                            let modsRaw = UInt64(state.maxFlags.rawValue)
                            var str = ""
                            if state.maxFlags.contains(.control) { str += "⌃ " }
                            if state.maxFlags.contains(.option) { str += "⌥ " }
                            if state.maxFlags.contains(.shift) { str += "⇧ " }
                            if state.maxFlags.contains(.command) { str += "⌘ " }
                            DispatchQueue.main.async { self.registerShortcut(keyCode: 0, modifiers: modsRaw, display: str.trimmingCharacters(in: .whitespaces)) }
                        }
                        return nil
                    }
                    state.pressedModifiers.removeAll(); state.maxFlags = []; state.didPressRegularKey = false; return nil
                }
            } else if event.type == .keyDown {
                state.didPressRegularKey = true
                let modsRaw = UInt64(flags.rawValue)
                var str = ""
                if flags.contains(.control) { str += "⌃ " }
                if flags.contains(.option) { str += "⌥ " }
                if flags.contains(.shift) { str += "⇧ " }
                if flags.contains(.command) { str += "⌘ " }
                
                // 🌟 특수키 및 펑션키 체크 로직 추가
                if keyCode == 49 {
                    str += "Space"
                } else if let special = SpecialKeyMap[keyCode] {
                    str += special
                } else if let mapped = QWERTYKeyMap[keyCode] {
                    str += mapped
                } else if let chars = event.charactersIgnoringModifiers?.uppercased(), !chars.isEmpty {
                    str += chars
                } else {
                    str += "Key(\(keyCode))"
                }
                
                DispatchQueue.main.async { self.registerShortcut(keyCode: keyCode, modifiers: modsRaw, display: str) }
                return nil
            }
            return event
        }
    }
    
    private func registerShortcut(keyCode: UInt16, modifiers: UInt64, display: String) {
        if SettingsManager.shared.customShortcuts.contains(where: { $0.id != shortcut.id && $0.keyCode == keyCode && $0.modifierFlags == modifiers && !$0.displayString.isEmpty }) {
            NSSound.beep(); showDuplicateWarning = true; isRecording = false; stopRecording()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { if showDuplicateWarning { showDuplicateWarning = false } }
        } else {
            shortcut.keyCode = keyCode; shortcut.modifierFlags = modifiers; shortcut.displayString = display; isRecording = false; stopRecording()
        }
    }
    private func stopRecording() { if let m = monitor { NSEvent.removeMonitor(m); monitor = nil } }
}
