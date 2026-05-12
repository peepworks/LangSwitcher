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
        41: ";",
        44: "/", 47: ".", 43: ",", 39: "'", 33: "["
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

                // 1. 타임아웃 복구 구간
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let refcon = refcon {
                        let monitor = Unmanaged<EventMonitor>.fromOpaque(refcon).takeUnretainedValue()
                        if let tap = monitor.eventTap {
                            CGEvent.tapEnable(tap: tap, enable: true)
                            
                            var log = ActionLog(timestamp: Date(), targetApp: "macOS System", appliedRule: "CGEventTap Recovery", finalInputSource: "Re-enabled successfully", result: .failure, failureReason: .unknown)
                            log.actionType = .systemRecovery
                            SettingsManager.shared.addLog(log)
                            
                            #if DEBUG
                            print("⚠️ LangSwitcher: CGEventTap disabled by system timeout. Auto-recovered!")
                            #endif
                        }
                    }
                    return Unmanaged.passUnretained(event)
                }
                
                // 🌟 [보안 1] 비밀번호 필드(Secure Input) 개입 차단
                if IsSecureEventInputEnabled() {
                    return Unmanaged.passUnretained(event)
                }

                let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
                let snapshot = SettingsManager.shared.snapshot
                let currentAppID = AppMonitor.shared.activeAppBundleID
                
                // 🌟 [보안 2] 예외 앱 정책 강화: 타이핑 버퍼를 기록하기 "전"에 차단하여 원천 봉쇄
                if snapshot.isExcludedAppsEnabled && !currentAppID.isEmpty {
                    if snapshot.excludedApps.contains(where: { $0.bundleIdentifier == currentAppID }) {
                        return Unmanaged.passUnretained(event)
                    }
                }
                
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
                
                // 🔽 텍스트 대치 및 오타 교정 처리 🔽
                if type == .keyDown {
                    if snapshot.isAutoTypoCorrectionEnabled || snapshot.isTextExpansionEnabled {
                        EventMonitor.shared.checkStaleAndResetBuffer()
                        let isEnterTrigger = snapshot.isAutoTypoCorrectionOnEnterEnabled && keyCode == 36
                        
                        let flags = event.flags
                        let hasModifiers = flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate)
                        let isPureSpace = (keyCode == 49) && !hasModifiers
                        
                        // 스페이스바 또는 엔터(설정 시)를 눌렀을 때 트리거 검사
                        if isPureSpace || isEnterTrigger {
                            let currentBuffer = EventMonitor.shared.typingBuffer
                            
                            #if DEBUG
                            print("Checking expansion for: \(currentBuffer)")
                            #endif
                            
                            // 1순위: Text Expansion (텍스트 대치)
                            if snapshot.isTextExpansionEnabled,
                                let matchedRule = TextExpander.shared.findMatch(in: currentBuffer, activeAppID: currentAppID, rules: snapshot.textExpansionRules) {
                                    
                                let parsedText = TextExpander.shared.parseDynamicVariables(text: matchedRule.replacement)
                                    
                                EventMonitor.shared.performTextExpansion(
                                    triggerLength: matchedRule.trigger.count,
                                    replacementText: parsedText,
                                    triggerKeyCode: UInt16(keyCode)
                                )
                                
                                // 🌟 [보안 3 & 안정성] 마스킹 및 actionType 분리 적용
                                let maskedText = String(repeating: "*", count: parsedText.count)
                                var log = ActionLog(
                                    timestamp: Date(),
                                    targetApp: currentAppID,
                                    appliedRule: "Text Expansion (\(matchedRule.trigger))",
                                    finalInputSource: "Expanded: \(maskedText) (\(parsedText.count) chars)",
                                    result: .success,
                                    failureReason: .none
                                )
                                log.actionType = .textExpansion // 신규 필드 안전하게 주입
                                SettingsManager.shared.addLog(log)
                                    
                                EventMonitor.shared.clearTypingBuffer()
                                return nil
                            }
                            
                            // 2순위: 기존 오타 교정 로직
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
                            // 🌟 [치명적 버그 수정] 한글 조합 깨짐 방지 로직 적용
                            if !EventMonitor.shared.isCurrentLanguageEnglish() {
                                // 현재 한글 모드라면, OS 조합기를 건드리지 않기 위해 글자 추출을 생략하고 버퍼만 비움
                                EventMonitor.shared.clearTypingBuffer()
                            } else {
                                // 영어 모드일 때만 안전하게 글자를 추출하여 버퍼에 담음
                                if let nsEvent = NSEvent(cgEvent: event),
                                   let chars = nsEvent.characters, !chars.isEmpty {
                                    let char = chars.first!
                                    
                                    if char.isLetter || char.isNumber || char.isPunctuation || char == ";" {
                                        EventMonitor.shared.appendToTypingBuffer(char)
                                    }
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
