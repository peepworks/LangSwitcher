//
//  EventMonitor.swift
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
import Carbon

@MainActor
class EventMonitor {
    static let shared = EventMonitor()

    var activeSnippetSession: ActiveSnippetSession?
    var eventTap: CFMachPort?
    var runLoopSource: CFRunLoopSource?
    var healthCheckTimer: Timer?
    var eventRunLoop: CFRunLoop?

    // 🌟 [수복 핵심 1] 타 파일과의 중복 선언(Invalid redeclaration) 충돌을 완벽히 소각하기 위해,
    // 오직 순정 백킹 필드 변수인 '_typingBuffer' 단 하나만 남겨두고 모든 유틸리티 함수들을 적출했습니다.
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
        32: "u", 34: "i", 35: "p", 37: "l", 38: "j", 40: "k", 45: "n", 46: "m",
        41: ";", 44: "/", 47: ".", 43: ",", 39: "'", 33: "["
    ]

    var localSnapshot: SettingsSnapshot?
    let snapshotLock = NSLock()

    var pendingInsertTasks: [DispatchWorkItem] = []

    private init() {}

    func start() {
        if eventTap != nil { return }

        let eventMask = (1 << CGEventType.keyDown.rawValue) |
                        (1 << CGEventType.keyUp.rawValue) |
                        (1 << CGEventType.flagsChanged.rawValue) |
                        (1 << CGEventType.leftMouseDown.rawValue) |
                        (1 << CGEventType.tapDisabledByTimeout.rawValue) |
                        (1 << CGEventType.tapDisabledByUserInput.rawValue)

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in

                return autoreleasepool {
                    guard Thread.isMainThread else {
                        dprint("⚠️ [EventMonitor] 콜백이 메인 스레드가 아닌 곳에서 감지되었습니다. 안전하게 바이패스합니다.")
                        return Unmanaged.passUnretained(event)
                    }

                    return MainActor.assumeIsolated { () -> Unmanaged<CGEvent>? in

                        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                            if let refcon = refcon {
                                let monitor = Unmanaged<EventMonitor>.fromOpaque(refcon).takeUnretainedValue()
                                if let tap = monitor.eventTap {
                                    CGEvent.tapEnable(tap: tap, enable: true)
                                }
                            }
                            return Unmanaged.passUnretained(event)
                        }

                        if type == .leftMouseDown {
                            EventMonitor.shared.clearTypingBuffer()
                            return Unmanaged.passUnretained(event)
                        }

                        if IsSecureEventInputEnabled() { return Unmanaged.passUnretained(event) }

                        EventMonitor.shared.snapshotLock.lock()
                        guard let snapshot = EventMonitor.shared.localSnapshot else {
                            EventMonitor.shared.snapshotLock.unlock()
                            return Unmanaged.passUnretained(event)
                        }
                        EventMonitor.shared.snapshotLock.unlock()

                        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
                        let currentAppID = globalActiveAppTracker.get()
                        
                        if let callback = EventMonitor.shared.shortcutRecordingCallback {
                            if type == .keyDown || type == .flagsChanged {
                                if let nsEvent = NSEvent(cgEvent: event) {
                                    DispatchQueue.main.async { callback(nsEvent) }
                                }
                                return nil
                            }
                        }

                        if type == .keyDown {
                            let flags = event.flags
                            if flags.contains(.maskCommand) && flags.contains(.maskAlternate) && flags.contains(.maskControl) && !flags.contains(.maskShift) && keyCode == 1 {
                                return nil
                            }
                        }

                        if snapshot.isHyperKeyEnabled {
                            if HyperKeyManager.shared.processEvent(type: type, event: event, keyCode: keyCode) { return nil }
                        }

                        let isSimulated = event.getIntegerValueField(.eventSourceUserData) == 9999
                        if isSimulated { return Unmanaged.passUnretained(event) }

                        if snapshot.isExcludedAppsEnabled && !currentAppID.isEmpty {
                            if snapshot.excludedApps.contains(where: { $0.bundleIdentifier == currentAppID }) {
                                var isLanguageSwitchKey = false
                                let nsFlags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue)).intersection(.deviceIndependentFlagsMask)
                                let toggleFlags = NSEvent.ModifierFlags(rawValue: UInt(snapshot.toggleModifierFlags)).intersection(.deviceIndependentFlagsMask)
                                
                                if type == .keyDown || type == .flagsChanged {
                                    let cleanNsFlags = nsFlags.subtracting(.capsLock)
                                    let cleanToggleFlags = toggleFlags.subtracting(.capsLock)
                                    
                                    if keyCode == snapshot.toggleKeyCode {
                                        if [57, 56, 60, 59, 62, 58, 61].contains(keyCode) { isLanguageSwitchKey = true }
                                        else if cleanNsFlags == cleanToggleFlags { isLanguageSwitchKey = true }
                                    }
                                    
                                    if keyCode == 49 {
                                        if cleanNsFlags == .command && snapshot.isCmdActive { isLanguageSwitchKey = true }
                                        if cleanNsFlags == .control && snapshot.isCtrlActive { isLanguageSwitchKey = true }
                                        if cleanNsFlags == .option && snapshot.isOptActive { isLanguageSwitchKey = true }
                                    }
                                }
                                if !isLanguageSwitchKey { return Unmanaged.passUnretained(event) }
                            }
                        }

                        // 텍스트 대치 및 스마트 자동 오타 교정 코어 엔진 구역
                        if type == .keyDown {
                            if snapshot.isAutoTypoCorrectionEnabled || snapshot.isTextExpansionEnabled {
                                EventMonitor.shared.checkStaleAndResetBuffer()
                                
                                let isEnterTrigger = snapshot.isAutoTypoCorrectionOnEnterEnabled && keyCode == 36
                                let flags = event.flags
                                let hasModifiers = flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate)
                                let isPureSpace = (keyCode == 49) && !hasModifiers

                                if isPureSpace || isEnterTrigger {
                                    // 🌟 [수복 핵심 2] 타 파일에 구현된 순정 typingBuffer 프로퍼티를 안전하게 호출 소비합니다.
                                    let currentBuffer = EventMonitor.shared.typingBuffer

                                    if snapshot.isTextExpansionEnabled,
                                       let matchedRule = TextExpander.shared.findMatch(for: currentBuffer, dict: snapshot.textExpansionDict, maxLength: snapshot.maxTriggerLength) {

                                        let renderedSnippet = TextExpander.shared.expand(template: matchedRule.replacement)
                                        EventMonitor.shared.performTextExpansion(triggerLength: matchedRule.trigger.count, snippet: renderedSnippet, triggerKeyCode: UInt16(keyCode), triggerText: matchedRule.trigger)

                                        let cursorLog = renderedSnippet.finalCaretOffset != nil ? " (Cursor Restored)" : ""
                                        var log = ActionLog(timestamp: Date(), targetApp: currentAppID, appliedRule: "Text Expansion", finalInputSource: "Trigger: [\(matchedRule.trigger)]\(cursorLog)", result: .success, failureReason: .none)
                                        log.actionType = .textExpansion
                                        SettingsManager.shared.addLog(log)

                                        EventMonitor.shared.clearTypingBuffer()
                                        return nil
                                    }

                                    if snapshot.isAutoTypoCorrectionEnabled {
                                        if currentBuffer.count >= 2 {
                                            if EventMonitor.shared.isCurrentLanguageEnglish() {
                                                if let convertedText = TypoConverter.shared.detectAndConvert(englishInput: currentBuffer) {
                                                    EventMonitor.shared.performAutoCorrection(originalLength: currentBuffer.count, correctedText: convertedText, triggerKeyCode: UInt16(keyCode))
                                                    EventMonitor.shared.clearTypingBuffer()
                                                    return nil
                                                }
                                            }
                                        }
                                    }
                                    EventMonitor.shared.clearTypingBuffer()
                                }
                                // 백스페이스 타건 시 장부 동기화 롤백 메커니즘을
                                // 본체 백킹 멤버 변수(_typingBuffer) 직접 제어로 안정하게 정산 수복
                                else if keyCode == 51 {
                                    if !EventMonitor.shared._typingBuffer.isEmpty {
                                        EventMonitor.shared._typingBuffer.removeLast()
                                    }
                                }
                                else if keyCode == 36 || (123...126).contains(keyCode) {
                                    EventMonitor.shared.clearTypingBuffer()
                                }
                                else {
                                    if let nsEvent = NSEvent(cgEvent: event), let chars = nsEvent.characters, !chars.isEmpty {
                                        let char = chars.first!
                                        if char.isLetter || char.isNumber || char.isPunctuation || char == ";" {
                                            EventMonitor.shared.appendToTypingBuffer(char)
                                        }
                                    }
                                }
                            }
                        }

                        if EventMonitor.shared.isPaused { return Unmanaged.passUnretained(event) }

                        var cleanRouterFlags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
                        cleanRouterFlags.remove(.capsLock)

                        if type == .flagsChanged { return EventMonitor.shared.handleFlagsChanged(event: event, keyCode: keyCode, modifierFlags: cleanRouterFlags) }
                        if type == .keyDown { return EventMonitor.shared.handleKeyDown(event: event, keyCode: keyCode, modifierFlags: cleanRouterFlags) }

                        return Unmanaged.passUnretained(event)
                    }
                }
            }, userInfo: Unmanaged.passUnretained(self).toOpaque())

        if let tap = eventTap {
            runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            let mainRL = CFRunLoopGetMain()
            CFRunLoopAddSource(mainRL, runLoopSource!, .commonModes)
            self.eventRunLoop = mainRL
            CGEvent.tapEnable(tap: tap, enable: true)
            startHealthCheck()
        }
    }

    func startHealthCheck() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self = self else { return }
                if let tap = self.eventTap {
                    if CGEvent.tapIsEnabled(tap: tap) == false {
                        CGEvent.tapEnable(tap: tap, enable: true)
                        let log = ActionLog(timestamp: Date(), targetApp: "LangSwitcher System", appliedRule: "Self-Healing Activation", finalInputSource: "EventTap Re-enabled", result: .success, failureReason: .none)
                        SettingsManager.shared.addLog(log)
                    }
                } else {
                    let log = ActionLog(timestamp: Date(), targetApp: "LangSwitcher System", appliedRule: "Self-Healing Infrastructure Rebuild", finalInputSource: "EventTap Port Recovered", result: .success, failureReason: .none)
                    SettingsManager.shared.addLog(log)
                    self.stop()
                    self.start()
                }
            }
        }
    }

    func stop() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource, let rl = eventRunLoop { CFRunLoopRemoveSource(rl, source, .commonModes) }
        eventTap = nil; runLoopSource = nil; eventRunLoop = nil
    }

    func targetLangIfPressed(keyCode: UInt16, flags: NSEvent.ModifierFlags, snapshot: SettingsSnapshot) -> String? {
        if keyCode == 49 {
            if flags == .control && snapshot.isCtrlActive { return snapshot.ctrlLang }
            if flags == .command && snapshot.isCmdActive { return snapshot.cmdLang }
            if flags == .option && snapshot.isOptActive { return snapshot.optLang }
        }
        return nil
    }
}
