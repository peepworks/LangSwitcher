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

    // 🌟 [수복] 연속 언어 변경 시 무거운 UI/햅틱/사운드의 낭비를 막는 스로틀링 타임 (80ms)
    private let uiEffectDebounceInterval: TimeInterval = 0.08
    private var uiEffectTask: Swift.Task<Void, Never>?

    private init() {
        fetchKeyboards()
    }

    // MARK: - 시스템 키보드 입력 소스 동적 인출 엔진

    func fetchKeyboards() {
        Task { @MainActor in
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

            self.availableKeyboards = localKeyboards
            dprint("✨ [InputSource] 메인 액터 격리 보장 하에 순정 TIS 키보드 레지스트리 \(localKeyboards.count)개 인출 완료.")
        }
    }

    // 🌟 [수복 정산 완료] 저수준 언어 전환은 딜레이 없이 실행하고, 무거운 피드백(UI/Sound/HUD)만 스로틀링 적용
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
            
            // 1. [즉시 처리] OS 입력 레이아웃 전환은 지연 없이 바로 즉시 집행합니다. (타이핑 무결성 유지)
            TISSelectInputSource(target)

            // 2. [부수 효과 예약 제거] 기존 대기 중인 UI 렌더링/사운드 재생 태스크가 있다면 빛의 속도로 취소시킵니다.
            uiEffectTask?.cancel()

            // 3. [스로틀링 레이어 작동] 80ms 디바운스 대기열을 새로이 수립합니다.
            uiEffectTask = Swift.Task { @MainActor in
                do {
                    // 지정된 시간 동안 추가 입력 소스 요청이 없는지 관망합니다.
                    try await Swift.Task.sleep(for: .seconds(self.uiEffectDebounceInterval))
                    guard !Swift.Task.isCancelled else { return }

                    // 🌟 관망 시간 동안 조용했다면, 최종 결정된 최적 소스의 무거운 피드백을 단 한 번만 일괄 배출합니다.
                    StatsManager.shared.incrementLanguageSwitch()
                    EdgeGlowManager.shared.showGlow(forLanguage: id)
                    SensoryFeedbackManager.shared.playFeedback(for: id)

                    if SettingsManager.shared.snapshot.showVisualFeedback {
                        if let namePtr = TISGetInputSourceProperty(target, kTISPropertyLocalizedName) {
                            let name = Unmanaged<CFString>.fromOpaque(namePtr).takeUnretainedValue() as String
                            HUDManager.shared.showHUD(languageName: name)
                        }
                    }
                    
                    #if DEBUG
                    dprint("🎨 [UI Sync] 최종 정산 언어(\(id))의 헤비 비주얼/하드웨어 이펙트 정산 완결.")
                    #endif

                } catch {
                    // Task가 취소되면 리소스 회수 후 가볍게 아웃
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

    func currentInputSourceID() -> String {
        guard let currentSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(currentSource, kTISPropertyInputSourceID) else {
            return ""
        }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    func switchInputSource(to sourceID: String) {
        let filter = [kTISPropertyInputSourceID as String: sourceID] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource],
              let source = list.first else { return }

        TISSelectInputSource(source)
    }

    var currentInputSourceName: String {
        guard let currentSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let namePtr = TISGetInputSourceProperty(currentSource, kTISPropertyLocalizedName) else {
            return "Unknown"
        }
        return Unmanaged<CFString>.fromOpaque(namePtr).takeUnretainedValue() as String
    }
}
