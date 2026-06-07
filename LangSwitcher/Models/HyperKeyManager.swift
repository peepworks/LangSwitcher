//
//  HyperKeyManager.swift
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

class HyperKeyManager {
    static let shared = HyperKeyManager()

    // 🌟 [교통정리] hidutil 명령어 실행이 절대 겹치지 않도록 조율하는 전용 직렬 백그라운드 큐
    private let hidutilQueue = DispatchQueue(label: "com.peepworks.langswitcher.hidutil", qos: .userInitiated)

    // 🌟 CGEventTap 스레드 문맥과 설정 UI 문맥 간의 완벽한 스레드 안전성을 보장하는 고성능 자물쇠
    private let stateLock = NSLock()

    private var isHyperDown = false
    private var tapStartTime: Date?
    private var isUsedAsModifier = false

    private let f19KeyCode: CGKeyCode = 80 // Mac 백엔드 F19 가상 키코드 고정
    private let hyperKeyCodes: [CGKeyCode] = [55, 58, 59, 56]

    // Caps Lock 디바운스를 위한 WorkItem 저장 변수
    private var capsLockWorkItem: DispatchWorkItem?

    // 🌟 [원상 복구 완수] 64비트 시스템 커널용 순정 데시멀 ID 장부 정렬
    private let capsLockSrc: Int = 30064771129 // 0x700000039 (Caps Lock)
    private let f19Dst: Int = 30064771182      // 0x70000006E (F19 Key)

    private init() {}

    func updateState(isEnabled: Bool) {
        setupHardwareMapping(enable: isEnabled)

        stateLock.lock()
        if !isEnabled { isHyperDown = false }
        stateLock.unlock()
    }

    private func setupHardwareMapping(enable: Bool) {
        // UI 메인 스레드를 단 1ms도 붙잡지 않도록 직렬 백그라운드 큐로 즉시 컨텍스트를 유기합니다.
        hidutilQueue.async { [weak self] in
            guard let self = self else { return }

            // 1. hidutil 정보 가져오기
            let getTask = Process()
            getTask.launchPath = "/usr/bin/hidutil"
            getTask.arguments = ["property", "--get", "UserKeyMapping"]
            let getPipe = Pipe()
            getTask.standardOutput = getPipe
            try? getTask.run()
            getTask.waitUntilExit() // 백그라운드 스레드 내부이므로 UI 프리즈를 절대 유발하지 않습니다.

            let getData = getPipe.fileHandleForReading.readDataToEndOfFile()
            let getString = String(data: getData, encoding: .utf8) ?? ""

            // 파일 디스크립터 즉시 반납으로 커널 자원 누수 차단
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

                    // 쓰기 완료 후 파이프를 명시적으로 닫아 plutil의 무한 행(Hang) 프리즈 현상을 원천 차단합니다.
                    plutilIn.fileHandleForWriting.closeFile()

                    plutilTask.waitUntilExit()

                    let jsonData = plutilOut.fileHandleForReading.readDataToEndOfFile()
                    if let parsed = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [[String: Int]] {
                        mappings = parsed
                    }

                    plutilOut.fileHandleForReading.closeFile()
                } catch {
                    dprint("HyperKeyManager: 기존 hidutil 맵핑을 파싱하는데 실패했습니다.")
                }
            }

            // 기존에 상주하던 Caps Lock 장부만 정밀 타겟팅하여 제거
            mappings.removeAll { dict in
                return dict["HIDKeyboardModifierMappingSrc"] == self.capsLockSrc
            }

            // 활성화 상태라면 순정 F19 데시멀 맵핑 결합
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

            // 🌟 [Swift 6 준수] 강한 순환 참조 고리를 자르고 인자로 유입된 proc 자원을 자가 해제합니다.
            setTask.terminationHandler = { proc in
                if proc.terminationStatus != 0 {
                    dprint("❌ hidutil 실행 반영 실패")
                } else {
                    #if DEBUG
                    dprint("✅ [HyperKeyManager] Caps Lock ➔ F19 이중 매핑 장부가 성공적으로 갱신되었습니다.")
                    #endif
                }
                proc.terminationHandler = nil
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

    // 🌟 [주의] 이 메서드는 CGEventTap 콜백 함수에 의해 실시간 동기식으로 호출되므로
    // @MainActor 격리벽을 세우지 않고, NSLock(stateLock) 체제를 유지하는 것이 아키텍처 정석입니다.
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

        task.terminationHandler = { proc in
            if proc.terminationStatus != 0 {
                DispatchQueue.main.async {
                    dprint("Caps Lock 토글 스크립트 실패 (종료 코드: \(proc.terminationStatus))")
                }
            }
            proc.terminationHandler = nil
        }

        do {
            try task.run()
        } catch {
            dprint("Caps Lock toggle 실행 자체를 실패함: \(error)")
        }
    }
}
