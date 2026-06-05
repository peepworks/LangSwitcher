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

    private init() {}

    func start() {
        if eventTap != nil {
            if !isEnabled { CGEvent.tapEnable(tap: eventTap!, enable: true) }
            return
        }

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
                    // 🌟 [최종 수복: 백그라운드 스레드 크래시 방어벽 구축]
                    // OS의 타이밍 꼬임이나 타임아웃 재활성화 경합으로 인해 이 콜백이
                    // 백그라운드 스레드에서 유입될 경우, MainActor.assumeIsolated가 앱을 즉사시키는 현상을 원천 차단합니다.
                    guard Thread.isMainThread else {
                        dprint("⚠️ [EventMonitor] 콜백이 메인 스레드가 아닌 곳에서 감지되었습니다. 안전하게 바이패스합니다.")
                        // 메인 스레드가 아닐 때는 격리된 인메모리 장부들을 건드릴 수 없으므로,
                        // 입력을 차단하거나 조작하지 않고 시스템 원래의 키보드 이벤트를 그대로 흘려보내 앱의 생존을 보장합니다.
                        return Unmanaged.passUnretained(event)
                    }

                    // 💡 위에서 100% 메인 스레드임이 검증되었으므로 안심하고 격리 해제를 집행합니다.
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

                        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
                        let snapshot = SettingsManager.shared.snapshot
                        let currentAppID = AppMonitor.shared.activeAppBundleID

                        if let callback = EventMonitor.shared.shortcutRecordingCallback {
                            if type == .keyDown || type == .flagsChanged {
                                if let nsEvent = NSEvent(cgEvent: event) {
                                    DispatchQueue.main.async { callback(nsEvent) }
                                }
                                return nil
                            }
                        }

                        // 시스템 긴급 제어
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

                        // Caps Lock (Hyper Key) 엔진 상시 동작
                        if snapshot.isHyperKeyEnabled {
                            if HyperKeyManager.shared.processEvent(type: type, event: event, keyCode: keyCode) { return nil }
                        }

                        // 단축키 레코더 가로채기
                        if let callback = EventMonitor.shared.shortcutRecordingCallback {
                            if type == .keyDown || type == .flagsChanged {
                                if let nsEvent = NSEvent(cgEvent: event) {
                                    DispatchQueue.main.async { callback(nsEvent) }
                                }
                                return nil
                            }
                        }

                        let isSimulated = event.getIntegerValueField(.eventSourceUserData) == 9999

                        if isSimulated {
                            return Unmanaged.passUnretained(event)
                        }

                        // 예외 등록 앱 필터링
                        if snapshot.isExcludedAppsEnabled && !currentAppID.isEmpty {
                            if snapshot.excludedApps.contains(where: { $0.bundleIdentifier == currentAppID }) {
                                
                                var isLanguageSwitchKey = false
                                let nsFlags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue)).intersection(.deviceIndependentFlagsMask)
                                let toggleFlags = NSEvent.ModifierFlags(rawValue: UInt(snapshot.toggleModifierFlags)).intersection(.deviceIndependentFlagsMask)
                                
                                if type == .keyDown || type == .flagsChanged {
                                    let cleanNsFlags = nsFlags.subtracting(.capsLock)
                                    let cleanToggleFlags = toggleFlags.subtracting(.capsLock)
                                    
                                    if keyCode == snapshot.toggleKeyCode {
                                        if [57, 56, 60, 59, 62, 58, 61].contains(keyCode) {
                                            isLanguageSwitchKey = true
                                        } else if cleanNsFlags == cleanToggleFlags {
                                            isLanguageSwitchKey = true
                                        }
                                    }
                                    
                                    if keyCode == 49 {
                                        if cleanNsFlags == .command && snapshot.isCmdActive { isLanguageSwitchKey = true }
                                        if cleanNsFlags == .control && snapshot.isCtrlActive { isLanguageSwitchKey = true }
                                        if cleanNsFlags == .option && snapshot.isOptActive { isLanguageSwitchKey = true }
                                    }
                                }
                                
                                if !isLanguageSwitchKey {
                                    return Unmanaged.passUnretained(event)
                                }
                            }
                        }

                        // 텍스트 대치 및 스마트 자동 오타 교정 코어 엔진
                        if type == .keyDown {
                            if snapshot.isAutoTypoCorrectionEnabled || snapshot.isTextExpansionEnabled {
                                EventMonitor.shared.checkStaleAndResetBuffer()
                                let isEnterTrigger = snapshot.isAutoTypoCorrectionOnEnterEnabled && keyCode == 36
                                let flags = event.flags
                                let hasModifiers = flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate)
                                let isPureSpace = (keyCode == 49) && !hasModifiers

                                if isPureSpace || isEnterTrigger {
                                    let currentBuffer = EventMonitor.shared.typingBuffer

                                    if snapshot.isTextExpansionEnabled,
                                       let matchedRule = TextExpander.shared.findMatch(
                                            for: currentBuffer,
                                            dict: snapshot.textExpansionDict,
                                            maxLength: snapshot.maxTriggerLength
                                       ) {

                                        let renderedSnippet = TextExpander.shared.expand(template: matchedRule.replacement)
                                        EventMonitor.shared.performTextExpansion(triggerLength: matchedRule.trigger.count, snippet: renderedSnippet, triggerKeyCode: UInt16(keyCode))

                                        let cursorLog = renderedSnippet.cursorOffsetFromStart != nil ? " (Cursor Restored)" : ""
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
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            // 🌟 [교정] 타이머가 깨어날 때도 메인 액터 격리 상태를 증명하여 컴파일 에러 예방
            MainActor.assumeIsolated {
                guard let self = self else { return }
                if self.eventTap != nil && !self.isEnabled { CGEvent.tapEnable(tap: self.eventTap!, enable: true) }
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

    func targetLangIfPressed(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> String? {
        let snapshot = SettingsManager.shared.snapshot
        if keyCode == 49 {
            if flags == .control && snapshot.isCtrlActive { return snapshot.ctrlLang }
            if flags == .command && snapshot.isCmdActive { return snapshot.cmdLang }
            if flags == .option && snapshot.isOptActive { return snapshot.optLang }
        }
        return nil
    }
}
