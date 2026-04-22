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

class AppDelegate: NSObject, NSApplicationDelegate {
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
        
        // 🌟 [리뷰 반영] 앱 실행 시 활성 앱 감지기(AppMonitor)를 명시적으로 시작합니다.
        // 이를 통해 예외 앱 및 앱별 키보드 전환 기능이 누락 없이 정상 동작하게 됩니다.
        AppMonitor.shared.start()
        
        // 백그라운드 24시간 단위 자동 업데이트 확인 타이머 가동
        UpdateManager.shared.setupAutoUpdateCheck()
        
        // 앱 시작 시, 저장된 설정값을 불러와서 Hyper Key 기능을 켤지 말지 결정합니다.
        HyperKeyManager.shared.updateState(isEnabled: UserDefaults.standard.bool(forKey: "isHyperKeyEnabled"))
    }

    // 2. 앱 종료 시 감지기를 안전하게 중지하여 시스템 자원 반환
    func applicationWillTerminate(_ notification: Notification) {
        EventMonitor.shared.stop()
        
        // 🌟 [리뷰 반영] 앱 종료 시 활성 앱 감지기도 안전하게 중지하여 자원(Notification Observer 등)을 반환합니다.
        AppMonitor.shared.stop()
        
        // 앱이 꺼질 때 Caps Lock을 다시 원래 상태로 돌려놓습니다.
        HyperKeyManager.shared.updateState(isEnabled: false)
        
        // 앱 종료 시 업데이트 확인 타이머를 안전하게 파기하여 RunLoop 자원 반환
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

        let settingsItem = NSMenuItem(
            title: String(localized: "Settings..."),
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        
        let quitItem = NSMenuItem(
            title: String(localized: "Quit"),
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }

    @objc func openSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = SettingsView()

        // 네이티브 사이드바 설정창 비율에 맞게 창을 와이드(Wide)하게 설정
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 750, height: 720),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)

        // 최소 크기 지정 (UI 깨짐 방지)
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
}
