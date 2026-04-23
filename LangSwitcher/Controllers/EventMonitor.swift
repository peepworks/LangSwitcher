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

class EventMonitor {
    static let shared = EventMonitor()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private let stateQueue = DispatchQueue(label: "com.peepworks.langswitcher.state", attributes: .concurrent)

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

    private init() {}

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
    // -------------------------------------------------------------------------

    // MARK: - 기능별 분리된 이벤트 처리기
    
    private func handleFlagsChanged(event: CGEvent, keyCode: CGKeyCode, modifierFlags: NSEvent.ModifierFlags) -> Unmanaged<CGEvent>? {
        // 🌟 [리뷰 반영] 원본 대신 스레드 안전성이 보장된 스냅샷(읽기 전용)을 가져옵니다.
        let snapshot = SettingsManager.shared.snapshot
        
        var targetLang: String? = nil; var targetAppBundleID: String? = nil; var targetAppName: String? = nil
        var isToggle = false; var appliedRule = ""

        let flags = modifierFlags.intersection(.deviceIndependentFlagsMask)

        if keyCode == 57 {
            let now = Date()
            if now.timeIntervalSince(self.lastCapsLockTime) < 0.25 { return nil }
            self.lastCapsLockTime = now

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
        // 🌟 [리뷰 반영] 스레드 안전성이 보장된 스냅샷 가져오기
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
                // 🌟 [리뷰 반영] 하드코딩된 배열 대신 전역 상수 사용!
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
                let isSingleModifier = [54,55,56,60,58,61,59,62,57,63].contains(shortcut.keyCode) && shortcut.modifierFlags == 0
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
        if eventTap != nil { return }

        let eventMask = (1 << CGEventType.keyDown.rawValue) |
                        (1 << CGEventType.keyUp.rawValue) |
                        (1 << CGEventType.flagsChanged.rawValue) |
                        (1 << CGEventType.tapDisabledByTimeout.rawValue) |
                        (1 << CGEventType.tapDisabledByUserInput.rawValue)

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in

                if event.getIntegerValueField(.eventSourceUserData) == 9999 {
                    return Unmanaged.passUnretained(event)
                }

                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = EventMonitor.shared.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                    return nil
                }

                if let callback = EventMonitor.shared.shortcutRecordingCallback {
                    if type == .keyDown || type == .flagsChanged {
                        if let nsEvent = NSEvent(cgEvent: event) { DispatchQueue.main.async { callback(nsEvent) } }
                        return nil
                    }
                }
                
                let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
                
                // 🌟 [리뷰 반영] 스냅샷 기반 읽기
                let snapshot = SettingsManager.shared.snapshot
                
                if snapshot.isHyperKeyEnabled {
                    let shouldBlock = HyperKeyManager.shared.processEvent(type: type, event: event, keyCode: keyCode)
                    if shouldBlock { return nil }
                }

                let currentAppID = AppMonitor.shared.activeAppBundleID
                if !currentAppID.isEmpty {
                    if snapshot.excludedApps.contains(where: { $0.bundleIdentifier == currentAppID }) {
                        return Unmanaged.passUnretained(event)
                    }
                }

                if EventMonitor.shared.isPaused { return Unmanaged.passUnretained(event) }

                let nsModifierFlags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))

                if type == .flagsChanged {
                    return EventMonitor.shared.handleFlagsChanged(event: event, keyCode: keyCode, modifierFlags: nsModifierFlags)
                }

                if type == .keyDown {
                    return EventMonitor.shared.handleKeyDown(event: event, keyCode: keyCode, modifierFlags: nsModifierFlags)
                }
                
                return Unmanaged.passUnretained(event)
            }, userInfo: nil)

        if let tap = eventTap {
            runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource!, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes) }
        eventTap = nil; runLoopSource = nil
    }
    
    func cancelShortcutRecording() {
        stateQueue.async(flags: .barrier) {
            self._shortcutRecordingCallback = nil
            self._isPaused = false
        }
    }

    private static func executeAction(targetLang: String?, targetAppID: String?, targetAppName: String? = nil, isToggle: Bool, rule: String) {
        // addLog는 내부적으로 DispatchQueue.main.async를 쓰므로 안전합니다.
        if !AccessibilityManager.shared.isTrusted {
            SettingsManager.shared.addLog(ActionLog(timestamp: Date(), targetApp: "System", appliedRule: rule, finalInputSource: targetLang ?? "Unknown", result: .failure, failureReason: .permissionIssue))
            return
        }

        guard EventMonitor.shared.canExecuteAction() else { return }

        // 🌟 [리뷰 반영] 스냅샷 기반 읽기
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
}

// 🌟 [리뷰 반영] 중복되던 단축키 녹화 로직을 하나로 통합한 공용 매니저 클래스
class ShortcutRecorder {
    static let shared = ShortcutRecorder()
    
    typealias Completion = (_ keyCode: UInt16, _ modifiers: UInt64, _ displayString: String) -> Void
    
    private var timeoutTask: DispatchWorkItem?
    
    private init() {}
    
    func startRecording(completion: @escaping Completion, onTimeout: @escaping () -> Void) {
        EventMonitor.shared.isPaused = true
        
        timeoutTask?.cancel()
        let task = DispatchWorkItem {
            self.stopRecording()
            onTimeout()
        }
        self.timeoutTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: task)

        // 상태를 안전하게 관리하기 위해 내부에 struct나 로컬 변수 사용
        class RState { var m = Set<UInt16>(); var f: NSEvent.ModifierFlags = []; var r = false }
        let state = RState()

        EventMonitor.shared.shortcutRecordingCallback = { e in
            let code = e.keyCode
            let flags = e.modifierFlags.intersection(.deviceIndependentFlagsMask)

            if e.type == .flagsChanged {
                let capturedCode = code
                if capturedCode == 57 {
                    DispatchQueue.main.async { completion(57, 0, "⇪ Caps Lock") }
                    return
                }
                
                if !flags.isEmpty { state.m.insert(capturedCode); state.f.formUnion(flags); return }
                else if !state.r && !state.m.isEmpty {
                    if state.m.count == 1 {
                        let c = state.m.first!
                        let str = [54:"Right ⌘", 55:"Left ⌘", 56:"Left ⇧", 60:"Right ⇧", 58:"Left ⌥", 61:"Right ⌥", 59:"Left ⌃", 62:"Right ⌃", 63:"fn"][c] ?? "Mod(\(c))"
                        let capturedC = c
                        DispatchQueue.main.async { completion(capturedC, 0, str) }
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
                state.r = true
                var str = ""
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
