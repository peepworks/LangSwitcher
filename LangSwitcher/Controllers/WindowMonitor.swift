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
        
        var shouldProceed = false
        stateQueue.sync(flags: .barrier) {
            if self._currentPID != pid {
                self._currentPID = pid
                shouldProceed = true
            }
        }
        
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
        
        let appElement = AXUIElementCreateApplication(pid)
        var focusedWindow: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow)
        
        // 🌟 [수정됨] Swift 컴파일러 경고 해결 및 완벽한 런타임 타입 방어
        if result == .success, let windowRef = focusedWindow {
            // 1. CoreFoundation 고유의 타입 검사 방식을 사용하여 실제 객체 타입을 확인합니다.
            if CFGetTypeID(windowRef) == AXUIElementGetTypeID() {
                // 2. 타입 검사가 완벽하게 끝났으므로, 컴파일러가 안심하도록 강제 캐스팅(as!)을 사용합니다.
                self.handleWindowFocusChanged(element: windowRef as! AXUIElement)
            } else {
                print("⚠️ [WindowMonitor] Expected AXUIElement but got a different CFType.")
            }
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
            // 1. 앱별 설정 지정 언어 확인
            var appSpecificLang: String? = nil
            if snapshot.isAppSpecificEnabled,
               let customApp = snapshot.customApps.first(where: { $0.bundleIdentifier == currentAppID }),
               !customApp.targetLanguage.isEmpty {
                appSpecificLang = customApp.targetLanguage
            }
            
            // 2. 창별 기억 데이터 확인
            let savedData = self.windowLanguageMemory[windowID]
            
            // 🌟 [핵심 수정] 3. 우선순위에 따른 타겟 언어 결정 (논리적 충돌 해결)
            var targetLang: String? = nil
            
            if snapshot.isWindowMemoryEnabled, let saved = savedData {
                // [1순위] 창별 기억이 켜져 있고 기록이 있다면 무조건 우선 복원
                targetLang = saved.lang
            } else if let appLang = appSpecificLang {
                // [2순위] 창별 기억이 꺼져 있거나 첫 창인 경우, 앱별 지정 언어 강제 적용
                targetLang = appLang
            }
            
            // 4. 언어 전환 실행
            if let lang = targetLang {
                DispatchQueue.main.async {
                    InputSourceManager.shared.switchLanguage(to: lang)
                }
            }
            
            // 5. 메모리 갱신 및 파괴 알림 등록
            let langToSave = targetLang ?? currentInputSource
            if !langToSave.isEmpty {
                if self.windowLanguageMemory[windowID] == nil && self.windowLanguageMemory.count >= 500 {
                    self.windowLanguageMemory.removeValue(forKey: self.windowLanguageMemory.keys.first!)
                }
                
                self.windowLanguageMemory[windowID] = (lang: langToSave, pid: pid)
                
                if savedData == nil, let observer = self.axObserver {
                    let refcon = Unmanaged.passUnretained(self).toOpaque()
                    AXObserverAddNotification(observer, element, kAXUIElementDestroyedNotification as CFString, refcon)
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
        // 🌟 창별 기억이 꺼져 있더라도 앱별 설정을 위해 메모리를 추적하도록 가드(guard) 조건 완화
        guard snapshot.isWindowMemoryEnabled || snapshot.isAppSpecificEnabled else { return }
        guard let element = activeWindowElement, let windowID = getWindowID(from: element) else { return }
        
        let pid = self.currentPID
        if let currentID = self.getCurrentInputSourceID() {
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
