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
import Combine
import ApplicationServices

class AccessibilityManager: ObservableObject {
    static let shared = AccessibilityManager()

    @Published var isTrusted: Bool = false
    @Published var isChromeAutomationTrusted: Bool = false
    @Published var isSafariAutomationTrusted: Bool = false

    private var timer: Timer?

    init() {
        self.isTrusted = AXIsProcessTrusted()
        self.checkAutomationPermissions(prompt: false)
        
        // 🌟 [핵심 추가 1] 앱이 화면의 포커스를 다시 받을 때마다 상태를 새로고침하도록 옵저버를 등록합니다.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshPermissions),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    // 🌟 [핵심 추가 2] 새로고침 실행 함수
    @objc private func refreshPermissions() {
        self.checkPermission(prompt: false)
        self.checkAutomationPermissions(prompt: false)
    }

    @discardableResult
    func checkPermission(prompt: Bool = false) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt]
        let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)

        DispatchQueue.main.async {
            if self.isTrusted != trusted {
                self.isTrusted = trusted
            }

            if trusted {
                EventMonitor.shared.start()
                AppMonitor.shared.start()
                self.stopMonitoring()
            } else {
                self.startMonitoring()
            }
        }
        return trusted
    }

    func checkAutomationPermissions(prompt: Bool = false) {
        DispatchQueue.main.async {
            self.isChromeAutomationTrusted = self.checkAppAutomation(for: "com.google.Chrome", prompt: prompt)
            self.isSafariAutomationTrusted = self.checkAppAutomation(for: "com.apple.Safari", prompt: prompt)
        }
    }

    private func checkAppAutomation(for bundleID: String, prompt: Bool) -> Bool {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        let status = AEDeterminePermissionToAutomateTarget(
            target.aeDesc,
            AEEventClass(0x2A2A2A2A),
            AEEventID(0x2A2A2A2A),
            prompt
        )
        return status == noErr
    }

    private func startMonitoring() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkPermission(prompt: false)
            self?.checkAutomationPermissions(prompt: false)
        }
    }

    private func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
}
