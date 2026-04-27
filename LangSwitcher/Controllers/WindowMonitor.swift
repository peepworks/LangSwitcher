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

// 🌟 [핵심 마법] Apple의 숨겨진 C 함수를 Swift에서 사용할 수 있게 연결해주는 브릿지 선언
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ id: inout CGWindowID) -> AXError

class WindowMonitor {
    static let shared = WindowMonitor()
    
    // 🌟 [수정됨] Key 타입을 불안정한 Int(hashValue)에서 완벽한 고유번호인 CGWindowID로 변경!
    private var windowLanguageMemory: [CGWindowID: (lang: String, pid: pid_t)] = [:]
    
    private var axObserver: AXObserver?
    
    private let stateQueue = DispatchQueue(label: "com.peepworks.langswitcher.windowstate", attributes: .concurrent)

    private var _currentPID: pid_t = 0
    var currentPID: pid_t {
        get { stateQueue.sync { _currentPID } }
        set { stateQueue.async(flags: .barrier) { self._currentPID = newValue } }
    }

    private var _activeWindowElement: AXUIElement?
    var activeWindowElement: AXUIElement? {
        get { stateQueue.sync { _activeWindowElement } }
        set { stateQueue.async(flags: .barrier) { self._activeWindowElement = newValue } }
    }

    private init() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(inputSourceChanged),
            name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil
        )
        
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appTerminated(_:)),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
    }
    
    // MARK: - 🌟 [새로 추가됨] 불안정한 hashValue 대신 창의 영구 ID를 가져오는 헬퍼 함수
    private func getWindowID(from element: AXUIElement) -> CGWindowID? {
        var windowID: CGWindowID = 0
        let result = _AXUIElementGetWindow(element, &windowID)
        return result == .success ? windowID : nil
    }
    
    @objc private func appTerminated(_ notification: Notification) {
        guard SettingsManager.shared.snapshot.isWindowMemoryCleanupEnabled else { return }
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        
        let terminatedPID = app.processIdentifier

        stateQueue.async(flags: .barrier) {
            let keysToRemove = self.windowLanguageMemory.filter { $0.value.pid == terminatedPID }.map { $0.key }
            for key in keysToRemove {
                self.windowLanguageMemory.removeValue(forKey: key)
            }
        }
    }
    
    func observeApp(pid: pid_t) {
        guard SettingsManager.shared.snapshot.isWindowMemoryEnabled else { return }
        
        // 🌟 [핵심 최적화 추가]
        // 방금 전까지 감시하던 앱(PID)과 동일하다면, 옵저버를 새로 만들 필요 없이 기존 것을 그대로 씁니다.
        if self.currentPID == pid {
            return
        }
        
        if let observer = axObserver {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
            self.axObserver = nil
        }
        
        self.currentPID = pid
        var observer: AXObserver?
        
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
        
        AXObserverAddNotification(newObserver, appElement, kAXFocusedWindowChangedNotification as CFString, refcon)
        AXObserverAddNotification(newObserver, appElement, kAXUIElementDestroyedNotification as CFString, refcon)
        
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(newObserver), .defaultMode)
        
        var focusedWindow: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow) == .success {
            handleWindowFocusChanged(element: focusedWindow as! AXUIElement)
        }
    }
    
    private func handleWindowFocusChanged(element: AXUIElement) {
        guard SettingsManager.shared.snapshot.isWindowMemoryEnabled else { return }
        self.activeWindowElement = element
        
        // 🌟 [핵심 수정] hashValue 대신 고유한 WindowID 추출
        guard let windowID = getWindowID(from: element) else { return }
        
        self.stateQueue.async(flags: .barrier) {
            if let savedData = self.windowLanguageMemory[windowID] {
                DispatchQueue.main.async {
                    InputSourceManager.shared.switchLanguage(to: savedData.lang)
                }
            } else {
                if let currentID = self.getCurrentInputSourceID() {
                    self.windowLanguageMemory[windowID] = (lang: currentID, pid: self.currentPID)
                }
            }
        }
    }
    
    private func handleWindowDestroyed(element: AXUIElement) {
        // 🌟 [핵심 수정] 파기할 때도 고유한 WindowID로 정확하게 찾아서 삭제 (메모리 누수 원천 차단!)
        guard let windowID = getWindowID(from: element) else { return }
        
        stateQueue.async(flags: .barrier) {
            self.windowLanguageMemory.removeValue(forKey: windowID)
        }
    }
    
    @objc private func inputSourceChanged() {
        guard SettingsManager.shared.snapshot.isWindowMemoryEnabled else { return }
        guard let element = activeWindowElement else { return }
        
        // 🌟 [핵심 수정] 언어가 변경될 때도 고유 WindowID를 기준으로 업데이트
        guard let windowID = getWindowID(from: element) else { return }
        
        if let currentID = self.getCurrentInputSourceID() {
            let pid = self.currentPID
            stateQueue.async(flags: .barrier) {
                self.windowLanguageMemory[windowID] = (lang: currentID, pid: pid)
            }
        }
    }
    
    private func getCurrentInputSourceID() -> String? {
        guard let currentSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(currentSource, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }
}
