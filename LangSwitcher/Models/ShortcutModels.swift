//
//  ShortcutModels.swift
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

/// 🌟 [수복 신설] 순차적 이중 키(Chord) 매칭을 위해 입력 궤적을 캡처하는 추적 노드
struct SequentialKeyStroke: Hashable, Sendable {
    let keyCode: UInt16
    let modifierFlags: UInt64
}

/// 🌟 [수복 신설] 단축키 엔진 내부의 넌블로킹 스냅샷 매칭 매트릭스
struct CompressedShortcutCache: Sendable {
    let toggleKey: SequentialKeyStroke?
    let customShortcuts: [SequentialKeyStroke: String]
    let appLaunchShortcuts: [SequentialKeyStroke: (bundleID: String, name: String)]
    let typoShortcut: SequentialKeyStroke?
}

/// 단축키 포맷 변환을 위한 초고속 공통 유틸리티
struct ShortcutFormatter {
    static func format(modifierFlags: UInt64, keyCode: UInt16) -> String {
        var parts: [String] = []
        let flags = NSEvent.ModifierFlags(rawValue: UInt(modifierFlags))

        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option)  { parts.append("⌥") }
        if flags.contains(.shift)   { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }

        if globalModifierKeyCodes.contains(keyCode) && modifierFlags == 0 {
            return globalKeyMap[keyCode] ?? "Unknown"
        }

        if keyCode != 0 {
            if let keyString = globalKeyMap[keyCode] {
                parts.append(keyString)
            }
        }
        return parts.joined(separator: "")
    }
}
