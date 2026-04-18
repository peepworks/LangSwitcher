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
    
    // UI(설정 창)로 이벤트를 쏴줄 콜백 함수 변수
    var shortcutRecordingCallback: ((NSEvent) -> Void)? = nil
    
    // 예외 앱 바이패스용 활성 앱 추적 변수
    var activeAppBundleID: String = ""
    private var workspaceObserver: NSObjectProtocol?
    
    private var currentModifiers: NSEvent.ModifierFlags = []
    private var maxModifiers: NSEvent.ModifierFlags = []
    private var didPressOtherKey = false
    private var singleModifierKeyCode: UInt16? = nil
    
    var isPaused = false
    private var lastActionTime: Date = Date.distantPast
    private let actionCooldown: TimeInterval = 0.15

    func start() {
        if eventTap != nil { return }
        
        activeAppBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { notification in
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                EventMonitor.shared.activeAppBundleID = app.bundleIdentifier ?? ""
            }
        }
        
        let eventMask = (1 << CGEventType.keyDown.rawValue) |
                        (1 << CGEventType.flagsChanged.rawValue) |
                        (1 << CGEventType.tapDisabledByTimeout.rawValue) |
                        (1 << CGEventType.tapDisabledByUserInput.rawValue)

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = EventMonitor.shared.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                    return Unmanaged.passRetained(event)
                }
                
                if let callback = EventMonitor.shared.shortcutRecordingCallback {
                    if type == .keyDown || type == .flagsChanged {
                        if let nsEvent = NSEvent(cgEvent: event) { DispatchQueue.main.async { callback(nsEvent) } }
                        return nil
                    }
                }
                
                if !EventMonitor.shared.activeAppBundleID.isEmpty {
                    if SettingsManager.shared.excludedApps.contains(where: { $0.bundleIdentifier == EventMonitor.shared.activeAppBundleID }) {
                        return Unmanaged.passRetained(event)
                    }
                }
                
                if EventMonitor.shared.isPaused { return Unmanaged.passRetained(event) }
                
                let settings = SettingsManager.shared
                var targetLang: String? = nil; var targetAppBundleID: String? = nil; var targetAppName: String? = nil
                var isToggle = false
                var appliedRule = ""

                let nsModifierFlags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))

                // ----------------------------------------------------
                // 5. 수식어 키 (Cmd, Option, Ctrl, Shift, Caps Lock 등) 처리 (.flagsChanged)
                // ----------------------------------------------------
                if type == .flagsChanged {
                    let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                    let flags = nsModifierFlags.intersection(.deviceIndependentFlagsMask)

                    if keyCode == 57 { // Caps Lock 처리
                        // 🌟 오타 변환: Caps Lock 단독 매칭
                        if settings.isTypoCorrectionEnabled && settings.typoModifierFlags == 0 && settings.typoKeyCode == 57 && !settings.typoDisplayString.isEmpty {
                            TypoConverter.shared.executeCorrection()
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
                            // 수식어 키가 눌렸을 때
                            if EventMonitor.shared.currentModifiers.isEmpty {
                                EventMonitor.shared.didPressOtherKey = false; EventMonitor.shared.maxModifiers = []; EventMonitor.shared.singleModifierKeyCode = keyCode
                            } else {
                                EventMonitor.shared.singleModifierKeyCode = nil
                            }
                            EventMonitor.shared.currentModifiers = flags; EventMonitor.shared.maxModifiers.formUnion(flags)
                        } else {
                            // 수식어 키에서 손을 뗐을 때
                            if !EventMonitor.shared.didPressOtherKey {
                                if let singleCode = EventMonitor.shared.singleModifierKeyCode {
                                    
                                    // 🌟 오타 변환: 단독 수식어 키 매칭 (Right Ctrl 등)
                                    if settings.isTypoCorrectionEnabled && settings.typoModifierFlags == 0 && settings.typoKeyCode == singleCode && !settings.typoDisplayString.isEmpty {
                                        TypoConverter.shared.executeCorrection()
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
                                    
                                    // 🌟 오타 변환: 다중 수식어 키 단독 매칭 (Cmd+Opt 만 누를 때 등)
                                    if settings.isTypoCorrectionEnabled && settings.typoKeyCode == 0 && settings.typoModifierFlags == modsRaw && !settings.typoDisplayString.isEmpty {
                                        TypoConverter.shared.executeCorrection()
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
                        if keyCode == 57 { return nil } // Caps Lock 차단
                        return Unmanaged.passRetained(event)
                    }
                }

                // ----------------------------------------------------
                // 6. 일반 키 (Tab, Space, 알파벳, F키 등) 처리 (.keyDown)
                // ----------------------------------------------------
                if type == .keyDown {
                    EventMonitor.shared.didPressOtherKey = true; EventMonitor.shared.singleModifierKeyCode = nil
                    let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                    let modifierFlags = nsModifierFlags.intersection([.command, .control, .option, .shift])

                    // 🌟 오타 변환: 일반 단축키 매칭 (Ctrl + Shift + Space 등)
                    if settings.isTypoCorrectionEnabled &&
                       settings.typoKeyCode == keyCode &&
                       NSEvent.ModifierFlags(rawValue: UInt(settings.typoModifierFlags)).intersection([.command, .control, .option, .shift]) == modifierFlags &&
                       !settings.typoDisplayString.isEmpty {
                        
                        TypoConverter.shared.executeCorrection()
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
                        return Unmanaged.passRetained(event)
                    }
                }
                return Unmanaged.passRetained(event)
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
        
        if let obs = workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(obs); workspaceObserver = nil }
    }
    
    private static func executeAction(targetLang: String?, targetAppID: String?, targetAppName: String? = nil, isToggle: Bool, rule: String) {
        if !AccessibilityManager.shared.isTrusted {
            SettingsManager.shared.addLog(ActionLog(timestamp: Date(), targetApp: "System", appliedRule: rule, finalInputSource: targetLang ?? "Unknown", result: .failure, failureReason: .permissionIssue))
            return
        }
        
        let now = Date()
        if now.timeIntervalSince(EventMonitor.shared.lastActionTime) < EventMonitor.shared.actionCooldown { return }
        EventMonitor.shared.lastActionTime = now
        
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
