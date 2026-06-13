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

// ====================================================================
// 🌟 [5번 리뷰 종결: 명시적 무적 스텔스 변수 선언]
// nonisolated(unsafe) 키워드를 사용하여 변수 자체의 격리 검열을 완전히 파괴합니다.
// 자물쇠(NSLock)로 이미 보호 중이므로 시스템 공학적으로 100% 안전한 정석 해법입니다.
// ====================================================================
final class HyperKeyResumeGuard: @unchecked Sendable {
    private let lock = NSLock()
    
    // 🌟 컴파일러에게 "이 변수는 내 자물쇠로 지키니 액터 검열에서 손 떼라"고 명령합니다.
    nonisolated(unsafe) private var isResumed = false
    
    private let continuation: CheckedContinuation<Bool, Never>

    nonisolated init(continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    nonisolated func resume(returning value: Bool) {
        lock.lock(); defer { lock.unlock() }
        guard !isResumed else { return }
        isResumed = true
        continuation.resume(returning: value)
    }
}

// MARK: - Core Manager

class HyperKeyManager {
    static let shared = HyperKeyManager()

    // hidutil 명령어 실행이 절대 겹치지 않도록 조율하는 전용 직렬 백그라운드 큐
    private let hidutilQueue = DispatchQueue(label: "com.peepworks.langswitcher.hidutil", qos: .userInitiated)

    // CGEventTap 스레드 문맥과 설정 UI 문맥 간의 완벽한 스레드 안전성을 보장하는 고성능 자물쇠
    private let stateLock = NSLock()

    private var isHyperDown = false
    private var tapStartTime: Date?
    private var isUsedAsModifier = false

    private let f19KeyCode: CGKeyCode = 80 // Mac 백엔드 F19 가상 키코드 고정
    private let hyperKeyCodes: [CGKeyCode] = [55, 58, 59, 56]

    // Caps Lock 디바운스를 위한 WorkItem 저장 변수
    private var capsLockWorkItem: DispatchWorkItem?

    // 64비트 시스템 커널용 순정 데시멀 ID 장부 정렬
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
        // 스위프트 동시성의 협력적 멀티스레드 풀로 태스크를 완전히 독립 격리합니다.
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }

            // ── 1단계: hidutil에서 현재 키 매핑 정보 비동기 인출 ──
            let getTask = Process()
            getTask.launchPath = "/usr/bin/hidutil"
            getTask.arguments = ["property", "--get", "UserKeyMapping"]
            let getPipe = Pipe()
            getTask.standardOutput = getPipe

            // 프로세스가 실행되기 전(Pre-Launch) 시점에 비동기 가두리를 개설하여 종료 인터럽트 수신 유실률을 0%로 통제합니다.
            let isGetSuccessful: Bool = await withCheckedContinuation { continuation in
                getTask.terminationHandler = { proc in
                    continuation.resume(returning: proc.terminationStatus == 0)
                }
                do {
                    try getTask.run()
                } catch {
                    dprint("❌ [HyperKeyManager] hidutil --get 프로세스 기동 실패: \(error.localizedDescription)")
                    getTask.terminationHandler = nil
                    continuation.resume(returning: false)
                }
            }

            guard isGetSuccessful else { return }

            // 현대적 I/O 마이그레이션 적용
            guard let getData = try? getPipe.fileHandleForReading.readToEnd() else { return }
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

                // 이중 재개 방지 가드 안착
                let isPlutilSuccessful: Bool = await withCheckedContinuation { continuation in
                    let resumeGuard = HyperKeyResumeGuard(continuation: continuation)
                    
                    plutilTask.terminationHandler = { @Sendable proc in
                        defer { proc.terminationHandler = nil }
                        resumeGuard.resume(returning: proc.terminationStatus == 0)
                    }
                    
                    do {
                        try plutilTask.run()
                        
                        try plutilIn.fileHandleForWriting.write(contentsOf: getData)
                        try plutilIn.fileHandleForWriting.close()
                    } catch {
                        dprint("⚠️ [HyperKeyManager] plutil 파이프 쓰기 또는 실행 실패: \(error.localizedDescription)")
                        try? plutilIn.fileHandleForWriting.close()
                        
                        plutilTask.terminationHandler = nil
                        resumeGuard.resume(returning: false)
                    }
                }

                if isPlutilSuccessful, let jsonData = try? plutilOut.fileHandleForReading.readToEnd() {
                    try? plutilOut.fileHandleForReading.close()
                    if let parsed = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [[String: Int]] {
                        mappings = parsed
                    }
                } else {
                    try? plutilOut.fileHandleForReading.close()
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
                    dprint("✅ [HyperKeyManager] Caps Lock ➔ F19 하드웨어 매핑 파이프라인 무결성 정산 완결.")
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
