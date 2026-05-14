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

class ShortcutRecorder {
    static let shared = ShortcutRecorder()
    typealias Completion = (_ keyCode: UInt16, _ modifiers: UInt64, _ displayString: String) -> Void
    private var timeoutTask: DispatchWorkItem?
    private init() {}
    
    // 🌟 [핵심 변경] isForAppLaunch 플래그 추가 (기본값 false)
    func startRecording(isForAppLaunch: Bool = false, completion: @escaping Completion, onTimeout: @escaping () -> Void) {
        EventMonitor.shared.isPaused = true
        timeoutTask?.cancel()
        
        let task = DispatchWorkItem { [weak self] in
            self?.stopRecording()
            onTimeout()
        }
        
        self.timeoutTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: task)

        class RState { var m = Set<UInt16>(); var f: NSEvent.ModifierFlags = []; var r = false }
        let state = RState()

        EventMonitor.shared.shortcutRecordingCallback = { e in
            let code = e.keyCode
            let flags = e.modifierFlags.intersection(.deviceIndependentFlagsMask)

            if e.type == .flagsChanged {
                let capturedCode = code
                if capturedCode == 57 { DispatchQueue.main.async { completion(57, 0, "⇪ Caps Lock") }; return }
                
                if !flags.isEmpty { state.m.insert(capturedCode); state.f.formUnion(flags); return }
                else if !state.r && !state.m.isEmpty {
                    if state.m.count == 1 {
                        let c = state.m.first!
                        let str = [54:"Right ⌘", 55:"Left ⌘", 56:"Left ⇧", 60:"Right ⇧", 58:"Left ⌥", 61:"Right ⌥", 59:"Left ⌃", 62:"Right ⌃", 63:"fn"][c] ?? "Mod(\(c))"
                        let capturedC = c; DispatchQueue.main.async { completion(capturedC, 0, str) }
                    } else {
                        var str = ""
                        if state.f.contains(.control) { str += "⌃ " }
                        if state.f.contains(.option) { str += "⌥ " }
                        if state.f.contains(.shift) { str += "⇧ " }
                        if state.f.contains(.command) { str += "⌘ " }
                        let capturedMods = UInt64(state.f.rawValue)
                        DispatchQueue.main.async { completion(0, capturedMods, str.trimmingCharacters(in: .whitespaces)) }
                    }
                    return
                }
                state.m.removeAll(); state.f = []; state.r = false; return
                
            } else if e.type == .keyDown {
                
                // 🌟 [핵심 변경] 앱 실행 단축키 화면(isForAppLaunch == true)일 때만 방어 로직 작동!
                if isForAppLaunch && code == 49 {
                    let snapshot = SettingsManager.shared.snapshot
                    let pureFlags = flags.intersection([.control, .command, .option, .shift])
                    
                    if pureFlags == .control && snapshot.isCtrlActive { state.r = true; return }
                    if pureFlags == .command && snapshot.isCmdActive { state.r = true; return }
                    if pureFlags == .option && snapshot.isOptActive { state.r = true; return }
                }
                
                state.r = true; var str = ""
                if flags.contains(.control) { str += "⌃ " }
                if flags.contains(.option) { str += "⌥ " }
                if flags.contains(.shift) { str += "⇧ " }
                if flags.contains(.command) { str += "⌘ " }

                let capturedCode = code
                if capturedCode == 49 { str += "Space" }
                else if let mapped = globalKeyMap[capturedCode] { str += mapped }
                else if let chars = e.charactersIgnoringModifiers?.uppercased(), !chars.isEmpty { str += chars }
                else { str += "Key(\(capturedCode))" }

                let capturedMods = UInt64(flags.rawValue)
                DispatchQueue.main.async { completion(capturedCode, capturedMods, str) }
                return
            }
        }
    }
    
    func stopRecording() {
        timeoutTask?.cancel()
        EventMonitor.shared.cancelShortcutRecording()
    }
}
