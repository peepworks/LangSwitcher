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

import Foundation
import Carbon
import Combine // 🌟 에러 해결: ObservableObject와 @Published를 사용하기 위한 필수 프레임워크

// macOS 시스템에 등록된 키보드 정보를 담는 구조체
struct MacKeyboard: Identifiable, Hashable {
    let id: String
    let name: String
}

class InputSourceManager: ObservableObject {
    static let shared = InputSourceManager()

    // UI에서 접근할 수 있도록 퍼블리싱된 키보드 배열
    @Published var availableKeyboards: [MacKeyboard] = []

    private init() {
        fetchKeyboards()
    }

    func fetchKeyboards() {
        guard let sourceList = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else { return }

        var keyboards: [MacKeyboard] = []

        for source in sourceList {
            guard let isSelectablePtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable) else { continue }
            let isSelectable = Unmanaged<CFBoolean>.fromOpaque(isSelectablePtr).takeUnretainedValue()
            if !CFBooleanGetValue(isSelectable) { continue }

            guard let namePtr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) else { continue }
            let name = Unmanaged<CFString>.fromOpaque(namePtr).takeUnretainedValue() as String

            guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { continue }
            let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String

            // 화면 키보드, 받아쓰기 등 제외
            let excludedIDs = ["com.apple.CharacterPaletteIM", "com.apple.KeyboardViewer", "com.apple.PressAndHold"]
            if excludedIDs.contains(id) || id.lowercased().contains("dictation") { continue }

            keyboards.append(MacKeyboard(id: id, name: name))
        }
        
        DispatchQueue.main.async {
            self.availableKeyboards = keyboards
        }
    }

    func switchLanguage(to id: String) {
        let filter = [kTISPropertyInputSourceID: id] as CFDictionary
        if let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource],
           let target = list.first {
            TISSelectInputSource(target)
            print("✅ 전환 성공: \(id)")
        } else {
            print("❌ 전환 실패: \(id) 키보드를 찾을 수 없습니다.")
        }
    }
}
