//
//  InputSourceManager.swift
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

import Foundation
import Carbon
import Combine

struct MacKeyboard: Identifiable, Hashable {
    let id: String
    let name: String
}

// 🌟 [최종 수복: Swift 6 전역 격리 완벽 수립]
@MainActor
class InputSourceManager: ObservableObject {
    static let shared = InputSourceManager()
    @Published var availableKeyboards: [MacKeyboard] = []

    private init() {
        // 초기화 시점에 비동기로 키보드 장부를 긁어와 앱 시작 레이턴시 블로킹을 원천 차단합니다.
        fetchKeyboards()
    }

    // MARK: - 시스템 키보드 입력 소스 동적 인출 엔진
        
    func fetchKeyboards() {
        // 🌟 [Swift 6 에러 완전 수복]
        // @MainActor가 상속되는 청정 Task 내부에서 백그라운드 독립 태스크(detached)를 구동하고,
        // 그 결과물([MacKeyboard])을 리턴값으로 안전하게 수령(await)하는 사상으로 전환합니다.
        Task {
            let keyboards = await Task.detached(priority: .userInitiated) { () -> [MacKeyboard] in
                guard let sourceList = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else { return [] }
                var localKeyboards: [MacKeyboard] = []

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

                    localKeyboards.append(MacKeyboard(id: id, name: name))
                }
                
                // 가변 장부를 클로저 캡처 없이 깨끗하게 데이터로 리턴합니다.
                return localKeyboards
            }.value

            // 🌟 백그라운드 연산이 끝나고 확약된 청정 상수 복사본(let keyboards)을
            // 메인 액터 컨텍스트 내부에서 직결 대입하므로 데이터 레이스 및 캡처 에러가 완벽하게 박멸됩니다.
            self.availableKeyboards = keyboards
            
            dprint("✨ [InputSource] 백그라운드 데이터 인출 및 메인 액터 장부 대입 완결.")
        }

        dprint("⌨️ [InputSource] 하드웨어 레지스트리 조회 태스크를 백그라운드 병렬 풀로 격리 이주 성공.")
    }

    func switchLanguage(to id: String) {
        if let currentSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
           let ptr = TISGetInputSourceProperty(currentSource, kTISPropertyInputSourceID) {
            let currentID = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
            
            if currentID == id {
                dprint("💡 이미 해당 언어(\(id))를 사용 중입니다. 전환 및 피드백 전개를 생략합니다.")
                return
            }
        }
        
        let filter = [kTISPropertyInputSourceID: id] as CFDictionary
        if let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource],
           let target = list.first {
            TISSelectInputSource(target)
            
            // 데이터 분석 커널에 안전 기입
            StatsManager.shared.incrementLanguageSwitch()
            
            // 🌟 [최적화 정산] 이미 @MainActor 구역이므로 불필요한 main.async 소각, 즉시 피드백 구동
            EdgeGlowManager.shared.showGlow(forLanguage: id)
            SensoryFeedbackManager.shared.playFeedback(forLanguageID: id)
                        
            if SettingsManager.shared.showVisualFeedback {
                if let namePtr = TISGetInputSourceProperty(target, kTISPropertyLocalizedName) {
                    let name = Unmanaged<CFString>.fromOpaque(namePtr).takeUnretainedValue() as String
                    HUDManager.shared.showHUD(languageName: name)
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
    
    // MARK: - Browser Tab Memory Helpers
    
    /// 현재 활성화된 키보드 입력 소스의 고유 ID를 안전하게 반환합니다.
    func currentInputSourceID() -> String {
        // 🌟 [우주 방어 수복] 닐 크래시를 유발하던 날것의 강제 추출을 제거하고 옵셔널 언랩 가드를 결속했습니다.
        guard let currentSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(currentSource, kTISPropertyInputSourceID) else {
            return ""
        }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }
    
    /// 주어진 고유 ID를 가진 입력 소스로 즉시 전환합니다.
    func switchInputSource(to sourceID: String) {
        let filter = [kTISPropertyInputSourceID as String: sourceID] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource],
              let source = list.first else { return }
        
        TISSelectInputSource(source)
    }
    
    /// 현재 선택된 입력 소스의 로컬라이즈 이름을 반환합니다.
    var currentInputSourceName: String {
        guard let currentSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let namePtr = TISGetInputSourceProperty(currentSource, kTISPropertyLocalizedName) else {
            return "Unknown"
        }
        return Unmanaged<CFString>.fromOpaque(namePtr).takeUnretainedValue() as String
    }
}
