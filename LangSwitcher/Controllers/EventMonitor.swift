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
                    
                    if keyCode == 49 { // Space Bar
                        // ✅ 하드디스크(UserDefaults) 대신 메모리(SettingsManager)를 즉시 읽습니다.
                        let settings = SettingsManager.shared
                        var targetLang: String? = nil
                        
                        let modifierFlags = flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
                        
                        if modifierFlags == .maskControl && settings.isCtrlActive {
                            targetLang = settings.ctrlLang
                        } else if modifierFlags == .maskCommand && settings.isCmdActive {
                            targetLang = settings.cmdLang
                        } else if modifierFlags == .maskAlternate && settings.isOptActive {
                            targetLang = settings.optLang
                        }

                        if let lang = targetLang {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                InputSourceManager.shared.switchLanguage(to: lang)
                            }
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
