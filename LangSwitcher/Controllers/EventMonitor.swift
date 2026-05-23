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
        32: "u", 34: "i", 35: "p", 37: "l", 38: "j", 40: "k", 45: "n", 46: "m",
        41: ";", 44: "/", 47: ".", 43: ",", 39: "'", 33: "["
    ]
    
    var localSnapshot: SettingsSnapshot?
    let snapshotLock = NSLock()
    
    var pendingInsertTasks: [DispatchWorkItem] = []
    
    init() {}

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

                return autoreleasepool {

                    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                        if let refcon = refcon {
                            let monitor = Unmanaged<EventMonitor>.fromOpaque(refcon).takeUnretainedValue()
                            if let tap = monitor.eventTap {
                                CGEvent.tapEnable(tap: tap, enable: true)
                            }
                        }
                        return Unmanaged.passUnretained(event)
                    }

                    if IsSecureEventInputEnabled() { return Unmanaged.passUnretained(event) }

                    let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
                    let snapshot = SettingsManager.shared.snapshot
                    let currentAppID = AppMonitor.shared.activeAppBundleID
                
                    if snapshot.isExcludedAppsEnabled && !currentAppID.isEmpty {
                        if snapshot.excludedApps.contains(where: { $0.bundleIdentifier == currentAppID }) {
                            return Unmanaged.passUnretained(event)
                        }
                    }
                    
                    if let callback = EventMonitor.shared.shortcutRecordingCallback {
                        if type == .keyDown || type == .flagsChanged {
                            if let nsEvent = NSEvent(cgEvent: event) { DispatchQueue.main.async { callback(nsEvent) } }
                            return nil
                        }
                    }
                    
                    let isSimulated = event.getIntegerValueField(.eventSourceUserData) == 9999

                    if type == .keyDown {
                        let flags = event.flags
                        let isCommand = flags.contains(.maskCommand)
                        let isOption = flags.contains(.maskAlternate)
                        let isControl = flags.contains(.maskControl)
                        let isShift = flags.contains(.maskShift)
                        
                        if isCommand && isOption && isControl && !isShift && keyCode == 1 {
                            DispatchQueue.main.async {
                                let newState = !EventMonitor.shared.isPaused
                                EventMonitor.shared.isPaused = newState
                                HUDManager.shared.showHUD(languageName: newState ? String(localized: "LangSwitcher Paused") : String(localized: "LangSwitcher Resumed"))
                            }
                            return nil
                        }
                        if isCommand && isOption && isControl && !isShift && keyCode == 8 {
                            DispatchQueue.main.async { SettingsManager.shared.clearAllAppCaches() }
                            return nil
                        }
                    }

                    if snapshot.isHyperKeyEnabled {
                        if HyperKeyManager.shared.processEvent(type: type, event: event, keyCode: keyCode) { return nil }
                    }

                    if let callback = EventMonitor.shared.shortcutRecordingCallback {
                        if type == .keyDown || type == .flagsChanged {
                            if let nsEvent = NSEvent(cgEvent: event) { DispatchQueue.main.async { callback(nsEvent) } }
                            return nil
                        }
                    }

                    // 🌟 [핵심 수정] 시뮬레이션 이벤트(가짜 입력) 필터링 및 방향키 예외 처리
                    if isSimulated {
                        // 시뮬레이션 이벤트라면 무조건 현재 모인 타자 버퍼를 깨끗이 비워버립니다.
                        // (앱 실행 시 시스템이 발생시키는 가짜 입력에 언어 전환이 씹히는 것을 방지)
                        EventMonitor.shared.clearTypingBuffer()
                        
                        // 무한 루프 방지를 위해 실제 이벤트 처리는 건너뛰고 그냥 통과시킵니다.
                        return Unmanaged.passUnretained(event)
                    }
                    
                    if type == .keyDown {
                        if snapshot.isAutoTypoCorrectionEnabled || snapshot.isTextExpansionEnabled {
                            EventMonitor.shared.checkStaleAndResetBuffer()
                            let isEnterTrigger = snapshot.isAutoTypoCorrectionOnEnterEnabled && keyCode == 36
                            let flags = event.flags
                            let hasModifiers = flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate)
                            let isPureSpace = (keyCode == 49) && !hasModifiers
                            
                            if isPureSpace || isEnterTrigger {
                                let currentBuffer = EventMonitor.shared.typingBuffer

                                // 🌟 [수정] TextExpander 호출 시 스냅샷의 안전한 캐시 배열을 전달합니다.
                                if snapshot.isTextExpansionEnabled,
                                let matchedRule = TextExpander.shared.findMatch(
                                        for: currentBuffer,
                                        dict: snapshot.textExpansionDict,
                                        maxLength: snapshot.maxTriggerLength
                                ) {
                                    
                                    // 🌟 1. 템플릿 렌더링 및 커서 위치 계산
                                    let renderedSnippet = TextExpander.shared.expand(template: matchedRule.replacement)
                                    
                                    // 🌟 2. 렌더링된 전체 결과(text, cursorOffset)를 전달
                                    EventMonitor.shared.performTextExpansion(triggerLength: matchedRule.trigger.count, snippet: renderedSnippet, triggerKeyCode: UInt16(keyCode))
                                    
                                    // 🌟 3. 디버거 로그 기록 (메모리 최적화)
                                    let cursorLog = renderedSnippet.cursorOffsetFromStart != nil ? " (Cursor Restored)" : ""
                                    // ✅ [개선됨] 수백 자의 치환 결과 대신, 어떤 단어(trigger)가 텍스트 확장을 발생시켰는지만 심플하게 남깁니다.
                                    var log = ActionLog(
                                        timestamp: Date(),
                                        targetApp: currentAppID,
                                        appliedRule: "Text Expansion",
                                        finalInputSource: "Trigger: [\(matchedRule.trigger)]\(cursorLog)",
                                        result: .success,
                                        failureReason: .none
                                    )
                                    log.actionType = .textExpansion
                                    SettingsManager.shared.addLog(log)

                                    EventMonitor.shared.clearTypingBuffer()
                                    return nil
                                }
                                
                                if snapshot.isAutoTypoCorrectionEnabled {
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
                                }
                                EventMonitor.shared.clearTypingBuffer()
                            }
                            else if keyCode == 36 || keyCode == 51 || (123...126).contains(keyCode) {
                                EventMonitor.shared.clearTypingBuffer()
                            }
                            else {
                                // 🌟 [버그 수정] OS 언어 상태 인식 지연으로 인한 첫 글자 유실 방지
                                // 언어 모드와 무관하게 사용자가 입력한 키는 항상 버퍼에 기록합니다.
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

                    let nsModifierFlags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
                    if type == .flagsChanged { return EventMonitor.shared.handleFlagsChanged(event: event, keyCode: keyCode, modifierFlags: nsModifierFlags) }
                    if type == .keyDown { return EventMonitor.shared.handleKeyDown(event: event, keyCode: keyCode, modifierFlags: nsModifierFlags) }

                    return Unmanaged.passUnretained(event)
                }
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
            if self.eventTap != nil && !self.isEnabled { CGEvent.tapEnable(tap: self.eventTap!, enable: true) }
        }
    }

    func stop() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource, let rl = eventRunLoop { CFRunLoopRemoveSource(rl, source, .commonModes) }
        eventTap = nil; runLoopSource = nil; eventRunLoop = nil
    }
    
    func targetLangIfPressed(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> String? {
        let snapshot = SettingsManager.shared.snapshot
        if keyCode == 49 { // Spacebar
            if flags == .control && snapshot.isCtrlActive { return snapshot.ctrlLang }
            if flags == .command && snapshot.isCmdActive { return snapshot.cmdLang }
            if flags == .option && snapshot.isOptActive { return snapshot.optLang }
        }
        return nil
    }
}
