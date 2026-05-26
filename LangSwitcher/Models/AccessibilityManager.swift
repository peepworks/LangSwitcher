//
//  AccessibilityManager.swift
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
import Combine
import ApplicationServices

class AccessibilityManager: ObservableObject {
    static let shared = AccessibilityManager()

    @Published var isTrusted: Bool = false
    @Published var isChromeAutomationTrusted: Bool = false
    @Published var isSafariAutomationTrusted: Bool = false

    // 🌟 [수정 1] 변수 중복을 없애고 단일 타이머(timer)만 사용합니다.
    private var timer: Timer?

    init() {
        self.isTrusted = AXIsProcessTrusted()
        self.checkAutomationPermissions(prompt: false)
        
        // 앱이 화면의 포커스를 다시 받을 때마다 상태를 새로고침합니다.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshPermissions),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

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
                // 🌟 [수정 2] 타이머가 이미 돌고 있다면 다시 부르지 않도록 방어막(guard) 추가
                if self.timer == nil {
                    self.startMonitoring()
                }
            }
        }
        return trusted
    }

    // 🌟 [수정 3] 컴파일 에러 해결: 자동화 권한 결과를 종합해서 Bool로 반환(return)하게 바꿉니다.
    @discardableResult
    func checkAutomationPermissions(prompt: Bool = false) -> Bool {
        let chromeGranted = self.checkAppAutomation(for: "com.google.Chrome", prompt: prompt)
        let safariGranted = self.checkAppAutomation(for: "com.apple.Safari", prompt: prompt)
        
        DispatchQueue.main.async {
            self.isChromeAutomationTrusted = chromeGranted
            self.isSafariAutomationTrusted = safariGranted
        }
        
        return chromeGranted && safariGranted
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

    func startMonitoring() {
        // 🌟 [핵심 추가] 타이머를 만들기 전에, 이미 필수 권한(접근성)이 있는지 먼저 확인합니다.
        // 권한이 이미 있다면 타이머를 생성조차 하지 않고 즉시 종료합니다.
        guard !checkPermission(prompt: false) else { return }
        
        // 이미 타이머가 존재하면 중복 생성하지 않고 무시합니다.
        guard timer == nil else { return }
        
        // 🌟 3초 간격으로 우아하게 상태를 확인합니다.
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // 1. 접근성 권한 확인 (이 안에서 권한 획득 시 알아서 stopMonitoring이 불립니다)
            self.checkPermission(prompt: false)
            
            // 2. 자동화 권한 확인
            self.checkAutomationPermissions(prompt: false)
            
            // 접근성(필수) 권한이 획득되면 타이머는 checkPermission 내부의 stopMonitoring()에 의해 파괴됩니다.
        }
    }

    private func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        dprint("AccessibilityManager: 권한 모니터링 타이머가 안전하게 종료되었습니다.")
    }
}
