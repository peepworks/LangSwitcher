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

    @MainActor
    func updateState(isEnabled: Bool) {
        let setTask = Process()
        setTask.launchPath = "/usr/bin/hidutil"
        
        // 유저 설정에 따라 Caps Lock을 하이퍼키 조합으로 매핑하거나, 원래대로 순정 복구하는 아규먼트 배치
        let propertyArgument = isEnabled ? "{\"UserKeyMapping\":[{\"HIDKeyboardModifierMappingSrc\":0x700000039,\"HIDKeyboardModifierMappingDst\":0x700000028}]}" : "{\"UserKeyMapping\":[]}"
        setTask.arguments = ["property", "--set", propertyArgument]

        // 🌟 [최종 수복: 비동기 프로세스 트래킹 요새 구축]
        // 메인 스레드를 멈춰 세우던 waitUntilExit()를 완전히 소각하고,
        // OS 커널이 백그라운드에서 처리를 끝내면 깨어나는 비동기 콜백을 주입합니다.
        setTask.terminationHandler = { proc in
            if proc.terminationStatus != 0 {
                dprint("⚠️ [HyperKeyManager] hidutil --set 실패, Status: \(proc.terminationStatus)")
            }
            
            // 강한 순환 참조 걱정 없이 내부 매개변수 메모리를 청정하게 해제합니다.
            proc.terminationHandler = nil
        }

        do {
            // 🚀 프로세스를 실행합니다. 이 명령은 메인 스레드를 단 1ms도 붙잡지 않습니다.
            try setTask.run()
            
            // ❌ [철거 완료] 메인 스레드를 마비시키던 동기식 대기 장치를 완벽히 적출했습니다.
            // setTask.waitUntilExit()
            
        } catch {
            dprint("❌ [HyperKeyManager] hidutil 프로세스 기동 자체에 실패했습니다: \(error.localizedDescription)")
        }
    }

    // 🌟 [최종 수복 완결본] defer 결속 구조를 통해 모든 연쇄 파이프 누수를 100% 원천 차단합니다.
    private func setupHardwareMapping(enable: Bool) {
        hidutilQueue.async { [weak self] in
            guard let self = self else { return }

            // 파이프 자원들을 블록 전역에서 추적할 수 있도록 선제 선언합니다.
            let getPipe = Pipe()
            let plutilIn = Pipe()
            let plutilOut = Pipe()
            let setOutPipe = Pipe()
            let letSetErrPipe = Pipe()

            // 🌟 [핵심 수복 지점] 이 비동기 큐의 실행 턴이 끝나는 최후의 순간(정상 탈출, catch 탈출 불문),
            // 개설된 모든 파이프의 읽기/쓰기 핸들을 한 자리에 모아 OS 커널에 강제 반납(문단속)합니다.
            defer {
                try? getPipe.fileHandleForReading.close()
                try? getPipe.fileHandleForWriting.close()
                
                try? plutilIn.fileHandleForReading.close()
                try? plutilIn.fileHandleForWriting.close()
                
                try? plutilOut.fileHandleForReading.close()
                try? plutilOut.fileHandleForWriting.close()
                
                try? setOutPipe.fileHandleForReading.close()
                try? setOutPipe.fileHandleForWriting.close()
                try? letSetErrPipe.fileHandleForReading.close()
                try? letSetErrPipe.fileHandleForWriting.close()
                
                dprint("🧹 [HyperKeyManager] setupHardwareMapping 내의 모든 좀비 파이프 핸들이 안전하게 소각되었습니다.")
            }

            // 1. hidutil 정보 가져오기
            let getTask = Process()
            getTask.launchPath = "/usr/bin/hidutil"
            getTask.arguments = ["property", "--get", "UserKeyMapping"]
            getTask.standardOutput = getPipe
            
            do {
                try getTask.run()
                let getData = getPipe.fileHandleForReading.readDataToEndOfFile()
                getTask.waitUntilExit()

                let getString = String(data: getData, encoding: .utf8) ?? ""
                var mappings: [[String: Int]] = []

                if !getString.contains("(null)") && !getString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let plutilTask = Process()
                    plutilTask.launchPath = "/usr/bin/plutil"
                    plutilTask.arguments = ["-convert", "json", "-", "-o", "-"]
                    plutilTask.standardInput = plutilIn
                    plutilTask.standardOutput = plutilOut

                    try plutilTask.run()
                    
                    // 데이터 주입
                    try? plutilIn.fileHandleForWriting.write(contentsOf: getData)
                    // EOF 신호를 주어 자식의 무한 대기(Hang) 방지
                    try? plutilIn.fileHandleForWriting.close()

                    let jsonData = plutilOut.fileHandleForReading.readDataToEndOfFile()
                    plutilTask.waitUntilExit()

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

                // 3. 최종 설정 반영 등록
                let setTask = Process()
                setTask.launchPath = "/usr/bin/hidutil"
                setTask.arguments = ["property", "--set", finalJsonString]
                setTask.standardOutput = setOutPipe
                setTask.standardError = letSetErrPipe

                setTask.terminationHandler = { proc in
                    if proc.terminationStatus != 0 {
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

    // MARK: - HyperKey 내이티브 캡스락 토글 커널

    func executeCapsLockToggle() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        task.arguments = ["property", "--set", "{\"UserKeyMapping\":[{\"HIDKeyboardModifierMappingSrc\":0x700000039,\"HIDKeyboardModifierMappingDst\":0x700000039}]}"]

        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe

        // 🌟 [최종 수복 완료] 파이프가 생성되자마자 읽기/쓰기 핸들을 한곳에 묶어 문단속을 예약합니다.
        // 이제 do 블록에서 성공하든, catch 블록으로 튕겨 나가든 100% 무조건 완벽하게 자원이 소각됩니다.
        defer {
            try? outPipe.fileHandleForReading.close()
            try? outPipe.fileHandleForWriting.close() // 💡 누락되었던 쓰기 핸들 추가 정산
            
            try? errPipe.fileHandleForReading.close()
            try? errPipe.fileHandleForWriting.close() // 💡 누락되었던 쓰기 핸들 추가 정산
            
            dprint("🧹 [HyperKeyManager] CapsLock 토글 커널 파이프 자원이 완전히 해제되었습니다.")
        }

        do {
            try task.run()
            
            // hidutil 프로세스가 임무를 마치고 종료될 때까지 동기 대기
            task.waitUntilExit()
            
            // ❌ [기존 파편화 코드 철거] 이제 상단의 defer가 단일화하여 처리하므로
            // 내부의 지저분한 close() 연산들은 전부 깔끔하게 걷어냅니다.
            
        } catch {
            dprint("❌ [HyperKeyManager] hidutil 커널 명령 집행 실패: \(error.localizedDescription)")
        }
    }
}
