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
import Darwin

typealias AXUIElementGetWindowFunc = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

class WindowMonitor {
    static let shared = WindowMonitor()
    
    private var windowLanguageMemory: [CGWindowID: (lang: String, pid: pid_t)] = [:]
    
    private var axObserver: AXObserver?
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
        let RTLD_DEFAULT = UnsafeMutableRawPointer(bitPattern: -2)
        
        if let handle = dlsym(RTLD_DEFAULT, "_AXUIElementGetWindow") {
            let getWindow = unsafeBitCast(handle, to: AXUIElementGetWindowFunc.self)
            if getWindow(element, &windowID) == .success {
                return windowID
            }
        }
        return CGWindowID(element.hashValue)
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
        let snapshot = SettingsManager.shared.snapshot
        guard snapshot.isWindowMemoryEnabled || snapshot.isAppSpecificEnabled else { return }
        
        var shouldProceed = false
        stateQueue.sync(flags: .barrier) {
            if self._currentPID != pid {
                self._currentPID = pid
                shouldProceed = true
            }
        }
        
        guard shouldProceed else { return }
        
        if let observer = axObserver, let rl = observerRunLoop {
            CFRunLoopRemoveSource(rl, AXObserverGetRunLoopSource(observer), .defaultMode)
            self.axObserver = nil
            self.observerRunLoop = nil
        }
        
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
        
        // 🌟 [수정됨] 앱 전체(appElement) 레벨에 등록했던 kAXUIElementDestroyedNotification을 여기서 삭제했습니다.
        
        let currentRL = CFRunLoopGetCurrent()
        CFRunLoopAddSource(currentRL, AXObserverGetRunLoopSource(newObserver), .defaultMode)
        self.observerRunLoop = currentRL
        
        var focusedWindow: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow) == .success {
            handleWindowFocusChanged(element: focusedWindow as! AXUIElement)
        }
    }
    
    private func handleWindowFocusChanged(element: AXUIElement) {
        let snapshot = SettingsManager.shared.snapshot
        guard snapshot.isWindowMemoryEnabled || snapshot.isAppSpecificEnabled else { return }
        
        self.activeWindowElement = element
        guard let windowID = getWindowID(from: element) else { return }
        
        // 🌟 데드락(Deadlock)을 피하기 위해 큐 진입 전 필요한 값을 미리 빼둡니다.
        let currentAppID = AppMonitor.shared.activeAppBundleID
        let currentInputSource = self.getCurrentInputSourceID() ?? ""
        let pid = self.currentPID
        
        // 🌟 [핵심 수정] 읽기 - 결정 - 쓰기를 단일 트랜잭션(barrier) 안에서 깔끔하게 통합 처리 (TOCTOU 방어)
        self.stateQueue.async(flags: .barrier) {
            
            if let savedData = self.windowLanguageMemory[windowID] {
                // 1. 기존 창인 경우: 저장된 언어로 복원
                if snapshot.isWindowMemoryEnabled {
                    DispatchQueue.main.async {
                        InputSourceManager.shared.switchLanguage(to: savedData.lang)
                    }
                }
            } else {
                // 2. 새로운 창인 경우: 앱별 지정 확인 후 신규 등록
                var targetLang: String? = nil
                
                if snapshot.isAppSpecificEnabled,
                   let customApp = snapshot.customApps.first(where: { $0.bundleIdentifier == currentAppID }),
                   !customApp.targetLanguage.isEmpty {
                    targetLang = customApp.targetLanguage
                }
                
                if let lang = targetLang {
                    DispatchQueue.main.async {
                        InputSourceManager.shared.switchLanguage(to: lang)
                    }
                }
                
                // 🌟 [수정됨] 강제 언래핑(!)을 제거하고 안전한 로직으로 대체 (크래시 위험 제거)
                let langToSave = targetLang ?? currentInputSource
                
                if !langToSave.isEmpty {
                    // 메모리 무한 증가 방어 (최대 500개)
                    if self.windowLanguageMemory.count >= 500 {
                        let overflow = self.windowLanguageMemory.count - 400
                        self.windowLanguageMemory.keys.prefix(overflow).forEach {
                            self.windowLanguageMemory.removeValue(forKey: $0)
                        }
                    }
                    
                    self.windowLanguageMemory[windowID] = (lang: langToSave, pid: pid)
                    
                    // 🌟 [핵심 수정] 개별 창 요소(element)에 소멸 센서를 직접 달아줍니다! (개별 창 소멸 감지 누락 해결)
                    if let observer = self.axObserver {
                        let refcon = Unmanaged.passUnretained(self).toOpaque()
                        AXObserverAddNotification(observer, element, kAXUIElementDestroyedNotification as CFString, refcon)
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
        let snapshot = SettingsManager.shared.snapshot
        guard snapshot.isWindowMemoryEnabled || snapshot.isAppSpecificEnabled else { return }
        
        guard let element = activeWindowElement else { return }
        guard let windowID = getWindowID(from: element) else { return }
        
        // 데드락 방지용 사전 추출
        let pid = self.currentPID
        
        if let currentID = self.getCurrentInputSourceID() {
            stateQueue.async(flags: .barrier) {
                if self.windowLanguageMemory[windowID] == nil && self.windowLanguageMemory.count >= 500 {
                    let overflow = self.windowLanguageMemory.count - 400
                    self.windowLanguageMemory.keys.prefix(overflow).forEach {
                        self.windowLanguageMemory.removeValue(forKey: $0)
                    }
                }
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
