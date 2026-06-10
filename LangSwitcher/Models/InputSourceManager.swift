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

    func fetchKeyboards() {
        // 🌟 [우주 방어 수복 포인트]
        // 변수 대입 방식(let fetchTask)을 탈피하고 클로저를 메인 큐 비동기 파이프라인에 인라인으로 직결합니다.
        // 클로저 도입부에 '@MainActor'를 명시함으로써 Swift 6 컴파일러가 요구하는
        // @MainActor @Sendable @convention(block) 조건을 전량 충족하고 컴파일 에러를 원천 박멸합니다.
        DispatchQueue.main.async { @MainActor [weak self] in
            guard let self = self else { return }
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
            
            // @MainActor 컨텍스트 내부이므로 @Published 프로퍼티 장부 대입 역시 완벽하게 세이프티합니다.
            self.availableKeyboards = keyboards
        }

        dprint("⌨️ [InputSource] 메인 스레드 교착 리스크를 원천 차단하며 비동기(async) 키보드 리스트 갱신 예약 완료.")
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
