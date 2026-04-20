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

    // 🌟 일반 Caps Lock 모드에서의 더블 트리거 방지 쿨다운
    private var _lastCapsLockTime: Date = Date.distantPast
    var lastCapsLockTime: Date {
        get { stateQueue.sync { _lastCapsLockTime } }
        set { stateQueue.async(flags: .barrier) { self._lastCapsLockTime = newValue } }
    }

    private let cooldownLock = NSLock()
    private var lastActionTime: Date = Date.distantPast
    private let actionCooldown: TimeInterval = 0.15

    private init() {}

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

                // 🌟 [무한루프 방지] 가짜 이벤트(9999)는 즉시 통과!
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
                
                if SettingsManager.shared.isHyperKeyEnabled {
                    let shouldBlock = HyperKeyManager.shared.processEvent(type: type, event: event, keyCode: keyCode)
                    if shouldBlock { return nil }
                }

                let currentAppID = AppMonitor.shared.activeAppBundleID
                if !currentAppID.isEmpty {
                    if SettingsManager.shared.excludedApps.contains(where: { $0.bundleIdentifier == currentAppID }) {
                        return Unmanaged.passUnretained(event)
                    }
                }

                if EventMonitor.shared.isPaused { return Unmanaged.passUnretained(event) }

                let settings = SettingsManager.shared
                var targetLang: String? = nil; var targetAppBundleID: String? = nil; var targetAppName: String? = nil
                var isToggle = false
                var appliedRule = ""

                let nsModifierFlags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))

                if type == .flagsChanged {
                    let flags = nsModifierFlags.intersection(.deviceIndependentFlagsMask)

                    if keyCode == 57 {
                        // 🌟 [핵심 변경] HyperKey가 꺼진 상태에서의 Caps Lock (isDown 검사 삭제)
                        // Caps Lock은 누를 때만 신호가 오므로, 불이 켜지든 꺼지든 무조건 실행하되 0.25초 쿨다운만 적용
                        let now = Date()
                        if now.timeIntervalSince(EventMonitor.shared.lastCapsLockTime) < 0.25 { return nil }
                        EventMonitor.shared.lastCapsLockTime = now

                        if settings.isTypoCorrectionEnabled && settings.typoModifierFlags == 0 && settings.typoKeyCode == 57 && !settings.typoDisplayString.isEmpty {
                            DispatchQueue.global(qos: .userInitiated).async { TypoConverter.shared.executeCorrection() }
                            return nil
                        }

                        if settings.toggleModifierFlags == 0 && settings.toggleKeyCode == 57 && !settings.toggleDisplayString.isEmpty {
                            isToggle = true; appliedRule = "Toggle Key"
                        } else {
                            for appLaunch in settings.appLaunchShortcuts where appLaunch.modifierFlags == 0 && appLaunch.keyCode == 57 && !appLaunch.displayString.isEmpty { targetAppBundleID = appLaunch.bundleIdentifier; targetAppName = appLaunch.appName; appliedRule = "App Launch"; break }
                            if targetAppBundleID == nil { for shortcut in settings.customShortcuts where shortcut.modifierFlags == 0 && shortcut.keyCode == 57 && !shortcut.displayString.isEmpty { targetLang = shortcut.targetLanguage; appliedRule = "Custom Shortcut"; break } }
                        }
                    } else {
                        if !flags.isEmpty {
                            if EventMonitor.shared.currentModifiers.isEmpty {
                                EventMonitor.shared.didPressOtherKey = false; EventMonitor.shared.maxModifiers = []; EventMonitor.shared.singleModifierKeyCode = keyCode
                            } else {
                                EventMonitor.shared.singleModifierKeyCode = nil
                            }
                            EventMonitor.shared.currentModifiers = flags; EventMonitor.shared.maxModifiers.formUnion(flags)
                        } else {
                            if !EventMonitor.shared.didPressOtherKey {
                                if let singleCode = EventMonitor.shared.singleModifierKeyCode {
                                    if settings.isTypoCorrectionEnabled && settings.typoModifierFlags == 0 && settings.typoKeyCode == singleCode && !settings.typoDisplayString.isEmpty {
                                        DispatchQueue.global(qos: .userInitiated).async { TypoConverter.shared.executeCorrection() }
                                        EventMonitor.shared.currentModifiers = []; EventMonitor.shared.maxModifiers = []; EventMonitor.shared.singleModifierKeyCode = nil
                                        return nil
                                    }

                                    if settings.toggleModifierFlags == 0 && settings.toggleKeyCode == singleCode && !settings.toggleDisplayString.isEmpty {
                                        isToggle = true; appliedRule = "Toggle Key"
                                    } else {
                                        for appLaunch in settings.appLaunchShortcuts where appLaunch.modifierFlags == 0 && appLaunch.keyCode == singleCode && !appLaunch.displayString.isEmpty { targetAppBundleID = appLaunch.bundleIdentifier; targetAppName = appLaunch.appName; appliedRule = "App Launch"; break }
                                        if targetAppBundleID == nil { for shortcut in settings.customShortcuts where shortcut.modifierFlags == 0 && shortcut.keyCode == singleCode && !shortcut.displayString.isEmpty { targetLang = shortcut.targetLanguage; appliedRule = "Custom Shortcut"; break } }
                                    }
                                } else if !EventMonitor.shared.maxModifiers.isEmpty {
                                    let modsRaw = UInt64(EventMonitor.shared.maxModifiers.rawValue)

                                    if settings.isTypoCorrectionEnabled && settings.typoKeyCode == 0 && settings.typoModifierFlags == modsRaw && !settings.typoDisplayString.isEmpty {
                                        DispatchQueue.global(qos: .userInitiated).async { TypoConverter.shared.executeCorrection() }
                                        EventMonitor.shared.currentModifiers = []; EventMonitor.shared.maxModifiers = []; EventMonitor.shared.singleModifierKeyCode = nil
                                        return nil
                                    }

                                    if settings.toggleKeyCode == 0 && settings.toggleModifierFlags == modsRaw && !settings.toggleDisplayString.isEmpty {
                                        isToggle = true; appliedRule = "Toggle Key"
                                    } else {
                                        for appLaunch in settings.appLaunchShortcuts where appLaunch.keyCode == 0 && appLaunch.modifierFlags == modsRaw && !appLaunch.displayString.isEmpty { targetAppBundleID = appLaunch.bundleIdentifier; targetAppName = appLaunch.appName; appliedRule = "App Launch"; break }
                                        if targetAppBundleID == nil { for shortcut in settings.customShortcuts where shortcut.keyCode == 0 && shortcut.modifierFlags == modsRaw && !shortcut.displayString.isEmpty { targetLang = shortcut.targetLanguage; appliedRule = "Custom Shortcut"; break } }
                                    }
                                }
                            }
                            EventMonitor.shared.currentModifiers = []; EventMonitor.shared.maxModifiers = []; EventMonitor.shared.singleModifierKeyCode = nil
                        }
                    }
                    if isToggle || targetAppBundleID != nil || targetLang != nil {
                        EventMonitor.executeAction(targetLang: targetLang, targetAppID: targetAppBundleID, targetAppName: targetAppName, isToggle: isToggle, rule: appliedRule)
                        if keyCode == 57 { return nil }
                        return Unmanaged.passUnretained(event)
                    }
                }

                if type == .keyDown {
                    EventMonitor.shared.didPressOtherKey = true; EventMonitor.shared.singleModifierKeyCode = nil
                    let modifierFlags = nsModifierFlags.intersection([.command, .control, .option, .shift])

                    if settings.isTypoCorrectionEnabled &&
                       settings.typoKeyCode == keyCode &&
                       NSEvent.ModifierFlags(rawValue: UInt(settings.typoModifierFlags)).intersection([.command, .control, .option, .shift]) == modifierFlags &&
                       !settings.typoDisplayString.isEmpty {
                        DispatchQueue.global(qos: .userInitiated).async { TypoConverter.shared.executeCorrection() }
                        return nil
                    }

                    if settings.toggleKeyCode == keyCode && !settings.toggleDisplayString.isEmpty {
                        let savedModifierFlags = NSEvent.ModifierFlags(rawValue: UInt(settings.toggleModifierFlags)).intersection([.command, .control, .option, .shift])
                        if modifierFlags == savedModifierFlags { isToggle = true; appliedRule = "Toggle Key" }
                    }

                    if !isToggle {
                        for appLaunch in settings.appLaunchShortcuts {
                            let isSingleModifier = [54,55,56,60,58,61,59,62,57,63].contains(appLaunch.keyCode) && appLaunch.modifierFlags == 0
                            let isMultiModifierOnly = appLaunch.keyCode == 0 && appLaunch.modifierFlags != 0
                            if !isSingleModifier && !isMultiModifierOnly {
                                if appLaunch.keyCode == keyCode && !appLaunch.displayString.isEmpty {
                                    let savedModifierFlags = NSEvent.ModifierFlags(rawValue: UInt(appLaunch.modifierFlags)).intersection([.command, .control, .option, .shift])
                                    if modifierFlags == savedModifierFlags { targetAppBundleID = appLaunch.bundleIdentifier; targetAppName = appLaunch.appName; appliedRule = "App Launch"; break }
                                }
                            }
                        }
                    }

                    if !isToggle && targetAppBundleID == nil {
                        for shortcut in settings.customShortcuts {
                            let isSingleModifier = [54,55,56,60,58,61,59,62,57,63].contains(shortcut.keyCode) && shortcut.modifierFlags == 0
                            let isMultiModifierOnly = shortcut.keyCode == 0 && shortcut.modifierFlags != 0
                            if !isSingleModifier && !isMultiModifierOnly {
                                if shortcut.keyCode == keyCode && !shortcut.displayString.isEmpty {
                                    let savedModifierFlags = NSEvent.ModifierFlags(rawValue: UInt(shortcut.modifierFlags)).intersection([.command, .control, .option, .shift])
                                    if modifierFlags == savedModifierFlags { targetLang = shortcut.targetLanguage; appliedRule = "Custom Shortcut"; break }
                                }
                            }
                        }
                    }

                    if !isToggle && targetAppBundleID == nil && targetLang == nil && keyCode == 49 {
                        if modifierFlags == .control && settings.isCtrlActive { targetLang = settings.ctrlLang; appliedRule = "Default Shortcut" }
                        else if modifierFlags == .command && settings.isCmdActive { targetLang = settings.cmdLang; appliedRule = "Default Shortcut" }
                        else if modifierFlags == .option && settings.isOptActive { targetLang = settings.optLang; appliedRule = "Default Shortcut" }
                    }

                    if isToggle || targetAppBundleID != nil || targetLang != nil {
                        EventMonitor.executeAction(targetLang: targetLang, targetAppID: targetAppBundleID, targetAppName: targetAppName, isToggle: isToggle, rule: appliedRule)
                        if isToggle { return nil }
                        return Unmanaged.passUnretained(event)
                    }
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

    private static func executeAction(targetLang: String?, targetAppID: String?, targetAppName: String? = nil, isToggle: Bool, rule: String) {
        if !AccessibilityManager.shared.isTrusted {
            SettingsManager.shared.addLog(ActionLog(timestamp: Date(), targetApp: "System", appliedRule: rule, finalInputSource: targetLang ?? "Unknown", result: .failure, failureReason: .permissionIssue))
            return
        }

        EventMonitor.shared.cooldownLock.lock()
        let now = Date()
        if now.timeIntervalSince(EventMonitor.shared.lastActionTime) < EventMonitor.shared.actionCooldown {
            EventMonitor.shared.cooldownLock.unlock()
            return
        }
        EventMonitor.shared.lastActionTime = now
        EventMonitor.shared.cooldownLock.unlock()

        let settings = SettingsManager.shared
        if settings.isTestMode {
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
