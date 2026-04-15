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
import Combine

struct MacKeyboard: Identifiable, Hashable {
    let id: String
    let name: String
}

class InputSourceManager: ObservableObject {
    static let shared = InputSourceManager()
    @Published var availableKeyboards: [MacKeyboard] = []

    private init() { fetchKeyboards() }

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

            let excludedIDs = ["com.apple.CharacterPaletteIM", "com.apple.KeyboardViewer", "com.apple.PressAndHold"]
            if excludedIDs.contains(id) || id.lowercased().contains("dictation") { continue }

            keyboards.append(MacKeyboard(id: id, name: name))
        }
        DispatchQueue.main.async { self.availableKeyboards = keyboards }
    }

    func switchLanguage(to id: String) {
        // 🌟 1. 현재 사용 중인 시스템 입력 소스의 ID를 가져와서 비교합니다.
        if let currentSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
           let ptr = TISGetInputSourceProperty(currentSource, kTISPropertyInputSourceID) {
            let currentID = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
            
            // 🌟 2. 현재 언어와 변경하려는 목표 언어가 이미 같다면 조용히 취소합니다. (HUD 표시 생략)
            if currentID == id {
                #if DEBUG
                print("💡 이미 해당 언어(\(id))를 사용 중입니다. 전환 및 HUD 표시를 생략합니다.")
                #endif
                return
            }
        }
        
        // 3. 기존 전환 로직 및 HUD 표시
        let filter = [kTISPropertyInputSourceID: id] as CFDictionary
        if let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource],
           let target = list.first {
            TISSelectInputSource(target)
            if SettingsManager.shared.showVisualFeedback {
                if let namePtr = TISGetInputSourceProperty(target, kTISPropertyLocalizedName) {
                    let name = Unmanaged<CFString>.fromOpaque(namePtr).takeUnretainedValue() as String
                    DispatchQueue.main.async { HUDManager.shared.showHUD(languageName: name) }
                }
            }
        }
    }
    
    // 🌟 새로운 기능: 다음 입력 소스로 순환(Toggle)하는 함수
    func switchToNextInputSource() {
        guard let currentSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let idPtr = TISGetInputSourceProperty(currentSource, kTISPropertyInputSourceID) else { return }
        let currentID = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String

        guard !availableKeyboards.isEmpty else { return }

        // 현재 언어의 인덱스를 찾아 다음 인덱스로 넘어갑니다 (끝에 도달하면 처음으로)
        if let currentIndex = availableKeyboards.firstIndex(where: { $0.id == currentID }) {
            let nextIndex = (currentIndex + 1) % availableKeyboards.count
            switchLanguage(to: availableKeyboards[nextIndex].id)
        } else {
            switchLanguage(to: availableKeyboards[0].id)
        }
    }
}
