//
//  Handlers.swift
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
                // 🌟 [우주 방어 수복 포인트 1: handleFlagsChanged 데드락 무력화]
                // 락 가드 내부에서의 동기 호출을 차단하고 비동기 메인 큐 홉으로 안전하게 밀어 올립니다.
                DispatchQueue.main.async {
                    TypoConverter.shared.executeCorrection()
                }
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
                            // 🌟 [우주 방어 수복 포인트 2: 싱글 모디파이어 오타 교정 비동기화]
                            DispatchQueue.main.async {
                                TypoConverter.shared.executeCorrection()
                            }
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
                            // 🌟 [우주 방어 수복 포인트 3: 다중 모디파이어 오타 교정 비동기화]
                            DispatchQueue.main.async {
                                TypoConverter.shared.executeCorrection()
                            }
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
            // 🌟 [성능 최적화: 핫 패스 오버헤드 평탄화 1]
            // 액션 실행 엔진을 메인 큐 비동기로 디스패치하여 락 점유 시간을 0ms로 소각합니다.
            DispatchQueue.main.async {
                EventMonitor.executeAction(targetLang: targetLang, targetAppID: targetAppBundleID, targetAppName: targetAppName, isToggle: isToggle, rule: appliedRule)
            }
            
            if keyCode == 57 { return nil } // Caps Lock 토글시 차단
            if targetAppBundleID != nil { return nil } // 오직 '앱 실행 단축키'일 때만 시스템 이벤트 무효화
            
            return Unmanaged.passUnretained(event)
        }
        return Unmanaged.passUnretained(event)
    }

    func handleKeyDown(event: CGEvent, keyCode: CGKeyCode, modifierFlags: NSEvent.ModifierFlags) -> Unmanaged<CGEvent>? {

        EventMonitor.shared.snapshotLock.lock()
        defer { EventMonitor.shared.snapshotLock.unlock() }

        guard let snapshot = EventMonitor.shared.localSnapshot else {
            return Unmanaged.passUnretained(event)
        }

        var targetLang: String? = nil
        var targetAppBundleID: String? = nil
        var targetAppName: String? = nil
        var isToggle = false
        var appliedRule = ""

        self.markOtherKeyPressed()
        let flags = modifierFlags.intersection([.command, .control, .option, .shift])
        let flagsRaw = UInt64(flags.rawValue)

        // 1. 수동/자동 오타 교정 트리거 검사
        if snapshot.isTypoCorrectionEnabled &&
           snapshot.typoKeyCode == keyCode &&
           NSEvent.ModifierFlags(rawValue: UInt(snapshot.typoModifierFlags)).intersection([.command, .control, .option, .shift]) == flags &&
           !snapshot.typoDisplayString.isEmpty {
            
            DispatchQueue.main.async {
                TypoConverter.shared.executeCorrection()
            }
            return nil
        }

        // 2. 입력 소스 토글 키 검사
        if snapshot.toggleKeyCode == keyCode && !snapshot.toggleDisplayString.isEmpty {
            let savedModifierFlags = NSEvent.ModifierFlags(rawValue: UInt(snapshot.toggleModifierFlags)).intersection([.command, .control, .option, .shift])
            if flags == savedModifierFlags {
                isToggle = true
                appliedRule = "Toggle Key"
            }
        }

        let searchKey = makeShortcutKey(keyCode: keyCode, modifiers: flagsRaw)

        // 3. 앱 실행 단축키 규칙 검사
        if !isToggle && snapshot.isAppLaunchEnabled {
            if let appLaunch = snapshot.appLaunchShortcutCache[searchKey], !appLaunch.displayString.isEmpty {
                let isSingleModifier = globalModifierKeyCodes.contains(appLaunch.keyCode) && appLaunch.modifierFlags == 0
                let isMultiModifierOnly = appLaunch.keyCode == 0 && appLaunch.modifierFlags != 0
                if !isSingleModifier && !isMultiModifierOnly {
                    targetAppBundleID = appLaunch.bundleIdentifier
                    targetAppName = appLaunch.appName
                    appliedRule = "App Launch"
                }
            }
        }

        // 4. 커스텀 단축키 규칙 검사
        if !isToggle && targetAppBundleID == nil && snapshot.isCustomShortcutsEnabled {
            if let shortcut = snapshot.customShortcutCache[searchKey], !shortcut.displayString.isEmpty {
                let isSingleModifier = globalModifierKeyCodes.contains(shortcut.keyCode) && shortcut.modifierFlags == 0
                let isMultiModifierOnly = shortcut.keyCode == 0 && shortcut.modifierFlags != 0
                if !isSingleModifier && !isMultiModifierOnly {
                    targetLang = shortcut.targetLanguage
                    appliedRule = "Custom Shortcut"
                }
            }
        }

        // 5. 기본 조합 단축키 검사 (Ctrl / Cmd / Opt + Space)
        if !isToggle && targetAppBundleID == nil && targetLang == nil && keyCode == 49 {
            if flags == .control && snapshot.isCtrlActive { targetLang = snapshot.ctrlLang; appliedRule = "Default Shortcut" }
            else if flags == .command && snapshot.isCmdActive { targetLang = snapshot.cmdLang; appliedRule = "Default Shortcut" }
            else if flags == .option && snapshot.isOptActive { targetLang = snapshot.optLang; appliedRule = "Default Shortcut" }
        }

        // ----------------------------------------------------------------
        // 최종 정산 및 수복 구역
        // ----------------------------------------------------------------
        
        // 1) 실제 액션(언어 전환 또는 앱 실행)이 발동해야 하는 경우
        if isToggle || targetAppBundleID != nil || targetLang != nil {
            // 🌟 [성능 최적화: 핫 패스 오버헤드 평탄화 2]
            DispatchQueue.main.async {
                EventMonitor.executeAction(targetLang: targetLang, targetAppID: targetAppBundleID, targetAppName: targetAppName, isToggle: isToggle, rule: appliedRule)
            }

            if isToggle { return nil }
            if targetAppBundleID != nil { return nil }
            return Unmanaged.passUnretained(event)
        }
        
        // 2) 🌟 [최종 컴파일 에러 수복 완료 구역]
        // 우리가 3개 파라미터형으로 개조한 targetLangIfPressed 규격에 맞게 keyCode 유닛 변환 및 snapshot 자산을 관통 주입합니다.
        else if let _ = targetLangIfPressed(keyCode: UInt16(keyCode), flags: flags, snapshot: snapshot), snapshot.isCursorHUDEnabled {

            // 🔧 [우주 방어 & 2프레임 지연 소각]
            DispatchQueue.main.async {
                let langName = InputSourceManager.shared.currentInputSourceName
                HUDManager.shared.showHUD(languageName: langName)
            }
        }

        return Unmanaged.passUnretained(event)
    }
}
