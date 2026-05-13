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
    
    // 🌟 [추가됨] LRU 메모리 관리를 위한 번호표 변수들
    private var windowAccessTicks: [CGWindowID: Int] = [:]
    private var currentTick: Int = 0
    private let maxWindowMemoryLimit = 200 // 최대 기억할 창의 개수
    
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
        
        // 🌟 안 쓰는 변수(latestAppID) 선언 삭제됨!
        let latestInputSource = self.getCurrentInputSourceID() ?? ""
        let pid = self.currentPID
        
        // 🌟 메인 스레드에서 실행할 부수 효과(Side-effects)를 밖으로 빼내기 위한 변수들
        var languageToSwitch: String? = nil
        var isNewMemory = false

        // 🌟 하나의 거대한 자물쇠(Barrier)로 TOCTOU 경쟁 조건 원천 차단
        stateQueue.sync(flags: .barrier) {
            let savedData = self.windowLanguageMemory[windowID]
            
            if let data = savedData {
                // [기존에 기록된 창]
                // 1. 전환할 언어를 예약
                languageToSwitch = data.lang
                // 2. 기록 최신화 및 LRU(최근 사용) 터치
                self.windowLanguageMemory[windowID] = (lang: data.lang, pid: pid)
                self.touchWindowMemory(windowID: windowID)
            } else {
                // [새로 인식된 창]
                // 1. 현재 사용 중인 언어로 장부 신규 기록
                self.windowLanguageMemory[windowID] = (lang: latestInputSource, pid: pid)
                self.touchWindowMemory(windowID: windowID)
                // 2. 옵저버 등록을 위해 새 메모리임을 표시
                isNewMemory = true
            }
        } // 자물쇠 해제!

        // 🌟 장벽(Barrier)을 빠져나온 후, 안전하게 메인 큐에서 한 번만 UI/시스템 작업 수행
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 1) 실제 언어 전환 실행
            if let lang = languageToSwitch {
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
        stateQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            self.windowLanguageMemory.removeAll()
            
            // 🌟 [추가됨] 번호표 초기화
            self.windowAccessTicks.removeAll()
            self.currentTick = 0
        }
    }
    
    // 🌟 [추가됨] 창 메모리를 최신으로 끌어올리고, 200개가 넘으면 가장 오래된 것을 삭제
    private func touchWindowMemory(windowID: CGWindowID) {
        if currentTick == Int.max {
            rebuildTicksFromScratch()
        }
        
        currentTick += 1
        windowAccessTicks[windowID] = currentTick
        
        if windowAccessTicks.count > maxWindowMemoryLimit {
            // 가장 번호표가 작은(오래된) 창을 찾아서 삭제
            if let oldest = windowAccessTicks.min(by: { $0.value < $1.value }) {
                let oldestKey = oldest.key
                windowLanguageMemory.removeValue(forKey: oldestKey)
                windowAccessTicks.removeValue(forKey: oldestKey)
                
                #if DEBUG
                print("WindowMonitor: 메모리 한계 도달로 오래된 창(\(oldestKey)) 기록을 삭제했습니다.")
                #endif
            }
        }
    }

    // 🌟 [추가됨] Int.max 오버플로우 방어
    private func rebuildTicksFromScratch() {
        let sortedKeys = windowAccessTicks.sorted { $0.value < $1.value }.map { $0.key }
        windowAccessTicks.removeAll(keepingCapacity: true)
        
        for (index, key) in sortedKeys.enumerated() {
            windowAccessTicks[key] = index + 1
        }
        currentTick = sortedKeys.count
    }
}
