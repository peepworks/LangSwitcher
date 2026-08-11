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

    var _typingBuffer: String = ""
    var _lastKeyTime: Date = Date()
    var _shortcutRecordingCallback: ((NSEvent) -> Void)? = nil
    var _currentModifiers: NSEvent.ModifierFlags = []
    var _maxModifiers: NSEvent.ModifierFlags = []
    var _didPressOtherKey = false
    var _singleModifierKeyCode: UInt16? = nil
    
    private let stateLock = NSLock()
    private var internalIsPaused: Bool = false
    
    var _isPaused: Bool {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return internalIsPaused
        }
        set {
            stateLock.lock()
            internalIsPaused = newValue
            stateLock.unlock()
        }
    }
    
    var _lastCapsLockTime: Date = Date.distantPast
    var _lastActionTime: Date = Date.distantPast
    let actionCooldown: TimeInterval = 0.15

    private var _cachedIsEnglish: Bool = true

    static let charKeyMap: [UInt16: Character] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v",
        11: "b", 12: "q", 13: "w", 14: "e", 15: "r", 16: "y", 17: "t", 31: "o",
        32: "u", 34: "i", 35: "p", 37: "l", 38: "j", 40: "k", 45: "n", 46: "m",
        41: ";", 44: "/", 47: ".", 43: ",", 39: "'", 33: "["
    ]

    var localSnapshot: SettingsSnapshot?
    let snapshotLock = NSLock()
    
    var snippetInsertionTask: Task<Void, Never>?

    private init() {
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                EventMonitor.shared.updateInputSourceCache()
            }
        }
        updateInputSourceCache()
    }

    private func updateInputSourceCache() {
        guard let currentSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(currentSource, kTISPropertyInputSourceID) else { return }
        let id = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
        let lower = id.lowercased()
        
        let isKorean = lower.contains("ko") || lower.contains("hangul") || lower.contains("두벌식") || lower.contains("3벌식") || lower.contains("세벌식")
        self._cachedIsEnglish = !isKorean
    }
    
    // 🌟 [수복 수용] Zero-Allocation 최적화가 적용된 실시간 물리 타자 언어 판독기
    @inline(__always)
    func updateRealTimeLanguage(from event: CGEvent) {
        // 1. 커맨드, 옵션, 컨트롤 단축키 입력 시 스킵하여 오버헤드 차단
        let flags = event.flags
        if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) {
            return
        }
        
        // 2. NSEvent/String 생성 없이 C-Style 유니코드 버퍼 직접 조회 (O(1) 메모리 Zero)
        let maxStringLength = 4 // 🌟 var -> let 으로 변경
        var actualStringLength = 0
        var unicodeChars = [UniChar](repeating: 0, count: maxStringLength)
        
        event.keyboardGetUnicodeString(maxStringLength: maxStringLength, actualStringLength: &actualStringLength, unicodeString: &unicodeChars)
        
        guard actualStringLength > 0 else { return }
        let charCode = unicodeChars[0]
        
        // 3. 한글 유니코드 스칼라 영역 판별
        let isHangul = (charCode >= 0xAC00 && charCode <= 0xD7A3) ||
                       (charCode >= 0x1100 && charCode <= 0x11FF) ||
                       (charCode >= 0x3130 && charCode <= 0x318F)
        
        // 영문 알파벳 범위 판별 (A-Z, a-z)
        let isEnglish = (charCode >= 0x41 && charCode <= 0x5A) || (charCode >= 0x61 && charCode <= 0x7A)
        
        if isHangul {
            self._cachedIsEnglish = false
        } else if isEnglish {
            self._cachedIsEnglish = true
        }
    }

    func isCurrentLanguageEnglish() -> Bool {
        return self._cachedIsEnglish
    }

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
                    guard Thread.isMainThread else { return Unmanaged.passUnretained(event) }
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

                        if IsSecureEventInputEnabled() {
                            return Unmanaged.passUnretained(event)
                        }

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

                        if type == .keyDown {
                            // 🌟 매 타자마다 최적화된 실시간 언어 판별기 호출
                            EventMonitor.shared.updateRealTimeLanguage(from: event)
                            
                            if snapshot.isAutoTypoCorrectionEnabled || snapshot.isTextExpansionEnabled {
                                EventMonitor.shared.checkStaleAndResetBuffer()
                                
                                let isEnterTrigger = snapshot.isAutoTypoCorrectionOnEnterEnabled && keyCode == 36
                                let flags = event.flags
                                let hasModifiers = flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate)
                                let isPureSpace = (keyCode == 49) && !hasModifiers

                                if isPureSpace || isEnterTrigger {
                                    let currentBuffer = EventMonitor.shared.typingBuffer

                                    // 1. 텍스트 스니펫 대치
                                    if snapshot.isTextExpansionEnabled {
                                        if let matchedRule = snapshot.textExpansionDict[currentBuffer] {
                                            EventMonitor.shared.performTextExpansion(
                                                triggerLength: matchedRule.trigger.count,
                                                template: matchedRule.replacement,
                                                triggerKeyCode: UInt16(keyCode),
                                                triggerText: matchedRule.trigger
                                            )

                                            EventMonitor.shared.clearTypingBuffer()
                                            return nil
                                        }
                                    }

                                    // 2. 스마트 자동 오타 교정
                                    if snapshot.isAutoTypoCorrectionEnabled && currentBuffer.count >= 2 {
                                        if EventMonitor.shared.isCurrentLanguageEnglish() {
                                            if let result = TypoConverter.shared.detectAndConvert(englishInput: currentBuffer) {
                                                
                                                EventMonitor.shared.performAutoCorrection(
                                                    originalLength: currentBuffer.count,
                                                    correctedText: result,
                                                    triggerKeyCode: UInt16(keyCode)
                                                )
                                                EventMonitor.shared.clearTypingBuffer()
                                                return nil
                                            }
                                        }
                                    }
                                    
                                    if isPureSpace {
                                        EventMonitor.shared.appendToTypingBuffer(" ")
                                    } else {
                                        EventMonitor.shared.clearTypingBuffer()
                                    }
                                }
                                else if keyCode == 51 {
                                    if !EventMonitor.shared._typingBuffer.isEmpty {
                                        EventMonitor.shared._typingBuffer.removeLast()
                                    }
                                }
                                else if (123...126).contains(keyCode) {
                                    EventMonitor.shared.clearTypingBuffer()
                                }
                                else {
                                    let charToAppend: Character? = EventMonitor.charKeyMap[UInt16(keyCode)] ?? {
                                        if let nsEvent = NSEvent(cgEvent: event), let chars = nsEvent.characters, let first = chars.first {
                                            return first
                                        }
                                        return nil
                                    }()

                                    if let char = charToAppend {
                                        if char.isLetter || char.isNumber || char.isPunctuation || char == ";" {
                                            EventMonitor.shared.appendToTypingBuffer(char)
                                        }
                                    }
                                }
                            }
                        }

                        if EventMonitor.shared._isPaused { return Unmanaged.passUnretained(event) }

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
        
        let timer = Timer(timeInterval: 5.0, repeats: true) { [weak self] _ in
            let _ = MainActor.assumeIsolated {
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
        RunLoop.main.add(timer, forMode: .common)
        self.healthCheckTimer = timer
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
