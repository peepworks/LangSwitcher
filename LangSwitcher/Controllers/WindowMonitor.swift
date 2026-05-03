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
                // 🌟 브라우저 탭 전환을 감지하기 위한 Title Changed 이벤트 구독
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
                self.handleWindowFocusChanged(element: windowRef as! AXUIElement)
            } else {
                print("⚠️ [WindowMonitor] Expected AXUIElement but got a different CFType.")
            }
        }
    }
    
    func handleWindowFocusChanged(element: AXUIElement) {
        let snapshot = SettingsManager.shared.snapshot
                
        // 1. 둘 다 꺼져있으면 아예 실행하지 않고 조기 종료
        guard snapshot.isWindowMemoryEnabled || snapshot.isAppSpecificEnabled else { return }
                
        // 2. 먼저 변수들을 안전하게 추출합니다. (순서가 매우 중요합니다!)
        self.activeWindowElement = element
        guard let windowID = getWindowID(from: element) else { return }
        
        let currentAppID = AppMonitor.shared.activeAppBundleID
        let currentInputSource = self.getCurrentInputSourceID() ?? ""
        let pid = self.currentPID
        
        // 3. 상태 변경은 반드시 stateQueue 안에서 처리합니다.
        stateQueue.async(flags: .barrier) {
            var targetLang: String? = nil
            let savedData = self.windowLanguageMemory[windowID]
            
            // 🌟 [핵심 수정] 기능별로 우선순위를 정하고, 독립적으로 체크합니다.
            
            // 우선순위 1: 창(Window) 단위 기억이 켜져 있을 때
            if snapshot.isWindowMemoryEnabled {
                if let saved = savedData {
                    targetLang = saved.lang
                }
            }
            
            // 우선순위 2: 앱(App) 단위 설정이 켜져 있고, 앞선 창 단위 데이터가 없을 때
            if targetLang == nil && snapshot.isAppSpecificEnabled {
                if let customApp = snapshot.customApps.first(where: { $0.bundleIdentifier == currentAppID }),
                   !customApp.targetLanguage.isEmpty {
                    targetLang = customApp.targetLanguage
                }
            }
            
            // 4. 최종적으로 찾은 언어가 있다면 메인 스레드에서 언어 전환 실행
            if let lang = targetLang {
                DispatchQueue.main.async {
                    InputSourceManager.shared.switchLanguage(to: lang)
                }
            }
            
            // 5. 메모리에 현재 언어 상태 저장 및 옵저버 등록 로직 (기존 코드 완벽 유지)
            let langToSave = targetLang ?? currentInputSource
            if !langToSave.isEmpty {
                // 용량 제한 관리 (500개)
                if self.windowLanguageMemory[windowID] == nil && self.windowLanguageMemory.count >= 500 {
                    if let firstKey = self.windowLanguageMemory.keys.first {
                        self.windowLanguageMemory.removeValue(forKey: firstKey)
                    }
                }
                
                self.windowLanguageMemory[windowID] = (lang: langToSave, pid: pid)
                
                // 새 창일 경우 파괴 이벤트 옵저버 등록
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
    
    // 🌟 [핵심 수정 1] 오류를 유발했던 중복 코드를 제거하고 깔끔하게 윈도우 메모리만 관리하도록 원복했습니다.
    // (이유: 브라우저 탭 메모리는 사용자가 타이핑 중 언어를 바꾸더라도 탭을 이동할 때 매니저가 알아서 '마지막 언어'를 캡처하여 저장하기 때문입니다.)
    @objc private func inputSourceChanged() {
        let snapshot = SettingsManager.shared.snapshot
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
    
    // 🌟 [핵심 수정 2] 창 제목 변경(탭 전환) 시 코어 엔진 호출
    func handleWindowTitleChanged(element: AXUIElement) {
        let snapshot = SettingsManager.shared.snapshot
        guard snapshot.isBrowserTabMemoryEnabled else { return }

        let pid = self.currentPID
        if let app = NSRunningApplication(processIdentifier: pid),
           let bundleID = app.bundleIdentifier,
           let appName = app.localizedName {
            
            // 🔥 BrowserTabManager가 내부적으로 탭 전환 감지, 현재 상태 캡처, 새 상태 복원까지 모든 것을 비동기로 자동 수행합니다!
            BrowserTabManager.shared.handleBrowserTabChanged(bundleID: bundleID, appName: appName)
        }
    }
}
