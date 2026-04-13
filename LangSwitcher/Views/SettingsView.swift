//
//  LangSwitcher
//  Copyright (C) 2026 peepboy
//

import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers

enum SettingsTab: Hashable {
    case general, customShortcuts, appSpecific, appLaunch, about
}

struct SettingsView: View {
    @StateObject private var accManager = AccessibilityManager.shared
    @State private var selectedTab: SettingsTab? = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                Section(header: Text(String(localized: "Settings"))) {
                    Label(String(localized: "General"), systemImage: "gearshape").tag(SettingsTab.general)
                    Label(String(localized: "Custom Shortcuts"), systemImage: "keyboard").tag(SettingsTab.customShortcuts)
                    Label(String(localized: "App-Specific Keyboards"), systemImage: "macwindow").tag(SettingsTab.appSpecific)
                    Label(String(localized: "App Launch Shortcuts"), systemImage: "square.grid.2x2").tag(SettingsTab.appLaunch)
                }
                Section(header: Text(String(localized: "System"))) {
                    Label(String(localized: "About & Support"), systemImage: "info.circle").tag(SettingsTab.about)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 250)
        } detail: {
            Group {
                switch selectedTab {
                case .general: GeneralSettingsView()
                case .customShortcuts: CustomShortcutsSettingsView()
                case .appSpecific: AppSpecificSettingsView()
                case .appLaunch: AppLaunchSettingsView()
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

// MARK: - 충돌 감지 헬퍼 함수
func getConflictMessage(keyCode: UInt16, modifiers: UInt64, currentID: UUID) -> String? {
    let settings = SettingsManager.shared
    if let conflict = settings.appLaunchShortcuts.first(where: { $0.id != currentID && $0.keyCode == keyCode && $0.modifierFlags == modifiers && !$0.displayString.isEmpty }) {
        return conflict.appName.isEmpty ? "App Launch" : conflict.appName
    }
    if let conflict = settings.customShortcuts.first(where: { $0.id != currentID && $0.keyCode == keyCode && $0.modifierFlags == modifiers && !$0.displayString.isEmpty }) {
        let langName = InputSourceManager.shared.availableKeyboards.first(where: { $0.id == conflict.targetLanguage })?.name ?? "Language"
        return langName
    }
    if keyCode == 49 {
        if modifiers == NSEvent.ModifierFlags.control.rawValue { return "Control+Space" }
        if modifiers == NSEvent.ModifierFlags.command.rawValue { return "Command+Space" }
        if modifiers == NSEvent.ModifierFlags.option.rawValue { return "Option+Space" }
    }
    return nil
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
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Startup & Updates")).font(.headline)
                    VStack(spacing: 0) {
                        HStack {
                            Text(String(localized: "Launch at login"))
                            Spacer()
                            Toggle("", isOn: $isAutoLaunchEnabled).toggleStyle(.switch).labelsHidden().controlSize(.small)
                                .onChange(of: isAutoLaunchEnabled) { newValue in
                                    do { if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch {}
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
                        Divider().padding(.horizontal, 15)
                        HStack {
                            Text(String(localized: "Rules Test Mode"))
                            Spacer()
                            Toggle("", isOn: $settings.isTestMode).toggleStyle(.switch).labelsHidden().controlSize(.small)
                        }.padding(.horizontal, 15).padding(.vertical, 6)
                    }
                    .background(Color(NSColor.textBackgroundColor)).cornerRadius(8).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Backup & Restore")).font(.headline)
                    VStack(spacing: 0) {
                        HStack {
                            Text(String(localized: "Export Settings"))
                            Spacer()
                            Button(String(localized: "Export...")) { exportSettings() }.padding(.trailing, -2)
                        }.padding(.horizontal, 15).padding(.vertical, 6)
                        Divider().padding(.horizontal, 15)
                        HStack {
                            Text(String(localized: "Import Settings"))
                            Spacer()
                            Button(String(localized: "Import...")) { importSettings() }.padding(.trailing, -2)
                        }.padding(.horizontal, 15).padding(.vertical, 6)
                    }
                    .background(Color(NSColor.textBackgroundColor)).cornerRadius(8).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                }
                
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
            }.padding(.horizontal, 25).padding(.vertical, 15)
            .alert(String(localized: "Backup Successful"), isPresented: $showBackupSuccess) { Button("OK", role: .cancel) { } }
            .alert(String(localized: "Restore Successful"), isPresented: $showRestoreSuccess) { Button("OK", role: .cancel) { } }
        }
    }
    
    private func exportSettings() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        let formatter = DateFormatter(); formatter.dateFormat = "yyyyMMdd_HHmm"
        panel.nameFieldStringValue = "LangSwitcher_Backup_\(formatter.string(from: Date())).json"
        panel.prompt = String(localized: "Export")
        if panel.runModal() == .OK, let url = panel.url { do { try settings.exportBackup(to: url); showBackupSuccess = true } catch {} }
    }
    
    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]; panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.prompt = String(localized: "Import")
        if panel.runModal() == .OK, let url = panel.url { do { try settings.importBackup(from: url); showRestoreSuccess = true } catch {} }
    }
}

// MARK: - 2. Custom Shortcuts View
struct CustomShortcutsSettingsView: View {
    @StateObject private var settings = SettingsManager.shared
    var hasIncomplete: Bool { settings.customShortcuts.contains { $0.displayString.isEmpty || $0.targetLanguage.isEmpty } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(String(localized: "Custom Shortcuts")).font(.title2.bold())
                Spacer()
                Button(action: { if !hasIncomplete { settings.customShortcuts.append(CustomShortcut(keyCode: 0, modifierFlags: 0, displayString: "", targetLanguage: "")) } }) {
                    Image(systemName: "plus.circle.fill").foregroundColor(hasIncomplete ? .secondary.opacity(0.5) : .blue)
                    Text(String(localized: "Add")).foregroundColor(hasIncomplete ? .secondary.opacity(0.5) : .primary)
                }.buttonStyle(.plain).disabled(hasIncomplete)
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

// MARK: - 3. App-Specific View
struct AppSpecificSettingsView: View {
    @StateObject private var settings = SettingsManager.shared
    var hasIncomplete: Bool { settings.customApps.contains { $0.targetLanguage.isEmpty } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(String(localized: "App-Specific Keyboards")).font(.title2.bold())
                Spacer()
                Button(action: selectApp) {
                    Image(systemName: "plus.app.fill").foregroundColor(hasIncomplete ? .secondary.opacity(0.5) : .green)
                    Text(String(localized: "Add App")).foregroundColor(hasIncomplete ? .secondary.opacity(0.5) : .primary)
                }.buttonStyle(.plain).disabled(hasIncomplete)
            }.padding(.horizontal, 30).padding(.top, 30).padding(.bottom, 15)
            
            ScrollView {
                VStack(spacing: 10) {
                    if settings.customApps.isEmpty { Text(String(localized: "No apps configured.")).font(.subheadline).foregroundColor(.secondary).padding(.vertical, 20) }
                    ForEach($settings.customApps) { $app in CustomAppRow(customApp: $app) { settings.customApps.removeAll { $0.id == app.id } } }
                }.padding(15).frame(maxWidth: .infinity, alignment: .top)
            }
            .background(Color(NSColor.textBackgroundColor)).cornerRadius(8).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
            .padding(.horizontal, 30).padding(.bottom, 30)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    private func selectApp() {
        let panel = NSOpenPanel(); panel.directoryURL = URL(fileURLWithPath: "/Applications"); panel.allowedContentTypes = [.application]; panel.canChooseFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            guard let bundle = Bundle(url: url), let bundleId = bundle.bundleIdentifier else { return }
            if !settings.customApps.contains(where: { $0.bundleIdentifier == bundleId }) { settings.customApps.append(CustomApp(bundleIdentifier: bundleId, appName: url.deletingPathExtension().lastPathComponent, targetLanguage: "")) }
        }
    }
}

// MARK: - 4. App Launch Shortcuts View
struct AppLaunchSettingsView: View {
    @StateObject private var settings = SettingsManager.shared
    var hasIncomplete: Bool { settings.appLaunchShortcuts.contains { $0.displayString.isEmpty || $0.bundleIdentifier.isEmpty } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(String(localized: "App Launch Shortcuts")).font(.title2.bold())
                Spacer()
                Button(action: { if !hasIncomplete { settings.appLaunchShortcuts.append(AppLaunchShortcut(keyCode: 0, modifierFlags: 0, displayString: "", bundleIdentifier: "", appName: "")) } }) {
                    Image(systemName: "plus.circle.fill").foregroundColor(hasIncomplete ? .secondary.opacity(0.5) : .purple)
                    Text(String(localized: "Add")).foregroundColor(hasIncomplete ? .secondary.opacity(0.5) : .primary)
                }.buttonStyle(.plain).disabled(hasIncomplete)
            }.padding(.horizontal, 30).padding(.top, 30).padding(.bottom, 15)
            
            ScrollView {
                VStack(spacing: 10) {
                    if settings.appLaunchShortcuts.isEmpty { Text(String(localized: "No app launch shortcuts added.")).font(.subheadline).foregroundColor(.secondary).padding(.vertical, 20) }
                    ForEach($settings.appLaunchShortcuts) { $shortcut in AppLaunchShortcutRow(shortcut: $shortcut) { settings.appLaunchShortcuts.removeAll { $0.id == shortcut.id } } }
                }.padding(15).frame(maxWidth: .infinity, alignment: .top)
            }
            .background(Color(NSColor.textBackgroundColor)).cornerRadius(8).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
            .padding(.horizontal, 30).padding(.bottom, 30)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
                    if let appIcon = NSImage(named: NSImage.applicationIconName) { Image(nsImage: appIcon).resizable().scaledToFit().frame(width: 80, height: 80).padding(.bottom, 10).shadow(color: Color.black.opacity(0.2), radius: 5, x: 0, y: 3)
                    } else { Image(systemName: "keyboard.macwindow").font(.system(size: 50)).foregroundColor(.blue).padding(.bottom, 10) }
                    Text("LangSwitcher").font(.title.bold())
                    Text("Version \(appVersion)").font(.subheadline).foregroundColor(.secondary)
                    
                    Button(action: { updateManager.checkForUpdates() }) { if updateManager.isChecking { ProgressView().controlSize(.small).frame(width: 100) } else { Text(String(localized: "Check for Updates...")).frame(width: 130) } }.padding(.top, 5)
                    .alert(Text(String(localized: "Update Available")), isPresented: $updateManager.showUpdateAlert) {
                        Button(String(localized: "Download"), role: .none) { if let url = updateManager.releaseURL { NSWorkspace.shared.open(url) } }
                        Button(String(localized: "Later"), role: .cancel) { }
                    } message: { Text("A new version (\(updateManager.latestVersion)) of LangSwitcher is available!") }
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

// MARK: - UI Components

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

struct CustomShortcutRow: View {
    @Binding var shortcut: CustomShortcut
    var onDelete: () -> Void
    @State private var isRecording = false
    @State private var showDuplicateWarning = false
    @State private var conflictMessage = ""
    @State private var monitor: Any?
    @StateObject private var inputManager = InputSourceManager.shared
    private let keyMap = makeKeyMap()

    var body: some View {
        HStack {
            Button(action: { shortcut.displayString = ""; shortcut.keyCode = 0; shortcut.modifierFlags = 0; showDuplicateWarning = false; isRecording = true; startRecording() }) {
                Text(showDuplicateWarning ? conflictMessage : (isRecording ? String(localized: "Press any keys...") : (shortcut.displayString.isEmpty ? String(localized: "Click to Record") : shortcut.displayString)))
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
        class RState { var m = Set<UInt16>(); var f: NSEvent.ModifierFlags = []; var r = false }
        let state = RState()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { e in
            let code = e.keyCode; let flags = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if e.type == .flagsChanged {
                if code == 57 { DispatchQueue.main.async { self.registerShortcut(keyCode: 57, modifiers: 0, display: "⇪ Caps Lock") }; return nil }
                if !flags.isEmpty { state.m.insert(code); state.f.formUnion(flags); return nil }
                else if !state.r && !state.m.isEmpty {
                    if state.m.count == 1 {
                        let c = state.m.first!; let str = [54:"Right ⌘", 55:"Left ⌘", 56:"Left ⇧", 60:"Right ⇧", 58:"Left ⌥", 61:"Right ⌥", 59:"Left ⌃", 62:"Right ⌃", 63:"fn"][c] ?? "Mod(\(c))"
                        DispatchQueue.main.async { self.registerShortcut(keyCode: c, modifiers: 0, display: str) }
                    } else {
                        var str = ""; if state.f.contains(.control){str+="⌃ "}; if state.f.contains(.option){str+="⌥ "}; if state.f.contains(.shift){str+="⇧ "}; if state.f.contains(.command){str+="⌘ "}
                        DispatchQueue.main.async { self.registerShortcut(keyCode: 0, modifiers: UInt64(state.f.rawValue), display: str.trimmingCharacters(in: .whitespaces)) }
                    }
                    return nil
                }
                state.m.removeAll(); state.f = []; state.r = false; return nil
            } else if e.type == .keyDown {
                state.r = true; var str = ""
                if flags.contains(.control){str+="⌃ "}; if flags.contains(.option){str+="⌥ "}; if flags.contains(.shift){str+="⇧ "}; if flags.contains(.command){str+="⌘ "}
                if code == 49 { str += "Space" } else if let mapped = keyMap[code] { str += mapped } else if let chars = e.charactersIgnoringModifiers?.uppercased(), !chars.isEmpty { str += chars } else { str += "Key(\(code))" }
                DispatchQueue.main.async { self.registerShortcut(keyCode: code, modifiers: UInt64(flags.rawValue), display: str) }
                return nil
            }
            return e
        }
    }
    
    private func registerShortcut(keyCode: UInt16, modifiers: UInt64, display: String) {
        if let conflictName = getConflictMessage(keyCode: keyCode, modifiers: modifiers, currentID: shortcut.id) {
            NSSound.beep(); conflictMessage = String(format: String(localized: "In use: %@"), conflictName); showDuplicateWarning = true; isRecording = false; stopRecording()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { showDuplicateWarning = false }
        } else { shortcut.keyCode = keyCode; shortcut.modifierFlags = modifiers; shortcut.displayString = display; isRecording = false; stopRecording() }
    }
    private func stopRecording() { if let m = monitor { NSEvent.removeMonitor(m); monitor = nil } }
}

struct AppLaunchShortcutRow: View {
    @Binding var shortcut: AppLaunchShortcut
    var onDelete: () -> Void
    @State private var isRecording = false
    @State private var showDuplicateWarning = false
    @State private var conflictMessage = ""
    @State private var monitor: Any?
    private let keyMap = makeKeyMap()

    var body: some View {
        HStack {
            Button(action: { shortcut.displayString = ""; shortcut.keyCode = 0; shortcut.modifierFlags = 0; showDuplicateWarning = false; isRecording = true; startRecording() }) {
                Text(showDuplicateWarning ? conflictMessage : (isRecording ? String(localized: "Press any keys...") : (shortcut.displayString.isEmpty ? String(localized: "Click to Record") : shortcut.displayString)))
                    .frame(width: 140).padding(.vertical, 4)
                    .background(showDuplicateWarning ? Color.red.opacity(0.15) : (isRecording ? Color.purple.opacity(0.2) : Color.secondary.opacity(0.1)))
                    .foregroundColor(showDuplicateWarning ? .red : .primary).cornerRadius(6)
            }.buttonStyle(.plain)
            Spacer()
            Button(action: selectApp) {
                Text(shortcut.appName.isEmpty ? String(localized: "Select App") : shortcut.appName).frame(width: 140).lineLimit(1).padding(.vertical, 4)
                    .background(shortcut.appName.isEmpty ? Color.secondary.opacity(0.1) : Color.green.opacity(0.15)).foregroundColor(shortcut.appName.isEmpty ? .secondary : .primary).cornerRadius(6)
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
        class RState { var m = Set<UInt16>(); var f: NSEvent.ModifierFlags = []; var r = false }
        let state = RState()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { e in
            let code = e.keyCode; let flags = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if e.type == .flagsChanged {
                if code == 57 { DispatchQueue.main.async { self.registerShortcut(keyCode: 57, modifiers: 0, display: "⇪ Caps Lock") }; return nil }
                if !flags.isEmpty { state.m.insert(code); state.f.formUnion(flags); return nil }
                else if !state.r && !state.m.isEmpty {
                    if state.m.count == 1 {
                        let c = state.m.first!; let str = [54:"Right ⌘", 55:"Left ⌘", 56:"Left ⇧", 60:"Right ⇧", 58:"Left ⌥", 61:"Right ⌥", 59:"Left ⌃", 62:"Right ⌃", 63:"fn"][c] ?? "Mod(\(c))"
                        DispatchQueue.main.async { self.registerShortcut(keyCode: c, modifiers: 0, display: str) }
                    } else {
                        var str = ""; if state.f.contains(.control){str+="⌃ "}; if state.f.contains(.option){str+="⌥ "}; if state.f.contains(.shift){str+="⇧ "}; if state.f.contains(.command){str+="⌘ "}
                        DispatchQueue.main.async { self.registerShortcut(keyCode: 0, modifiers: UInt64(state.f.rawValue), display: str.trimmingCharacters(in: .whitespaces)) }
                    }
                    return nil
                }
                state.m.removeAll(); state.f = []; state.r = false; return nil
            } else if e.type == .keyDown {
                state.r = true; var str = ""
                if flags.contains(.control){str+="⌃ "}; if flags.contains(.option){str+="⌥ "}; if flags.contains(.shift){str+="⇧ "}; if flags.contains(.command){str+="⌘ "}
                if code == 49 { str += "Space" } else if let mapped = keyMap[code] { str += mapped } else if let chars = e.charactersIgnoringModifiers?.uppercased(), !chars.isEmpty { str += chars } else { str += "Key(\(code))" }
                DispatchQueue.main.async { self.registerShortcut(keyCode: code, modifiers: UInt64(flags.rawValue), display: str) }
                return nil
            }
            return e
        }
    }
    
    private func registerShortcut(keyCode: UInt16, modifiers: UInt64, display: String) {
        if let conflictName = getConflictMessage(keyCode: keyCode, modifiers: modifiers, currentID: shortcut.id) {
            NSSound.beep(); conflictMessage = String(format: String(localized: "In use: %@"), conflictName); showDuplicateWarning = true; isRecording = false; stopRecording()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { showDuplicateWarning = false }
        } else { shortcut.keyCode = keyCode; shortcut.modifierFlags = modifiers; shortcut.displayString = display; isRecording = false; stopRecording() }
    }
    private func stopRecording() { if let m = monitor { NSEvent.removeMonitor(m); monitor = nil } }
}

// QWERTY 및 특수키 매핑 통합 헬퍼
func makeKeyMap() -> [UInt16: String] {
    return [
        0:"A", 1:"S", 2:"D", 3:"F", 4:"H", 5:"G", 6:"Z", 7:"X", 8:"C", 9:"V", 11:"B", 12:"Q", 13:"W", 14:"E", 15:"R", 16:"Y", 17:"T", 31:"O", 32:"U", 34:"I", 35:"P", 37:"L", 38:"J", 40:"K", 45:"N", 46:"M", 18:"1", 19:"2", 20:"3", 21:"4", 23:"5", 22:"6", 26:"7", 28:"8", 25:"9", 29:"0", 27:"-", 24:"=", 33:"[", 30:"]", 42:"\\", 41:";", 39:"'", 43:",", 47:".", 44:"/",
        122:"F1", 120:"F2", 99:"F3", 118:"F4", 96:"F5", 97:"F6", 98:"F7", 100:"F8", 101:"F9", 109:"F10", 103:"F11", 111:"F12", 105:"F13", 107:"F14", 113:"F15", 106:"F16", 64:"F17", 79:"F18", 80:"F19", 90:"F20", 53:"Esc", 48:"Tab", 36:"Return", 51:"Delete", 117:"Fwd Del", 115:"Home", 119:"End", 116:"PgUp", 121:"PgDn", 123:"←", 124:"→", 125:"↓", 126:"↑"
    ]
}
