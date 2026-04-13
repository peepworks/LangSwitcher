//
//  LangSwitcher
//  Copyright (C) 2026 peepboy
//

import Cocoa

class EventMonitor {
    static let shared = EventMonitor()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    private var currentModifiers: NSEvent.ModifierFlags = []
    private var maxModifiers: NSEvent.ModifierFlags = []
    private var didPressOtherKey = false
    private var singleModifierKeyCode: UInt16? = nil

    func start() {
        if eventTap != nil { return }
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                let settings = SettingsManager.shared
                var targetLang: String? = nil
                var targetAppBundleID: String? = nil
                var targetAppName: String? = nil

                let nsModifierFlags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))

                // --- 1. 수식어 키 감지 (Caps Lock 및 단일 탭) ---
                if type == .flagsChanged {
                    let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                    let flags = nsModifierFlags.intersection(.deviceIndependentFlagsMask)

                    if keyCode == 57 { // Caps Lock
                        for appLaunch in settings.appLaunchShortcuts where appLaunch.modifierFlags == 0 && appLaunch.keyCode == 57 && !appLaunch.displayString.isEmpty {
                            targetAppBundleID = appLaunch.bundleIdentifier; targetAppName = appLaunch.appName; break
                        }
                        if targetAppBundleID == nil {
                            for shortcut in settings.customShortcuts where shortcut.modifierFlags == 0 && shortcut.keyCode == 57 && !shortcut.displayString.isEmpty {
                                targetLang = shortcut.targetLanguage; break
                            }
                        }
                    } else {
                        if !flags.isEmpty {
                            if EventMonitor.shared.currentModifiers.isEmpty {
                                EventMonitor.shared.didPressOtherKey = false; EventMonitor.shared.maxModifiers = []; EventMonitor.shared.singleModifierKeyCode = keyCode
                            } else { EventMonitor.shared.singleModifierKeyCode = nil }
                            EventMonitor.shared.currentModifiers = flags; EventMonitor.shared.maxModifiers.formUnion(flags)
                        } else {
                            if !EventMonitor.shared.didPressOtherKey {
                                if let singleCode = EventMonitor.shared.singleModifierKeyCode {
                                    for appLaunch in settings.appLaunchShortcuts where appLaunch.modifierFlags == 0 && appLaunch.keyCode == singleCode && !appLaunch.displayString.isEmpty {
                                        targetAppBundleID = appLaunch.bundleIdentifier; targetAppName = appLaunch.appName; break
                                    }
                                    if targetAppBundleID == nil {
                                        for shortcut in settings.customShortcuts where shortcut.modifierFlags == 0 && shortcut.keyCode == singleCode && !shortcut.displayString.isEmpty {
                                            targetLang = shortcut.targetLanguage; break
                                        }
                                    }
                                } else if !EventMonitor.shared.maxModifiers.isEmpty {
                                    let modsRaw = UInt64(EventMonitor.shared.maxModifiers.rawValue)
                                    for appLaunch in settings.appLaunchShortcuts where appLaunch.keyCode == 0 && appLaunch.modifierFlags == modsRaw && !appLaunch.displayString.isEmpty {
                                        targetAppBundleID = appLaunch.bundleIdentifier; targetAppName = appLaunch.appName; break
                                    }
                                    if targetAppBundleID == nil {
                                        for shortcut in settings.customShortcuts where shortcut.keyCode == 0 && shortcut.modifierFlags == modsRaw && !shortcut.displayString.isEmpty {
                                            targetLang = shortcut.targetLanguage; break
                                        }
                                    }
                                }
                            }
                            EventMonitor.shared.currentModifiers = []; EventMonitor.shared.maxModifiers = []; EventMonitor.shared.singleModifierKeyCode = nil
                        }
                    }
                    
                    if targetAppBundleID != nil || targetLang != nil {
                        EventMonitor.executeAction(targetLang: targetLang, targetAppID: targetAppBundleID, targetAppName: targetAppName)
                        return Unmanaged.passRetained(event)
                    }
                }

                // --- 2. 일반 단축키 감지 ---
                if type == .keyDown {
                    EventMonitor.shared.didPressOtherKey = true
                    EventMonitor.shared.singleModifierKeyCode = nil
                    
                    let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                    let modifierFlags = nsModifierFlags.intersection([.command, .control, .option, .shift])

                    // 앱 실행 단축키
                    for appLaunch in settings.appLaunchShortcuts {
                        let isSingleModifier = [54,55,56,60,58,61,59,62,57,63].contains(appLaunch.keyCode) && appLaunch.modifierFlags == 0
                        let isMultiModifierOnly = appLaunch.keyCode == 0 && appLaunch.modifierFlags != 0
                        if !isSingleModifier && !isMultiModifierOnly {
                            if appLaunch.keyCode == keyCode && !appLaunch.displayString.isEmpty {
                                let savedModifierFlags = NSEvent.ModifierFlags(rawValue: UInt(appLaunch.modifierFlags)).intersection([.command, .control, .option, .shift])
                                if modifierFlags == savedModifierFlags {
                                    targetAppBundleID = appLaunch.bundleIdentifier; targetAppName = appLaunch.appName; break
                                }
                            }
                        }
                    }

                    // 커스텀 언어 단축키
                    if targetAppBundleID == nil {
                        for shortcut in settings.customShortcuts {
                            let isSingleModifier = [54,55,56,60,58,61,59,62,57,63].contains(shortcut.keyCode) && shortcut.modifierFlags == 0
                            let isMultiModifierOnly = shortcut.keyCode == 0 && shortcut.modifierFlags != 0
                            if !isSingleModifier && !isMultiModifierOnly {
                                if shortcut.keyCode == keyCode && !shortcut.displayString.isEmpty {
                                    let savedModifierFlags = NSEvent.ModifierFlags(rawValue: UInt(shortcut.modifierFlags)).intersection([.command, .control, .option, .shift])
                                    if modifierFlags == savedModifierFlags { targetLang = shortcut.targetLanguage; break }
                                }
                            }
                        }
                    }

                    // 기본 언어 단축키
                    if targetAppBundleID == nil && targetLang == nil && keyCode == 49 {
                        if modifierFlags == .control && settings.isCtrlActive { targetLang = settings.ctrlLang }
                        else if modifierFlags == .command && settings.isCmdActive { targetLang = settings.cmdLang }
                        else if modifierFlags == .option && settings.isOptActive { targetLang = settings.optLang }
                    }

                    if targetAppBundleID != nil || targetLang != nil {
                        EventMonitor.executeAction(targetLang: targetLang, targetAppID: targetAppBundleID, targetAppName: targetAppName)
                        return Unmanaged.passRetained(event)
                    }
                }
                return Unmanaged.passRetained(event)
            },
            userInfo: nil
        )

        if let tap = eventTap {
            runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource!, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes) }
        eventTap = nil
        runLoopSource = nil
    }
    
    // 🌟 실행 로직 통합 (테스트 모드 지원)
    private static func executeAction(targetLang: String?, targetAppID: String?, targetAppName: String? = nil) {
        let settings = SettingsManager.shared
        if settings.isTestMode {
            var testLabel = ""
            if let appName = targetAppName { testLabel = "[Test] \(appName)" }
            else if let langID = targetLang {
                let langName = InputSourceManager.shared.availableKeyboards.first(where: { $0.id == langID })?.name ?? langID
                testLabel = "[Test] \(langName)"
            }
            if !testLabel.isEmpty { DispatchQueue.main.async { HUDManager.shared.showHUD(languageName: testLabel) } }
        } else {
            if let bundleID = targetAppID {
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
