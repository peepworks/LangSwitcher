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

// MARK: - Thread Safety Guard for Continuation Resume
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

    private let stateLock = NSLock()

    private var isHyperDown = false
    private var tapStartTime: Date?
    private var isUsedAsModifier = false

    private let f19KeyCode: CGKeyCode = 80
    private let hyperKeyCodes: [CGKeyCode] = [55, 58, 59, 56]

    private var capsLockWorkItem: DispatchWorkItem?

    private let capsLockSrc: Int = 30064771129
    private let f19Dst: Int = 30064771182

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
        stateLock.lock()
        let previousTask = currentMappingTask
        
        let newTask = Task.detached(priority: .userInitiated) { [weak self] in
            _ = await previousTask?.value
            guard let self = self else { return }

            // 1단계: hidutil에서 현재 키 매핑 정보 비동기 인출
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

            guard isGetSuccessful, let getData = try? getPipe.fileHandleForReading.readToEnd() else { return }
            let getString = String(data: getData, encoding: .utf8) ?? ""
            try? getPipe.fileHandleForReading.close()

            var mappings: [[String: Int]] = []

            // 2단계: Plist 바이너리를 비동기적으로 안전하게 JSON 파싱하여 기존 매핑 보존
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

            // 3단계: 장부 조율 및 CapsLock ➔ F19 매핑 적용
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

            // 4단계: hidutil --set 최종 시스템 커널 적용
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
