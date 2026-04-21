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

class HyperKeyManager {
    static let shared = HyperKeyManager()

    // 🌟 [리뷰 반영] 스레드 안전성을 보장하기 위한 가벼운 자물쇠(Lock) 추가
    private let stateLock = NSLock()

    private var isHyperDown = false
    private var tapStartTime: Date?
    private var isUsedAsModifier = false

    private let f19KeyCode: CGKeyCode = 80
    private let hyperKeyCodes: [CGKeyCode] = [55, 58, 59, 56]

    private init() {}

    func updateState(isEnabled: Bool) {
        setupHardwareMapping(enable: isEnabled)
        
        // 🌟 외부(UI 스레드)에서 상태를 변경할 때도 안전하게 잠금 처리
        stateLock.lock()
        if !isEnabled { isHyperDown = false }
        stateLock.unlock()
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

    private func handleTap() {
        DispatchQueue.main.async {
            InputSourceManager.shared.switchToNextInputSource()
        }
    }

    func processEvent(type: CGEventType, event: CGEvent, keyCode: CGKeyCode) -> Bool {
        // 🌟 시스템에 이벤트를 전송(Side-Effect)할 동작들을 임시 저장할 변수들
        var shouldBlock = false
        var shouldPostDown = false
        var shouldPostUp = false
        var shouldHandleTap = false
        var modifiedFlags: CGEventFlags? = nil

        // 🌟 1단계: 자물쇠를 잠그고 내부 상태(State)만 안전하게 평가 및 수정합니다.
        stateLock.lock()
        
        if keyCode == f19KeyCode {
            if type == .keyDown {
                if !isHyperDown {
                    isHyperDown = true
                    tapStartTime = Date()
                    isUsedAsModifier = false
                    shouldPostDown = true // 나중에 실행할 예약
                }
                shouldBlock = true
            } else if type == .keyUp {
                isHyperDown = false
                shouldPostUp = true // 나중에 실행할 예약
                
                if let startTime = tapStartTime, !isUsedAsModifier {
                    let duration = Date().timeIntervalSince(startTime)
                    if duration < 0.3 {
                        shouldHandleTap = true // 나중에 실행할 예약
                    }
                }
                shouldBlock = true
            }
        }

        if !shouldBlock && isHyperDown && (type == .keyDown || type == .keyUp || type == .flagsChanged) {
            if type == .keyDown { isUsedAsModifier = true }
            var flags = event.flags
            flags.insert([.maskCommand, .maskAlternate, .maskControl, .maskShift])
            modifiedFlags = flags // 나중에 플래그 교체할 예약
        }
        
        stateLock.unlock()
        // 🔓 자물쇠 해제 완료

        // 🌟 2단계: 자물쇠가 풀린 안전한 상태에서 시스템 관련 동작(Side-Effect)을 실행합니다. (데드락 방지)
        if shouldPostDown { postHyperModifiers(isDown: true) }
        if shouldPostUp { postHyperModifiers(isDown: false) }
        if shouldHandleTap { handleTap() }
        if let newFlags = modifiedFlags { event.flags = newFlags }

        return shouldBlock
    }
}
