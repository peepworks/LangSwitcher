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
            if getWindow(element, &windowID) == .success { return windowID }
        }
        return CGWindowID(element.hashValue)
    }
    
    @objc private func appTerminated(_ notification: Notification) {
        guard SettingsManager.shared.snapshot.isWindowMemoryCleanupEnabled else { return }
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        let terminatedPID = app.processIdentifier
        stateQueue.async(flags: .barrier) {
            let keysToRemove = self.windowLanguageMemory.filter { $0.value.pid == terminatedPID }.map { $0.key }
            for key in keysToRemove { self.windowLanguageMemory.removeValue(forKey: key) }
        }
    }
    
    func observeApp(pid: pid_t) {
        let snapshot = SettingsManager.shared.snapshot
        guard snapshot.isWindowMemoryEnabled || snapshot.isAppSpecificEnabled else { return }
        
        // 1. 원자적 PID 체크 및 갱신
        var shouldProceed = false
        stateQueue.sync(flags: .barrier) {
            if self._currentPID != pid {
                self._currentPID = pid
                shouldProceed = true
            }
        }
        
        // 2. [옵저버 등록] 앱이 바뀌었을 때만 새로운 감시자를 생성합니다.
        if shouldProceed {
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
            if result == .success, let newObserver = observer {
                self.axObserver = newObserver
                let appRef = AXUIElementCreateApplication(pid)
                let refcon = Unmanaged.passUnretained(self).toOpaque()
                
                AXObserverAddNotification(newObserver, appRef, kAXFocusedWindowChangedNotification as CFString, refcon)
                
                let currentRL = CFRunLoopGetCurrent()
                CFRunLoopAddSource(currentRL, AXObserverGetRunLoopSource(newObserver), .defaultMode)
                self.observerRunLoop = currentRL
            }
        }
        
        // 3. [즉시 처리] 현재 포커스된 창을 안전하게 1회 실행합니다. (이 로직은 함수 하단에 한 번만 있으면 됩니다)
        let appElement = AXUIElementCreateApplication(pid)
        var focusedWindow: CFTypeRef?
                
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow)
                
        // 🌟 강제 캐스팅(as!)이 완전히 제거된 안전한 블록
        if result == .success, let windowRef = focusedWindow {
            if CFGetTypeID(windowRef) == AXUIElementGetTypeID() {
                self.handleWindowFocusChanged(element: windowRef as! AXUIElement)
            }
        } else {
            print("ℹ️ [WindowMonitor] No focused window found for PID: \(pid)")
        }
    }
    
    func handleWindowFocusChanged(element: AXUIElement) {
        let snapshot = SettingsManager.shared.snapshot
        guard snapshot.isWindowMemoryEnabled || snapshot.isAppSpecificEnabled else { return }
        
        self.activeWindowElement = element
        guard let windowID = getWindowID(from: element) else { return }
        
        let currentAppID = AppMonitor.shared.activeAppBundleID
        let currentInputSource = self.getCurrentInputSourceID() ?? ""
        let pid = self.currentPID
        
        stateQueue.async(flags: .barrier) {
            if let savedData = self.windowLanguageMemory[windowID] {
                // 1. 이미 기록이 있는 창: 저장된 언어로 복구
                if snapshot.isWindowMemoryEnabled {
                    DispatchQueue.main.async {
                        InputSourceManager.shared.switchLanguage(to: savedData.lang)
                    }
                }
            } else {
                // 2. 처음 보는 창: 앱별 설정 확인
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
                
                // 메모리 등록
                let langToSave = targetLang ?? currentInputSource
                if !langToSave.isEmpty {
                    if self.windowLanguageMemory.count >= 500 {
                        self.windowLanguageMemory.removeValue(forKey: self.windowLanguageMemory.keys.first!)
                    }
                    self.windowLanguageMemory[windowID] = (lang: langToSave, pid: pid)
                    
                    // 이 창이 닫힐 때를 대비해 파괴 알림 등록
                    if let observer = self.axObserver {
                        let refcon = Unmanaged.passUnretained(self).toOpaque()
                        AXObserverAddNotification(observer, element, kAXUIElementDestroyedNotification as CFString, refcon)
                    }
                }
            }
        }
    }
    
    func handleWindowDestroyed(element: AXUIElement) {
        guard let windowID = getWindowID(from: element) else { return }
        stateQueue.async(flags: .barrier) {
            self.windowLanguageMemory.removeValue(forKey: windowID)
        }
    }
    
    @objc private func inputSourceChanged() {
        let snapshot = SettingsManager.shared.snapshot
        guard snapshot.isWindowMemoryEnabled else { return }
        guard let element = activeWindowElement, let windowID = getWindowID(from: element) else { return }
        
        let pid = self.currentPID
        if let currentID = self.getCurrentInputSourceID() {
            stateQueue.async(flags: .barrier) {
                // 🌟 [수정] 무조건 저장하여 사용자가 수동으로 바꾼 언어를 기억하게 함
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
