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

class EventMonitor {
    static let shared = EventMonitor()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    func start() {
        if eventTap != nil { return }

        let eventMask = (1 << CGEventType.keyDown.rawValue)

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                if type == .keyDown {
                    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                    let flags = event.flags

                    let settings = SettingsManager.shared
                    var targetLang: String? = nil

                    let modifierFlags = flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])

                    // --- 1. 커스텀 단축키 우선 검사 ---
                    for shortcut in settings.customShortcuts {
                        if shortcut.keyCode == UInt16(keyCode) && !shortcut.displayString.isEmpty {
                            let savedFlags = CGEventFlags(rawValue: shortcut.modifierFlags)
                            let savedModifierFlags = savedFlags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])

                            if modifierFlags == savedModifierFlags {
                                targetLang = shortcut.targetLanguage
                                break
                            }
                        }
                    }

                    // --- 2. 기존 고정 단축키 검사 ---
                    if targetLang == nil && keyCode == 49 {
                        if modifierFlags == .maskControl && settings.isCtrlActive {
                            targetLang = settings.ctrlLang
                        } else if modifierFlags == .maskCommand && settings.isCmdActive {
                            targetLang = settings.cmdLang
                        } else if modifierFlags == .maskAlternate && settings.isOptActive {
                            targetLang = settings.optLang
                        }
                    }

                    // --- 3. InputSourceManager 호출 ---
                    // 🌟 비어있는 초기값("") 이 아닐 때만 동작하도록 처리
                    if let lang = targetLang, !lang.isEmpty {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            InputSourceManager.shared.switchLanguage(to: lang)
                        }
                    }
                }
                return Unmanaged.passRetained(event)
            },
            userInfo: nil
        )

        if let tap = eventTap {
            runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource!, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes) }
        eventTap = nil
        runLoopSource = nil
    }
}
