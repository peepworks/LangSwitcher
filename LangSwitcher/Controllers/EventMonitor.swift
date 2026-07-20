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

    // 🌟 [수복] 동시성 안전 가이드 및 상태값 정의
    var _typingBuffer: String = ""
    var _lastKeyTime: Date = Date()
    var _shortcutRecordingCallback: ((NSEvent) -> Void)? = nil
    var _currentModifiers: NSEvent.ModifierFlags = []
    var _maxModifiers: NSEvent.ModifierFlags = []
    var _didPressOtherKey = false
    var _singleModifierKeyCode: UInt16? = nil
    
    // 🌟 [충돌 회피 & 원자적 격리 락]
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

    // 🌟 TIS 조회를 방어하기 위한 언어 상태 캐시
    private var _cachedIsEnglish: Bool = true

    static let charKeyMap: [UInt16: Character] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v",
        11: "b", 12: "q", 13: "w", 14: "e", 15: "r", 16: "y", 17: "t", 31: "o",
        32: "u", 34: "i", 35: "p", 37: "l", 38: "j", 40: "k", 45: "n", 46: "m",
        41: ";", 44: "/", 47: ".", 43: ",", 39: "'", 33: "["
    ]

    var localSnapshot: SettingsSnapshot?
    let snapshotLock = NSLock()
    
    // 🌟 [수복] Simulation.swift에서 가로채서 취소할 수 있도록 private 제거 (internal로 변경)
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
        self._cachedIsEnglish = lower.contains("en") || lower.contains("abc") || lower.contains("us")
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
                            #if DEBUG
                            dprint("🔒 [EventMonitor] Secure Event Input 작동 중으로 키 인출이 잠시 보류되었습니다.")
                            #endif
                            return Unmanaged.passUnretained(event)
                        }

                        EventMonitor.shared.snapshotLock.lock()
                        guard let snapshot = EventMonitor.shared.localSnapshot else {
                            EventMonitor.shared.snapshotLock.unlock()
                            return Unmanaged.passUnretained(event)
                        }
                        EventMonitor.shared.snapshotLock.unlock()

                        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
                        let currentAppID = WorkspaceAppTracker.shared.activeBundleID
                        
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
                            if snapshot.isAutoTypoCorrectionEnabled || snapshot.isTextExpansionEnabled {
                                EventMonitor.shared.checkStaleAndResetBuffer()
                                
                                let isEnterTrigger = snapshot.isAutoTypoCorrectionOnEnterEnabled && keyCode == 36
                                let flags = event.flags
                                let hasModifiers = flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate)
                                let isPureSpace = (keyCode == 49) && !hasModifiers

                                if isPureSpace || isEnterTrigger {
                                    let currentBuffer = EventMonitor.shared.typingBuffer

                                    if snapshot.isTextExpansionEnabled {
                                        // 🌟 [수복] O(1) 해시 맵 즉시 매칭으로 루프 연산 비용 소각
                                        if let matchedRule = snapshot.textExpansionDict[currentBuffer] {
                                            
                                            // 🌟 [Hot Path 혁명] 비싼 템플릿 파싱(TextExpander.shared.expand)을
                                            // 동기 콜백에서 완전히 도려내고, 비동기 파이프라인으로 원문(replacement)만 넘깁니다.
                                            EventMonitor.shared.performTextExpansion(
                                                triggerLength: matchedRule.trigger.count,
                                                template: matchedRule.replacement, // 스니펫 템플릿 원문을 그대로 전달
                                                triggerKeyCode: UInt16(keyCode),
                                                triggerText: matchedRule.trigger
                                            )

                                            EventMonitor.shared.clearTypingBuffer()
                                            return nil // 이벤트 핫패스 즉시 탈출 (Timeout 위험률 0%)
                                        }
                                    }

                                    // 오토 코렉션 및 버퍼 비우기 트랙 (기존 유지하되 최소화)
                                    if snapshot.isAutoTypoCorrectionEnabled && currentBuffer.count >= 2 {
                                        if EventMonitor.shared.isCurrentLanguageEnglish(),
                                           let result = TypoConverter.shared.detectAndConvert(englishInput: currentBuffer) {
                                            
                                            // 🌟 [수복] result가 이미 완벽한 String이므로 불필요한 안전 가이드(as? String)를 완전히 소각합니다.
                                            let correctedText = result
                                            
                                            EventMonitor.shared.performAutoCorrection(originalLength: currentBuffer.count, correctedText: correctedText, triggerKeyCode: UInt16(keyCode))
                                            EventMonitor.shared.clearTypingBuffer()
                                            return nil
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
                                    if let nsEvent = NSEvent(cgEvent: event), let chars = nsEvent.characters, !chars.isEmpty {
                                        let char = chars.first!
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
