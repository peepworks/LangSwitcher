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
        
        // 🌟 [최적화] 여기도 안전하게 [weak self]를 걸어줍니다.
        stateQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            let keysToRemove = self.windowLanguageMemory.filter { $0.value.pid == terminatedPID }.map { $0.key }
            for key in keysToRemove { self.windowLanguageMemory.removeValue(forKey: key) }
        }
    }
    
    func observeApp(pid: pid_t) {
        let snapshot = SettingsManager.shared.snapshot
        guard snapshot.isWindowMemoryEnabled || snapshot.isAppSpecificEnabled || snapshot.isBrowserTabMemoryEnabled else { return }
        
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
                } else if notifString == kAXTitleChangedNotification as String {
                    monitor.handleWindowTitleChanged(element: axElement)
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
                AXObserverAddNotification(newObserver, appRef, kAXTitleChangedNotification as CFString, refcon)
                
                let currentRL = CFRunLoopGetCurrent()
                CFRunLoopAddSource(currentRL, AXObserverGetRunLoopSource(newObserver), .defaultMode)
                self.observerRunLoop = currentRL
            }
        }
        
        let appElement = AXUIElementCreateApplication(pid)
        var focusedWindow: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow)
        
        if result == .success, let windowRef = focusedWindow {
            if CFGetTypeID(windowRef) == AXUIElementGetTypeID() {
                let element = windowRef as! AXUIElement
                self.handleWindowFocusChanged(element: element)
            } else {
                print("Invalid window reference format.")
            }
        }
    }
    
    func handleWindowFocusChanged(element: AXUIElement) {
        let snapshot = SettingsManager.shared.snapshot
        guard snapshot.isWindowMemoryEnabled || snapshot.isAppSpecificEnabled else { return }
                
        self.activeWindowElement = element
        guard let windowID = getWindowID(from: element) else { return }
        
        let latestAppID = AppMonitor.shared.activeAppBundleID
        let latestInputSource = self.getCurrentInputSourceID() ?? ""
        let pid = self.currentPID
        
        // 🌟 [1단계: 읽기] 어떤 언어로 바꿀지 안전하게 계산 (단순 동기화)
        var targetLang: String? = nil
        var isNewMemory = false
        
        stateQueue.sync { // barrier 없이 다중 읽기 허용(빠름)
            let savedData = self.windowLanguageMemory[windowID]
            
            if snapshot.isWindowMemoryEnabled {
                if let saved = savedData {
                    targetLang = saved.lang
                }
            }
            
            if targetLang == nil && snapshot.isAppSpecificEnabled {
                if let customApp = snapshot.customApps.first(where: { $0.bundleIdentifier == latestAppID }),
                   !customApp.targetLanguage.isEmpty {
                    targetLang = customApp.targetLanguage
                }
            }
            
            if savedData == nil {
                isNewMemory = true
            }
        }
        
        // 🌟 [2단계: 쓰기] 계산된 결과를 바탕으로 장부에 비동기로 기록 (중첩 큐 없음)
        let langToSave = targetLang ?? latestInputSource
        if !langToSave.isEmpty {
            stateQueue.async(flags: .barrier) { [weak self] in
                guard let self = self else { return }
                
                // 500개 초과 시 오래된 기억(첫 번째 요소) 삭제
                if self.windowLanguageMemory[windowID] == nil && self.windowLanguageMemory.count >= 500 {
                    if let firstKey = self.windowLanguageMemory.keys.first {
                        self.windowLanguageMemory.removeValue(forKey: firstKey)
                    }
                }
                
                self.windowLanguageMemory[windowID] = (lang: langToSave, pid: pid)
            }
        }
        
        // 🌟 [3단계: 부수 효과 실행] 장부 쓰기 블록과 완전히 분리되어 메인 큐에 스케줄링됨
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 1) 실제 언어 전환
            if let lang = targetLang {
                InputSourceManager.shared.switchLanguage(to: lang)
            }
            
            // 2) 윈도우 파괴 감지 옵저버 등록 (AX API는 메인 큐에서 안전하게 실행)
            if isNewMemory, let observer = self.axObserver {
                let refcon = Unmanaged.passUnretained(self).toOpaque()
                AXObserverAddNotification(observer, element, kAXUIElementDestroyedNotification as CFString, refcon)
            }
        }
    }
    
    func handleWindowDestroyed(element: AXUIElement) {
        guard let windowID = getWindowID(from: element) else { return }
        stateQueue.async(flags: .barrier) { [weak self] in // 👈 1. 여기에 추가
            guard let self = self else { return }
            self.windowLanguageMemory.removeValue(forKey: windowID)
        }
    }
    
    @objc private func inputSourceChanged() {
        let snapshot = SettingsManager.shared.snapshot
        guard snapshot.isWindowMemoryEnabled || snapshot.isAppSpecificEnabled else { return }
        guard let element = activeWindowElement, let windowID = getWindowID(from: element) else { return }
        
        let pid = self.currentPID
        
        // 🌟 [핵심 수정] 여기서도 TIS API는 메인 스레드에서 미리 호출하여 안전하게 캡처합니다.
        if let latestID = self.getCurrentInputSourceID() {
            stateQueue.async(flags: .barrier) { [weak self] in
                guard let self = self else { return }
                self.windowLanguageMemory[windowID] = (lang: latestID, pid: pid)
            }
        }
    }
    
    // ⚠️ 주의: 이 함수는 반드시 메인 스레드 또는 메인 런루프와 연결된 컨텍스트에서만 호출되어야 합니다. (Carbon 제약)
    private func getCurrentInputSourceID() -> String? {
        guard let currentSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(currentSource, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }
    
    func handleWindowTitleChanged(element: AXUIElement) {
        let snapshot = SettingsManager.shared.snapshot
        guard snapshot.isBrowserTabMemoryEnabled else { return }

        let pid = self.currentPID
        if let app = NSRunningApplication(processIdentifier: pid),
           let bundleID = app.bundleIdentifier,
           let appName = app.localizedName {
            
            BrowserTabManager.shared.handleBrowserTabChanged(bundleID: bundleID, appName: appName)
        }
    }
    
    // WindowMonitor 클래스 내부에 추가
    func clearMemory() {
        stateQueue.async(flags: .barrier) {
            self.windowLanguageMemory.removeAll()
            // 필요한 경우 현재 활성화된 PID 추적 정보도 초기화
            self._currentPID = 0
            self._activeWindowElement = nil
        }
    }
}
