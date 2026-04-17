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
    
    // 🌟 1. UI(설정 창)로 이벤트를 쏴줄 콜백 함수 변수 추가
    var shortcutRecordingCallback: ((NSEvent) -> Void)? = nil
    
    private var currentModifiers: NSEvent.ModifierFlags = []
    private var maxModifiers: NSEvent.ModifierFlags = []
    private var didPressOtherKey = false
    private var singleModifierKeyCode: UInt16? = nil
    
    var isPaused = false
    private var lastActionTime: Date = Date.distantPast
    private let actionCooldown: TimeInterval = 0.15

    func start() {
        if eventTap != nil { return }
        
        let eventMask = (1 << CGEventType.keyDown.rawValue) |
                        (1 << CGEventType.flagsChanged.rawValue) |
                        (1 << CGEventType.tapDisabledByTimeout.rawValue) |
                        (1 << CGEventType.tapDisabledByUserInput.rawValue)

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                
                // 타임아웃 감지 및 즉시 재활성화 (생존 로직)
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = EventMonitor.shared.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                    return Unmanaged.passRetained(event)
                }
                
                // 🌟 2. 단축키 녹화 중일 때: 이벤트를 가로채서 시스템에 안 넘기고 UI로만 보냄!
                if let callback = EventMonitor.shared.shortcutRecordingCallback {
                    if type == .keyDown || type == .flagsChanged {
                        if let nsEvent = NSEvent(cgEvent: event) {
                            DispatchQueue.main.async { callback(nsEvent) }
                        }
                        return nil // 이벤트를 완전히 소멸시킴 (Spotlight, Gemini 실행 차단)
                    }
                }
                
                if EventMonitor.shared.isPaused { return Unmanaged.passRetained(event) }
                
                let settings = SettingsManager.shared
                var targetLang: String? = nil; var targetAppBundleID: String? = nil; var targetAppName: String? = nil
                var isToggle = false
                var appliedRule = ""

                let nsModifierFlags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))

                // ----------------------------------------------------
                // 수식어 키 (Cmd, Option, Ctrl, Shift, Caps Lock 등) 처리
                // ----------------------------------------------------
                if type == .flagsChanged {
                    let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                    let flags = nsModifierFlags.intersection(.deviceIndependentFlagsMask)

                    if keyCode == 57 {
                        if settings.toggleModifierFlags == 0 && settings.toggleKeyCode == 57 && !settings.toggleDisplayString.isEmpty {
                            isToggle = true; appliedRule = "Toggle Key"
                        } else {
                            for appLaunch in settings.appLaunchShortcuts where appLaunch.modifierFlags == 0 && appLaunch.keyCode == 57 && !appLaunch.displayString.isEmpty { targetAppBundleID = appLaunch.bundleIdentifier; targetAppName = appLaunch.appName; appliedRule = "App Launch"; break }
                            if targetAppBundleID == nil { for shortcut in settings.customShortcuts where shortcut.modifierFlags == 0 && shortcut.keyCode == 57 && !shortcut.displayString.isEmpty { targetLang = shortcut.targetLanguage; appliedRule = "Custom Shortcut"; break } }
                        }
                    } else {
                        if !flags.isEmpty {
                            if EventMonitor.shared.currentModifiers.isEmpty { EventMonitor.shared.didPressOtherKey = false; EventMonitor.shared.maxModifiers = []; EventMonitor.shared.singleModifierKeyCode = keyCode
                            } else { EventMonitor.shared.singleModifierKeyCode = nil }
                            EventMonitor.shared.currentModifiers = flags; EventMonitor.shared.maxModifiers.formUnion(flags)
                        } else {
                            if !EventMonitor.shared.didPressOtherKey {
                                if let singleCode = EventMonitor.shared.singleModifierKeyCode {
                                    if settings.toggleModifierFlags == 0 && settings.toggleKeyCode == singleCode && !settings.toggleDisplayString.isEmpty {
                                        isToggle = true; appliedRule = "Toggle Key"
                                    } else {
                                        for appLaunch in settings.appLaunchShortcuts where appLaunch.modifierFlags == 0 && appLaunch.keyCode == singleCode && !appLaunch.displayString.isEmpty { targetAppBundleID = appLaunch.bundleIdentifier; targetAppName = appLaunch.appName; appliedRule = "App Launch"; break }
                                        if targetAppBundleID == nil { for shortcut in settings.customShortcuts where shortcut.modifierFlags == 0 && shortcut.keyCode == singleCode && !shortcut.displayString.isEmpty { targetLang = shortcut.targetLanguage; appliedRule = "Custom Shortcut"; break } }
                                    }
                                } else if !EventMonitor.shared.maxModifiers.isEmpty {
                                    let modsRaw = UInt64(EventMonitor.shared.maxModifiers.rawValue)
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
                        if keyCode == 57 { return nil } // Caps Lock 대소문자 기본 변경 차단
                        return Unmanaged.passRetained(event)
                    }
                }

                // ----------------------------------------------------
                // 일반 키 (Tab, Space, 알파벳, F키 등) 처리
                // ----------------------------------------------------
                if type == .keyDown {
                    EventMonitor.shared.didPressOtherKey = true; EventMonitor.shared.singleModifierKeyCode = nil
                    let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                    let modifierFlags = nsModifierFlags.intersection([.command, .control, .option, .shift])

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
                        
                        if isToggle { return nil } // 전환 키일 때만 시스템 이벤트 소멸
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
    }
    
    private static func executeAction(targetLang: String?, targetAppID: String?, targetAppName: String? = nil, isToggle: Bool, rule: String) {
        if !AccessibilityManager.shared.isTrusted {
            SettingsManager.shared.addLog(ActionLog(timestamp: Date(), targetApp: "System", appliedRule: rule, finalInputSource: targetLang ?? "Unknown", result: .failure, failureReason: .permissionIssue))
            return
        }
        
        let now = Date()
        if now.timeIntervalSince(EventMonitor.shared.lastActionTime) < EventMonitor.shared.actionCooldown {
            SettingsManager.shared.addLog(ActionLog(timestamp: Date(), targetApp: targetAppName ?? "System", appliedRule: rule, finalInputSource: "Ignored (Cooldown)", result: .failure, failureReason: .conditionMismatch))
            return
        }
        EventMonitor.shared.lastActionTime = now
        
        let settings = SettingsManager.shared
        
        if settings.isTestMode {
            var testLabel = ""
            if isToggle { testLabel = "[Test] Toggle Language" }
            else if let appName = targetAppName { testLabel = "[Test] \(appName)" }
            else if let langID = targetLang {
                let langName = InputSourceManager.shared.availableKeyboards.first(where: { $0.id == langID })?.name ?? langID
                testLabel = "[Test] \(langName)"
            }
            if !testLabel.isEmpty { DispatchQueue.main.async { HUDManager.shared.showHUD(languageName: testLabel) } }
            SettingsManager.shared.addLog(ActionLog(timestamp: now, targetApp: targetAppName ?? "Test Mode", appliedRule: rule, finalInputSource: "Test Triggered", result: .success, failureReason: .none))
        } else {
            let finalTargetName = isToggle ? "Next Source" : (targetAppName ?? targetLang ?? "Unknown")
            SettingsManager.shared.addLog(ActionLog(timestamp: now, targetApp: targetAppName ?? "System", appliedRule: rule, finalInputSource: finalTargetName, result: .success, failureReason: .none))
            
            if isToggle {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { InputSourceManager.shared.switchToNextInputSource() }
            } else if let bundleID = targetAppID {
                launchApp(bundleID: bundleID)
            } else if let lang = targetLang {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { InputSourceManager.shared.switchLanguage(to: lang) }
            }
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
