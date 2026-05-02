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
import Carbon // TIS API 사용을 위해 추가

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 앱이 메뉴바 전용(Accessory)으로 동작하도록 설정
        NSApp.setActivationPolicy(.accessory)
        setupMenu()

        // 1. 앱 실행 시 접근성 권한이 있다면 즉시 키보드 감지(EventMonitor) 시작
        if AccessibilityManager.shared.isTrusted {
            EventMonitor.shared.start()
        } else {
            // 권한이 없다면 사용자에게 권한 요청 알림을 띄웁니다.
            AccessibilityManager.shared.checkPermission(prompt: true)
        }

        // 앱 실행 시 활성 앱 감지기(AppMonitor)를 명시적으로 시작합니다.
        AppMonitor.shared.start()

        // 백그라운드 24시간 단위 자동 업데이트 확인 타이머 가동
        UpdateManager.shared.setupAutoUpdateCheck()

        // 앱 시작 시, 저장된 설정값을 불러와서 Hyper Key 기능을 켤지 말지 결정합니다.
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
        menu.delegate = self // 🌟 동적 메뉴를 위해 delegate 연결
        statusItem.menu = menu
    }

    // 🌟 메뉴가 열리기 직전에 호출됨: 여기서 실시간 상태 및 아이콘 정렬 반영
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

        // 1. 현재 입력 소스 (지구본 아이콘)
        let langItem = NSMenuItem(title: "\(String(localized: "Language")): \(currentLang)", action: #selector(toggleLanguage), keyEquivalent: "")
        langItem.image = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
        menu.addItem(langItem)
        
        menu.addItem(NSMenuItem.separator())

        // 2. 앱 일시 정지 (Kill Switch)
        let pauseItem = NSMenuItem(title: String(localized: "Pause LangSwitcher"), action: #selector(togglePause), keyEquivalent: "")
        pauseItem.state = EventMonitor.shared.isPaused ? .on : .off
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
        
        // 🌟 [수정됨] 영어를 기본값으로 변경하고, 변수명 에러(statusMenu) 해결
        let browserTabMenuItem = NSMenuItem(
            title: String(localized: "Browser Tab Memory"),
            action: #selector(toggleBrowserTabMemory(_:)),
            keyEquivalent: ""
        )
        browserTabMenuItem.state = snapshot.isBrowserTabMemoryEnabled ? .on : .off
        browserTabMenuItem.target = self
        menu.addItem(browserTabMenuItem)

        menu.addItem(NSMenuItem.separator())

        // 4. 동적 예외 앱 관리 (+ / - 아이콘 적용)
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

        // 5. 시스템 메뉴 (설정 및 종료 아이콘 적용)
        let settingsItem = NSMenuItem(title: String(localized: "Settings..."), action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: String(localized: "Quit"), action: #selector(quitApp), keyEquivalent: "q")
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil) // 🌟 전원(종료) 아이콘
        menu.addItem(quitItem)
    }

    // MARK: - Actions

    @objc func toggleLanguage() { InputSourceManager.shared.switchToNextInputSource() }
    @objc func togglePause() { EventMonitor.shared.isPaused.toggle() }
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
            contentRect: NSRect(x: 0, y: 0, width: 750, height: 720),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)

        window.minSize = NSSize(width: 700, height: 600)
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
    
    // MARK: - Menu Actions

    @objc func toggleBrowserTabMemory(_ sender: NSMenuItem) {
        let manager = SettingsManager.shared
        let newState = !manager.isBrowserTabMemoryEnabled
        manager.isBrowserTabMemoryEnabled = newState
        
        sender.state = newState ? .on : .off
        
        if newState {
            // 1. 시스템에 기본 권한 팝업을 요청합니다.
            AccessibilityManager.shared.checkAutomationPermissions(prompt: true)
            
            // 2. 🌟 [핵심 UX] 크롬이나 사파리 중 하나라도 권한이 없다면 커스텀 알림을 띄웁니다.
            let acc = AccessibilityManager.shared
            let needsPermission = !acc.isChromeAutomationTrusted || !acc.isSafariAutomationTrusted
            
            if needsPermission {
                // 백그라운드 앱(Accessory)의 알림창이 다른 앱 뒤에 숨지 않도록 강제로 최상단으로 끌어올립니다.
                NSApp.activate(ignoringOtherApps: true)
                
                let alert = NSAlert()
                alert.messageText = String(localized: "Automation Permission Required")
                alert.informativeText = String(localized: "To remember tab languages, LangSwitcher needs Automation permission for your browsers. Please enable it in System Settings, or check the 'Info & Support' tab.")
                alert.addButton(withTitle: String(localized: "Open System Settings")) // 첫 번째 버튼 (Return)
                alert.addButton(withTitle: String(localized: "OK")) // 두 번째 버튼 (Cancel)
                
                // 알림창 띄우기 및 버튼 클릭 결과 확인
                if alert.runModal() == .alertFirstButtonReturn {
                    // "설정 열기" 버튼을 누른 경우
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
                }
            }
        }
    }
}
