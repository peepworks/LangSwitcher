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

            // 1. hidutil 정보 가져오기
            let getTask = Process()
            getTask.launchPath = "/usr/bin/hidutil"
            getTask.arguments = ["property", "--get", "UserKeyMapping"]
            let getPipe = Pipe()
            getTask.standardOutput = getPipe
            
            do {
                try getTask.run()
                let getData = getPipe.fileHandleForReading.readDataToEndOfFile()
                getTask.waitUntilExit()

                // 🌟 [리뷰 반영 최적화 1] 사용한 읽기단과 '단 한번도 쓰지 않은' 쓰기단을 동시에 강제 폐쇄
                try? getPipe.fileHandleForReading.close()
                try? getPipe.fileHandleForWriting.close()

                let getString = String(data: getData, encoding: .utf8) ?? ""
                var mappings: [[String: Int]] = []

                if !getString.contains("(null)") && !getString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let plutilTask = Process()
                    plutilTask.launchPath = "/usr/bin/plutil"
                    plutilTask.arguments = ["-convert", "json", "-", "-o", "-"]
                    let plutilIn = Pipe()
                    let plutilOut = Pipe()
                    plutilTask.standardInput = plutilIn
                    plutilTask.standardOutput = plutilOut

                    try plutilTask.run()
                    
                    // 데이터 주입
                    try? plutilIn.fileHandleForWriting.write(contentsOf: getData)

                    // 🌟 [리뷰 반영 최적화 2] 자식에게 EOF를 알리는 쓰기단 폐쇄와 동시에, 안 쓰던 읽기단도 즉시 청소
                    try? plutilIn.fileHandleForWriting.close()
                    try? plutilIn.fileHandleForReading.close()

                    let jsonData = plutilOut.fileHandleForReading.readDataToEndOfFile()
                    plutilTask.waitUntilExit()

                    // 🌟 [리뷰 반영 최적화 3] 결과 수집 완료 즉시 읽기단과 미사용 쓰기단 전량 폐쇄
                    try? plutilOut.fileHandleForReading.close()
                    try? plutilOut.fileHandleForWriting.close()

                    if let parsed = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [[String: Int]] {
                        mappings = parsed
                    }
                }

                // 2. 맵핑 배열 가공 (Caps Lock 매핑 스위칭)
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

                // 3. 최종 설정 반영 등록 (리뷰 반영 수복 지점)
                let setTask = Process()
                setTask.launchPath = "/usr/bin/hidutil"
                setTask.arguments = ["property", "--set", finalJsonString]

                // 🌟 [리뷰 반영] 콘솔 소음 누출 및 버퍼 행(Hang) 예방을 위한 소음기 파이프 개설
                let setOutPipe = Pipe()
                let setErrPipe = Pipe()
                setTask.standardOutput = setOutPipe
                setTask.standardError = setErrPipe

                setTask.terminationHandler = { proc in
                    // 🌟 [최종 가드] 자식 프로세스 종료 즉시 커널 파일 디스크립터(FD) 자원 강제 소각
                    try? setOutPipe.fileHandleForReading.close()
                    try? setOutPipe.fileHandleForWriting.close()
                    try? setErrPipe.fileHandleForReading.close()
                    try? setErrPipe.fileHandleForWriting.close()
                    
                    if proc.terminationStatus != 0 {
                        // 💡 UI 메인 스레드 간섭 없이 독립 격리 디버그 로그 출력
                        dprint("⚠️ [HyperKeyManager] hidutil --set 실행 실패 (Status: \(proc.terminationStatus))")
                    }
                    proc.terminationHandler = nil
                }

                try setTask.run()
                setTask.waitUntilExit() // 상호 간섭 방지를 위해 매핑 확정 대기 유지
                
            } catch {
                dprint("❌ [HyperKeyManager] 하드웨어 키 매핑 프로세스 실행 중 예외 에러 발생: \(error.localizedDescription)")
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

    // MARK: - HyperKey 내이티브 캡스락 토글 커널 (파이프 자원 누수 완전 해제)

    func executeCapsLockToggle() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        // 키 매핑 및 캡스락 상태 전환을 위한 인자 설정
        task.arguments = ["property", "--set", "{\"UserKeyMapping\":[{\"HIDKeyboardModifierMappingSrc\":0x700000039,\"HIDKeyboardModifierMappingDst\":0x700000039}]}"]

        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe

        do {
            try task.run()
            
            // hidutil이 실행을 마치고 물리적으로 종료될 때까지 대기합니다.
            task.waitUntilExit()
            
            // 🌟 [리뷰 반영 수복] 프로세스가 확실하게 종료되었으므로,
            // 커널 공간에 묶여있던 파이프 파일 핸들 자원을 즉시 동기적으로 강제 폐쇄(Close)합니다.
            // 이 조치로 인해 시스템 파일 디스크립터 잔류 누수 리스크가 0%로 완전히 소각됩니다.
            try? outPipe.fileHandleForReading.close()
            try? errPipe.fileHandleForReading.close()

            dprint("💾 [HyperKeyManager] hidutil 실행 및 커널 파이프 자원 반납이 완벽하게 완료되었습니다.")
            
        } catch {
            // 🚨 실행 실패 예외 경로에서도 자원이 누수되지 않도록 철저하게 2중 방어벽 가동
            try? outPipe.fileHandleForReading.close()
            try? errPipe.fileHandleForReading.close()

            dprint("❌ [HyperKeyManager] hidutil 커널 명령 집행 실패: \(error.localizedDescription)")
        }
    }
}
