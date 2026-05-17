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
    
    // 🌟 [핵심 변경 1] 순서 최적화 및 딜레이 제거
    func performAutoCorrection(originalLength: Int, correctedText: String, triggerKeyCode: UInt16) {
        // 1. 가장 먼저 한글 전환을 OS에 던져놓아 물리적 딜레이 시간을 법니다.
        self.safeSwitchToKorean()
        
        // 2. 딜레이(async) 없이 빛의 속도로 백스페이스를 쏟아냅니다.
        self.batchDelete(count: originalLength)
        
        // 3. 딜레이 없이 즉각 교정 텍스트 삽입
        self.postUnicodeString(correctedText)
        
        // 4. 스페이스바 즉각 전송
        self.postTriggerKey(keyCode: triggerKeyCode)
        
        StatsManager.shared.incrementTypoCorrection()
    }

    // 🌟 [핵심 변경 2] 타이머 완전 삭제. 사용자 입력과 뒤섞이는 끔찍한 버그 해결
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
        triggerDown?.setIntegerValueField(.eventSourceUserData, value: 9999)
        triggerUp?.setIntegerValueField(.eventSourceUserData, value: 9999)
        triggerDown?.post(tap: .cghidEventTap)
        triggerUp?.post(tap: .cghidEventTap)
    }
    
    func getCharacter(from keyCode: UInt16) -> Character? {
        return EventMonitor.charKeyMap[keyCode]
    }
    
    // 🌟 [수정] 파라미터를 replacementText에서 snippet: RenderedSnippet으로 변경
    func performTextExpansion(triggerLength: Int, snippet: RenderedSnippet, triggerKeyCode: UInt16, triggerText: String = "Unknown") {
        // 🌟 텍스트 대치 시에도 즉각 삭제 사용
        self.batchDelete(count: triggerLength)
        
        // 🌟 교체: 단순 문자열이 아닌 snippet.text를 삽입
        self.insertLongUnicodeText(snippet.text) { [weak self] in
            guard let self = self else { return }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                // 1. 트리거 키(예: 스페이스바, 엔터) 전송
                self.postTriggerKey(keyCode: triggerKeyCode)
                
                // 2. 🌟 커서 위치 복원 연산 및 실행
                if let cursorOffset = snippet.cursorOffsetFromStart {
                    let textLength = snippet.text.count
                    
                    // 주의: 방금 위에서 postTriggerKey로 스페이스/엔터가 추가되었으므로
                    // 커서가 1칸 더 우측으로 밀려 있습니다. 따라서 '+ 1'을 해줍니다.
                    // (만약 텍스트 대치 후 스페이스바가 남는 것이 싫다면, 커서가 있을 때 postTriggerKey를 생략하는 분기 처리를 해도 됩니다.)
                    let moveLeftCount = (textLength - cursorOffset) + 1
                    
                    if moveLeftCount > 0 {
                        self.moveCursorLeft(count: moveLeftCount)
                    }
                }
                
                let trace = TraceFactory.create(event: .snippetExpansion, result: .expanded, reason: .snippetExpanded(trigger: triggerText))
                DecisionTraceManager.shared.record(trace)
            }
        }
    }
    
    // 🌟 [추가] 지정된 횟수만큼 왼쪽 방향키(←) 이벤트를 발생시키는 헬퍼 메서드
    func moveCursorLeft(count: Int) {
        guard count > 0 else { return }
        let leftArrowKeyCode: CGKeyCode = 123 // kVK_LeftArrow
        
        for _ in 0..<count {
            let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: leftArrowKeyCode, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: leftArrowKeyCode, keyDown: false)
            
            // EventMonitor의 재귀적 루프를 막기 위해 9999 태그 부여
            keyDown?.setIntegerValueField(.eventSourceUserData, value: 9999)
            keyUp?.setIntegerValueField(.eventSourceUserData, value: 9999)
            
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
        }
    }
    
    func insertLongUnicodeText(_ text: String, completion: @escaping () -> Void) {
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
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
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
        }
        
        let lastChunkIndex = max(0, chunks.count - 1)
        let totalDelay = Double(lastChunkIndex) * chunkDelay + 0.05
        DispatchQueue.main.asyncAfter(deadline: .now() + totalDelay) { completion() }
    }
}
