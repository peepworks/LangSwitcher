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

    // 🌟 스레드 안전성을 보장하기 위한 가벼운 자물쇠(Lock) 추가
    private let stateLock = NSLock()

    private var isHyperDown = false
    private var tapStartTime: Date?
    private var isUsedAsModifier = false

    private let f19KeyCode: CGKeyCode = 80
    private let hyperKeyCodes: [CGKeyCode] = [55, 58, 59, 56]
    
    // 🌟 [추가됨] Caps Lock 디바운스를 위한 WorkItem 저장 변수
    private var capsLockWorkItem: DispatchWorkItem?

    private init() {}

    func updateState(isEnabled: Bool) {
        setupHardwareMapping(enable: isEnabled)
        
        // 외부(UI 스레드)에서 상태를 변경할 때도 안전하게 잠금 처리
        stateLock.lock()
        if !isEnabled { isHyperDown = false }
        stateLock.unlock()
    }

    // 무거운 I/O 및 외부 프로세스 작업을 백그라운드 스레드로 분리하여 메인 UI 블로킹 방지
    private func setupHardwareMapping(enable: Bool) {
        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.launchPath = "/usr/bin/hidutil"

            let mappingString = enable
                ? "{\"UserKeyMapping\":[{\"HIDKeyboardModifierMappingSrc\":0x700000039,\"HIDKeyboardModifierMappingDst\":0x70000006E}]}"
                : "{\"UserKeyMapping\":[{\"HIDKeyboardModifierMappingSrc\":0x700000039,\"HIDKeyboardModifierMappingDst\":0x700000039}]}"

            task.arguments = ["property", "--set", mappingString]

            do {
                try task.run()
                task.waitUntilExit()
                    
                if task.terminationStatus != 0 {
                    let errorMessage = "hidutil exited with code: \(task.terminationStatus)"
                    SettingsManager.shared.addLog(ActionLog(
                        timestamp: Date(),
                        targetApp: "System",
                        appliedRule: "Hyper Key Mapping",
                        finalInputSource: "Failed",
                        result: .failure,
                        failureReason: .unknown
                    ))
                    print("hidutil 실행 실패: \(errorMessage)")
                }
                    
            } catch {
                SettingsManager.shared.addLog(ActionLog(
                    timestamp: Date(),
                    targetApp: "System",
                    appliedRule: "Hyper Key Mapping",
                    finalInputSource: "Failed",
                    result: .failure,
                    failureReason: .unknown
                ))
                print("hidutil 실행 실패: \(error)")
            }
        }
    }

    private func postHyperModifiers(isDown: Bool) {
        guard let eventSource = CGEventSource(stateID: .hidSystemState) else { return }
        
        // 🌟 [수정됨] 불필요한 플래그(fn, caps lock 등)가 섞이지 않도록,
        // 하이퍼 키를 구성하는 정확히 4개의 모디파이어만 조합하여 안전한 플래그 세트를 만듭니다.
        let hyperFlags: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        
        for keyCode in hyperKeyCodes {
            if let event = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: isDown) {
                // 🌟 [수정됨] 뭉뚱그려진 deviceIndependentFlagsMask 대신 정확한 hyperFlags를 주입합니다.
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

        // 1단계: 자물쇠를 잠그고 내부 상태(State)만 안전하게 평가 및 수정합니다.
        stateLock.lock()
        
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
                        shouldToggleCapsLock = true // 0.3초 이상: 대/소문자 전환(Caps Lock)
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
        
        stateLock.unlock()
        // 🔓 자물쇠 해제 완료

        // 2단계: 자물쇠가 풀린 안전한 상태에서 시스템 관련 동작을 실행합니다.
        if shouldPostDown { postHyperModifiers(isDown: true) }
        if shouldPostUp { postHyperModifiers(isDown: false) }
        if shouldHandleTap { handleTap() }
        if shouldToggleCapsLock { toggleNativeCapsLock() } // 대/소문자 전환 실행
        if let newFlags = modifiedFlags { event.flags = newFlags }

        return shouldBlock
    }
    
    // 🌟 [수정됨] 디바운스 적용: 빠른 연타 시 이전 작업을 취소하고 마지막 1번만 실행합니다.
    private func toggleNativeCapsLock() {
        // 1. 이전에 예약된 작업이 있다면 취소 (연타 방지)
        capsLockWorkItem?.cancel()
        
        // 2. 실행할 작업 정의
        let item = DispatchWorkItem { [weak self] in
            self?.executeCapsLockToggle()
        }
        
        // 3. 작업 저장 (다음 연타 시 취소할 수 있도록)
        capsLockWorkItem = item
        
        // 4. 0.05초(50ms) 대기 후 백그라운드 스레드에서 실행
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.05, execute: item)
    }

    // 🌟 [추가됨] 실제 JXA 스크립트를 실행하는 로직 분리
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

        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-l", "JavaScript", "-e", script]
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            print("Caps Lock toggle failed: \(error)")
        }
    }
}
