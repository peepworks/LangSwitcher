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

import Cocoa
import SwiftUI
import Carbon

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
        
        let activeAppID = AppMonitor.shared.activeAppBundleID
        let activeAppName = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == activeAppID })?.localizedName ?? "App"

        var currentLang = "Unknown"
        if let currentSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
           let ptr = TISGetInputSourceProperty(currentSource, kTISPropertyLocalizedName) {
            currentLang = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
        }

        // 1. 현재 입력 소스
        let langItem = NSMenuItem(title: "\(String(localized: "Language")): \(currentLang)", action: #selector(toggleLanguage), keyEquivalent: "")
        langItem.image = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
        menu.addItem(langItem)
        
        menu.addItem(NSMenuItem.separator())

        // 2. 앱 일시 정지 (🌟 요청하신 대로 아이콘을 제거하고 '체크 표시' 방식으로 복구)
        let isPaused = EventMonitor.shared.isPaused
        let pauseItem = NSMenuItem(title: String(localized: "Pause LangSwitcher"), action: #selector(togglePause), keyEquivalent: "s")
        pauseItem.keyEquivalentModifierMask = [.control, .option, .command]
        pauseItem.state = isPaused ? .on : .off // 일시 정지 상태일 때 체크 표시가 나타납니다.
        menu.addItem(pauseItem)

        menu.addItem(NSMenuItem.separator())

        // 3. 핵심 기능 빠른 토글
        let typoItem = NSMenuItem(title: String(localized: "Typo Correction"), action: #selector(toggleTypo), keyEquivalent: "")
        typoItem.state = snapshot.isTypoCorrectionEnabled ? .on : .off
        menu.addItem(typoItem)

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

        // 5. 시스템 메뉴 (🌟 요청하신 대로 '앱 기록 초기화'를 환경설정 바로 위로 이동)
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

    @objc func toggleLanguage() { InputSourceManager.shared.switchToNextInputSource() }
    
    // 🌟 [수정됨] 메인 스레드 강제 할당 및 상태 업데이트 동기화
    @objc func togglePause() {
        DispatchQueue.main.async {
            let currentState = EventMonitor.shared.isPaused
            let newState = !currentState
            EventMonitor.shared.isPaused = newState
            
            // 상태값 텍스트 생성
            let statusMessage = newState ? String(localized: "LangSwitcher Paused") : String(localized: "LangSwitcher Resumed")
            
            // HUD 호출
            HUDManager.shared.showHUD(languageName: statusMessage)
            
            #if DEBUG
            print("메뉴바 클릭: LangSwitcher 일시 정지 상태 -> \(newState)")
            #endif
        }
    }
    
    @objc func clearAppMemory() { SettingsManager.shared.clearAllAppCaches() }
    @objc func toggleTypo() { SettingsManager.shared.isTypoCorrectionEnabled.toggle() }
    @objc func toggleHyper() { SettingsManager.shared.isHyperKeyEnabled.toggle() }
    @objc func toggleWindowMemory() { SettingsManager.shared.isWindowMemoryEnabled.toggle() }

    @objc func toggleExcludeCurrentApp(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String: String],
              let id = info["id"], let name = info["name"] else { return }
        
        var currentList = SettingsManager.shared.excludedApps
        if let index = currentList.firstIndex(where: { $0.bundleIdentifier == id }) {
            currentList.remove(at: index)
        } else {
            currentList.append(ExcludedApp(bundleIdentifier: id, appName: name))
        }
        SettingsManager.shared.excludedApps = currentList
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
