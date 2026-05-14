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
    
    private var dict: [CGWindowID: (lang: String, pid: pid_t)] = [:]
    private var keys: [CGWindowID] = []
    private let capacity = 200
    
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
            self, selector: #selector(inputSourceChanged),
            name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appTerminated(_:)),
            name: NSWorkspace.didTerminateApplicationNotification, object: nil
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
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        let terminatedPID = app.processIdentifier
        stateQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            let keysToRemove = self.dict.filter { $0.value.pid == terminatedPID }.map { $0.key }
            for key in keysToRemove {
                self.dict.removeValue(forKey: key)
                if let idx = self.keys.firstIndex(of: key) { self.keys.remove(at: idx) }
            }
        }
    }

    func handleWindowFocusChanged(element: AXUIElement) {
        let snapshot = SettingsManager.shared.snapshot
        // 앱별 설정이나 창 기억 중 하나라도 켜져 있어야 작동
        guard snapshot.isAppSpecificEnabled || snapshot.isWindowMemoryEnabled else { return }
        
        self.activeWindowElement = element
        guard let windowID = getWindowID(from: element) else { return }
        
        let latestAppID = AppMonitor.shared.activeAppBundleID
        let latestInputSource = self.getCurrentInputSourceID() ?? ""
        let pid = self.currentPID
        
        var targetLang: String? = nil
        var traceToRecord: DecisionTrace? = nil

        stateQueue.sync(flags: .barrier) {
            if let data = self.dict[windowID] {
                // 1. 이미 기록이 있는 창인 경우
                if snapshot.isWindowMemoryEnabled {
                    targetLang = data.lang
                    traceToRecord = TraceFactory.create(event: .restore, result: .restored, reason: .windowRestore, appName: latestAppID)
                } else if snapshot.isAppSpecificEnabled,
                          let appLang = snapshot.customApps.first(where: { $0.bundleIdentifier == latestAppID })?.targetLanguage {
                    // 창 기억은 꺼져있지만 앱별 설정은 켜져있는 경우 규칙 재적용
                    targetLang = appLang
                    traceToRecord = TraceFactory.create(event: .languageSwitch, result: .switched, reason: .appRule(appName: latestAppID), appName: latestAppID)
                }
                
                // LRU 순서 갱신
                if let idx = self.keys.firstIndex(of: windowID) { self.keys.remove(at: idx) }
                self.keys.append(windowID)
            } else {
                // 2. 처음 발견된 창인 경우
                if snapshot.isAppSpecificEnabled,
                   let appLang = snapshot.customApps.first(where: { $0.bundleIdentifier == latestAppID })?.targetLanguage {
                    targetLang = appLang
                    traceToRecord = TraceFactory.create(event: .languageSwitch, result: .switched, reason: .appRule(appName: latestAppID), appName: latestAppID)
                }
                
                // 메모리에 기록 저장
                self.dict[windowID] = (lang: targetLang ?? latestInputSource, pid: pid)
                self.keys.append(windowID)
                if self.keys.count > capacity {
                    let old = self.keys.removeFirst()
                    self.dict.removeValue(forKey: old)
                }
            }
        }

        // 언어 전환 실행 (nil이 아닐 때만)
        if let lang = targetLang {
            let delay = snapshot.appDelays.first(where: { $0.bundleIdentifier == latestAppID })?.delay ?? 0.05
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                InputSourceManager.shared.switchLanguage(to: lang)
                if let trace = traceToRecord { DecisionTraceManager.shared.record(trace) }
            }
        } else if let trace = traceToRecord {
            DispatchQueue.main.async { DecisionTraceManager.shared.record(trace) }
        }
    }

    func handleWindowDestroyed(element: AXUIElement) {
        guard let windowID = getWindowID(from: element) else { return }
        stateQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            self.dict.removeValue(forKey: windowID)
            if let idx = self.keys.firstIndex(of: windowID) { self.keys.remove(at: idx) }
        }
    }

    @objc private func inputSourceChanged() {
        guard let element = activeWindowElement, let windowID = getWindowID(from: element),
              let latestID = self.getCurrentInputSourceID() else { return }
        let pid = self.currentPID
        stateQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            if self.dict[windowID] != nil {
                self.dict[windowID] = (lang: latestID, pid: pid)
            }
        }
    }

    private func getCurrentInputSourceID() -> String? {
        guard let currentSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(currentSource, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }
    
    func clearMemory() {
        stateQueue.async(flags: .barrier) { [weak self] in
            self?.dict.removeAll()
            self?.keys.removeAll()
        }
    }

    func observeApp(pid: pid_t) {
        let snapshot = SettingsManager.shared.snapshot
        guard snapshot.isWindowMemoryEnabled || snapshot.isAppSpecificEnabled || snapshot.isBrowserTabMemoryEnabled else { return }
        
        if self._currentPID != pid {
            self._currentPID = pid
            
            // 기존 옵저버 제거
            if let observer = axObserver, let rl = observerRunLoop {
                CFRunLoopRemoveSource(rl, AXObserverGetRunLoopSource(observer), .defaultMode)
            }
            
            var observer: AXObserver?
            let callback: AXObserverCallback = { (obs, el, notif, ref) in
                guard let ref = ref else { return }
                let mon = Unmanaged<WindowMonitor>.fromOpaque(ref).takeUnretainedValue()
                let nsNotif = notif as String
                if nsNotif == kAXFocusedWindowChangedNotification as String { mon.handleWindowFocusChanged(element: el) }
                else if nsNotif == kAXTitleChangedNotification as String { mon.handleWindowTitleChanged(element: el) }
                else if nsNotif == kAXUIElementDestroyedNotification as String { mon.handleWindowDestroyed(element: el) }
            }
            
            if AXObserverCreate(pid, callback, &observer) == .success, let newObs = observer {
                self.axObserver = newObs
                let appRef = AXUIElementCreateApplication(pid)
                let refcon = Unmanaged.passUnretained(self).toOpaque()
                AXObserverAddNotification(newObs, appRef, kAXFocusedWindowChangedNotification as CFString, refcon)
                AXObserverAddNotification(newObs, appRef, kAXTitleChangedNotification as CFString, refcon)
                
                let currentRL = CFRunLoopGetCurrent()
                CFRunLoopAddSource(currentRL, AXObserverGetRunLoopSource(newObs), .defaultMode)
                self.observerRunLoop = currentRL
            }
        }
        
        // 🌟 [핵심 보강] 앱 관찰 시작 시, 현재 포커스된 창을 즉시 찾아 처리 로직 실행
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let appElement = AXUIElementCreateApplication(pid)
            var focusedWindow: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow) == .success,
               let windowRef = focusedWindow, CFGetTypeID(windowRef) == AXUIElementGetTypeID() {
                self.handleWindowFocusChanged(element: windowRef as! AXUIElement)
            }
        }
    }

    func handleWindowTitleChanged(element: AXUIElement) {
        if SettingsManager.shared.snapshot.isBrowserTabMemoryEnabled {
            if let app = NSRunningApplication(processIdentifier: self.currentPID),
               let bundleID = app.bundleIdentifier, let appName = app.localizedName {
                BrowserTabManager.shared.handleBrowserTabChanged(bundleID: bundleID, appName: appName)
            }
        }
    }
}
