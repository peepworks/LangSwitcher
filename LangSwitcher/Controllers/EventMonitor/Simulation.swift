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

@MainActor
extension EventMonitor {

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
        self.postUnicodeString(" ")
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
        triggerDown?.setIntegerValueField(.eventSourceUserData, value: 9999)
        triggerUp?.setIntegerValueField(.eventSourceUserData, value: 9999)
        triggerDown?.post(tap: .cghidEventTap)
        triggerUp?.post(tap: .cghidEventTap)
    }

    func getCharacter(from keyCode: UInt16) -> Character? {
        return EventMonitor.charKeyMap[keyCode]
    }

    // MARK: - 🌟 IDE 컨텍스트 인지형 하이브리드 대치 엔진
    func performTextExpansion(triggerLength: Int, template: String, triggerKeyCode: UInt16, triggerText: String = "Unknown") {
        self.snippetInsertionTask?.cancel()

        self.batchDelete(count: triggerLength)

        self.snippetInsertionTask = Task { [weak self] in
            guard let self = self else { return }
            
            let snippet = TextExpander.shared.expand(template: template)
            
            let insertText = snippet.text
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\n", with: "\r")
            let insertLength = insertText.count

            let currentAppID = globalActiveAppTracker.get()
            let autoCompletingIDEs = ["com.microsoft.VSCode", "com.apple.dt.Xcode", "com.google.android.studio"]
            let isIDE = autoCompletingIDEs.contains(where: { currentAppID.lowercased().contains($0.lowercased()) }) || autoCompletingIDEs.contains(currentAppID)
            
            let hasNavigation = !snippet.tabStops.isEmpty || snippet.finalCaretOffset != nil
            let isLongText = insertLength >= 200

            guard !Task.isCancelled else { return }
            
            if isIDE || (isLongText && !hasNavigation) {
                await self.insertViaClipboardPacingAsync(insertText)
            } else {
                await self.insertLongUnicodeTextAsync(insertText)
            }
            
            guard !Task.isCancelled else { return }
            
            do {
                try await Task.sleep(nanoseconds: 200_000_000)
            } catch { return }
            
            guard !Task.isCancelled else { return }
            
            if !hasNavigation {
                self.postTriggerKey(keyCode: triggerKeyCode)
            }

            if !snippet.tabStops.isEmpty {
                let activePID = WindowMonitor.shared.currentPID
                let session = ActiveSnippetSession(
                    targetPID: activePID,
                    initialCaretLocation: NSRange(location: 0, length: 0),
                    tabStops: snippet.tabStops
                )
                session.finalCaretOffset = snippet.finalCaretOffset
                self.activeSnippetSession = session
                
                let firstStop = snippet.tabStops[0]
                let initialMoveLeft = insertLength - firstStop.range.location
                
                if initialMoveLeft > 0 {
                    await self.moveCursorLeftAsync(count: initialMoveLeft)
                }
                
                guard !Task.isCancelled else { return }
                
                if firstStop.range.length > 0 {
                    do {
                        try await Task.sleep(nanoseconds: 20_000_000)
                    } catch { return }
                    
                    guard !Task.isCancelled else { return }
                    await self.simulateArrowMovementAsync(keyCode: 124, count: firstStop.range.length, withShift: true)
                }
            } else if let offset = snippet.finalCaretOffset {
                let moveLeftCount = insertLength - offset
                if moveLeftCount > 0 {
                    await self.moveCursorLeftAsync(count: moveLeftCount)
                }
            }

            guard !Task.isCancelled else { return }

            StatsManager.shared.incrementTextExpansion()
            let trace = TraceFactory.create(event: .snippetExpansion, result: .expanded, reason: .snippetExpanded(trigger: triggerText))
            DecisionTraceManager.shared.record(trace)
        }
    }

    func moveCursorLeftAsync(count: Int) async {
        guard count > 0 else { return }
        let leftArrowKeyCode: CGKeyCode = 123
        let source = CGEventSource(stateID: .combinedSessionState)
        for _ in 0..<count {
            guard !Task.isCancelled else { break }
            
            let down = CGEvent(keyboardEventSource: source, virtualKey: leftArrowKeyCode, keyDown: true)
            let up = CGEvent(keyboardEventSource: source, virtualKey: leftArrowKeyCode, keyDown: false)
            down?.setIntegerValueField(.eventSourceUserData, value: 9999)
            up?.setIntegerValueField(.eventSourceUserData, value: 9999)
            
            down?.post(tap: .cghidEventTap)
            
            do {
                try await Task.sleep(nanoseconds: 2_000_000)
                guard !Task.isCancelled else { break }
                up?.post(tap: .cghidEventTap)
                try await Task.sleep(nanoseconds: 2_000_000)
            } catch {
                break
            }
        }
    }

    func insertLongUnicodeTextAsync(_ text: String) async {
        let chars = Array(text.utf16)
        if chars.isEmpty { return }

        let source = CGEventSource(stateID: .combinedSessionState)
        for char in chars {
            guard !Task.isCancelled else { break }
            
            var unicodeChar = char
            if let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
               let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {

                down.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unicodeChar)
                down.setIntegerValueField(.eventSourceUserData, value: 9999)
                
                up.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unicodeChar)
                // 🌟 [정산] 오타 수정 완료: .setIntegerValueField -> .eventSourceUserData
                up.setIntegerValueField(.eventSourceUserData, value: 9999)

                down.post(tap: .cghidEventTap)
                
                do {
                    try await Task.sleep(nanoseconds: 1_000_000)
                    guard !Task.isCancelled else { break }
                    up.post(tap: .cghidEventTap)
                    try await Task.sleep(nanoseconds: 1_000_000)
                } catch {
                    break
                }
            }
        }
    }

    private func insertViaClipboardPacingAsync(_ text: String) async {
        guard !Task.isCancelled else { return }
        
        let pasteboard = NSPasteboard.general
        let oldString = pasteboard.string(forType: .string)
        
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let source = CGEventSource(stateID: .combinedSessionState)
        if let vDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
           let vUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) {
            
            vDown.flags = .maskCommand
            vUp.flags = .maskCommand
            vDown.setIntegerValueField(.eventSourceUserData, value: 9999)
            vUp.setIntegerValueField(.eventSourceUserData, value: 9999)

            vDown.post(tap: .cghidEventTap)
            vUp.post(tap: .cghidEventTap)
        }

        do {
            try await Task.sleep(nanoseconds: 80_000_000)
        } catch {
            if let old = oldString {
                pasteboard.clearContents()
                pasteboard.setString(old, forType: .string)
            }
            return
        }

        if let old = oldString {
            pasteboard.clearContents()
            pasteboard.setString(old, forType: .string)
        }
    }
    
    func insertLongUnicodeText(_ text: String, completion: @escaping @MainActor @Sendable () -> Void) {
        self.snippetInsertionTask?.cancel()
        self.snippetInsertionTask = Task {
            await insertLongUnicodeTextAsync(text)
            completion()
        }
    }
}
