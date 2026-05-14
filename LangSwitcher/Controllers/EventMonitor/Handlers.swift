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
    
    // 🌟 공통 키 생성 유틸리티 (keyCode와 modifiers를 하나의 UInt64로 병합)
    private func makeShortcutKey(keyCode: UInt16, modifiers: UInt64) -> UInt64 {
        return (UInt64(keyCode) << 32) | modifiers
    }
    
    func handleFlagsChanged(event: CGEvent, keyCode: CGKeyCode, modifierFlags: NSEvent.ModifierFlags) -> Unmanaged<CGEvent>? {
        
        EventMonitor.shared.snapshotLock.lock()
        defer { EventMonitor.shared.snapshotLock.unlock() }
        
        guard let snapshot = EventMonitor.shared.localSnapshot else {
            return Unmanaged.passUnretained(event)
        }
        
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
                let searchKey = makeShortcutKey(keyCode: 57, modifiers: 0)
                
                if snapshot.isAppLaunchEnabled, let appLaunch = snapshot.appLaunchShortcutCache[searchKey], !appLaunch.displayString.isEmpty {
                    targetAppBundleID = appLaunch.bundleIdentifier; targetAppName = appLaunch.appName; appliedRule = "App Launch"
                } else if snapshot.isCustomShortcutsEnabled, let shortcut = snapshot.customShortcutCache[searchKey], !shortcut.displayString.isEmpty {
                    targetLang = shortcut.targetLanguage; appliedRule = "Custom Shortcut"
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
                            let searchKey = makeShortcutKey(keyCode: singleCode, modifiers: 0)
                            
                            if snapshot.isAppLaunchEnabled, let appLaunch = snapshot.appLaunchShortcutCache[searchKey], !appLaunch.displayString.isEmpty {
                                targetAppBundleID = appLaunch.bundleIdentifier; targetAppName = appLaunch.appName; appliedRule = "App Launch"
                            } else if snapshot.isCustomShortcutsEnabled, let shortcut = snapshot.customShortcutCache[searchKey], !shortcut.displayString.isEmpty {
                                targetLang = shortcut.targetLanguage; appliedRule = "Custom Shortcut"
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
                            let searchKey = makeShortcutKey(keyCode: 0, modifiers: modsRaw)
                            
                            if snapshot.isAppLaunchEnabled, let appLaunch = snapshot.appLaunchShortcutCache[searchKey], !appLaunch.displayString.isEmpty {
                                targetAppBundleID = appLaunch.bundleIdentifier; targetAppName = appLaunch.appName; appliedRule = "App Launch"
                            } else if snapshot.isCustomShortcutsEnabled, let shortcut = snapshot.customShortcutCache[searchKey], !shortcut.displayString.isEmpty {
                                targetLang = shortcut.targetLanguage; appliedRule = "Custom Shortcut"
                            }
                        }
                    }
                }
            }
        }
        
        if isToggle || targetAppBundleID != nil || targetLang != nil {
            EventMonitor.executeAction(targetLang: targetLang, targetAppID: targetAppBundleID, targetAppName: targetAppName, isToggle: isToggle, rule: appliedRule)
            
            if keyCode == 57 { return nil } // Caps Lock 토글시 차단
            
            // 🌟 [요청사항 반영] 오직 '앱 실행 단축키'일 때만 시스템 이벤트 무효화
            if targetAppBundleID != nil { return nil }
            
            return Unmanaged.passUnretained(event) // 나머지는 통과
        }
        return Unmanaged.passUnretained(event)
    }

    func handleKeyDown(event: CGEvent, keyCode: CGKeyCode, modifierFlags: NSEvent.ModifierFlags) -> Unmanaged<CGEvent>? {
        
        EventMonitor.shared.snapshotLock.lock()
        defer { EventMonitor.shared.snapshotLock.unlock() }
        
        guard let snapshot = EventMonitor.shared.localSnapshot else {
            return Unmanaged.passUnretained(event)
        }
        
        var targetLang: String? = nil; var targetAppBundleID: String? = nil; var targetAppName: String? = nil
        var isToggle = false; var appliedRule = ""

        self.markOtherKeyPressed()
        let flags = modifierFlags.intersection([.command, .control, .option, .shift])
        let flagsRaw = UInt64(flags.rawValue)

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

        let searchKey = makeShortcutKey(keyCode: keyCode, modifiers: flagsRaw)

        if !isToggle && snapshot.isAppLaunchEnabled {
            if let appLaunch = snapshot.appLaunchShortcutCache[searchKey], !appLaunch.displayString.isEmpty {
                let isSingleModifier = globalModifierKeyCodes.contains(appLaunch.keyCode) && appLaunch.modifierFlags == 0
                let isMultiModifierOnly = appLaunch.keyCode == 0 && appLaunch.modifierFlags != 0
                if !isSingleModifier && !isMultiModifierOnly {
                    targetAppBundleID = appLaunch.bundleIdentifier; targetAppName = appLaunch.appName; appliedRule = "App Launch"
                }
            }
        }

        if !isToggle && targetAppBundleID == nil && snapshot.isCustomShortcutsEnabled {
            if let shortcut = snapshot.customShortcutCache[searchKey], !shortcut.displayString.isEmpty {
                let isSingleModifier = globalModifierKeyCodes.contains(shortcut.keyCode) && shortcut.modifierFlags == 0
                let isMultiModifierOnly = shortcut.keyCode == 0 && shortcut.modifierFlags != 0
                if !isSingleModifier && !isMultiModifierOnly {
                    targetLang = shortcut.targetLanguage; appliedRule = "Custom Shortcut"
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
            
            if isToggle { return nil } // 토글 동작시 차단
            
            // 🌟 [요청사항 반영] 오직 '앱 실행 단축키'일 때만 시스템 이벤트 무효화
            if targetAppBundleID != nil { return nil }
            
            return Unmanaged.passUnretained(event) // 커스텀 단축키 및 기본 단축키는 그대로 통과
        }
        return Unmanaged.passUnretained(event)
    }
}
