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
    // 🌟 [복원] 누락되었던 필수 연산 프로퍼티를 메인 액터 격리 환경에 맞게 안착시킵니다.
    var isEnabled: Bool {
        guard let tap = eventTap else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    var typingBuffer: String {
        get { _typingBuffer }
        set { _typingBuffer = newValue }
    }

    var lastKeyTime: Date {
        get { _lastKeyTime }
        set { _lastKeyTime = newValue }
    }

    var shortcutRecordingCallback: ((NSEvent) -> Void)? {
        get { _shortcutRecordingCallback }
        set { _shortcutRecordingCallback = newValue }
    }

    var currentModifiers: NSEvent.ModifierFlags {
        get { _currentModifiers }
        set { _currentModifiers = newValue }
    }

    var maxModifiers: NSEvent.ModifierFlags {
        get { _maxModifiers }
        set { _maxModifiers = newValue }
    }

    var didPressOtherKey: Bool {
        get { _didPressOtherKey }
        set { _didPressOtherKey = newValue }
    }

    var singleModifierKeyCode: UInt16? {
        get { _singleModifierKeyCode }
        set { _singleModifierKeyCode = newValue }
    }

    var isPaused: Bool {
        get { _isPaused }
        set { _isPaused = newValue }
    }

    var lastCapsLockTime: Date {
        get { _lastCapsLockTime }
        set { _lastCapsLockTime = newValue }
    }

    func updateSettingsSnapshot(_ newSnapshot: SettingsSnapshot) {
        self.localSnapshot = newSnapshot
    }

    // MARK: - 고성능 타이핑 입력 버퍼 주입 (O(n) 시프팅 일관성 수복 완료)
    func appendToTypingBuffer(_ char: Character) {
        self.typingBuffer.append(char)

        if self.typingBuffer.count > 50 {
            self.typingBuffer = String(self.typingBuffer.suffix(50))
            
            #if DEBUG
            dprint("⌨️ [EventState] 타이핑 윈도우 오버플로우 트리밍: 최신 15자 컨텍스트 슬라이스 고정")
            #endif
        }
    }

    func clearTypingBuffer() {
        self._typingBuffer = ""
    }

    func checkStaleAndResetBuffer() {
        let now = Date()
        if now.timeIntervalSince(self._lastKeyTime) > 2.0 {
            self._typingBuffer = ""
        }
        self._lastKeyTime = now
    }

    func shouldDebounceCapsLock() -> Bool {
        let now = Date()
        if now.timeIntervalSince(self._lastCapsLockTime) < 0.25 {
            return true
        } else {
            self._lastCapsLockTime = now
            return false
        }
    }

    func updateModifierState(keyCode: UInt16, flags: NSEvent.ModifierFlags) {
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

    func consumeModifierState() -> (didPressOtherKey: Bool, singleCode: UInt16?, maxMods: NSEvent.ModifierFlags) {
        let snapshot = (self._didPressOtherKey, self._singleModifierKeyCode, self._maxModifiers)
        self._currentModifiers = []
        self._maxModifiers = []
        self._singleModifierKeyCode = nil
        return snapshot
    }

    func markOtherKeyPressed() {
        self._didPressOtherKey = true
        self._singleModifierKeyCode = nil
    }

    func canExecuteAction() -> Bool {
        let now = Date()
        if now.timeIntervalSince(self._lastActionTime) >= self.actionCooldown {
            self._lastActionTime = now
            return true
        }
        return false
    }

    func cancelShortcutRecording() {
        self._shortcutRecordingCallback = nil
        self._isPaused = false
    }
}
