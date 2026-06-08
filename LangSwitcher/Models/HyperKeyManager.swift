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
        // 🌟 [우주 방어 수복 포인트 1]
        // 직렬 큐의 스레드를 물리적으로 잠그던 레거시 구조를 전면 파괴하고,
        // 스위프트 동시성의 협력적 멀티스레드 풀(Background Global Pool)로 태스크를 격리합니다.
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }

            // ── 1단계: hidutil에서 현재 키 매핑 정보 비동기 인출 ──
            let getTask = Process()
            getTask.launchPath = "/usr/bin/hidutil"
            getTask.arguments = ["property", "--get", "UserKeyMapping"]
            let getPipe = Pipe()
            getTask.standardOutput = getPipe

            do {
                try getTask.run()
                
                // 🌟 [핵심 수복] 스레드를 통째로 얼려버리던 getTask.waitUntilExit()를 완전히 들어내고
                // 커널 종료 인터럽트 시점에 태스크를 깨우는 넌블로킹 비동기 Continuation으로 대체합니다.
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    getTask.terminationHandler = { _ in
                        continuation.resume()
                    }
                }
            } catch {
                dprint("❌ [HyperKeyManager] hidutil --get 프로세스 기동 실패: \(error.localizedDescription)")
                return
            }

            let getData = getPipe.fileHandleForReading.readDataToEndOfFile()
            let getString = String(data: getData, encoding: .utf8) ?? ""
            try? getPipe.fileHandleForReading.close()

            var mappings: [[String: Int]] = []

            // ── 2단계: Plist 바이너리를 비동기적으로 안전하게 JSON 파싱 ──
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
                    
                    // 데이터 주입 후 즉시 파이프를 닫아 plutil 프로세스의 교착(Hang)을 차단
                    plutilIn.fileHandleForWriting.write(getData)
                    try? plutilIn.fileHandleForWriting.close()

                    // 🌟 [핵심 수복] 두 번째 병목 지점이었던 plutilTask.waitUntilExit() 역시
                    // 스레드를 점유하지 않는 넌블로킹 비동기 대기로 깔끔하게 정산합니다.
                    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                        plutilTask.terminationHandler = { _ in
                            continuation.resume()
                        }
                    }

                    let jsonData = plutilOut.fileHandleForReading.readDataToEndOfFile()
                    try? plutilOut.fileHandleForReading.close()
                    
                    if let parsed = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [[String: Int]] {
                        mappings = parsed
                    }
                } catch {
                    dprint("⚠️ [HyperKeyManager] plutil 데이터 파싱 예외 발생: \(error.localizedDescription)")
                }
            }

            // ── 3단계: 장부 조율 및 캡락 매핑 목적지 주입 ──
            mappings.removeAll { $0["HIDKeyboardModifierMappingSrc"] == self.capsLockSrc }

            if enable {
                mappings.append([
                    "HIDKeyboardModifierMappingSrc": self.capsLockSrc,
                    "HIDKeyboardModifierMappingDst": self.f19Dst
                ])
            }

            let finalMappingDict: [String: Any] = ["UserKeyMapping": mappings]
            guard let finalJsonData = try? JSONSerialization.data(withJSONObject: finalMappingDict, options: []),
                  let finalJsonString = String(data: finalJsonData, encoding: .utf8) else { return }

            // ── 4단계: hidutil --set 최종 시스템 커널 적용 ──
            let setTask = Process()
            setTask.launchPath = "/usr/bin/hidutil"
            setTask.arguments = ["property", "--set", finalJsonString]

            setTask.terminationHandler = { proc in
                if proc.terminationStatus != 0 {
                    dprint("❌ [HyperKeyManager] hidutil --set 하드웨어 반영 실패")
                } else {
                    dprint("✅ [HyperKeyManager] Caps Lock ➔ F1 F19 매핑 파이프라인 전 구간 비동기화 완료.")
                }
                proc.terminationHandler = nil
            }

            do {
                try setTask.run()
            } catch {
                dprint("❌ [HyperKeyManager] hidutil set 실행 커널 오류: \(error.localizedDescription)")
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
