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
    
    // 🌟 다중 수식어 추적을 위한 전역 상태 변수들
    private var currentModifiers: NSEvent.ModifierFlags = []
    private var maxModifiers: NSEvent.ModifierFlags = []
    private var didPressOtherKey = false
    private var singleModifierKeyCode: UInt16? = nil

    func start() {
        if eventTap != nil { return }

        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                let settings = SettingsManager.shared
                var targetLang: String? = nil

                // 🌟 핵심 수정: C 기반의 CGEventFlags를 Swift의 NSEvent.ModifierFlags로 변환하여 완벽 호환
                let nsModifierFlags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))

                // --- 1. 수식어 키 감지 (단일 및 다중 조합 탭 처리) ---
                if type == .flagsChanged {
                    let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                    let flags = nsModifierFlags.intersection(.deviceIndependentFlagsMask)

                    if keyCode == 57 { // Caps Lock은 누르는 즉시 판정
                        for shortcut in settings.customShortcuts {
                            if shortcut.modifierFlags == 0 && shortcut.keyCode == 57 && !shortcut.displayString.isEmpty {
                                targetLang = shortcut.targetLanguage
                                break
                            }
                        }
                    } else {
                        if !flags.isEmpty {
                            if EventMonitor.shared.currentModifiers.isEmpty {
                                // 처음 수식어 키가 눌렸을 때
                                EventMonitor.shared.didPressOtherKey = false
                                EventMonitor.shared.maxModifiers = []
                                EventMonitor.shared.singleModifierKeyCode = keyCode
                            } else {
                                // 두 개 이상의 수식어가 눌렸다면 단일키 판정 취소
                                EventMonitor.shared.singleModifierKeyCode = nil
                            }
                            EventMonitor.shared.currentModifiers = flags
                            EventMonitor.shared.maxModifiers.formUnion(flags)
                        } else {
                            // 모든 수식어 키에서 손을 뗐을 때
                            if !EventMonitor.shared.didPressOtherKey {
                                if let singleCode = EventMonitor.shared.singleModifierKeyCode {
                                    // 🌟 단일 수식어 실행 (Left Cmd 등)
                                    for shortcut in settings.customShortcuts {
                                        if shortcut.modifierFlags == 0 && shortcut.keyCode == singleCode && !shortcut.displayString.isEmpty {
                                            targetLang = shortcut.targetLanguage
                                            break
                                        }
                                    }
                                } else if !EventMonitor.shared.maxModifiers.isEmpty {
                                    // 🌟 다중 수식어 실행 (Cmd+Opt 등 조합)
                                    let modsRaw = UInt64(EventMonitor.shared.maxModifiers.rawValue)
                                    for shortcut in settings.customShortcuts {
                                        if shortcut.keyCode == 0 && shortcut.modifierFlags == modsRaw && !shortcut.displayString.isEmpty {
                                            targetLang = shortcut.targetLanguage
                                            break
                                        }
                                    }
                                }
                            }
                            // 변수 초기화
                            EventMonitor.shared.currentModifiers = []
                            EventMonitor.shared.maxModifiers = []
                            EventMonitor.shared.singleModifierKeyCode = nil
                        }
                    }

                    if let lang = targetLang, !lang.isEmpty {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            InputSourceManager.shared.switchLanguage(to: lang)
                        }
                    }
                    return Unmanaged.passRetained(event)
                }

                // --- 2. 일반 단축키 감지 (기존 Cmd+S 등 처리) ---
                if type == .keyDown {
                    // 일반 키가 눌리면 수식어 탭 조건은 무효화 됨
                    EventMonitor.shared.didPressOtherKey = true
                    EventMonitor.shared.singleModifierKeyCode = nil
                    
                    let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                    let modifierFlags = nsModifierFlags.intersection([.command, .control, .option, .shift])

                    for shortcut in settings.customShortcuts {
                        // 수식어 전용이 아닌 일반 조합 단축키들만 여기서 검사
                        let isSingleModifier = [54,55,56,60,58,61,59,62,57,63].contains(shortcut.keyCode) && shortcut.modifierFlags == 0
                        let isMultiModifierOnly = shortcut.keyCode == 0 && shortcut.modifierFlags != 0
                        
                        if !isSingleModifier && !isMultiModifierOnly {
                            if shortcut.keyCode == keyCode && !shortcut.displayString.isEmpty {
                                let savedFlags = NSEvent.ModifierFlags(rawValue: UInt(shortcut.modifierFlags))
                                let savedModifierFlags = savedFlags.intersection([.command, .control, .option, .shift])

                                if modifierFlags == savedModifierFlags {
                                    targetLang = shortcut.targetLanguage
                                    break
                                }
                            }
                        }
                    }

                    // 기본 고정 단축키 검사
                    if targetLang == nil && keyCode == 49 {
                        if modifierFlags == .control && settings.isCtrlActive {
                            targetLang = settings.ctrlLang
                        } else if modifierFlags == .command && settings.isCmdActive {
                            targetLang = settings.cmdLang
                        } else if modifierFlags == .option && settings.isOptActive {
                            targetLang = settings.optLang
                        }
                    }

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
