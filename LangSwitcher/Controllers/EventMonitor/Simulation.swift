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
            // 🌟 [디버거 로깅 추가] 사용자의 수동 전환 이벤트 기록
            let trace = TraceFactory.create(
                event: .languageSwitch,
                result: .switched,
                reason: .manualOverride,
                appName: targetAppName
            )
            
            if isToggle {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    InputSourceManager.shared.switchToNextInputSource()
                    StatsManager.shared.incrementLanguageSwitch()
                    DecisionTraceManager.shared.record(trace) // 🌟 기록 저장
                }
            }
            else if let bundleID = targetAppID {
                launchApp(bundleID: bundleID)
            }
            else if let lang = targetLang {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    InputSourceManager.shared.switchLanguage(to: lang)
                    StatsManager.shared.incrementLanguageSwitch()
                    DecisionTraceManager.shared.record(trace) // 🌟 기록 저장
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
        self.batchDelete(count: originalLength) { [weak self] in
            guard let self = self else { return }
            
            // 1. 교정된 텍스트 먼저 삽입
            self.postUnicodeString(correctedText)
            
            // 2. 텍스트가 대상 앱에 완전히 입력될 시간을 0.03초 기다린 후 한글 전환 명령
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                self.safeSwitchToKorean()
                
                // 🌟 [핵심 수정] macOS가 실제로 입력 소스를 한글로 완전히 바꾸는 물리적 여유 시간(Buffer)을 0.02초 추가로 줍니다.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                    self.postTriggerKey(keyCode: triggerKeyCode)
                    StatsManager.shared.incrementTypoCorrection()
                }
            }
        }
    }

    func batchDelete(count: Int, completion: @escaping () -> Void) {
        guard count > 0 else {
            completion()
            return
        }
        for i in 0..<count {
            let delay = Double(i) * 0.01
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self.postKeyEvent(keyCode: 51, keyDown: true)
                self.postKeyEvent(keyCode: 51, keyDown: false)
            }
        }
        let totalDelay = Double(count) * 0.01 + 0.005
        DispatchQueue.main.asyncAfter(deadline: .now() + totalDelay) {
            completion()
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
    
    // 🌟 [디버거 로깅 추가] 트리거 텍스트를 받아서 기록하는 로직 추가
    func performTextExpansion(triggerLength: Int, replacementText: String, triggerKeyCode: UInt16, triggerText: String = "Unknown") {
        
        self.batchDelete(count: triggerLength) { [weak self] in
            guard let self = self else { return }
            
            self.insertLongUnicodeText(replacementText) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                    self.postTriggerKey(keyCode: triggerKeyCode)
                    
                    // 🌟 스니펫 확장 성공 로깅
                    let trace = TraceFactory.create(
                        event: .snippetExpansion,
                        result: .expanded,
                        reason: .snippetExpanded(trigger: triggerText)
                    )
                    DecisionTraceManager.shared.record(trace) // 🌟 기록 저장
                }
            }
        }
    }
    
    // 🌟 [최적화 유지] 무거운 앱 호환성을 위한 버퍼 적용 로직 유지
    func insertLongUnicodeText(_ text: String, completion: @escaping () -> Void) {
        let chars = Array(text.utf16)
        if chars.isEmpty {
            completion()
            return
        }
        
        let chunkSize = 20
        var chunks: [[UTF16.CodeUnit]] = []
        for i in stride(from: 0, to: chars.count, by: chunkSize) {
            let end = min(i + chunkSize, chars.count)
            chunks.append(Array(chars[i..<end]))
        }
        
        let chunkDelay: TimeInterval = 0.015 // 안전한 청크 딜레이
        
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
        
        // 충분한 여유(Buffer) 시간 확보
        let lastChunkIndex = max(0, chunks.count - 1)
        let lastChunkDelay = Double(lastChunkIndex) * chunkDelay
        let completionBuffer: TimeInterval = 0.05
        
        let totalDelay = lastChunkDelay + completionBuffer
        
        DispatchQueue.main.asyncAfter(deadline: .now() + totalDelay) {
            completion()
        }
    }
}
