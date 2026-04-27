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
    
    private var windowLanguageMemory: [CGWindowID: (lang: String, pid: pid_t)] = [:]
    
    private var axObserver: AXObserver?
    
    // 🌟 [핵심 추가] 옵저버를 등록했던 정확한 RunLoop를 기억하기 위한 변수
    private var observerRunLoop: CFRunLoop?
    
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
        
        // 방금 전까지 감시하던 앱(PID)과 동일하다면, 옵저버를 새로 만들 필요 없이 기존 것을 그대로 씁니다.
        if self.currentPID == pid {
            return
        }
        
        // 🌟 [핵심 수정] 무작정 현재 RunLoop를 가져오는 대신, 기억해둔 RunLoop(observerRunLoop)에서 옵저버를 정확히 제거합니다.
        if let observer = axObserver, let rl = observerRunLoop {
            CFRunLoopRemoveSource(rl, AXObserverGetRunLoopSource(observer), .defaultMode)
            self.axObserver = nil
            self.observerRunLoop = nil // 제거 후 영수증도 파기
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
        
        // 🌟 [핵심 수정] 새 옵저버를 추가할 때, 어느 RunLoop에 추가했는지 기억(저장)해둡니다.
        let currentRL = CFRunLoopGetCurrent()
        CFRunLoopAddSource(currentRL, AXObserverGetRunLoopSource(newObserver), .defaultMode)
        self.observerRunLoop = currentRL
        
        var focusedWindow: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow) == .success {
            handleWindowFocusChanged(element: focusedWindow as! AXUIElement)
        }
    }
    
    private func handleWindowFocusChanged(element: AXUIElement) {
        guard SettingsManager.shared.snapshot.isWindowMemoryEnabled else { return }
        self.activeWindowElement = element
        
        guard let windowID = getWindowID(from: element) else { return }
        
        // 1. 금고(stateQueue)에 짧게 들어가서 데이터가 있는지 '읽기'만 수행 (.sync)
        // 금고를 독점하지 않으므로 다른 스레드들이 방해받지 않습니다.
        var langToSwitch: String? = nil
        var needsToSave = false
        
        self.stateQueue.sync {
            if let savedData = self.windowLanguageMemory[windowID] {
                langToSwitch = savedData.lang
            } else {
                needsToSave = true
            }
        }
        
        // 2. 금고 밖에서 메인 스레드로 UI 작업 지시 (교착 위험 원천 차단!)
        if let lang = langToSwitch {
            DispatchQueue.main.async {
                InputSourceManager.shared.switchLanguage(to: lang)
            }
        }
        // 3. 기록이 없었다면 현재 언어를 파악한 뒤, 안전하게 '쓰기' 수행
        else if needsToSave {
            // 무거운 C 함수 호출은 금고 밖에서 수행하여 큐 점유(Lock) 시간을 최소화합니다.
            if let currentID = self.getCurrentInputSourceID() {
                let pid = self.currentPID
                
                // 쓰기 작업을 할 때만 잠깐 금고를 독점(.barrier)합니다.
                self.stateQueue.async(flags: .barrier) {
                    // 🌟 [이중 검사(Double-Check) 로직]
                    // 밖에서 언어를 파악하는 그 짧은 틈에 다른 스레드가 이미 값을 썼을 수도 있으니,
                    // 진짜로 비어있는지 한 번 더 확인하고 안전하게 넣습니다.
                    if self.windowLanguageMemory[windowID] == nil {
                        self.windowLanguageMemory[windowID] = (lang: currentID, pid: pid)
                    }
                }
            }
        }
    }
    
    private func handleWindowDestroyed(element: AXUIElement) {
        guard let windowID = getWindowID(from: element) else { return }
        
        stateQueue.async(flags: .barrier) {
            self.windowLanguageMemory.removeValue(forKey: windowID)
        }
    }
    
    @objc private func inputSourceChanged() {
        guard SettingsManager.shared.snapshot.isWindowMemoryEnabled else { return }
        guard let element = activeWindowElement else { return }
        
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
