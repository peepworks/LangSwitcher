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

class HyperKeyManager {
    static let shared = HyperKeyManager()

    private var isHyperDown = false
    private var tapStartTime: Date?
    private var isUsedAsModifier = false

    private let f19KeyCode: CGKeyCode = 80
    private let hyperKeyCodes: [CGKeyCode] = [55, 58, 59, 56]

    private init() {}

    func updateState(isEnabled: Bool) {
        setupHardwareMapping(enable: isEnabled)
        if !isEnabled { isHyperDown = false }
    }

    private func setupHardwareMapping(enable: Bool) {
        let task = Process()
        task.launchPath = "/usr/bin/hidutil"

        let mappingString = enable
            ? "{\"UserKeyMapping\":[{\"HIDKeyboardModifierMappingSrc\":0x700000039,\"HIDKeyboardModifierMappingDst\":0x70000006E}]}"
            : "{\"UserKeyMapping\":[{\"HIDKeyboardModifierMappingSrc\":0x700000039,\"HIDKeyboardModifierMappingDst\":0x700000039}]}"

        task.arguments = ["property", "--set", mappingString]

        do {
            try task.run()
            task.waitUntilExit()
            // 로그 기록 삭제됨
        } catch {
            print("hidutil 실행 실패: \(error)")
        }
    }

    private func postHyperModifiers(isDown: Bool) {
        guard let eventSource = CGEventSource(stateID: .hidSystemState) else { return }
        for keyCode in hyperKeyCodes {
            if let event = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: isDown) {
                event.flags = isDown ? CGEventFlags(rawValue: UInt64(NSEvent.ModifierFlags.deviceIndependentFlagsMask.rawValue)) : []
                event.setIntegerValueField(.eventSourceUserData, value: 9999)
                event.post(tap: .cghidEventTap)
            }
        }
    }

    func processEvent(type: CGEventType, event: CGEvent, keyCode: CGKeyCode) -> Bool {
        if keyCode == f19KeyCode {
            if type == .keyDown {
                if !isHyperDown {
                    isHyperDown = true
                    tapStartTime = Date()
                    isUsedAsModifier = false
                    postHyperModifiers(isDown: true)
                }
                return true
            } else if type == .keyUp {
                isHyperDown = false
                postHyperModifiers(isDown: false)
                
                if let startTime = tapStartTime, !isUsedAsModifier {
                    let duration = Date().timeIntervalSince(startTime)
                    if duration < 0.3 {
                        DispatchQueue.main.async { InputSourceManager.shared.switchToNextInputSource() }
                    }
                }
                return true
            }
        }

        if isHyperDown && (type == .keyDown || type == .keyUp || type == .flagsChanged) {
            if type == .keyDown { isUsedAsModifier = true }
            var flags = event.flags
            flags.insert([.maskCommand, .maskAlternate, .maskControl, .maskShift])
            event.flags = flags
        }
        
        return false
    }
}
