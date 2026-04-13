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

// 🌟 사이드바 메뉴 탭에 앱 실행 단축키(appLaunch) 추가
enum SettingsTab: Hashable {
    case general
    case customShortcuts
    case appSpecific
    case appLaunch // NEW
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
                    // 🌟 수정됨: Launchpad 모양의 공식 앱 런처 아이콘 적용
                    Label(String(localized: "App Launch Shortcuts"), systemImage: "square.grid.2x2")
                        .tag(SettingsTab.appLaunch)
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
                case .general: GeneralSettingsView()
                case .customShortcuts: CustomShortcutsSettingsView()
                case .appSpecific: AppSpecificSettingsView()
                case .appLaunch: AppLaunchSettingsView() // NEW
                case .about: AboutSettingsView()
                case nil: Text(String(localized: "Select a menu item.")).foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .onAppear { accManager.checkPermission() }
    }
}

// MARK: - 1. General Settings View
struct GeneralSettingsView: View {
    @StateObject private var settings = SettingsManager.shared
    @StateObject private var updateManager = UpdateManager.shared
    @State private var isAutoLaunchEnabled: Bool = SMAppService.mainApp.status == .enabled
    @State private var showBackupSuccess = false
    @State private var showRestoreSuccess = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                Text(String(localized: "General")).font(.title2.bold())
                
                // --- 1. Startup & Updates Box ---
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Startup & Updates")).font(.headline)
                    VStack(spacing: 0) {
                        HStack {
                            Text(String(localized: "Launch at login"))
                            Spacer()
                            Toggle("", isOn: $isAutoLaunchEnabled).toggleStyle(.switch).labelsHidden().controlSize(.small)
                                .onChange(of: isAutoLaunchEnabled) { newValue in
                                    let service = SMAppService.mainApp
                                    do { if newValue { try service.register() } else { try service.unregister() } } catch { print("Launch error: \(error)") }
                                }
                        }.padding(.horizontal, 15).padding(.vertical, 6)
                        
                        Divider().padding(.horizontal, 15)
                        
                        HStack {
                            Text(String(localized: "Automatically check for updates"))
                            Spacer()
                            Toggle("", isOn: $updateManager.isAutoUpdateEnabled).toggleStyle(.switch).labelsHidden().controlSize(.small)
                        }.padding(.horizontal, 15).padding(.vertical, 6)
                        
                        Divider().padding(.horizontal, 15)
                        
                        HStack {
                            Text(String(localized: "Show visual feedback (HUD)"))
                            Spacer()
                            Toggle("", isOn: $settings.showVisualFeedback).toggleStyle(.switch).labelsHidden().controlSize(.small)
                        }.padding(.horizontal, 15).padding(.vertical, 6)
                    }
                    .background(Color(NSColor.textBackgroundColor)).cornerRadius(8).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                }
                
                // --- 2. Backup & Restore Box ---
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Backup & Restore")).font(.headline)
                    VStack(spacing: 0) {
                        HStack {
                            Text(String(localized: "Export Settings"))
                            Spacer()
                            Button(String(localized: "Export...")) { exportSettings() }
                                .padding(.trailing, -2) // 🌟 버튼의 투명 마진 상쇄 (우측으로 살짝 당김)
                        }.padding(.horizontal, 15).padding(.vertical, 6)
                        
                        Divider().padding(.horizontal, 15)
                        
                        HStack {
                            Text(String(localized: "Import Settings"))
                            Spacer()
                            Button(String(localized: "Import...")) { importSettings() }
                                .padding(.trailing, -2) // 🌟 버튼의 투명 마진 상쇄
                        }.padding(.horizontal, 15).padding(.vertical, 6)
                    }
                    .background(Color(NSColor.textBackgroundColor)).cornerRadius(8).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                }
                
                // --- 3. Default Shortcuts Box ---
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Default Shortcuts")).font(.headline)
                    VStack(spacing: 0) {
                        LanguageRow(title: "⌃ Control + Space", isActive: $settings.isCtrlActive, selection: $settings.ctrlLang)
                        Divider().padding(.horizontal, 15)
                        LanguageRow(title: "⌘ Command + Space", isActive: $settings.isCmdActive, selection: $settings.cmdLang)
                        Divider().padding(.horizontal, 15)
                        LanguageRow(title: "⌥ Option + Space", isActive: $settings.isOptActive, selection: $settings.optLang)
                    }
                    .background(Color(NSColor.textBackgroundColor)).cornerRadius(8).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                }
            }
            .padding(.horizontal, 25)
            .padding(.vertical, 15)
            .alert(String(localized: "Backup Successful"), isPresented: $showBackupSuccess) { Button("OK", role: .cancel) { } }
            .alert(String(localized: "Restore Successful"), isPresented: $showRestoreSuccess) { Button("OK", role: .cancel) { } }
        }
    }
    
    // 내보내기
    private func exportSettings() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmm"
        let dateString = formatter.string(from: Date())
        panel.nameFieldStringValue = "LangSwitcher_Backup_\(dateString).json"
        panel.prompt = String(localized: "Export")
        
        if panel.runModal() == .OK, let url = panel.url {
            do { try settings.exportBackup(to: url); showBackupSuccess = true } catch { print("Export failed: \(error)") }
        }
    }
    
    // 불러오기
    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.prompt = String(localized: "Import")
        
        if panel.runModal() == .OK, let url = panel.url {
            do { try settings.importBackup(from: url); showRestoreSuccess = true } catch { print("Import failed: \(error)") }
        }
    }
}

// MARK: - 2. Custom Shortcuts View (유지)
struct CustomShortcutsSettingsView: View {
    @StateObject private var settings = SettingsManager.shared
    var hasIncompleteShortcut: Bool { settings.customShortcuts.contains { $0.displayString.isEmpty || $0.targetLanguage.isEmpty } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(String(localized: "Custom Shortcuts")).font(.title2.bold())
                Spacer()
                Button(action: {
                    if !hasIncompleteShortcut { settings.customShortcuts.append(CustomShortcut(keyCode: 0, modifierFlags: 0, displayString: "", targetLanguage: "")) }
                }) {
                    Image(systemName: "plus.circle.fill").foregroundColor(hasIncompleteShortcut ? .secondary.opacity(0.5) : .blue)
                    Text(String(localized: "Add")).foregroundColor(hasIncompleteShortcut ? .secondary.opacity(0.5) : .primary)
                }.buttonStyle(.plain).disabled(hasIncompleteShortcut)
            }.padding(.horizontal, 30).padding(.top, 30).padding(.bottom, 15)
            
            ScrollView {
                VStack(spacing: 10) {
                    if settings.customShortcuts.isEmpty { Text(String(localized: "No custom shortcuts added.")).font(.subheadline).foregroundColor(.secondary).padding(.vertical, 20) }
                    ForEach($settings.customShortcuts) { $shortcut in
                        CustomShortcutRow(shortcut: $shortcut) { settings.customShortcuts.removeAll { $0.id == shortcut.id } }
                    }
                }.padding(15).frame(maxWidth: .infinity, alignment: .top)
            }
            .background(Color(NSColor.textBackgroundColor)).cornerRadius(8).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
            .padding(.horizontal, 30).padding(.bottom, 30)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - 3. App-Specific View (유지)
struct AppSpecificSettingsView: View {
    @StateObject private var settings = SettingsManager.shared
    var hasIncompleteApp: Bool { settings.customApps.contains { $0.targetLanguage.isEmpty } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(String(localized: "App-Specific Keyboards")).font(.title2.bold())
                Spacer()
                Button(action: selectApp) {
                    Image(systemName: "plus.app.fill").foregroundColor(hasIncompleteApp ? .secondary.opacity(0.5) : .green)
                    Text(String(localized: "Add App")).foregroundColor(hasIncompleteApp ? .secondary.opacity(0.5) : .primary)
                }.buttonStyle(.plain).disabled(hasIncompleteApp)
            }.padding(.horizontal, 30).padding(.top, 30).padding(.bottom, 15)
            
            ScrollView {
                VStack(spacing: 10) {
                    if settings.customApps.isEmpty { Text(String(localized: "No apps configured.")).font(.subheadline).foregroundColor(.secondary).padding(.vertical, 20) }
                    ForEach($settings.customApps) { $app in
                        CustomAppRow(customApp: $app) { settings.customApps.removeAll { $0.id == app.id } }
                    }
                }.padding(15).frame(maxWidth: .infinity, alignment: .top)
            }
            .background(Color(NSColor.textBackgroundColor)).cornerRadius(8).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
            .padding(.horizontal, 30).padding(.bottom, 30)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    
    private func selectApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications"); panel.allowedContentTypes = [.application]; panel.allowsMultipleSelection = false; panel.canChooseDirectories = false; panel.canChooseFiles = true; panel.prompt = String(localized: "Select App")
        if panel.runModal() == .OK, let url = panel.url {
            guard let bundle = Bundle(url: url), let bundleId = bundle.bundleIdentifier else { return }
            let appName = url.deletingPathExtension().lastPathComponent
            if !settings.customApps.contains(where: { $0.bundleIdentifier == bundleId }) { settings.customApps.append(CustomApp(bundleIdentifier: bundleId, appName: appName, targetLanguage: "")) }
        }
    }
}

// MARK: - 🌟 4. App Launch Shortcuts View (새로운 탭 뷰)
struct AppLaunchSettingsView: View {
    @StateObject private var settings = SettingsManager.shared
    var hasIncompleteShortcut: Bool {
        settings.appLaunchShortcuts.contains { $0.displayString.isEmpty || $0.bundleIdentifier.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(String(localized: "App Launch Shortcuts")).font(.title2.bold())
                Spacer()
                Button(action: {
                    if !hasIncompleteShortcut {
                        settings.appLaunchShortcuts.append(AppLaunchShortcut(keyCode: 0, modifierFlags: 0, displayString: "", bundleIdentifier: "", appName: ""))
                    }
                }) {
                    Image(systemName: "plus.circle.fill").foregroundColor(hasIncompleteShortcut ? .secondary.opacity(0.5) : .purple)
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
                    if settings.appLaunchShortcuts.isEmpty {
                        Text(String(localized: "No app launch shortcuts added."))
                            .font(.subheadline).foregroundColor(.secondary).padding(.vertical, 20)
                    }
                    ForEach($settings.appLaunchShortcuts) { $shortcut in
                        AppLaunchShortcutRow(shortcut: $shortcut) {
                            settings.appLaunchShortcuts.removeAll { $0.id == shortcut.id }
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


// MARK: - 5. About & Support View
struct AboutSettingsView: View {
    @StateObject private var accManager = AccessibilityManager.shared
    @StateObject private var updateManager = UpdateManager.shared
    var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                Text(String(localized: "About & Support")).font(.title2.bold())
                VStack(alignment: .center, spacing: 10) {
                    if let appIcon = NSImage(named: NSImage.applicationIconName) {
                        Image(nsImage: appIcon).resizable().scaledToFit().frame(width: 80, height: 80).padding(.bottom, 10).shadow(color: Color.black.opacity(0.2), radius: 5, x: 0, y: 3)
                    } else {
                        Image(systemName: "keyboard.macwindow").font(.system(size: 50)).foregroundColor(.blue).padding(.bottom, 10)
                    }
                    Text("LangSwitcher").font(.title.bold())
                    
                    // 🌟 1. 백슬래시 오타 수정: \(appVersion) 으로 변경하여 정상적으로 버전을 불러옵니다.
                    Text("Version \(appVersion)").font(.subheadline).foregroundColor(.secondary)
                    
                    Button(action: { updateManager.checkForUpdates() }) {
                        if updateManager.isChecking { ProgressView().controlSize(.small).frame(width: 100) } else { Text(String(localized: "Check for Updates...")).frame(width: 130) }
                    }.padding(.top, 5)
                    .alert(Text(String(localized: "Update Available")), isPresented: $updateManager.showUpdateAlert) {
                        Button(String(localized: "Download"), role: .none) { if let url = updateManager.releaseURL { NSWorkspace.shared.open(url) } }
                        Button(String(localized: "Later"), role: .cancel) { }
                    } message: {
                        // 🌟 2. 다국어 오류 수정: Text 안에 변수를 바로 넣으면 Xcode가 자동으로 %@ 로 인식합니다.
                        Text("A new version (\(updateManager.latestVersion)) of LangSwitcher is available!")
                    }
                    .alert(Text(String(localized: "Up to Date")), isPresented: $updateManager.showUpToDateAlert) { Button("OK", role: .cancel) { } } message: { Text(String(localized: "You are running the latest version of LangSwitcher.")) }
                }.frame(maxWidth: .infinity).padding(.vertical, 20).background(Color.secondary.opacity(0.05)).cornerRadius(12)
                
                VStack(alignment: .leading, spacing: 15) {
                    Text(String(localized: "Permissions")).font(.headline)
                    HStack {
                        if accManager.isTrusted { Label(String(localized: "Accessibility Granted"), systemImage: "checkmark.shield.fill").foregroundColor(.green) } else { Label(String(localized: "Accessibility Required"), systemImage: "exclamationmark.triangle.fill").foregroundColor(.orange) }
                        Spacer()
                        Button(String(localized: "Open System Settings")) { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!) }
                    }.padding().background(Color.secondary.opacity(0.05)).cornerRadius(8)
                }
            }.padding(30)
        }
    }
}

// MARK: - Shared Row Components

// 🌟 앱 실행 단축키 전용 Row
struct AppLaunchShortcutRow: View {
    @Binding var shortcut: AppLaunchShortcut
    var onDelete: () -> Void
    @State private var isRecording = false
    @State private var showDuplicateWarning = false
    @State private var monitor: Any?
    
    private let QWERTYKeyMap: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U", 34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0", 27: "-", 24: "=", 33: "[", 30: "]", 42: "\\", 41: ";", 39: "'", 43: ",", 47: ".", 44: "/"
    ]
    private let SpecialKeyMap: [UInt16: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20", 53: "Esc", 48: "Tab", 36: "Return", 51: "Delete", 117: "Fwd Del", 115: "Home", 119: "End", 116: "PgUp", 121: "PgDn", 123: "←", 124: "→", 125: "↓", 126: "↑"
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
                    .background(showDuplicateWarning ? Color.red.opacity(0.15) : (isRecording ? Color.purple.opacity(0.2) : Color.secondary.opacity(0.1)))
                    .foregroundColor(showDuplicateWarning ? .red : .primary).cornerRadius(6)
            }.buttonStyle(.plain)
            
            Spacer()
            
            // 앱 선택 버튼 (선택 안됐을 때와 됐을 때 디자인 분기)
            Button(action: selectApp) {
                Text(shortcut.appName.isEmpty ? String(localized: "Select App") : shortcut.appName)
                    .frame(width: 140)
                    .lineLimit(1)
                    .padding(.vertical, 4)
                    .background(shortcut.appName.isEmpty ? Color.secondary.opacity(0.1) : Color.green.opacity(0.15))
                    .foregroundColor(shortcut.appName.isEmpty ? .secondary : .primary)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
            
            Button(role: .destructive, action: onDelete) { Image(systemName: "trash").foregroundColor(.red) }
            .buttonStyle(.plain).padding(.leading, 10)
        }.onDisappear { stopRecording() }
    }
    
    private func selectApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications"); panel.allowedContentTypes = [.application]; panel.allowsMultipleSelection = false; panel.canChooseDirectories = false; panel.canChooseFiles = true; panel.prompt = String(localized: "Select App")
        if panel.runModal() == .OK, let url = panel.url {
            guard let bundle = Bundle(url: url), let bundleId = bundle.bundleIdentifier else { return }
            shortcut.appName = url.deletingPathExtension().lastPathComponent
            shortcut.bundleIdentifier = bundleId
        }
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
                
                if keyCode == 49 { str += "Space" } else if let special = SpecialKeyMap[keyCode] { str += special } else if let mapped = QWERTYKeyMap[keyCode] { str += mapped } else if let chars = event.charactersIgnoringModifiers?.uppercased(), !chars.isEmpty { str += chars } else { str += "Key(\(keyCode))" }
                DispatchQueue.main.async { self.registerShortcut(keyCode: keyCode, modifiers: modsRaw, display: str) }
                return nil
            }
            return event
        }
    }
    
    private func registerShortcut(keyCode: UInt16, modifiers: UInt64, display: String) {
        let isDuplicateCustom = SettingsManager.shared.customShortcuts.contains { $0.keyCode == keyCode && $0.modifierFlags == modifiers && !$0.displayString.isEmpty }
        let isDuplicateApp = SettingsManager.shared.appLaunchShortcuts.contains { $0.id != shortcut.id && $0.keyCode == keyCode && $0.modifierFlags == modifiers && !$0.displayString.isEmpty }
        
        if isDuplicateCustom || isDuplicateApp {
            NSSound.beep(); showDuplicateWarning = true; isRecording = false; stopRecording()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { if showDuplicateWarning { showDuplicateWarning = false } }
        } else {
            shortcut.keyCode = keyCode; shortcut.modifierFlags = modifiers; shortcut.displayString = display; isRecording = false; stopRecording()
        }
    }
    private func stopRecording() { if let m = monitor { NSEvent.removeMonitor(m); monitor = nil } }
}

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


// 🌟 LanguageRow 프레임 내 우측 정렬 강제
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
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                } else {
                    Text(String(localized: "Disabled"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.trailing, 16) // 피커의 우측 꺾쇠(화살표) 공간만큼 패딩 보정
                }
            }
            .frame(width: 130, alignment: .trailing) // 🌟 핵심 1: 130px 상자 안에서 내용물을 '우측'으로 완전히 밉니다.
            .padding(.trailing, -3) // 🌟 핵심 2: 스위치(Toggle)와 완벽한 일직선을 만들기 위해 3px 우측으로 당깁니다.
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 6)
    }
}

struct CustomShortcutRow: View {
    @Binding var shortcut: CustomShortcut
    var onDelete: () -> Void
    @State private var isRecording = false
    @State private var showDuplicateWarning = false
    @State private var monitor: Any?
    @StateObject private var inputManager = InputSourceManager.shared
    
    private let QWERTYKeyMap: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U", 34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0", 27: "-", 24: "=", 33: "[", 30: "]", 42: "\\", 41: ";", 39: "'", 43: ",", 47: ".", 44: "/"
    ]
    private let SpecialKeyMap: [UInt16: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20", 53: "Esc", 48: "Tab", 36: "Return", 51: "Delete", 117: "Fwd Del", 115: "Home", 119: "End", 116: "PgUp", 121: "PgDn", 123: "←", 124: "→", 125: "↓", 126: "↑"
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
            Button(role: .destructive, action: onDelete) { Image(systemName: "trash").foregroundColor(.red) }.buttonStyle(.plain).padding(.leading, 10)
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
                
                if keyCode == 49 { str += "Space" } else if let special = SpecialKeyMap[keyCode] { str += special } else if let mapped = QWERTYKeyMap[keyCode] { str += mapped } else if let chars = event.charactersIgnoringModifiers?.uppercased(), !chars.isEmpty { str += chars } else { str += "Key(\(keyCode))" }
                DispatchQueue.main.async { self.registerShortcut(keyCode: keyCode, modifiers: modsRaw, display: str) }
                return nil
            }
            return event
        }
    }
    
    private func registerShortcut(keyCode: UInt16, modifiers: UInt64, display: String) {
        let isDuplicateCustom = SettingsManager.shared.customShortcuts.contains { $0.id != shortcut.id && $0.keyCode == keyCode && $0.modifierFlags == modifiers && !$0.displayString.isEmpty }
        let isDuplicateApp = SettingsManager.shared.appLaunchShortcuts.contains { $0.keyCode == keyCode && $0.modifierFlags == modifiers && !$0.displayString.isEmpty }
        
        if isDuplicateCustom || isDuplicateApp {
            NSSound.beep(); showDuplicateWarning = true; isRecording = false; stopRecording()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { if showDuplicateWarning { showDuplicateWarning = false } }
        } else {
            shortcut.keyCode = keyCode; shortcut.modifierFlags = modifiers; shortcut.displayString = display; isRecording = false; stopRecording()
        }
    }
    private func stopRecording() { if let m = monitor { NSEvent.removeMonitor(m); monitor = nil } }
}
