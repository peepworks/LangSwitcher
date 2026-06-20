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

struct MacKeyboard: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
}

@MainActor
class InputSourceManager: ObservableObject {
    static let shared = InputSourceManager()
    @Published var availableKeyboards: [MacKeyboard] = []

    private init() {
        // 초기화 시점에 안전하게 메인 스레드 비동기 루프로 스케줄링을 이관합니다.
        fetchKeyboards()
    }

    // MARK: - 시스템 키보드 입력 소스 동적 인출 엔진

    func fetchKeyboards() {
        // 🌟 [우주 방어 수복 포인트] Carbon TIS/TSM 계통 커널 API는 반드시 메인 스레드(Queue)에서 실행되어야 합니다.
        // Task 구조 안에서 명시적으로 메인 스레드 바인딩을 보장하여 SIGTRAP 5 크래시를 원천 박멸합니다.
        Task { @MainActor in
            
            // 데이터 수집 연산은 메인 스레드에서 안전하게 집행합니다.
            // (이 API는 캐시된 장부를 긁어오므로 메인 큐에서 동작해도 프레임 드롭이 전혀 없습니다)
            guard let sourceList = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
                self.availableKeyboards = []
                return
            }
            
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

            // 인메모리 장부에 원자적 플러시 대입 완료
            self.availableKeyboards = localKeyboards
            dprint("✨ [InputSource] 메인 액터 격리 보장 하에 순정 TIS 키보드 레지스트리 \(localKeyboards.count)개 인출 완료.")
        }
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

            EdgeGlowManager.shared.showGlow(forLanguage: id)

            // 라벨 동기화 정산
            SensoryFeedbackManager.shared.playFeedback(for: id)

            if SettingsManager.shared.snapshot.showVisualFeedback {
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
