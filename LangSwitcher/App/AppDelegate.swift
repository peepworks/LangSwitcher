//
//  AppDelegate.swift
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

import Cocoa
import SwiftUI
import Carbon
import AppIntents

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupMenu()

        if AccessibilityManager.shared.isTrusted {
            EventMonitor.shared.start()
        } else {
            AccessibilityManager.shared.checkPermission(prompt: true)
        }
        
        Task {
            LangSwitcherShortcuts.updateAppShortcutParameters()
            dprint("단축어(App Intents) 강제 업데이트 완료!")
        }

        AppMonitor.shared.start()
        UpdateManager.shared.setupAutoUpdateCheck()
        HyperKeyManager.shared.updateState(isEnabled: UserDefaults.standard.bool(forKey: "isHyperKeyEnabled"))
    }

    func applicationWillTerminate(_ notification: Notification) {
        EventMonitor.shared.stop()
        AppMonitor.shared.stop()
        HyperKeyManager.shared.updateState(isEnabled: false)
        UpdateManager.shared.stopAutoUpdateCheck()
    }

    func setupMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            if let customImage = NSImage(named: "StatusIcon") {
                customImage.isTemplate = true
                button.image = customImage
            } else {
                button.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "LangSwitcher")
            }
        }

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        let snapshot = SettingsManager.shared.snapshot
        
        // 🌟 [수복 포인트] 무격리 글로벌 트래커에서 안전하게 활성 앱 ID를 인출합니다.
        let activeAppID = globalActiveAppTracker.get()
        let activeAppName = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == activeAppID })?.localizedName ?? "App"

        var currentLang = "Unknown"
        if let currentSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
           let ptr = TISGetInputSourceProperty(currentSource, kTISPropertyLocalizedName) {
            currentLang = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
        }

        // 0. 프로필 빠른 전환 메뉴
        let activeProfileName = SettingsManager.shared.activeProfile.name
        let profileMenuItem = NSMenuItem(title: String(localized: "Profile: \(activeProfileName)"), action: nil, keyEquivalent: "")
        profileMenuItem.image = NSImage(systemSymbolName: "person.crop.circle", accessibilityDescription: nil)
        
        let profileSubmenu = NSMenu()
        for profile in SettingsManager.shared.profiles {
            let item = NSMenuItem(title: profile.name, action: #selector(switchProfile(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = profile.id.uuidString
            item.state = (SettingsManager.shared.activeProfileID == profile.id) ? .on : .off
            profileSubmenu.addItem(item)
        }
        
        profileSubmenu.addItem(NSMenuItem.separator())
        let manageItem = NSMenuItem(title: String(localized: "Manage Profiles..."), action: #selector(openProfileSettings), keyEquivalent: "")
        manageItem.target = self
        profileSubmenu.addItem(manageItem)
        
        profileMenuItem.submenu = profileSubmenu
        menu.addItem(profileMenuItem)
        menu.addItem(NSMenuItem.separator())

        // 1. 현재 입력 소스
        let langItem = NSMenuItem(title: "\(String(localized: "Language")): \(currentLang)", action: #selector(toggleLanguage), keyEquivalent: "")
        langItem.image = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
        menu.addItem(langItem)
        
        menu.addItem(NSMenuItem.separator())

        // 2. 앱 일시 정지
        let isPaused = EventMonitor.shared.isPaused
        let pauseItem = NSMenuItem(title: String(localized: "Pause LangSwitcher"), action: #selector(togglePause), keyEquivalent: "s")
        pauseItem.keyEquivalentModifierMask = [.control, .option, .command]
        pauseItem.state = isPaused ? .on : .off
        menu.addItem(pauseItem)

        menu.addItem(NSMenuItem.separator())

        // 3. 핵심 기능 빠른 토글
        let autoTypoItem = NSMenuItem(title: String(localized: "Smart Auto Typo Correction"), action: #selector(toggleAutoTypo), keyEquivalent: "")
        autoTypoItem.state = snapshot.isAutoTypoCorrectionEnabled ? .on : .off
        menu.addItem(autoTypoItem)
        
        let manualTypoItem = NSMenuItem(title: String(localized: "Manual Typo Correction"), action: #selector(toggleManualTypo), keyEquivalent: "")
        manualTypoItem.state = snapshot.isTypoCorrectionEnabled ? .on : .off
        menu.addItem(manualTypoItem)
        
        let textExpansionItem = NSMenuItem(title: String(localized: "Text Expansion"), action: #selector(toggleTextExpansion), keyEquivalent: "")
        textExpansionItem.state = snapshot.isTextExpansionEnabled ? .on : .off
        menu.addItem(textExpansionItem)

        let hyperItem = NSMenuItem(title: String(localized: "Hyper Key (Caps Lock)"), action: #selector(toggleHyper), keyEquivalent: "")
        hyperItem.state = snapshot.isHyperKeyEnabled ? .on : .off
        menu.addItem(hyperItem)

        let windowItem = NSMenuItem(title: String(localized: "Window Memory"), action: #selector(toggleWindowMemory), keyEquivalent: "")
        windowItem.state = snapshot.isWindowMemoryEnabled ? .on : .off
        menu.addItem(windowItem)
        
        let browserTabMenuItem = NSMenuItem(title: String(localized: "Browser Tab Memory"), action: #selector(toggleBrowserTabMemory(_:)), keyEquivalent: "")
        browserTabMenuItem.state = snapshot.isBrowserTabMemoryEnabled ? .on : .off
        browserTabMenuItem.target = self
        menu.addItem(browserTabMenuItem)

        menu.addItem(NSMenuItem.separator())

        // 4. 동적 예외 앱 관리
        if !activeAppID.isEmpty && activeAppID != Bundle.main.bundleIdentifier {
            let isExcluded = snapshot.excludedApps.contains { $0.bundleIdentifier == activeAppID }
            let title = isExcluded
                ? String(localized: "Remove \(activeAppName) from Excluded Apps")
                : String(localized: "Add \(activeAppName) to Excluded Apps")
            
            let excludeItem = NSMenuItem(title: title, action: #selector(toggleExcludeCurrentApp), keyEquivalent: "")
            excludeItem.image = NSImage(systemSymbolName: isExcluded ? "minus.circle" : "plus.circle", accessibilityDescription: nil)
            excludeItem.representedObject = ["id": activeAppID, "name": activeAppName]
            menu.addItem(excludeItem)
            
            menu.addItem(NSMenuItem.separator())
        }

        // 5. 시스템 메뉴
        let clearCacheItem = NSMenuItem(title: String(localized: "Clear App Memory"), action: #selector(clearAppMemory), keyEquivalent: "c")
        clearCacheItem.keyEquivalentModifierMask = [.control, .option, .command]
        clearCacheItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        menu.addItem(clearCacheItem)
        
        let settingsItem = NSMenuItem(title: String(localized: "Settings..."), action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: String(localized: "Quit"), action: #selector(quitApp), keyEquivalent: "q")
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(quitItem)
    }

    // MARK: - Actions
    
    @objc func switchProfile(_ sender: NSMenuItem) {
        guard let idString = sender.representedObject as? String,
              let profileID = UUID(uuidString: idString) else { return }
        
        SettingsManager.shared.activeProfileID = profileID
        HUDManager.shared.showHUD(languageName: "Profile: \(SettingsManager.shared.activeProfile.name)")
    }
    
    @objc func openProfileSettings() {
        SettingsManager.shared.selectedTab = .profiles
        openSettings()
    }

    @objc func toggleLanguage() { InputSourceManager.shared.switchToNextInputSource() }
    
    @objc func togglePause() {
        DispatchQueue.main.async {
            let currentState = EventMonitor.shared.isPaused
            let newState = !currentState
            EventMonitor.shared.isPaused = newState
            let statusMessage = newState ? String(localized: "LangSwitcher Paused") : String(localized: "LangSwitcher Resumed")
            HUDManager.shared.showHUD(languageName: statusMessage)
        }
    }
    
    @objc func clearAppMemory() { SettingsManager.shared.clearAllAppCaches() }
    
    @objc func toggleAutoTypo() {
        var profile = SettingsManager.shared.activeProfile
        profile.payload.isAutoTypoCorrectionEnabled.toggle()
        SettingsManager.shared.activeProfile = profile
    }
    @objc func toggleManualTypo() {
        var profile = SettingsManager.shared.activeProfile
        profile.payload.isTypoCorrectionEnabled.toggle()
        SettingsManager.shared.activeProfile = profile
    }
    @objc func toggleTextExpansion() {
        var profile = SettingsManager.shared.activeProfile
        profile.payload.isTextExpansionEnabled.toggle()
        SettingsManager.shared.activeProfile = profile
    }
    
    @objc func toggleHyper() { SettingsManager.shared.isHyperKeyEnabled.toggle() }
    @objc func toggleWindowMemory() { SettingsManager.shared.isWindowMemoryEnabled.toggle() }

    @objc func toggleExcludeCurrentApp(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String: String],
              let id = info["id"], let name = info["name"] else { return }
        
        var profile = SettingsManager.shared.activeProfile
        if let index = profile.payload.excludedApps.firstIndex(where: { $0.bundleIdentifier == id }) {
            profile.payload.excludedApps.remove(at: index)
        } else {
            profile.payload.excludedApps.append(ExcludedApp(bundleIdentifier: id, appName: name))
        }
        SettingsManager.shared.activeProfile = profile
    }

    @objc func openSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = SettingsView()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 750, height: 850),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)

        window.minSize = NSSize(width: 700, height: 750)
        window.center()
        window.title = String(localized: "LangSwitcher Settings")
        window.contentView = NSHostingView(rootView: contentView)
        window.isReleasedWhenClosed = false

        self.settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(self)
    }
    
    @objc func toggleBrowserTabMemory(_ sender: NSMenuItem) {
        let manager = SettingsManager.shared
        let newState = !manager.isBrowserTabMemoryEnabled
        manager.isBrowserTabMemoryEnabled = newState
        sender.state = newState ? .on : .off
        
        if newState {
            AccessibilityManager.shared.checkAutomationPermissions(prompt: true)
            let acc = AccessibilityManager.shared
            if !acc.isChromeAutomationTrusted || !acc.isSafariAutomationTrusted {
                NSApp.activate(ignoringOtherApps: true)
                let alert = NSAlert()
                if let appIcon = NSImage(named: NSImage.applicationIconName) {
                    alert.icon = appIcon
                }
                
                alert.messageText = String(localized: "Automation Permission Required")
                alert.informativeText = String(localized: "To remember tab languages, LangSwitcher needs Automation permission for your browsers. Please enable it in System Settings, or check the 'Info & Support' tab.")
                alert.addButton(withTitle: String(localized: "Open System Settings"))
                alert.addButton(withTitle: String(localized: "OK"))
                if alert.runModal() == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
                }
            }
        }
    }
}
