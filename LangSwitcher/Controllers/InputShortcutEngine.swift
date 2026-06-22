//
//  InputShortcutEngine.swift
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
import Carbon

@MainActor
final class InputShortcutEngine { // 🌟 [최종 수복] 불필요한 유령 ObservableObject 상속을 제거하여 스레드 안전성 최적화
    static let shared = InputShortcutEngine()

    // 하드웨어 이벤트를 전송하는 비동기 스트림 관로
    private var streamContinuation: AsyncStream<SequentialKeyStroke>.Continuation?
    private var activeCache: CompressedShortcutCache?
    
    // 이중 조합키(Chord) 매칭 시퀀스 버퍼 상태 장부
    private var primaryStrokeBuffer: SequentialKeyStroke?
    private var chordResetTask: Task<Void, Never>?

    private init() {
        setupPipelineStream()
    }

    /// 하드웨어를 소비하는 청정 비동기 관측 파이프라인 개설
    private func setupPipelineStream() {
        let keyStream = AsyncStream<SequentialKeyStroke> { continuation in
            self.sendContinuation(continuation)
        }

        Task { [weak self] in
            for await stroke in keyStream {
                guard let self = self else { return }
                self.processRouteEvaluation(stroke)
            }
        }
    }
    
    // Continuation 캡처용 주입 헬퍼
    private func sendContinuation(_ continuation: AsyncStream<SequentialKeyStroke>.Continuation) {
        self.streamContinuation = continuation
    }

    /// 하드웨어 스레드에서 락 프리(Lock-Free) 사양으로 이벤트를 수신하는 기입 창구
    nonisolated func injectEvent(keyCode: UInt16, modifierFlags: UInt64) {
        Task { @MainActor in
            self.streamContinuation?.yield(SequentialKeyStroke(keyCode: keyCode, modifierFlags: modifierFlags))
        }
    }

    /// 엔진 스냅샷 대입 플러시 (SettingsManager 연동선)
    func syncEngineCache(_ snapshot: SettingsSnapshot) {
        let cleanToggle = snapshot.toggleKeyCode > 0 || snapshot.toggleModifierFlags > 0 ?
            SequentialKeyStroke(keyCode: snapshot.toggleKeyCode, modifierFlags: snapshot.toggleModifierFlags) : nil
        
        var customs: [SequentialKeyStroke: String] = [:]
        for (_, rule) in snapshot.customShortcutCache {
            customs[SequentialKeyStroke(keyCode: rule.keyCode, modifierFlags: rule.modifierFlags)] = rule.targetLanguage
        }

        var launches: [SequentialKeyStroke: (bundleID: String, name: String)] = [:]
        for (_, rule) in snapshot.appLaunchShortcutCache {
            launches[SequentialKeyStroke(keyCode: rule.keyCode, modifierFlags: rule.modifierFlags)] = (rule.bundleIdentifier, rule.appName)
        }

        let cleanTypo = snapshot.isTypoCorrectionEnabled && snapshot.typoKeyCode > 0 ?
            SequentialKeyStroke(keyCode: snapshot.typoKeyCode, modifierFlags: snapshot.typoModifierFlags) : nil

        self.activeCache = CompressedShortcutCache(
            toggleKey: cleanToggle,
            customShortcuts: customs,
            appLaunchShortcuts: launches,
            typoShortcut: cleanTypo
        )
    }

    // MARK: - 비동기 순차 매칭 라우터 오토마타 (Evaluation Router)

    private func processRouteEvaluation(_ stroke: SequentialKeyStroke) {
        guard let cache = activeCache else { return }
        
        // 1단계: 기존 이중 조합(Chord) 버퍼가 차있을 때 후행 연속키 조합 매칭 정산
        if let primary = primaryStrokeBuffer {
            chordResetTask?.cancel()
            primaryStrokeBuffer = nil
            
            dprint("🔗 [ShortcutEngine] 후행 이중 조합키 매칭 라우팅 진입 -> Primary: \(primary.keyCode), Secondary: \(stroke.keyCode)")
            return
        }

        // 2단계: 단일 조합 핫 패스 매칭 평가 개시 (O(1) 해시 넌블로킹 통과)
        
        // A. 한/영 토글 규칙 평가
        if let toggle = cache.toggleKey, toggle == stroke {
            dprint("🎯 [ShortcutEngine] 스트림 매칭 성공: 한/영 전환 토글 작동선 돌파.")
            EventMonitor.executeAction(targetLang: nil, targetAppID: nil, isToggle: true, rule: "Stream Toggle Key")
            return
        }

        // B. 오타 교정 규칙 평가
        if let typo = cache.typoShortcut, typo == stroke {
            dprint("🎯 [ShortcutEngine] 스트림 매칭 성공: 수동 오타 교정 집행.")
            TypoConverter.shared.executeCorrection()
            return
        }

        // C. 앱 실행 단축키 규칙 평가
        if let launch = cache.appLaunchShortcuts[stroke] {
            dprint("🎯 [ShortcutEngine] 스트림 매칭 성공: 앱 실행 [\(launch.name)]")
            EventMonitor.executeAction(targetLang: nil, targetAppID: launch.bundleID, targetAppName: launch.name, isToggle: false, rule: "Stream App Launch")
            return
        }

        // D. 커스텀 언어 직결 단축키 규칙 평가
        if let targetLang = cache.customShortcuts[stroke] {
            dprint("🎯 [ShortcutEngine] 스트림 매칭 성공: 특정 언어 직결 전환 [\(targetLang)]")
            EventMonitor.executeAction(targetLang: targetLang, targetAppID: nil, isToggle: false, rule: "Stream Custom Shortcut")
            return
        }
    }
}
