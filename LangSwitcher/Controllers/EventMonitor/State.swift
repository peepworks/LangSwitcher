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
    var isEnabled: Bool {
        guard let tap = eventTap else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    var typingBuffer: String {
        get { stateQueue.sync { _typingBuffer } }
        set { stateQueue.async(flags: .barrier) { self._typingBuffer = newValue } }
    }
    
    var lastKeyTime: Date {
        get { stateQueue.sync { _lastKeyTime } }
        set { stateQueue.async(flags: .barrier) { self._lastKeyTime = newValue } }
    }

    var shortcutRecordingCallback: ((NSEvent) -> Void)? {
        get { stateQueue.sync { _shortcutRecordingCallback } }
        set { stateQueue.async(flags: .barrier) { self._shortcutRecordingCallback = newValue } }
    }

    var currentModifiers: NSEvent.ModifierFlags {
        get { stateQueue.sync { _currentModifiers } }
        set { stateQueue.async(flags: .barrier) { self._currentModifiers = newValue } }
    }

    var maxModifiers: NSEvent.ModifierFlags {
        get { stateQueue.sync { _maxModifiers } }
        set { stateQueue.async(flags: .barrier) { self._maxModifiers = newValue } }
    }

    var didPressOtherKey: Bool {
        get { stateQueue.sync { _didPressOtherKey } }
        set { stateQueue.async(flags: .barrier) { self._didPressOtherKey = newValue } }
    }

    var singleModifierKeyCode: UInt16? {
        get { stateQueue.sync { _singleModifierKeyCode } }
        set { stateQueue.async(flags: .barrier) { self._singleModifierKeyCode = newValue } }
    }

    var isPaused: Bool {
        get { stateQueue.sync { _isPaused } }
        set { stateQueue.async(flags: .barrier) { self._isPaused = newValue } }
    }

    var lastCapsLockTime: Date {
        get { stateQueue.sync { _lastCapsLockTime } }
        set { stateQueue.async(flags: .barrier) { self._lastCapsLockTime = newValue } }
    }
    
    func updateSettingsSnapshot(_ newSnapshot: SettingsSnapshot) {
        snapshotLock.lock()
        self.localSnapshot = newSnapshot
        snapshotLock.unlock()
    }

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
    
    func cancelShortcutRecording() {
        stateQueue.async(flags: .barrier) {
            self._shortcutRecordingCallback = nil
            self._isPaused = false
        }
    }
}
