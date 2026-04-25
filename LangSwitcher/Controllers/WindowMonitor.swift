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
import Carbon

class WindowMonitor {
    static let shared = WindowMonitor()
    
    // 🌟 창 고유 해시값을 Key로, '언어 ID'와 해당 앱의 'PID'를 튜플(Value)로 묶어서 저장하는 메모리
    private var windowLanguageMemory: [Int: (lang: String, pid: pid_t)] = [:]
    
    private var axObserver: AXObserver?
    private var currentPID: pid_t = 0
    private var activeWindowElement: AXUIElement?
    
    // 동시성 처리를 위한 큐 (딕셔너리 데이터 경합 방지)
    private let stateQueue = DispatchQueue(label: "com.peepworks.langswitcher.windowmonitor", attributes: .concurrent)

    private init() {
        // 1. 시스템 언어 변경 알림 구독 (사용자가 타이핑 중 언어를 바꾸면 감지)
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(inputSourceChanged),
            name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil
        )
        
        // 2. 앱 종료 알림 구독 (종료된 앱의 창 기록을 메모리에서 지우기 위함)
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appTerminated(_:)),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
    }
    
    @objc private func appTerminated(_ notification: Notification) {
        // "앱 종료 시 기록 지우기" 옵션이 켜져 있을 때만 실행
        guard SettingsManager.shared.snapshot.isWindowMemoryCleanupEnabled else { return }
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        
        let terminatedPID = app.processIdentifier

        stateQueue.async(flags: .barrier) {
            // 종료된 앱의 PID와 일치하는 창 기록들만 필터링하여 일괄 제거
            let keysToRemove = self.windowLanguageMemory.filter { $0.value.pid == terminatedPID }.map { $0.key }
            for key in keysToRemove {
                self.windowLanguageMemory.removeValue(forKey: key)
            }
        }
    }
    
    // 특정 앱(PID)에 대한 창 전환 감지 시작 (AppMonitor.swift 에서 호출됨)
    func observeApp(pid: pid_t) {
        guard SettingsManager.shared.snapshot.isWindowMemoryEnabled else { return }
        
        // 기존에 등록된 옵저버가 있다면 제거 (메모리 누수 방지)
        if let observer = axObserver {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
            self.axObserver = nil
        }
        
        self.currentPID = pid
        var observer: AXObserver?
        
        // 🌟 C-Callback 함수: AXAPI (접근성 API) 이벤트가 발생하면 여기로 들어옴
        let callback: AXObserverCallback = { (axObserver, axElement, notification, refcon) in
            guard let refcon = refcon else { return }
            let monitor = Unmanaged<WindowMonitor>.fromOpaque(refcon).takeUnretainedValue()
            
            let notifString = notification as String
            if notifString == kAXFocusedWindowChangedNotification as String {
                monitor.handleWindowFocusChanged(element: axElement)
            } else if notifString == kAXUIElementDestroyedNotification as String {
                monitor.handleWindowDestroyed(element: axElement)
            }
        }
        
        let result = AXObserverCreate(pid, callback, &observer)
        guard result == .success, let newObserver = observer else { return }
        
        self.axObserver = newObserver
        let appElement = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        
        // 창 포커스 변경 및 창 닫힘 이벤트 구독
        AXObserverAddNotification(newObserver, appElement, kAXFocusedWindowChangedNotification as CFString, refcon)
        AXObserverAddNotification(newObserver, appElement, kAXUIElementDestroyedNotification as CFString, refcon)
        
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(newObserver), .defaultMode)
        
        // 앱이 활성화된 직후, 현재 포커스된 창의 상태를 강제로 한 번 읽어옵니다.
        var focusedWindow: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow) == .success {
            handleWindowFocusChanged(element: focusedWindow as! AXUIElement)
        }
    }
    
    private func handleWindowFocusChanged(element: AXUIElement) {
        guard SettingsManager.shared.snapshot.isWindowMemoryEnabled else { return }
        self.activeWindowElement = element
        let windowHash = element.hashValue
        
        stateQueue.sync {
            if let savedData = windowLanguageMemory[windowHash] {
                // 1. 딕셔너리에 저장된 언어 기록이 있다면 해당 언어로 즉시 복원
                DispatchQueue.main.async {
                    InputSourceManager.shared.switchLanguage(to: savedData.lang)
                }
            } else {
                // 2. 처음 띄운 창이라면 현재 시스템 언어를 딕셔너리에 기록해둠 (PID 포함)
                if let currentID = self.getCurrentInputSourceID() {
                    let pid = self.currentPID
                    // 비동기로 안전하게 쓰기
                    DispatchQueue.global().async {
                        self.stateQueue.async(flags: .barrier) {
                            self.windowLanguageMemory[windowHash] = (lang: currentID, pid: pid)
                        }
                    }
                }
            }
        }
    }
    
    private func handleWindowDestroyed(element: AXUIElement) {
        // 창 자체가 닫히면 메모리 최적화를 위해 딕셔너리에서 해당 창 데이터 파기
        let windowHash = element.hashValue
        stateQueue.async(flags: .barrier) {
            self.windowLanguageMemory.removeValue(forKey: windowHash)
        }
    }
    
    @objc private func inputSourceChanged() {
        guard SettingsManager.shared.snapshot.isWindowMemoryEnabled else { return }
        guard let element = activeWindowElement else { return }
        let windowHash = element.hashValue
        
        // 사용자가 한/영 키를 눌러 언어를 바꾸면, 현재 띄워진 창의 데이터를 최신 언어로 덮어씌움
        if let currentID = self.getCurrentInputSourceID() {
            let pid = self.currentPID
            stateQueue.async(flags: .barrier) {
                self.windowLanguageMemory[windowHash] = (lang: currentID, pid: pid)
            }
        }
    }
    
    // 헬퍼 함수: 현재 시스템의 입력 소스 ID(예: com.apple.keylayout.ABC) 가져오기
    private func getCurrentInputSourceID() -> String? {
        guard let currentSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(currentSource, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }
}
