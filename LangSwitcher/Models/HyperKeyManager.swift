//
//  HyperKeyManager.swift
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
import CoreGraphics
import Foundation // 🌟 Process 실행을 위해 필요

class HyperKeyManager {
    static let shared = HyperKeyManager()

    fileprivate var eventTap: CFMachPort?
    fileprivate var runLoopSource: CFRunLoopSource?

    fileprivate var isHyperDown = false
    fileprivate var tapStartTime: Date?
    fileprivate var isUsedAsModifier = false

    fileprivate let f19KeyCode: CGKeyCode = 80
    fileprivate let hyperKeyCodes: [CGKeyCode] = [55, 58, 59, 56]

    private init() {}

    func updateState(isEnabled: Bool) {
        if isEnabled {
            setupHardwareMapping(enable: true) // 🌟 하드웨어 매핑 켜기
            start()
        } else {
            setupHardwareMapping(enable: false) // 🌟 하드웨어 매핑 끄기 (원상복구)
            stop()
        }
    }

    // 🌟 macOS 내부 유틸리티(hidutil)를 사용하여 Caps Lock을 F19로 강제 변환하는 마법!
    private func setupHardwareMapping(enable: Bool) {
        let task = Process()
        task.launchPath = "/usr/bin/hidutil"
        
        if enable {
            // Caps Lock(0x39)의 물리 신호를 F19(0x6E)로 변환
            let jsonString = "{\"UserKeyMapping\":[{\"HIDKeyboardModifierMappingSrc\":0x700000039,\"HIDKeyboardModifierMappingDst\":0x70000006E}]}"
            task.arguments = ["property", "--set", jsonString]
        } else {
            // 빈 배열을 전달하여 매핑을 초기화 (원래 Caps Lock으로 복구)
            task.arguments = ["property", "--set", "{\"UserKeyMapping\":[]}"]
        }
        
        try? task.run()
    }

    private func start() {
        guard eventTap == nil else { return }

        let eventMask = (1 << CGEventType.keyDown.rawValue) |
                        (1 << CGEventType.keyUp.rawValue) |
                        (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: eventCallback,
            userInfo: nil
        ) else {
            print("Failed to create event tap for Hyper Key.")
            return
        }

        self.eventTap = tap
        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        
        if let runLoopSource = self.runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }

        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            }
            CFMachPortInvalidate(tap)
            self.eventTap = nil
            self.runLoopSource = nil
        }
    }

    fileprivate func postHyperModifiers(isDown: Bool) {
        let loc = CGEventTapLocation.cgSessionEventTap
        for keyCode in hyperKeyCodes {
            if let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: isDown) {
                event.post(tap: loc)
            }
        }
    }

    fileprivate func handleTap() {
        DispatchQueue.main.async {
            let frontAppName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "System"
            let frontAppID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""

            if SettingsManager.shared.excludedApps.contains(where: { $0.bundleIdentifier == frontAppID }) { return }

            InputSourceManager.shared.switchToNextInputSource()

            let log = ActionLog(
                timestamp: Date(), targetApp: frontAppName, appliedRule: "Hyper Key (Caps Lock)",
                finalInputSource: "Next Source", result: .success, failureReason: .none
            )
            SettingsManager.shared.addLog(log)
        }
    }
}

// MARK: - C 콜백 함수
private func eventCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    let manager = HyperKeyManager.shared
    let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

    if keyCode == manager.f19KeyCode {
        if type == .keyDown {
            if !manager.isHyperDown {
                manager.isHyperDown = true
                manager.tapStartTime = Date()
                manager.isUsedAsModifier = false
                manager.postHyperModifiers(isDown: true)
            }
            return nil
        } else if type == .keyUp {
            manager.isHyperDown = false
            manager.postHyperModifiers(isDown: false)

            if let startTime = manager.tapStartTime, !manager.isUsedAsModifier {
                let duration = Date().timeIntervalSince(startTime)
                if duration < 0.2 { manager.handleTap() }
            }
            return nil
        }
    }

    if manager.isHyperDown && type == .keyDown {
        manager.isUsedAsModifier = true
        var flags = event.flags
        flags.insert([.maskCommand, .maskAlternate, .maskControl, .maskShift])
        event.flags = flags
    }

    return Unmanaged.passRetained(event)
}
