//
//  Simulation.swift
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

// 🌟 [최종 수복 포인트 1: 전체 익스텐션 메인 액터 격리벽 수립]
// 하부의 모든 매니저 자산들과 궤적을 일치시켜 스레드 경계 침범 에러(Snapshot 컴파일 에러)를 근본적으로 소각합니다.
@MainActor
extension EventMonitor {
    
    func isCurrentLanguageEnglish() -> Bool {
        guard let currentSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(currentSource, kTISPropertyInputSourceID) else { return false }
        let id = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
        let lower = id.lowercased()
        return lower.contains("en") || lower.contains("abc") || lower.contains("us")
    }

    func safeSwitchToKorean() {
        let filter: NSDictionary = [
            (kTISPropertyInputSourceType as String): (kTISTypeKeyboardLayout as String)
        ]
        guard let list = TISCreateInputSourceList(filter as CFDictionary, false)?.takeRetainedValue() as? [TISInputSource] else { return }

        for source in list {
            if let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
                let id = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
                let lower = id.lowercased()
                if lower.contains("ko") || lower.contains("hangul") || lower.contains("두벌식") || lower.contains("세벌식") {
                    // 🌟 [8번 리뷰 수복 완료: 밀수 경로 차단 및 중복 피드백 소각]
                    // 정문인 switchLanguage가 모든 햅틱/글로우 처리를 수반하므로 수동 playFeedback 라인을 제거하여 투스텝 진동 버그를 진압합니다.
                    InputSourceManager.shared.switchLanguage(to: id)
                    break
                }
            }
        }
    }

    static func executeAction(targetLang: String?, targetAppID: String?, targetAppName: String? = nil, isToggle: Bool, rule: String) {
        if !AccessibilityManager.shared.isTrusted {
            SettingsManager.shared.addLog(ActionLog(timestamp: Date(), targetApp: "System", appliedRule: rule, finalInputSource: targetLang ?? "Unknown", result: .failure, failureReason: .permissionIssue))
            return
        }

        guard EventMonitor.shared.canExecuteAction() else { return }

        // @MainActor 격리 도메인에 합류했으므로 아무런 비동기 장벽 오버헤드 없이 청정하게 상수를 스캔합니다.
        let snapshot = SettingsManager.shared.snapshot
        if snapshot.isTestMode {
            var testLabel = ""
            if isToggle { testLabel = "[Test] Toggle Language" }
            else if let appName = targetAppName { testLabel = "[Test] \(appName)" }
            else if let langID = targetLang { testLabel = "[Test] \(InputSourceManager.shared.availableKeyboards.first(where: { $0.id == langID })?.name ?? langID)" }
            if !testLabel.isEmpty {
                HUDManager.shared.showHUD(languageName: testLabel)
            }
        } else {
            let trace = TraceFactory.create(event: .languageSwitch, result: .switched, reason: .manualOverride, appName: targetAppName)
            if isToggle {
                // 🌟 [아키텍처 평탄화] 불필요한 DispatchQueue 홉 가두리를 폐기하고 직관적인 프레임 지연 Task로 마이그레이션합니다.
                Task {
                    try? await Task.sleep(for: .seconds(0.05))
                    InputSourceManager.shared.switchToNextInputSource()
                    StatsManager.shared.incrementLanguageSwitch()
                    DecisionTraceManager.shared.record(trace)
                }
            } else if let bundleID = targetAppID {
                launchApp(bundleID: bundleID)
            } else if let lang = targetLang {
                Task {
                    try? await Task.sleep(for: .seconds(0.05))
                    InputSourceManager.shared.switchLanguage(to: lang)
                    StatsManager.shared.incrementLanguageSwitch()
                    DecisionTraceManager.shared.record(trace)
                }
            }
        }
    }

    static func launchApp(bundleID: String) {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: nil)
        }
    }
    
    func performAutoCorrection(originalLength: Int, correctedText: String, triggerKeyCode: UInt16) {
        self.safeSwitchToKorean()
        self.batchDelete(count: originalLength)
        self.postUnicodeString(correctedText)
        self.postTriggerKey(keyCode: triggerKeyCode)
        StatsManager.shared.incrementTypoCorrection()
    }

    func batchDelete(count: Int) {
        guard count > 0 else { return }
        for _ in 0..<count {
            self.postKeyEvent(keyCode: 51, keyDown: true)
            self.postKeyEvent(keyCode: 51, keyDown: false)
        }
    }

    func postKeyEvent(keyCode: UInt16, keyDown: Bool) {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: keyDown)
        event?.setIntegerValueField(.eventSourceUserData, value: 9999)
        event?.post(tap: .cghidEventTap)
    }

    func postUnicodeString(_ text: String) {
        var chars = Array(text.utf16)
        if !chars.isEmpty {
            let textEvent = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)
            textEvent?.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: &chars)
            textEvent?.setIntegerValueField(.eventSourceUserData, value: 9999)
            textEvent?.post(tap: .cghidEventTap)
        }
    }

    func postTriggerKey(keyCode: UInt16) {
        let triggerDown = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: true)
        let triggerUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: false)
        dprint("⌨️ [Simulation] 포스트 트리거 키 전송 완결: \(keyCode)")
        triggerDown?.setIntegerValueField(.eventSourceUserData, value: 9999)
        triggerUp?.setIntegerValueField(.eventSourceUserData, value: 9999)
        triggerDown?.post(tap: .cghidEventTap)
        triggerUp?.post(tap: .cghidEventTap)
    }
    
    func getCharacter(from keyCode: UInt16) -> Character? {
        return EventMonitor.charKeyMap[keyCode]
    }

    func performTextExpansion(triggerLength: Int, snippet: RenderedSnippet, triggerKeyCode: UInt16, triggerText: String = "Unknown") {
        self.batchDelete(count: triggerLength)

        self.insertLongUnicodeText(snippet.text) { [weak self] in
            guard let self = self else { return }

            Task {
                try? await Task.sleep(for: .seconds(0.02))
                self.postTriggerKey(keyCode: triggerKeyCode)

                if let offset = snippet.cursorOffsetFromStart {
                    let moveLeftCount = snippet.text.count - offset
                    if moveLeftCount > 0 {
                        self.moveCursorLeft(count: moveLeftCount)
                    }
                }

                // 🌟 [통계 아키텍처 결속] 텍스트 스니펫이 화면에 성공적으로 각인된 시점에 카운트를 폭발시킵니다.
                StatsManager.shared.incrementTextExpansion()

                let trace = TraceFactory.create(event: .snippetExpansion, result: .expanded, reason: .snippetExpanded(trigger: triggerText))
                DecisionTraceManager.shared.record(trace)
            }
        }
    }
    
    func moveCursorLeft(count: Int) {
        guard count > 0 else { return }
        let leftArrowKeyCode: CGKeyCode = 123
        
        for _ in 0..<count {
            let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: leftArrowKeyCode, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: leftArrowKeyCode, keyDown: false)
            
            keyDown?.setIntegerValueField(.eventSourceUserData, value: 9999)
            keyUp?.setIntegerValueField(.eventSourceUserData, value: 9999)
            
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
        }
    }
    
    // 🌟 [최종 최적화 수복 포인트 2: 안전한 스레드 보호막 완결]
    // 메인 액터 단일 타겟 스코프가 되었으므로, 수동 자물쇠 정산 루프(assumeIsolated)의 오버헤드가 완전히 걷혀 나갔습니다.
    func insertLongUnicodeText(_ text: String, completion: @escaping @MainActor @Sendable () -> Void) {
        self.pendingInsertTasks.forEach { $0.cancel() }
        self.pendingInsertTasks.removeAll()

        let chars = Array(text.utf16)
        if chars.isEmpty { completion(); return }

        let chunkSize = 20
        var chunks: [[UTF16.CodeUnit]] = []
        for i in stride(from: 0, to: chars.count, by: chunkSize) {
            let end = min(i + chunkSize, chars.count)
            chunks.append(Array(chars[i..<end]))
        }

        let chunkDelay: TimeInterval = 0.015

        for (index, chunk) in chunks.enumerated() {
            let delay = Double(index) * chunkDelay

            let item = DispatchWorkItem {
                var localChunk = chunk
                if let eventDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) {
                    eventDown.keyboardSetUnicodeString(stringLength: localChunk.count, unicodeString: &localChunk)
                    eventDown.setIntegerValueField(.eventSourceUserData, value: 9999)
                    eventDown.post(tap: .cghidEventTap)
                }
                if let eventUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) {
                    eventUp.keyboardSetUnicodeString(stringLength: localChunk.count, unicodeString: &localChunk)
                    eventUp.setIntegerValueField(.eventSourceUserData, value: 9999)
                    eventUp.post(tap: .cghidEventTap)
                }
            }

            self.pendingInsertTasks.append(item)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        }

        let lastChunkIndex = max(0, chunks.count - 1)
        let totalDelay = Double(lastChunkIndex) * chunkDelay + 0.03

        let completionItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            
            // 메인 액터 격리가 완결되어 데이터 레이스 경고 없이 청정하게 장부를 청소하고 생명줄 콜백을 방출합니다.
            self.pendingInsertTasks.removeAll()
            completion()
        }

        self.pendingInsertTasks.append(completionItem)
        DispatchQueue.main.asyncAfter(deadline: .now() + totalDelay, execute: completionItem)
    }
}
