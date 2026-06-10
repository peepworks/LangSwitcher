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
                    TISSelectInputSource(source)
                    SensoryFeedbackManager.shared.playFeedback(forLanguageID: id)
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

        let snapshot = SettingsManager.shared.snapshot
        if snapshot.isTestMode {
            var testLabel = ""
            if isToggle { testLabel = "[Test] Toggle Language" }
            else if let appName = targetAppName { testLabel = "[Test] \(appName)" }
            else if let langID = targetLang { testLabel = "[Test] \(InputSourceManager.shared.availableKeyboards.first(where: { $0.id == langID })?.name ?? langID)" }
            if !testLabel.isEmpty { DispatchQueue.main.async { HUDManager.shared.showHUD(languageName: testLabel) } }
        } else {
            let trace = TraceFactory.create(event: .languageSwitch, result: .switched, reason: .manualOverride, appName: targetAppName)
            if isToggle {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    InputSourceManager.shared.switchToNextInputSource()
                    StatsManager.shared.incrementLanguageSwitch()
                    DecisionTraceManager.shared.record(trace)
                }
            } else if let bundleID = targetAppID {
                launchApp(bundleID: bundleID)
            } else if let lang = targetLang {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    InputSourceManager.shared.switchLanguage(to: lang)
                    StatsManager.shared.incrementLanguageSwitch()
                    DecisionTraceManager.shared.record(trace)
                }
            }
        }
    }

    static func launchApp(bundleID: String) {
        DispatchQueue.main.async {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                let config = NSWorkspace.OpenConfiguration()
                NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: nil)
            }
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
        
        // 후행 클로저에 메인 액터 및 샌더블 마킹을 결속하여 동시성 레이스를 사전 차단합니다.
        self.insertLongUnicodeText(snippet.text) { [weak self] in
            guard let self = self else { return }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                self.postTriggerKey(keyCode: triggerKeyCode)
                
                if let offset = snippet.cursorOffsetFromStart {
                    let moveLeftCount = snippet.text.count - offset
                    if moveLeftCount > 0 {
                        self.moveCursorLeft(count: moveLeftCount)
                    }
                }
                
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
    
    // 🌟 [6번 리뷰 및 프로덕션 킬러 버그 완벽 정산 수복 완료 본]
    func insertLongUnicodeText(_ text: String, completion: @escaping @MainActor @Sendable () -> Void) {
        // 1. 새로운 대치가 개시되므로 기존 어레이 장부를 순회하며 타이머 전량 사살 및 초기화
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

        // 2. 청크 단위 타이핑 입력 이벤트 예약 파이프라인
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

        // 3단계: 최종 마감 조립 구역 (복잡성 제거 및 100% 동기화 안착)
        let lastChunkIndex = max(0, chunks.count - 1)
        let totalDelay = Double(lastChunkIndex) * chunkDelay + 0.03

        // 마스터 캔슬 플래그 껍데기를 치워버리고, completionItem 그 자체를 추적 장부에 직결 락온합니다.
        let completionItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
                
            // Swift 6 컴파일러에게 이 구역이 맑은 메인 액터 도메인임을 런타임 단언문으로 증명 통과시킵니다.
            MainActor.assumeIsolated {
                // 상주형 대기 태스크 장부 청소 완결
                self.pendingInsertTasks.removeAll()
                
                // 🌟 [우주 방어 수복 포인트: 드롭되었던 생명줄 복원]
                // 누락되어 텍스트 치환 엔진 전체를 멈추게 만들었던 후행 정산 콜백을 칼같이 실행 확약합니다!
                completion()
            }
        }

        // 이제 진짜 주행 대상을 장부에 대입하여 외부 연타 취소 신호가 100% 동기 반영되도록 설계합니다.
        self.pendingInsertTasks.append(completionItem)
        DispatchQueue.main.asyncAfter(deadline: .now() + totalDelay, execute: completionItem)
    }
}
