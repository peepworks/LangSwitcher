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
import Carbon

class EventMonitor {
    static let shared = EventMonitor()
    
    // MARK: - Stored Properties
    // 🌟 분리된 파일에서 접근할 수 있도록 private 키워드를 제거했습니다 (internal로 작동)
    var eventTap: CFMachPort?
    var runLoopSource: CFRunLoopSource?
    var healthCheckTimer: Timer?
    var eventRunLoop: CFRunLoop?
    
    let stateQueue = DispatchQueue(label: "com.peepworks.langswitcher.state", attributes: .concurrent)

    var _typingBuffer: String = ""
    var _lastKeyTime: Date = Date()
    var _shortcutRecordingCallback: ((NSEvent) -> Void)? = nil
    var _currentModifiers: NSEvent.ModifierFlags = []
    var _maxModifiers: NSEvent.ModifierFlags = []
    var _didPressOtherKey = false
    var _singleModifierKeyCode: UInt16? = nil
    var _isPaused = false
    var _lastCapsLockTime: Date = Date.distantPast
    var _lastActionTime: Date = Date.distantPast
    let actionCooldown: TimeInterval = 0.15
    
    static let charKeyMap: [UInt16: Character] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v",
        11: "b", 12: "q", 13: "w", 14: "e", 15: "r", 16: "y", 17: "t", 31: "o",
        32: "u", 34: "i", 35: "p", 37: "l", 38: "j", 40: "k", 45: "n", 46: "m"
    ]
    
    var localSnapshot: SettingsSnapshot?
    let snapshotLock = NSLock()
    
    init() {}

    // MARK: - Lifecycle

    func start() {
        if eventTap != nil {
            if !isEnabled { CGEvent.tapEnable(tap: eventTap!, enable: true) }
            return
        }

        let eventMask = (1 << CGEventType.keyDown.rawValue) |
                        (1 << CGEventType.keyUp.rawValue) |
                        (1 << CGEventType.flagsChanged.rawValue) |
                        (1 << CGEventType.tapDisabledByTimeout.rawValue) |
                        (1 << CGEventType.tapDisabledByUserInput.rawValue)

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in

                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let refcon = refcon {
                        let monitor = Unmanaged<EventMonitor>.fromOpaque(refcon).takeUnretainedValue()
                        if let tap = monitor.eventTap {
                            CGEvent.tapEnable(tap: tap, enable: true)
                            
                            let log = ActionLog(timestamp: Date(), targetApp: "macOS System", appliedRule: "CGEventTap Recovery", finalInputSource: "Re-enabled successfully", result: .failure, failureReason: .unknown)
                            SettingsManager.shared.addLog(log)
                            
                            #if DEBUG
                            print("⚠️ LangSwitcher: CGEventTap disabled by system timeout. Auto-recovered!")
                            #endif
                        }
                    }
                    return Unmanaged.passUnretained(event)
                }

                let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
                let snapshot = SettingsManager.shared.snapshot
                
                if type == .keyDown {
                    let flags = event.flags
                    let isCommand = flags.contains(.maskCommand)
                    let isOption = flags.contains(.maskAlternate)
                    let isControl = flags.contains(.maskControl)
                    let isShift = flags.contains(.maskShift)
                    
                    if isCommand && isOption && isControl && !isShift && keyCode == 1 {
                        DispatchQueue.main.async {
                            let currentState = EventMonitor.shared.isPaused
                            let newState = !currentState
                            EventMonitor.shared.isPaused = newState
                            
                            let statusMessage = newState ? String(localized: "LangSwitcher Paused") : String(localized: "LangSwitcher Resumed")
                            HUDManager.shared.showHUD(languageName: statusMessage)
                        }
                        return nil
                    }
                    if isCommand && isOption && isControl && !isShift && keyCode == 8 {
                        DispatchQueue.main.async {
                            SettingsManager.shared.clearAllAppCaches()
                        }
                        return nil
                    }
                }

                if snapshot.isHyperKeyEnabled {
                    let shouldBlock = HyperKeyManager.shared.processEvent(type: type, event: event, keyCode: keyCode)
                    if shouldBlock { return nil }
                }

                let isSimulated = event.getIntegerValueField(.eventSourceUserData) == 9999

                if let callback = EventMonitor.shared.shortcutRecordingCallback {
                    if type == .keyDown || type == .flagsChanged {
                        if let nsEvent = NSEvent(cgEvent: event) { DispatchQueue.main.async { callback(nsEvent) } }
                        return nil
                    }
                }

                if isSimulated { return Unmanaged.passUnretained(event) }
                
                if type == .keyDown {
                    if snapshot.isAutoTypoCorrectionEnabled {
                        EventMonitor.shared.checkStaleAndResetBuffer()
                        let isEnterTrigger = snapshot.isAutoTypoCorrectionOnEnterEnabled && keyCode == 36
                        
                        let flags = event.flags
                        let hasModifiers = flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate)
                        let isPureSpace = (keyCode == 49) && !hasModifiers
                        
                        if isPureSpace || isEnterTrigger {
                            let currentBuffer = EventMonitor.shared.typingBuffer
                            if currentBuffer.count >= 2 {
                                if EventMonitor.shared.isCurrentLanguageEnglish() {
                                    if let convertedText = TypoConverter.shared.detectAndConvert(englishInput: currentBuffer) {
                                        EventMonitor.shared.performAutoCorrection(
                                            originalLength: currentBuffer.count,
                                            correctedText: convertedText,
                                            triggerKeyCode: UInt16(keyCode)
                                        )
                                        EventMonitor.shared.clearTypingBuffer()
                                        return nil
                                    }
                                }
                            }
                            EventMonitor.shared.clearTypingBuffer()
                        }
                        else if keyCode == 36 || keyCode == 51 || (123...126).contains(keyCode) {
                            EventMonitor.shared.clearTypingBuffer()
                        }
                        else if let char = EventMonitor.shared.getCharacter(from: UInt16(keyCode)) {
                            if EventMonitor.shared.isCurrentLanguageEnglish() {
                                EventMonitor.shared.appendToTypingBuffer(char)
                            } else {
                                EventMonitor.shared.clearTypingBuffer()
                            }
                        }
                    }
                }

                let currentAppID = AppMonitor.shared.activeAppBundleID
                if snapshot.isExcludedAppsEnabled && !currentAppID.isEmpty {
                    if snapshot.excludedApps.contains(where: { $0.bundleIdentifier == currentAppID }) {
                        return Unmanaged.passUnretained(event)
                    }
                }

                if EventMonitor.shared.isPaused { return Unmanaged.passUnretained(event) }

                let nsModifierFlags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))

                if type == .flagsChanged { return EventMonitor.shared.handleFlagsChanged(event: event, keyCode: keyCode, modifierFlags: nsModifierFlags) }
                if type == .keyDown { return EventMonitor.shared.handleKeyDown(event: event, keyCode: keyCode, modifierFlags: nsModifierFlags) }
                
                return Unmanaged.passUnretained(event)
            }, userInfo: nil)

        if let tap = eventTap {
            runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            let currentRL = CFRunLoopGetCurrent()
            CFRunLoopAddSource(currentRL, runLoopSource!, .commonModes)
            self.eventRunLoop = currentRL
            
            CGEvent.tapEnable(tap: tap, enable: true)
            startHealthCheck()
        }
    }

    func startHealthCheck() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.eventTap != nil && !self.isEnabled {
                CGEvent.tapEnable(tap: self.eventTap!, enable: true)
            }
        }
    }

    func stop() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        
        if let source = runLoopSource, let rl = eventRunLoop {
            CFRunLoopRemoveSource(rl, source, .commonModes)
        }
        
        eventTap = nil
        runLoopSource = nil
        eventRunLoop = nil
    }
}
