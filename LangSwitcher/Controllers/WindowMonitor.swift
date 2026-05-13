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
        
        let latestAppID = AppMonitor.shared.activeAppBundleID
        let latestInputSource = self.getCurrentInputSourceID() ?? ""
        let pid = self.currentPID
        
        var appSpecificLang: String? = nil
        if snapshot.isAppSpecificEnabled {
            if let customApp = snapshot.customApps.first(where: { $0.bundleIdentifier == latestAppID }) {
                appSpecificLang = customApp.targetLanguage
            }
        }
        
        var switchDelay: TimeInterval = 0.05
        if let customDelay = snapshot.appDelays.first(where: { $0.bundleIdentifier == latestAppID }) {
            switchDelay = customDelay.delay
        }

        var languageToSwitch: String? = nil
        var isNewMemory = false
        
        // 🌟 [추가됨] 어떤 이유로 결정되었는지 담아둘 변수
        var traceToRecord: DecisionTrace? = nil

        stateQueue.sync(flags: .barrier) {
            let savedData = self.windowLanguageMemory[windowID]
            
            if let data = savedData {
                // [기존에 열려있던 창]
                if snapshot.isWindowMemoryEnabled {
                    languageToSwitch = data.lang
                    // 🌟 로깅: 창 기억에 의해 복원됨
                    traceToRecord = TraceFactory.create(event: .restore, result: .restored, reason: .windowRestore, appName: latestAppID)
                } else if let targetLang = appSpecificLang {
                    languageToSwitch = targetLang
                    // 🌟 로깅: 앱별 규칙 적용
                    traceToRecord = TraceFactory.create(event: .languageSwitch, result: .switched, reason: .appRule(appName: latestAppID), appName: latestAppID)
                } else {
                    // 🌟 로깅: 아무 규칙도 해당 없음
                    traceToRecord = TraceFactory.create(event: .languageSwitch, result: .kept, reason: .noMatchingRule, appName: latestAppID)
                }
                
                if let lang = languageToSwitch {
                    self.windowLanguageMemory[windowID] = (lang: lang, pid: pid)
                }
                self.touchWindowMemory(windowID: windowID)
                
            } else {
                // [처음 열린 새 창]
                if let targetLang = appSpecificLang {
                    languageToSwitch = targetLang
                    self.windowLanguageMemory[windowID] = (lang: targetLang, pid: pid)
                    // 🌟 로깅: 앱별 규칙 적용
                    traceToRecord = TraceFactory.create(event: .languageSwitch, result: .switched, reason: .appRule(appName: latestAppID), appName: latestAppID)
                } else {
                    self.windowLanguageMemory[windowID] = (lang: latestInputSource, pid: pid)
                    // 🌟 로깅: 아무 규칙도 해당 없음
                    traceToRecord = TraceFactory.create(event: .languageSwitch, result: .kept, reason: .noMatchingRule, appName: latestAppID)
                }
                self.touchWindowMemory(windowID: windowID)
                isNewMemory = true
            }
        }

        // 🌟 지연 후 안전하게 실행 및 기록
        if let lang = languageToSwitch {
            DispatchQueue.main.asyncAfter(deadline: .now() + switchDelay) {
                InputSourceManager.shared.switchLanguage(to: lang)
                
                // 🌟 메인 스레드에서 UI를 그리는 매니저에게 기록 전달
                if let trace = traceToRecord {
                    DecisionTraceManager.shared.record(trace)
                }
            }
        } else {
            // 언어가 바뀌지 않았어도(kept) 기록은 남김
            DispatchQueue.main.async {
                if let trace = traceToRecord {
                    DecisionTraceManager.shared.record(trace)
                }
            }
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
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
