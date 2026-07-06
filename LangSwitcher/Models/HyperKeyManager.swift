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
import IOKit

private typealias IOHIDSetModifierLockStateFunc = @convention(c) (io_connect_t, Int32, Bool) -> Int32

// ====================================================================
// 🌟 [5번 리뷰 종결: 명시적 무적 스텔스 변수 선언]
// nonisolated(unsafe) 키워드를 사용하여 변수 자체의 격리 검열을 완전히 파괴합니다.
// 자물쇠(NSLock)로 이미 보호 중이므로 시스템 공학적으로 100% 안전한 정석 해법입니다.
// ====================================================================
final class HyperKeyResumeGuard: @unchecked Sendable {
    private let lock = NSLock()
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

    // CGEventTap 스레드 문맥과 설정 UI 문맥 간의 완벽한 스레드 안전성을 보장하는 고성능 자물쇠
    private let stateLock = NSLock()

    private var isHyperDown = false
    private var tapStartTime: Date?
    private var isUsedAsModifier = false

    private let f19KeyCode: CGKeyCode = 80
    private let hyperKeyCodes: [CGKeyCode] = [55, 58, 59, 56]

    private var capsLockWorkItem: DispatchWorkItem?

    private let capsLockSrc: Int = 30064771129
    private let f19Dst: Int = 30064771182

    // ── 🌟 [수복 포인트 1: 직렬 태스크 체이닝 백킹 파이프라인] ──
    // 무용지물이던 레거시 hidutilQueue를 전면 폐기하고, Swift Concurrency 전용
    // 직렬화 체인 링크 보관용 태스크 변수를 결속합니다. (stateLock으로 보호)
    private var currentMappingTask: Task<Void, Never>?

    private var IOHIDSetModifierLockState: IOHIDSetModifierLockStateFunc? = {
        let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)
        if let sym = dlsym(handle, "IOHIDSetModifierLockState") {
            return unsafeBitCast(sym, to: IOHIDSetModifierLockStateFunc.self)
        }
        return nil
    }()

    private init() {}

    func updateState(isEnabled: Bool) {
        setupHardwareMapping(enable: isEnabled)

        stateLock.lock()
        if !isEnabled { isHyperDown = false }
        stateLock.unlock()
    }

    private func setupHardwareMapping(enable: Bool) {
        // ── 🌟 [수복 포인트 2: 원자적 포인터 스왑 및 비블로킹 직렬 파이프라인 집행] ──
        stateLock.lock()
        let previousTask = currentMappingTask
        
        let newTask = Task.detached(priority: .userInitiated) { [weak self] in
            // 앞선 hidutil 매핑 공정이 (연타 시에도) 완전히 마감 정산될 때까지 대기줄을 세웁니다.
            _ = await previousTask?.value
            
            guard let self = self else { return }

            // ── 1단계: hidutil에서 현재 키 매핑 정보 비동기 인출 ──
            let getTask = Process()
            getTask.launchPath = "/usr/bin/hidutil"
            getTask.arguments = ["property", "--get", "UserKeyMapping"]
            let getPipe = Pipe()
            getTask.standardOutput = getPipe

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
                    dprint("✅ [HyperKeyManager] Caps Lock ➔ F19 하드웨어 매핑 파이프라인 무결성 직렬 정산 완결.")
                }
                proc.terminationHandler = nil
            }

            do {
                try setTask.run()
            } catch {
                dprint("❌ [HyperKeyManager] hidutil set 실행 커널 오류: \(error.localizedDescription)")
            }
        }
        
        // 현재 생성된 최신 태스크를 다음 연타의 선행 주자로 교체 후 자물쇠를 해제합니다.
        currentMappingTask = newTask
        stateLock.unlock()
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

        guard let item = capsLockWorkItem, !item.isCancelled else { return }

        if let matchingDict = IOServiceMatching("IOHIDSystem") {
            let service = IOServiceGetMatchingService(0, matchingDict)
            if service != 0 {
                var connect: io_connect_t = 0
                let openStatus = IOServiceOpen(service, mach_task_self_, 0, &connect)
                
                if openStatus == KERN_SUCCESS {
                    if let toggleFunc = self.IOHIDSetModifierLockState {
                        _ = toggleFunc(connect, 1, newState)
                        #if DEBUG
                        dprint("⚡️ [HyperKey] OS 프로세스 소각 완결 ➔ Caps Lock을 인프로세스 C API로 즉시 정산 [\(newState)]")
                        #endif
                    }
                    IOServiceClose(connect)
                }
            }
        }
    }
}
