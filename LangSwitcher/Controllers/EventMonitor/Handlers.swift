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
import Carbon

extension EventMonitor {

    func handleFlagsChanged(event: CGEvent, keyCode: CGKeyCode, modifierFlags: NSEvent.ModifierFlags) -> Unmanaged<CGEvent>? {
        let flags = modifierFlags.intersection(.deviceIndependentFlagsMask)

        if keyCode == 57 {
            if EventMonitor.shared.shouldDebounceCapsLock() { return nil }
            InputShortcutEngine.shared.injectEvent(keyCode: 57, modifierFlags: 0)
            return nil
        } else {
            if !flags.isEmpty {
                self.updateModifierState(keyCode: keyCode, flags: flags)
            } else {
                let stateSnap = self.consumeModifierState()
                if !stateSnap.didPressOtherKey {
                    if let singleCode = stateSnap.singleCode {
                        InputShortcutEngine.shared.injectEvent(keyCode: singleCode, modifierFlags: 0)
                        return nil
                    } else if !stateSnap.maxMods.isEmpty {
                        InputShortcutEngine.shared.injectEvent(keyCode: 0, modifierFlags: UInt64(stateSnap.maxMods.rawValue))
                        return nil
                    }
                }
            }
        }
        return Unmanaged.passUnretained(event)
    }

    func handleKeyDown(event: CGEvent, keyCode: CGKeyCode, modifierFlags: NSEvent.ModifierFlags) -> Unmanaged<CGEvent>? {
        let isSimulated = event.getIntegerValueField(.eventSourceUserData) == 9999
        if isSimulated {
            return Unmanaged.passUnretained(event)
        }
        
        if let session = EventMonitor.shared.activeSnippetSession {
            if session.isExpired {
                EventMonitor.shared.activeSnippetSession = nil
            } else if keyCode == 48 {
                
                let currentStop = session.currentTabStop
                
                if let nextStop = session.advance() {
                    let currentSnapshot = currentStop
                    let nextSnapshot = nextStop
                    
                    Task {
                        if let current = currentSnapshot {
                            await self.jumpToNextTabStopAsync(from: current, to: nextSnapshot)
                        }
                    }
                    return nil
                } else {
                    let currentSnapshot = currentStop
                    let finalOffset = session.finalCaretOffset
                    
                    Task {
                        if let current = currentSnapshot, let targetOffset = finalOffset {
                            await self.jumpToFinalCaretAsync(from: current, toOffset: targetOffset)
                        }
                    }
                    
                    EventMonitor.shared.activeSnippetSession = nil
                    return nil
                }
            }
        }
        
        self.markOtherKeyPressed()
        
        let flags = modifierFlags.intersection([.command, .control, .option, .shift])
        let rawFlags = UInt64(flags.rawValue)

        EventMonitor.shared.snapshotLock.lock()
        guard let snapshot = EventMonitor.shared.localSnapshot else {
            EventMonitor.shared.snapshotLock.unlock()
            return Unmanaged.passUnretained(event)
        }
        EventMonitor.shared.snapshotLock.unlock()

        if keyCode == 49 {
            let isControl = flags.contains(.control)
            let isCommand = flags.contains(.command)
            let isOption = flags.contains(.option)
            
            if (isControl && snapshot.isCtrlActive) || (isCommand && snapshot.isCmdActive) || (isOption && snapshot.isOptActive) {
                let targetLang = targetLangIfPressed(keyCode: keyCode, flags: flags, snapshot: snapshot) ?? ""
                InputSourceManager.shared.switchLanguage(to: targetLang)
                
                let source = CGEventSource(stateID: .combinedSessionState)
                let spaceDown = CGEvent(keyboardEventSource: source, virtualKey: 49, keyDown: true)
                let spaceUp = CGEvent(keyboardEventSource: source, virtualKey: 49, keyDown: false)
                
                spaceDown?.flags = event.flags
                spaceUp?.flags = event.flags
                spaceDown?.setIntegerValueField(.eventSourceUserData, value: 9999)
                spaceUp?.setIntegerValueField(.eventSourceUserData, value: 9999)
                
                spaceDown?.post(tap: .cghidEventTap)
                spaceUp?.post(tap: .cghidEventTap)
                
                if snapshot.isCursorHUDEnabled {
                    DispatchQueue.main.async { HUDManager.shared.showHUD(languageName: InputSourceManager.shared.currentInputSourceName) }
                }
                return nil
            }
            return Unmanaged.passUnretained(event)
        }

        InputShortcutEngine.shared.injectEvent(keyCode: UInt16(keyCode), modifierFlags: rawFlags)
        return Unmanaged.passUnretained(event)
    }

    private func jumpToNextTabStopAsync(from current: SnippetTabStop, to next: SnippetTabStop) async {
        let currentSelectionLength = current.range.length
        
        if currentSelectionLength > 0 {
            await self.simulateArrowMovementAsync(keyCode: 124, count: 1, withShift: false)
        }
        
        let currentEnd = current.range.location + current.range.length
        let nextStart = next.range.location
        let delta = nextStart - currentEnd
        
        if delta > 0 {
            await self.simulateArrowMovementAsync(keyCode: 124, count: delta, withShift: false)
        } else if delta < 0 {
            await self.simulateArrowMovementAsync(keyCode: 123, count: abs(delta), withShift: false)
        }
        
        if next.range.length > 0 {
            try? await Task.sleep(nanoseconds: 10_000_000)
            await self.simulateArrowMovementAsync(keyCode: 124, count: next.range.length, withShift: true)
        }
    }

    private func jumpToFinalCaretAsync(from current: SnippetTabStop, toOffset finalOffset: Int) async {
        let currentSelectionLength = current.range.length
        if currentSelectionLength > 0 {
            await self.simulateArrowMovementAsync(keyCode: 124, count: 1, withShift: false)
        }
        
        let currentEnd = current.range.location + current.range.length
        let delta = finalOffset - currentEnd
        
        if delta > 0 {
            await self.simulateArrowMovementAsync(keyCode: 124, count: delta, withShift: false)
        } else if delta < 0 {
            await self.simulateArrowMovementAsync(keyCode: 123, count: abs(delta), withShift: false)
        }
    }
    
    // 🌟 [수복 핵심] OS 패킷 증발을 막는 안전 페이싱(2ms) 부활!
    func simulateArrowMovementAsync(keyCode: CGKeyCode, count: Int, withShift: Bool) async {
        guard count > 0 else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        
        if withShift {
            let shiftDown = CGEvent(keyboardEventSource: source, virtualKey: 56, keyDown: true)
            shiftDown?.flags = .maskShift
            shiftDown?.setIntegerValueField(.eventSourceUserData, value: 9999)
            shiftDown?.post(tap: .cghidEventTap)
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        for _ in 0..<count {
            let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
            let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
            
            if withShift {
                down?.flags = .maskShift
                up?.flags = .maskShift
            }
            down?.setIntegerValueField(.eventSourceUserData, value: 9999)
            up?.setIntegerValueField(.eventSourceUserData, value: 9999)
            
            down?.post(tap: .cghidEventTap)
            try? await Task.sleep(nanoseconds: 2_000_000) // 🌟 2ms 절대 보장
            up?.post(tap: .cghidEventTap)
            try? await Task.sleep(nanoseconds: 2_000_000) // 🌟 2ms 절대 보장
        }

        if withShift {
            try? await Task.sleep(nanoseconds: 10_000_000)
            let shiftUp = CGEvent(keyboardEventSource: source, virtualKey: 56, keyDown: false)
            shiftUp?.flags = []
            shiftUp?.setIntegerValueField(.eventSourceUserData, value: 9999)
            shiftUp?.post(tap: .cghidEventTap)
        }
    }
}
