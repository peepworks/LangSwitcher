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
                        (1 << CGEventType.leftMouseDown.rawValue) | // 🌟 안전장치: 마우스 클릭 감지 추가
                        (1 << CGEventType.tapDisabledByTimeout.rawValue) |
                        (1 << CGEventType.tapDisabledByUserInput.rawValue)

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in

                return autoreleasepool {
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

                        // 🌟 [수복 1] 시스템 긴급 제어는 어떤 예외 상황에서도 무조건 1순위로 작동해야 하므로 최상단으로 끌어올립니다.
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

                        // 🌟 [수복 2] Caps Lock (Hyper Key) 엔진 역시 예외 앱 화면인지 아닌지 따지지 않고 상시 동작하도록 위로 올립니다.
                        if snapshot.isHyperKeyEnabled {
                            if HyperKeyManager.shared.processEvent(type: type, event: event, keyCode: keyCode) { return nil }
                        }

                        // 3. 단축키 레코더 가로채기 (설정 화면 UI 보호용)
                        if let callback = EventMonitor.shared.shortcutRecordingCallback {
                            if type == .keyDown || type == .flagsChanged {
                                if let nsEvent = NSEvent(cgEvent: event) {
                                    DispatchQueue.main.async { callback(nsEvent) }
                                }
                                return nil
                            }
                        }

                        let isSimulated = event.getIntegerValueField(.eventSourceUserData) == 9999

                        // 🌟 [핵심 수복: 무한 루프 차단] 앱이 스스로 발생시킨 가상 이벤트는
                        // 장부를 오염시키거나 재귀에 빠지지 않도록 즉시 그대로 통과(Bypass)시킵니다.
                        if isSimulated {
                            return Unmanaged.passUnretained(event)
                        }

                        // 🌟 [수복 3] 예외 등록 앱 필터링 (한영 전환키 VIP 패스 로직 추가)
                        if snapshot.isExcludedAppsEnabled && !currentAppID.isEmpty {
                            if snapshot.excludedApps.contains(where: { $0.bundleIdentifier == currentAppID }) {
                                
                                var isLanguageSwitchKey = false
                                let nsFlags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue)).intersection(.deviceIndependentFlagsMask)
                                let toggleFlags = NSEvent.ModifierFlags(rawValue: UInt(snapshot.toggleModifierFlags)).intersection(.deviceIndependentFlagsMask)
                                
                                if type == .keyDown || type == .flagsChanged {
                                    // 🌟 [핵심 교정] CapsLock 상태가 섞여서 엄격한 비교가 실패하는 것을 막기 위해 캡스락 플래그를 걷어낸 순수 상태를 만듭니다.
                                    let cleanNsFlags = nsFlags.subtracting(.capsLock)
                                    let cleanToggleFlags = toggleFlags.subtracting(.capsLock)
                                    
                                    // A. 일반 설정에서 지정한 커스텀 입력소스 전환키 확인
                                    if keyCode == snapshot.toggleKeyCode {
                                        // 💡 CapsLock(57) 등 단일 수식어 자체가 전환키인 경우, 플래그 검사를 무시하고 무조건 VIP 패스 발급!
                                        if [57, 56, 60, 59, 62, 58, 61].contains(keyCode) {
                                            isLanguageSwitchKey = true
                                        } else if cleanNsFlags == cleanToggleFlags {
                                            isLanguageSwitchKey = true
                                        }
                                    }
                                    
                                    // B. 기본 조합(Cmd/Opt/Ctrl + Space) 한영 전환키 확인
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

                        // 8. 텍스트 대치(Snippets) 및 스마트 자동 오타 교정 코어 엔진
                        if type == .keyDown {
                            if snapshot.isAutoTypoCorrectionEnabled || snapshot.isTextExpansionEnabled {
                                EventMonitor.shared.checkStaleAndResetBuffer()
                                let isEnterTrigger = snapshot.isAutoTypoCorrectionOnEnterEnabled && keyCode == 36
                                let flags = event.flags
                                let hasModifiers = flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate)
                                let isPureSpace = (keyCode == 49) && !hasModifiers

                                if isPureSpace || isEnterTrigger {
                                    let currentBuffer = EventMonitor.shared.typingBuffer

                                    // 피처 A: 단어 기반 텍스트 확장
                                    if snapshot.isTextExpansionEnabled, // 🌟 'isTextExpansionEnabled'로 정정합니다.
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

                                    // 피처 B: 영→한 자동 오타 교정
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

                        // 9. 일시정지 상태 최종 플래그 검증
                        if EventMonitor.shared.isPaused { return Unmanaged.passUnretained(event) }

                        // 10. 수동 언어 전환 및 단축키 매칭 라우터 이관
                        // 🌟 [핵심 수복] 하위 함수들이 CapsLock 찌꺼기 때문에 엄격한 일치 검사(==)에서
                        // 튕겨내는 현상을 막기 위해, 캡스락 플래그를 완전히 세척하여 내려보냅니다.
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
