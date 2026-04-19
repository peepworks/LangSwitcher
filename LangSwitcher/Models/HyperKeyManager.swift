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

    fileprivate var isHyperDown = false
    fileprivate var tapStartTime: Date?
    fileprivate var isUsedAsModifier = false

    fileprivate let f19KeyCode: CGKeyCode = 80
    fileprivate let hyperKeyCodes: [CGKeyCode] = [55, 58, 59, 56]

    private init() {}

    // 하드웨어 매핑 로직은 그대로 유지
    func updateState(isEnabled: Bool) {
        setupHardwareMapping(enable: isEnabled)
    }
    
    private func setupHardwareMapping(enable: Bool) { /* 기존과 동일 */ }
    fileprivate func postHyperModifiers(isDown: Bool) { /* 기존과 동일 */ }
    fileprivate func handleTap() { /* 기존과 동일 */ }

    // 🌟 추가됨: EventMonitor가 호출할 검사 함수 (true를 반환하면 이벤트 차단)
    func processEvent(type: CGEventType, event: CGEvent, keyCode: CGKeyCode) -> Bool {
        if keyCode == f19KeyCode {
            if type == .keyDown {
                if !isHyperDown {
                    isHyperDown = true
                    tapStartTime = Date()
                    isUsedAsModifier = false
                    postHyperModifiers(isDown: true)
                }
                return true // 🌟 차단 (EventMonitor에서 return nil 처리됨)
            } else if type == .keyUp {
                isHyperDown = false
                postHyperModifiers(isDown: false)
                if let startTime = tapStartTime, !isUsedAsModifier {
                    let duration = Date().timeIntervalSince(startTime)
                    if duration < 0.2 { handleTap() }
                }
                return true // 🌟 차단
            }
        }

        if isHyperDown && type == .keyDown {
            isUsedAsModifier = true
            var flags = event.flags
            flags.insert([.maskCommand, .maskAlternate, .maskControl, .maskShift])
            event.flags = flags
        }
        return false // 🌟 통과 (수정된 event 그대로 전달)
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
