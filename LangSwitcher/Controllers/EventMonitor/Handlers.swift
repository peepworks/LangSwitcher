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

extension EventMonitor {
    func handleFlagsChanged(event: CGEvent, keyCode: CGKeyCode, modifierFlags: NSEvent.ModifierFlags) -> Unmanaged<CGEvent>? {
        
        // 🌟 1. 잠금 (Lock) 추가
        EventMonitor.shared.snapshotLock.lock()
        
        // 🌟 2. 나갈 때 알아서 해제 (Defer)
        defer { EventMonitor.shared.snapshotLock.unlock() }
        
        guard let snapshot = EventMonitor.shared.localSnapshot else {
            // 💡 수동 unlock() 제거됨 (defer가 알아서 해줍니다)
            return Unmanaged.passUnretained(event)
        }
        // 💡 수동 unlock() 제거됨
        
        var targetLang: String? = nil; var targetAppBundleID: String? = nil; var targetAppName: String? = nil
        var isToggle = false; var appliedRule = ""
        let flags = modifierFlags.intersection(.deviceIndependentFlagsMask)

        if keyCode == 57 {
            if EventMonitor.shared.shouldDebounceCapsLock() { return nil }

            if snapshot.isTypoCorrectionEnabled && snapshot.typoModifierFlags == 0 && snapshot.typoKeyCode == 57 && !snapshot.typoDisplayString.isEmpty {
                TypoConverter.shared.executeCorrection()
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
                            TypoConverter.shared.executeCorrection()
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
                            TypoConverter.shared.executeCorrection()
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

    func handleKeyDown(event: CGEvent, keyCode: CGKeyCode, modifierFlags: NSEvent.ModifierFlags) -> Unmanaged<CGEvent>? {
        
        // 🌟 handleKeyDown에도 동일한 잠금/스냅샷 로직 통일 적용
        EventMonitor.shared.snapshotLock.lock()
        defer { EventMonitor.shared.snapshotLock.unlock() }
        
        guard let snapshot = EventMonitor.shared.localSnapshot else {
            return Unmanaged.passUnretained(event)
        }
        
        var targetLang: String? = nil; var targetAppBundleID: String? = nil; var targetAppName: String? = nil
        var isToggle = false; var appliedRule = ""

        self.markOtherKeyPressed()
        let flags = modifierFlags.intersection([.command, .control, .option, .shift])

        if snapshot.isTypoCorrectionEnabled &&
           snapshot.typoKeyCode == keyCode &&
           NSEvent.ModifierFlags(rawValue: UInt(snapshot.typoModifierFlags)).intersection([.command, .control, .option, .shift]) == flags &&
           !snapshot.typoDisplayString.isEmpty {
            TypoConverter.shared.executeCorrection()
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
}
