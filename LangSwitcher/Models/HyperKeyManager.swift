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

class HyperKeyManager {
    static let shared = HyperKeyManager()
    
    // 🌟 [핵심 개선] hidutil 명령어 실행이 절대 겹치지 않도록 교통정리를 해주는 전용 직렬 큐
    private let hidutilQueue = DispatchQueue(label: "com.peepworks.langswitcher.hidutil", qos: .userInitiated)

    // 🌟 스레드 안전성을 보장하기 위한 가벼운 자물쇠(Lock)
    private let stateLock = NSLock()

    private var isHyperDown = false
    private var tapStartTime: Date?
    private var isUsedAsModifier = false

    private let f19KeyCode: CGKeyCode = 80
    private let hyperKeyCodes: [CGKeyCode] = [55, 58, 59, 56]
    
    // Caps Lock 디바운스를 위한 WorkItem 저장 변수
    private var capsLockWorkItem: DispatchWorkItem?

    // 🌟 맵핑을 위한 상수 (0x700000039 = Caps Lock, 0x70000006E = F19)
    private let capsLockSrc: Int = 30064771129
    private let f19Dst: Int = 30064771182

    private init() {}

    func updateState(isEnabled: Bool) {
        setupHardwareMapping(enable: isEnabled)
        
        stateLock.lock()
        if !isEnabled { isHyperDown = false }
        stateLock.unlock()
    }

    // 🌟 [수정] 파일 디스크립터(Pipe) 누수를 막기 위해 명시적으로 자원을 닫습니다.
    private func setupHardwareMapping(enable: Bool) {
        hidutilQueue.async { [weak self] in
            guard let self = self else { return }

            let getTask = Process()
            getTask.launchPath = "/usr/bin/hidutil"
            getTask.arguments = ["property", "--get", "UserKeyMapping"]
            let getPipe = Pipe()
            getTask.standardOutput = getPipe
            try? getTask.run()
            getTask.waitUntilExit()

            let getData = getPipe.fileHandleForReading.readDataToEndOfFile()
            let getString = String(data: getData, encoding: .utf8) ?? ""
            
            // 🌟 1. 파이프 사용이 끝나면 무조건 닫아주어 메모리 누수 방지
            getPipe.fileHandleForReading.closeFile()

            var mappings: [[String: Int]] = []

            if !getString.contains("(null)") && !getString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let plutilTask = Process()
                plutilTask.launchPath = "/usr/bin/plutil"
                plutilTask.arguments = ["-convert", "json", "-", "-o", "-"]
                let plutilIn = Pipe()
                let plutilOut = Pipe()
                plutilTask.standardInput = plutilIn
                plutilTask.standardOutput = plutilOut

                do {
                    try plutilTask.run()
                    plutilIn.fileHandleForWriting.write(getData)
                    plutilIn.fileHandleForWriting.closeFile() // 🌟 2. 쓰기 닫기
                    plutilTask.waitUntilExit()

                    let jsonData = plutilOut.fileHandleForReading.readDataToEndOfFile()
                    if let parsed = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [[String: Int]] {
                        mappings = parsed
                    }
                    // 🌟 3. 읽기 닫기
                    plutilOut.fileHandleForReading.closeFile()
                } catch {
                    dprint("HyperKeyManager: 기존 hidutil 맵핑을 파싱하는데 실패했습니다.")
                }
            }

            mappings.removeAll { dict in
                return dict["HIDKeyboardModifierMappingSrc"] == self.capsLockSrc
            }

            if enable {
                mappings.append([
                    "HIDKeyboardModifierMappingSrc": self.capsLockSrc,
                    "HIDKeyboardModifierMappingDst": self.f19Dst
                ])
            }

            let finalMappingDict: [String: Any] = ["UserKeyMapping": mappings]
            guard let finalJsonData = try? JSONSerialization.data(withJSONObject: finalMappingDict, options: []),
                  let finalJsonString = String(data: finalJsonData, encoding: .utf8) else {
                return
            }

            let setTask = Process()
            setTask.launchPath = "/usr/bin/hidutil"
            setTask.arguments = ["property", "--set", finalJsonString]
            
            // 🌟 4. [weak setTask]로 순환 참조 방지
            setTask.terminationHandler = { [weak setTask] proc in
                if proc.terminationStatus != 0 {
                    DispatchQueue.main.async {
                        // ... 기존 에러 로그 남기는 부분 그대로 ...
                        dprint("hidutil 실행 실패")
                    }
                }
                // 🌟 5. 프로세스가 끝나면 강제로 할당 해제
                setTask?.terminationHandler = nil
            }

            do {
                try setTask.run()
            } catch {
                dprint("hidutil set 실행 자체를 실패함: \(error)")
            }
        }
    }

    private func postHyperModifiers(isDown: Bool) {
        guard let eventSource = CGEventSource(stateID: .hidSystemState) else { return }
        
        let hyperFlags: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        
        for keyCode in hyperKeyCodes {
            if let event = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: isDown) {
                event.flags = isDown ? hyperFlags : []
                event.setIntegerValueField(.eventSourceUserData, value: 9999)
                event.post(tap: .cghidEventTap)
            }
        }
    }

    private func handleTap() {
        DispatchQueue.main.async {
            InputSourceManager.shared.switchToNextInputSource()
        }
    }

    func processEvent(type: CGEventType, event: CGEvent, keyCode: CGKeyCode) -> Bool {
        var shouldBlock = false
        var shouldPostDown = false
        var shouldPostUp = false
        var shouldHandleTap = false
        var shouldToggleCapsLock = false
        var modifiedFlags: CGEventFlags? = nil

        do {
            stateLock.lock()
            defer { stateLock.unlock() }
            
            if keyCode == f19KeyCode {
                if type == .keyDown {
                    if !isHyperDown {
                        isHyperDown = true
                        tapStartTime = Date()
                        isUsedAsModifier = false
                        shouldPostDown = true
                    }
                    shouldBlock = true
                } else if type == .keyUp {
                    isHyperDown = false
                    shouldPostUp = true
                    
                    if let startTime = tapStartTime, !isUsedAsModifier {
                        let duration = Date().timeIntervalSince(startTime)
                        if duration < 0.3 {
                            shouldHandleTap = true
                        } else {
                            shouldToggleCapsLock = true
                        }
                    }
                    shouldBlock = true
                }
            }

            if !shouldBlock && isHyperDown && (type == .keyDown || type == .keyUp || type == .flagsChanged) {
                if type == .keyDown { isUsedAsModifier = true }
                var flags = event.flags
                flags.insert([.maskCommand, .maskAlternate, .maskControl, .maskShift])
                modifiedFlags = flags
            }
        }

        if shouldPostDown { postHyperModifiers(isDown: true) }
        if shouldPostUp { postHyperModifiers(isDown: false) }
        if shouldHandleTap { handleTap() }
        if shouldToggleCapsLock { toggleNativeCapsLock() }
        if let newFlags = modifiedFlags { event.flags = newFlags }

        return shouldBlock
    }
    
    private func toggleNativeCapsLock() {
        capsLockWorkItem?.cancel()
        
        let item = DispatchWorkItem { [weak self] in
            self?.executeCapsLockToggle()
        }
        capsLockWorkItem = item
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.05, execute: item)
    }

    private func executeCapsLockToggle() {
        let currentFlags = CGEventSource.flagsState(.hidSystemState)
        let currentState = currentFlags.contains(.maskAlphaShift)
        let newState = !currentState

        let script = """
        ObjC.import('IOKit');
        var ioConnect = Ref();
        $.IOServiceOpen(
            $.IOServiceGetMatchingService(0, $.IOServiceMatching('IOHIDSystem')),
            $.mach_task_self_,
            0,
            ioConnect
        );
        $.IOHIDSetModifierLockState(ioConnect, 1, \(newState ? "true" : "false"));
        $.IOServiceClose(ioConnect);
        """
        
        guard let item = capsLockWorkItem, !item.isCancelled else { return }

        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-l", "JavaScript", "-e", script]
        
        // 🌟 [수정] 순환 참조의 고리를 끊고, 콜백이 끝난 뒤 깔끔하게 날려버립니다.
        task.terminationHandler = { [weak task] proc in
            if proc.terminationStatus != 0 {
                DispatchQueue.main.async {
                    dprint("Caps Lock 토글 스크립트 실패 (종료 코드: \(proc.terminationStatus))")
                    // ... 기존 로그 남기는 부분 그대로 ...
                }
            }
            // 🌟 메모리 해제
            task?.terminationHandler = nil
        }

        do {
            try task.run()
        } catch {
            dprint("Caps Lock toggle 실행 자체를 실패함: \(error)")
        }
    }
}
