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
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var healthCheckTimer: Timer?
    
    // 🌟 [수정 3] 옵저버를 등록했던 정확한 RunLoop를 기억하기 위한 영수증 변수
    private var eventRunLoop: CFRunLoop?
        
    var isEnabled: Bool {
        guard let tap = eventTap else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    private let stateQueue = DispatchQueue(label: "com.peepworks.langswitcher.state", attributes: .concurrent)

    private var _typingBuffer: String = ""
    var typingBuffer: String {
        get { stateQueue.sync { _typingBuffer } }
        set { stateQueue.async(flags: .barrier) { self._typingBuffer = newValue } }
    }
    
    private var _lastKeyTime: Date = Date()
    var lastKeyTime: Date {
        get { stateQueue.sync { _lastKeyTime } }
        set { stateQueue.async(flags: .barrier) { self._lastKeyTime = newValue } }
    }

    private var _shortcutRecordingCallback: ((NSEvent) -> Void)? = nil
    var shortcutRecordingCallback: ((NSEvent) -> Void)? {
        get { stateQueue.sync { _shortcutRecordingCallback } }
        set { stateQueue.async(flags: .barrier) { self._shortcutRecordingCallback = newValue } }
    }

    private var _currentModifiers: NSEvent.ModifierFlags = []
    var currentModifiers: NSEvent.ModifierFlags {
        get { stateQueue.sync { _currentModifiers } }
        set { stateQueue.async(flags: .barrier) { self._currentModifiers = newValue } }
    }

    private var _maxModifiers: NSEvent.ModifierFlags = []
    var maxModifiers: NSEvent.ModifierFlags {
        get { stateQueue.sync { _maxModifiers } }
        set { stateQueue.async(flags: .barrier) { self._maxModifiers = newValue } }
    }

    private var _didPressOtherKey = false
    var didPressOtherKey: Bool {
        get { stateQueue.sync { _didPressOtherKey } }
        set { stateQueue.async(flags: .barrier) { self._didPressOtherKey = newValue } }
    }

    private var _singleModifierKeyCode: UInt16? = nil
    var singleModifierKeyCode: UInt16? {
        get { stateQueue.sync { _singleModifierKeyCode } }
        set { stateQueue.async(flags: .barrier) { self._singleModifierKeyCode = newValue } }
    }

    private var _isPaused = false
    var isPaused: Bool {
        get { stateQueue.sync { _isPaused } }
        set { stateQueue.async(flags: .barrier) { self._isPaused = newValue } }
    }

    private var _lastCapsLockTime: Date = Date.distantPast
    var lastCapsLockTime: Date {
        get { stateQueue.sync { _lastCapsLockTime } }
        set { stateQueue.async(flags: .barrier) { self._lastCapsLockTime = newValue } }
    }

    private var _lastActionTime: Date = Date.distantPast
    private let actionCooldown: TimeInterval = 0.15
    
    // 🌟 [수정 2] 매번 할당되던 딕셔너리를 메모리에 한 번만 올려두는 전역 상수로 변경 (성능 극대화)
    private static let charKeyMap: [UInt16: Character] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v",
        11: "b", 12: "q", 13: "w", 14: "e", 15: "r", 16: "y", 17: "t", 31: "o",
        32: "u", 34: "i", 35: "p", 37: "l", 38: "j", 40: "k", 45: "n", 46: "m"
    ]

    private init() {}

    // MARK: - 스레드 안전성을 완벽 보장하는 버퍼 조작 헬퍼 함수들
    
    func appendToTypingBuffer(_ char: Character) {
        stateQueue.async(flags: .barrier) {
            self._typingBuffer.append(char)
            if self._typingBuffer.count > 15 {
                self._typingBuffer.removeFirst()
            }
        }
    }
    
    func clearTypingBuffer() {
        stateQueue.async(flags: .barrier) {
            self._typingBuffer = ""
        }
    }
    
    func checkStaleAndResetBuffer() {
        stateQueue.async(flags: .barrier) {
            let now = Date()
            if now.timeIntervalSince(self._lastKeyTime) > 2.0 {
                self._typingBuffer = ""
            }
            self._lastKeyTime = now
        }
    }
    
    // MARK: - 캡스락 디바운스를 위한 완벽한 스레드 안전 헬퍼 함수
    func shouldDebounceCapsLock() -> Bool {
        var shouldBlock = false
        stateQueue.sync(flags: .barrier) {
            let now = Date()
            if now.timeIntervalSince(self._lastCapsLockTime) < 0.25 {
                shouldBlock = true
            } else {
                self._lastCapsLockTime = now
                shouldBlock = false
            }
        }
        return shouldBlock
    }

    // MARK: - 언어 감지 및 안전한 전환 헬퍼
    
    private func isCurrentLanguageEnglish() -> Bool {
        guard let currentSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(currentSource, kTISPropertyInputSourceID) else { return false }
        let id = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
        let lower = id.lowercased()
        return lower.contains("en") || lower.contains("abc") || lower.contains("us")
    }

    private func safeSwitchToKorean() {
        let filter: NSDictionary = [
            (kTISPropertyInputSourceType as String): (kTISTypeKeyboardLayout as String)
        ]
        
        guard let list = TISCreateInputSourceList(filter as CFDictionary, false)?.takeRetainedValue() as? [TISInputSource] else { return }

        for source in list {
            if let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
                let id = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
                let lower = id.lowercased()
                if lower.contains("ko") || lower.contains("hangul") || lower.contains("두벌식") || lower.contains("세벌식") {
                    TISSelectInputSource(source)
                    SensoryFeedbackManager.shared.playFeedback(forLanguageID: id)
                    break
                }
            }
        }
    }

    // MARK: - Atomic State Updates
    
    func updateModifierState(keyCode: UInt16, flags: NSEvent.ModifierFlags) {
        stateQueue.async(flags: .barrier) {
            if self._currentModifiers.isEmpty {
                self._didPressOtherKey = false
                self._singleModifierKeyCode = keyCode
                self._currentModifiers = flags
                self._maxModifiers = flags
            } else {
                self._singleModifierKeyCode = nil
                self._currentModifiers = flags
                self._maxModifiers.formUnion(flags)
            }
        }
    }

    func consumeModifierState() -> (didPressOtherKey: Bool, singleCode: UInt16?, maxMods: NSEvent.ModifierFlags) {
        var snapshot: (Bool, UInt16?, NSEvent.ModifierFlags) = (false, nil, [])
        stateQueue.sync(flags: .barrier) {
            snapshot = (self._didPressOtherKey, self._singleModifierKeyCode, self._maxModifiers)
            self._currentModifiers = []
            self._maxModifiers = []
            self._singleModifierKeyCode = nil
        }
        return snapshot
    }

    func markOtherKeyPressed() {
        stateQueue.async(flags: .barrier) {
            self._didPressOtherKey = true
            self._singleModifierKeyCode = nil
        }
    }

    func canExecuteAction() -> Bool {
        var allowed = false
        stateQueue.sync(flags: .barrier) {
            let now = Date()
            if now.timeIntervalSince(self._lastActionTime) >= self.actionCooldown {
                self._lastActionTime = now
                allowed = true
            }
        }
        return allowed
    }

    // MARK: - 기능별 분리된 이벤트 처리기
    
    private func handleFlagsChanged(event: CGEvent, keyCode: CGKeyCode, modifierFlags: NSEvent.ModifierFlags) -> Unmanaged<CGEvent>? {
        let snapshot = SettingsManager.shared.snapshot
        var targetLang: String? = nil; var targetAppBundleID: String? = nil; var targetAppName: String? = nil
        var isToggle = false; var appliedRule = ""
        let flags = modifierFlags.intersection(.deviceIndependentFlagsMask)

        if keyCode == 57 {
            if EventMonitor.shared.shouldDebounceCapsLock() { return nil }

            if snapshot.isTypoCorrectionEnabled && snapshot.typoModifierFlags == 0 && snapshot.typoKeyCode == 57 && !snapshot.typoDisplayString.isEmpty {
                DispatchQueue.global(qos: .userInitiated).async { TypoConverter.shared.executeCorrection() }
                return nil
            }

            if snapshot.toggleModifierFlags == 0 && snapshot.toggleKeyCode == 57 && !snapshot.toggleDisplayString.isEmpty {
                isToggle = true; appliedRule = "Toggle Key"
            } else {
                if snapshot.isAppLaunchEnabled {
                    for appLaunch in snapshot.appLaunchShortcuts where appLaunch.modifierFlags == 0 && appLaunch.keyCode == 57 && !appLaunch.displayString.isEmpty { targetAppBundleID = appLaunch.bundleIdentifier; targetAppName = appLaunch.appName; appliedRule = "App Launch"; break }
                }
                if targetAppBundleID == nil && snapshot.isCustomShortcutsEnabled {
                    for shortcut in snapshot.customShortcuts where shortcut.modifierFlags == 0 && shortcut.keyCode == 57 && !shortcut.displayString.isEmpty { targetLang = shortcut.targetLanguage; appliedRule = "Custom Shortcut"; break }
                }
            }
        } else {
            if !flags.isEmpty {
                self.updateModifierState(keyCode: keyCode, flags: flags)
            } else {
                let stateSnap = self.consumeModifierState()
                
                if !stateSnap.didPressOtherKey {
                    if let singleCode = stateSnap.singleCode {
                        if snapshot.isTypoCorrectionEnabled && snapshot.typoModifierFlags == 0 && snapshot.typoKeyCode == singleCode && !snapshot.typoDisplayString.isEmpty {
                            DispatchQueue.global(qos: .userInitiated).async { TypoConverter.shared.executeCorrection() }
                            return nil
                        }

                        if snapshot.toggleModifierFlags == 0 && snapshot.toggleKeyCode == singleCode && !snapshot.toggleDisplayString.isEmpty {
                            isToggle = true; appliedRule = "Toggle Key"
                        } else {
                            if snapshot.isAppLaunchEnabled {
                                for appLaunch in snapshot.appLaunchShortcuts where appLaunch.modifierFlags == 0 && appLaunch.keyCode == singleCode && !appLaunch.displayString.isEmpty { targetAppBundleID = appLaunch.bundleIdentifier; targetAppName = appLaunch.appName; appliedRule = "App Launch"; break }
                            }
                            if targetAppBundleID == nil && snapshot.isCustomShortcutsEnabled {
                                for shortcut in snapshot.customShortcuts where shortcut.modifierFlags == 0 && shortcut.keyCode == singleCode && !shortcut.displayString.isEmpty { targetLang = shortcut.targetLanguage; appliedRule = "Custom Shortcut"; break }
                            }
                        }
                    } else if !stateSnap.maxMods.isEmpty {
                        let modsRaw = UInt64(stateSnap.maxMods.rawValue)

                        if snapshot.isTypoCorrectionEnabled && snapshot.typoKeyCode == 0 && snapshot.typoModifierFlags == modsRaw && !snapshot.typoDisplayString.isEmpty {
                            DispatchQueue.global(qos: .userInitiated).async { TypoConverter.shared.executeCorrection() }
                            return nil
                        }

                        if snapshot.toggleKeyCode == 0 && snapshot.toggleModifierFlags == modsRaw && !snapshot.toggleDisplayString.isEmpty {
                            isToggle = true; appliedRule = "Toggle Key"
                        } else {
                            if snapshot.isAppLaunchEnabled {
                                for appLaunch in snapshot.appLaunchShortcuts where appLaunch.keyCode == 0 && appLaunch.modifierFlags == modsRaw && !appLaunch.displayString.isEmpty { targetAppBundleID = appLaunch.bundleIdentifier; targetAppName = appLaunch.appName; appliedRule = "App Launch"; break }
                            }
                            if targetAppBundleID == nil && snapshot.isCustomShortcutsEnabled {
                                for shortcut in snapshot.customShortcuts where shortcut.keyCode == 0 && shortcut.modifierFlags == modsRaw && !shortcut.displayString.isEmpty { targetLang = shortcut.targetLanguage; appliedRule = "Custom Shortcut"; break }
                            }
                        }
                    }
                }
            }
        }
        
        if isToggle || targetAppBundleID != nil || targetLang != nil {
            EventMonitor.executeAction(targetLang: targetLang, targetAppID: targetAppBundleID, targetAppName: targetAppName, isToggle: isToggle, rule: appliedRule)
            if keyCode == 57 { return nil }
            return Unmanaged.passUnretained(event)
        }
        return Unmanaged.passUnretained(event)
    }

    private func handleKeyDown(event: CGEvent, keyCode: CGKeyCode, modifierFlags: NSEvent.ModifierFlags) -> Unmanaged<CGEvent>? {
        let snapshot = SettingsManager.shared.snapshot
        var targetLang: String? = nil; var targetAppBundleID: String? = nil; var targetAppName: String? = nil
        var isToggle = false; var appliedRule = ""

        self.markOtherKeyPressed()
        let flags = modifierFlags.intersection([.command, .control, .option, .shift])

        if snapshot.isTypoCorrectionEnabled &&
           snapshot.typoKeyCode == keyCode &&
           NSEvent.ModifierFlags(rawValue: UInt(snapshot.typoModifierFlags)).intersection([.command, .control, .option, .shift]) == flags &&
           !snapshot.typoDisplayString.isEmpty {
            DispatchQueue.global(qos: .userInitiated).async { TypoConverter.shared.executeCorrection() }
            return nil
        }

        if snapshot.toggleKeyCode == keyCode && !snapshot.toggleDisplayString.isEmpty {
            let savedModifierFlags = NSEvent.ModifierFlags(rawValue: UInt(snapshot.toggleModifierFlags)).intersection([.command, .control, .option, .shift])
            if flags == savedModifierFlags { isToggle = true; appliedRule = "Toggle Key" }
        }

        if !isToggle && snapshot.isAppLaunchEnabled {
            for appLaunch in snapshot.appLaunchShortcuts {
                let isSingleModifier = globalModifierKeyCodes.contains(appLaunch.keyCode) && appLaunch.modifierFlags == 0
                let isMultiModifierOnly = appLaunch.keyCode == 0 && appLaunch.modifierFlags != 0
                if !isSingleModifier && !isMultiModifierOnly {
                    if appLaunch.keyCode == keyCode && !appLaunch.displayString.isEmpty {
                        let savedModifierFlags = NSEvent.ModifierFlags(rawValue: UInt(appLaunch.modifierFlags)).intersection([.command, .control, .option, .shift])
                        if flags == savedModifierFlags { targetAppBundleID = appLaunch.bundleIdentifier; targetAppName = appLaunch.appName; appliedRule = "App Launch"; break }
                    }
                }
            }
        }

        if !isToggle && targetAppBundleID == nil && snapshot.isCustomShortcutsEnabled {
            for shortcut in snapshot.customShortcuts {
                let isSingleModifier = globalModifierKeyCodes.contains(shortcut.keyCode) && shortcut.modifierFlags == 0
                let isMultiModifierOnly = shortcut.keyCode == 0 && shortcut.modifierFlags != 0
                if !isSingleModifier && !isMultiModifierOnly {
                    if shortcut.keyCode == keyCode && !shortcut.displayString.isEmpty {
                        let savedModifierFlags = NSEvent.ModifierFlags(rawValue: UInt(shortcut.modifierFlags)).intersection([.command, .control, .option, .shift])
                        if flags == savedModifierFlags { targetLang = shortcut.targetLanguage; appliedRule = "Custom Shortcut"; break }
                    }
                }
            }
        }

        if !isToggle && targetAppBundleID == nil && targetLang == nil && keyCode == 49 {
            if flags == .control && snapshot.isCtrlActive { targetLang = snapshot.ctrlLang; appliedRule = "Default Shortcut" }
            else if flags == .command && snapshot.isCmdActive { targetLang = snapshot.cmdLang; appliedRule = "Default Shortcut" }
            else if flags == .option && snapshot.isOptActive { targetLang = snapshot.optLang; appliedRule = "Default Shortcut" }
        }

        if isToggle || targetAppBundleID != nil || targetLang != nil {
            EventMonitor.executeAction(targetLang: targetLang, targetAppID: targetAppBundleID, targetAppName: targetAppName, isToggle: isToggle, rule: appliedRule)
            if isToggle { return nil }
            return Unmanaged.passUnretained(event)
        }
        return Unmanaged.passUnretained(event)
    }

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
                    if let tap = EventMonitor.shared.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                    return nil
                }

                let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
                let snapshot = SettingsManager.shared.snapshot

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
                        
                        if keyCode == 49 || isEnterTrigger {
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
            // 🌟 [수정 3] 등록한 컨베이어 벨트를 기억해 둡니다.
            self.eventRunLoop = currentRL
            
            CGEvent.tapEnable(tap: tap, enable: true)
            startHealthCheck()
        }
    }

    private func startHealthCheck() {
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
        
        // 🌟 [수정 3] 영수증(eventRunLoop)을 보고 정확한 컨베이어 벨트에서 찾아 지웁니다.
        if let source = runLoopSource, let rl = eventRunLoop {
            CFRunLoopRemoveSource(rl, source, .commonModes)
        }
        
        eventTap = nil
        runLoopSource = nil
        eventRunLoop = nil
    }
    
    func cancelShortcutRecording() {
        stateQueue.async(flags: .barrier) {
            self._shortcutRecordingCallback = nil
            self._isPaused = false
        }
    }

    private static func executeAction(targetLang: String?, targetAppID: String?, targetAppName: String? = nil, isToggle: Bool, rule: String) {
        if !AccessibilityManager.shared.isTrusted {
            SettingsManager.shared.addLog(ActionLog(timestamp: Date(), targetApp: "System", appliedRule: rule, finalInputSource: targetLang ?? "Unknown", result: .failure, failureReason: .permissionIssue))
            return
        }

        guard EventMonitor.shared.canExecuteAction() else { return }

        let snapshot = SettingsManager.shared.snapshot
        if snapshot.isTestMode {
            var testLabel = ""
            if isToggle { testLabel = "[Test] Toggle Language" }
            else if let appName = targetAppName { testLabel = "[Test] \(appName)" }
            else if let langID = targetLang { testLabel = "[Test] \(InputSourceManager.shared.availableKeyboards.first(where: { $0.id == langID })?.name ?? langID)" }
            if !testLabel.isEmpty { DispatchQueue.main.async { HUDManager.shared.showHUD(languageName: testLabel) } }
        } else {
            if isToggle { DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { InputSourceManager.shared.switchToNextInputSource() } }
            else if let bundleID = targetAppID { launchApp(bundleID: bundleID) }
            else if let lang = targetLang { DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { InputSourceManager.shared.switchLanguage(to: lang) } }
        }
    }

    private static func launchApp(bundleID: String) {
        DispatchQueue.main.async {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                let config = NSWorkspace.OpenConfiguration()
                NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: nil)
            }
        }
    }
    
    private func performAutoCorrection(originalLength: Int, correctedText: String, triggerKeyCode: UInt16) {
        DispatchQueue.global(qos: .userInteractive).async {
            for _ in 0..<originalLength {
                let deleteDown = CGEvent(keyboardEventSource: nil, virtualKey: 51, keyDown: true)
                let deleteUp = CGEvent(keyboardEventSource: nil, virtualKey: 51, keyDown: false)
                deleteDown?.setIntegerValueField(.eventSourceUserData, value: 9999)
                deleteUp?.setIntegerValueField(.eventSourceUserData, value: 9999)
                deleteDown?.post(tap: .cghidEventTap)
                deleteUp?.post(tap: .cghidEventTap)
                Thread.sleep(forTimeInterval: 0.002)
            }
            
            Thread.sleep(forTimeInterval: 0.01)
            
            var chars = Array(correctedText.utf16)
            if !chars.isEmpty {
                let textEvent = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)
                textEvent?.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: &chars)
                textEvent?.setIntegerValueField(.eventSourceUserData, value: 9999)
                textEvent?.post(tap: .cghidEventTap)
            }
            
            Thread.sleep(forTimeInterval: 0.015)
            
            // 🌟 [수정 1] 비동기(async) 추측 대신, 완벽하게 전환이 끝날 때까지 동기식(sync)으로 대기합니다.
            DispatchQueue.main.sync {
                EventMonitor.shared.safeSwitchToKorean()
            }
            
            Thread.sleep(forTimeInterval: 0.015)
            
            let triggerDown = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(triggerKeyCode), keyDown: true)
            let triggerUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(triggerKeyCode), keyDown: false)
            triggerDown?.setIntegerValueField(.eventSourceUserData, value: 9999)
            triggerUp?.setIntegerValueField(.eventSourceUserData, value: 9999)
            triggerDown?.post(tap: .cghidEventTap)
            triggerUp?.post(tap: .cghidEventTap)
        }
    }
    
    // 🌟 [수정 2] 전역 상수를 사용하여 더 이상 무거운 딕셔너리를 매번 만들지 않습니다.
    private func getCharacter(from keyCode: UInt16) -> Character? {
        return Self.charKeyMap[keyCode]
    }
}

class ShortcutRecorder {
    static let shared = ShortcutRecorder()
    typealias Completion = (_ keyCode: UInt16, _ modifiers: UInt64, _ displayString: String) -> Void
    private var timeoutTask: DispatchWorkItem?
    private init() {}
    
    func startRecording(completion: @escaping Completion, onTimeout: @escaping () -> Void) {
        EventMonitor.shared.isPaused = true
        timeoutTask?.cancel()
        
        // 🌟 [핵심 수정] [weak self]를 사용하여 타이머 클로저가 self(ShortcutRecorder)를 강하게 붙잡지 않도록(메모리 얽힘 방지) 수정합니다.
        let task = DispatchWorkItem { [weak self] in
            self?.stopRecording()
            onTimeout()
        }
        
        self.timeoutTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: task)

        class RState { var m = Set<UInt16>(); var f: NSEvent.ModifierFlags = []; var r = false }
        let state = RState()

        EventMonitor.shared.shortcutRecordingCallback = { e in
            let code = e.keyCode
            let flags = e.modifierFlags.intersection(.deviceIndependentFlagsMask)

            if e.type == .flagsChanged {
                let capturedCode = code
                if capturedCode == 57 { DispatchQueue.main.async { completion(57, 0, "⇪ Caps Lock") }; return }
                
                if !flags.isEmpty { state.m.insert(capturedCode); state.f.formUnion(flags); return }
                else if !state.r && !state.m.isEmpty {
                    if state.m.count == 1 {
                        let c = state.m.first!
                        let str = [54:"Right ⌘", 55:"Left ⌘", 56:"Left ⇧", 60:"Right ⇧", 58:"Left ⌥", 61:"Right ⌥", 59:"Left ⌃", 62:"Right ⌃", 63:"fn"][c] ?? "Mod(\(c))"
                        let capturedC = c; DispatchQueue.main.async { completion(capturedC, 0, str) }
                    } else {
                        var str = ""
                        if state.f.contains(.control) { str += "⌃ " }
                        if state.f.contains(.option) { str += "⌥ " }
                        if state.f.contains(.shift) { str += "⇧ " }
                        if state.f.contains(.command) { str += "⌘ " }
                        let capturedMods = UInt64(state.f.rawValue)
                        DispatchQueue.main.async { completion(0, capturedMods, str.trimmingCharacters(in: .whitespaces)) }
                    }
                    return
                }
                state.m.removeAll(); state.f = []; state.r = false; return
            } else if e.type == .keyDown {
                state.r = true; var str = ""
                if flags.contains(.control) { str += "⌃ " }
                if flags.contains(.option) { str += "⌥ " }
                if flags.contains(.shift) { str += "⇧ " }
                if flags.contains(.command) { str += "⌘ " }

                let capturedCode = code
                if capturedCode == 49 { str += "Space" }
                else if let mapped = globalKeyMap[capturedCode] { str += mapped }
                else if let chars = e.charactersIgnoringModifiers?.uppercased(), !chars.isEmpty { str += chars }
                else { str += "Key(\(capturedCode))" }

                let capturedMods = UInt64(flags.rawValue)
                DispatchQueue.main.async { completion(capturedCode, capturedMods, str) }
                return
            }
        }
    }
    
    func stopRecording() {
        timeoutTask?.cancel()
        EventMonitor.shared.cancelShortcutRecording()
    }
}
