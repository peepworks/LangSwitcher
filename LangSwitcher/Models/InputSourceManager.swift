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
        // 🌟 [리뷰 반영] 메인 스레드에서만 실행되어야 하는 TIS API 로직을 하나의 블록으로 묶습니다.
        let fetchTask = {
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
            
            // @Published 변수 업데이트는 당연히 메인 스레드에서 이루어집니다.
            self.availableKeyboards = keyboards
        }

        // 🌟 [리뷰 반영] 현재 실행 중인 스레드가 메인 스레드인지 확인합니다.
        // 메인 스레드라면 즉시 실행하고, 아니라면 메인 큐에 동기(sync)로 밀어 넣어 데드락과 크래시를 원천 방지합니다.
        if Thread.isMainThread {
            fetchTask()
        } else {
            DispatchQueue.main.sync {
                fetchTask()
            }
        }
    }

    func switchLanguage(to id: String) {
        if let currentSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
           let ptr = TISGetInputSourceProperty(currentSource, kTISPropertyInputSourceID) {
            let currentID = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
            
            if currentID == id {
                #if DEBUG
                print("💡 이미 해당 언어(\(id))를 사용 중입니다. 전환 및 HUD 표시를 생략합니다.")
                #endif
                return
            }
        }
        
        let filter = [kTISPropertyInputSourceID: id] as CFDictionary
        if let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource],
           let target = list.first {
            TISSelectInputSource(target)
            // 🌟 [추가] 노치 엣지 글로우 피드백 실행
            EdgeGlowManager.shared.showGlow(forLanguage: id)
            
            // 🌟 [추가] 언어 전환 성공 시 햅틱 및 사운드 실행!
            SensoryFeedbackManager.shared.playFeedback(forLanguageID: id)
                        
            if SettingsManager.shared.showVisualFeedback {
                if let namePtr = TISGetInputSourceProperty(target, kTISPropertyLocalizedName) {
                    let name = Unmanaged<CFString>.fromOpaque(namePtr).takeUnretainedValue() as String
                    DispatchQueue.main.async { HUDManager.shared.showHUD(languageName: name) }
                }
            }
        }
    }
    
    func switchToNextInputSource() {
        guard let currentSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let idPtr = TISGetInputSourceProperty(currentSource, kTISPropertyInputSourceID) else { return }
        let currentID = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String

        guard !availableKeyboards.isEmpty else { return }

        if let currentIndex = availableKeyboards.firstIndex(where: { $0.id == currentID }) {
            let nextIndex = (currentIndex + 1) % availableKeyboards.count
            switchLanguage(to: availableKeyboards[nextIndex].id)
        } else {
            switchLanguage(to: availableKeyboards[0].id)
        }
    }
}
