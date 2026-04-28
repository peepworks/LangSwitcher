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
        // 🌟 [수정됨] 윈도우 메모리나 앱별 언어 지정 기능 중 하나라도 켜져 있으면 옵저버를 가동합니다.
        guard snapshot.isWindowMemoryEnabled || snapshot.isAppSpecificEnabled else { return }
        
        if self.currentPID == pid { return }
        
        if let observer = axObserver, let rl = observerRunLoop {
            CFRunLoopRemoveSource(rl, AXObserverGetRunLoopSource(observer), .defaultMode)
            self.axObserver = nil
            self.observerRunLoop = nil
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
        
        var langToSwitch: String? = nil
        var needsToSave = false
        
        self.stateQueue.sync {
            if let savedData = self.windowLanguageMemory[windowID] {
                // 🌟 1순위: 윈도우 메모리가 켜져 있고, 이 창에 대한 기록이 이미 존재할 경우
                if snapshot.isWindowMemoryEnabled {
                    langToSwitch = savedData.lang
                }
            } else {
                needsToSave = true
            }
        }
        
        // 🌟 2순위: 윈도우 메모리에 기록이 없고(새로운 창), 앱별 지정 언어 기능이 켜져 있는 경우
        var appliedAppSpecific = false
        if needsToSave && snapshot.isAppSpecificEnabled {
            let currentAppID = AppMonitor.shared.activeAppBundleID
            if let customApp = snapshot.customApps.first(where: { $0.bundleIdentifier == currentAppID }), !customApp.targetLanguage.isEmpty {
                langToSwitch = customApp.targetLanguage
                appliedAppSpecific = true
            }
        }
        
        if let lang = langToSwitch {
            DispatchQueue.main.async {
                InputSourceManager.shared.switchLanguage(to: lang)
            }
        }
        
        if needsToSave {
            // 앱별 지정 언어가 적용되었으면 그 언어를, 아니면 현재 시스템 언어를 가져와서 저장합니다.
            let currentID = appliedAppSpecific ? langToSwitch! : (self.getCurrentInputSourceID() ?? "")
            
            if !currentID.isEmpty {
                let pid = self.currentPID
                self.stateQueue.async(flags: .barrier) {
                    if self.windowLanguageMemory[windowID] == nil {
                        if self.windowLanguageMemory.count >= 500 {
                            let overflow = self.windowLanguageMemory.count - 400
                            self.windowLanguageMemory.keys.prefix(overflow).forEach {
                                self.windowLanguageMemory.removeValue(forKey: $0)
                            }
                        }
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
        let snapshot = SettingsManager.shared.snapshot
        guard snapshot.isWindowMemoryEnabled || snapshot.isAppSpecificEnabled else { return }
        
        guard let element = activeWindowElement else { return }
        guard let windowID = getWindowID(from: element) else { return }
        
        if let currentID = self.getCurrentInputSourceID() {
            let pid = self.currentPID
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
