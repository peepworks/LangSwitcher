//
//  WindowMonitor.swift
//  LangSwitcher
//
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
import Foundation

typealias AXUIElementGetWindowFunc = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

class WindowMonitor {
    static let shared = WindowMonitor()

    private let windowMemory = WindowLRUCache(capacity: 200)

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
            self?.windowMemory.removeWindowsForPID(terminatedPID)
        }
    }

    func handleWindowFocusChanged(element: AXUIElement) {
        let snapshot = SettingsManager.shared.snapshot
        guard snapshot.isAppSpecificEnabled || snapshot.isWindowMemoryEnabled else { return }

        self.activeWindowElement = element
        guard let windowID = getWindowID(from: element) else { return }

        let latestAppID = AppMonitor.shared.activeAppBundleID
        
        // 🌟 [교통정리 1: 브라우저 충돌 방어]
        // 전면에 뜬 앱이 브라우저라면, 윈도우 메모리가 탭 메모리를 덮어쓰지(Overwrite) 못하도록 여기서 실행을 강제 종료(return)시킵니다.
        if (snapshot.isBrowserTabMemoryEnabled || snapshot.isBrowserDomainModeEnabled) &&
            BrowserTabManager.shared.supportedBrowserBundleIDs.contains(latestAppID) {
            if let app = NSRunningApplication(processIdentifier: self.currentPID), let appName = app.localizedName {
                BrowserTabManager.shared.handleBrowserTabChanged(bundleID: latestAppID, appName: appName)
            }
            return
        }

        let latestInputSource = self.getCurrentInputSourceID() ?? ""
        let pid = self.currentPID

        var targetLang: String? = nil
        var traceToRecord: DecisionTrace? = nil

        stateQueue.sync(flags: .barrier) {
            if let data = self.windowMemory.getLanguage(for: windowID) {
                if snapshot.isWindowMemoryEnabled {
                    targetLang = data.language
                    traceToRecord = TraceFactory.create(event: .restore, result: .restored, reason: .windowRestore, appName: latestAppID)
                } else if snapshot.isAppSpecificEnabled,
                          let appLang = snapshot.customApps.first(where: { $0.bundleIdentifier == latestAppID })?.targetLanguage {
                    targetLang = appLang
                    traceToRecord = TraceFactory.create(event: .languageSwitch, result: .switched, reason: .appRule(appName: latestAppID), appName: latestAppID)
                }
            } else {
                if snapshot.isAppSpecificEnabled,
                   let appLang = snapshot.customApps.first(where: { $0.bundleIdentifier == latestAppID })?.targetLanguage {
                    targetLang = appLang
                    traceToRecord = TraceFactory.create(event: .languageSwitch, result: .switched, reason: .appRule(appName: latestAppID), appName: latestAppID)
                }
                self.windowMemory.setLanguage(targetLang ?? latestInputSource, pid: pid, for: windowID)
            }
        }

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
            self?.windowMemory.removeWindow(windowID)
        }
    }

    @objc private func inputSourceChanged() {
        guard let element = activeWindowElement, let windowID = getWindowID(from: element),
              let latestID = self.getCurrentInputSourceID() else { return }

        let latestAppID = AppMonitor.shared.activeAppBundleID
        
        // 🌟 [교통정리 2: 수동 언어 변경 바인딩]
        // 사용자가 브라우저 안에서 한영 전환을 누르면 윈도우 장부가 아니라 탭 장부에 실시간 저장합니다.
        if (SettingsManager.shared.snapshot.isBrowserTabMemoryEnabled || SettingsManager.shared.snapshot.isBrowserDomainModeEnabled) &&
            BrowserTabManager.shared.supportedBrowserBundleIDs.contains(latestAppID) {
            BrowserTabManager.shared.updateManualLanguageChange(latestID)
            return
        }

        stateQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            let currentPID = self._currentPID
            if self.windowMemory.getLanguage(for: windowID) != nil {
                self.windowMemory.setLanguage(latestID, pid: currentPID, for: windowID)
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
            self?.windowMemory.clear()
        }
    }

    func observeApp(pid: pid_t) {
        let snapshot = SettingsManager.shared.snapshot
        guard snapshot.isWindowMemoryEnabled || snapshot.isAppSpecificEnabled || snapshot.isBrowserTabMemoryEnabled else { return }

        stateQueue.sync(flags: .barrier) {
            guard self._currentPID != pid else { return }
            self._currentPID = pid

            if let observer = self.axObserver, let rl = self.observerRunLoop {
                CFRunLoopRemoveSource(rl, AXObserverGetRunLoopSource(observer), .defaultMode)
                self.axObserver = nil
                self.observerRunLoop = nil
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

                let mainRunLoop = CFRunLoopGetMain()
                CFRunLoopAddSource(mainRunLoop, AXObserverGetRunLoopSource(newObs), .defaultMode)
                self.observerRunLoop = mainRunLoop
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            let currentPIDInMain = self.currentPID
            guard currentPIDInMain == pid else { return }

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

class WindowNode {
    let windowID: CGWindowID
    var language: String
    var pid: pid_t

    var prev: WindowNode?
    var next: WindowNode?

    init(windowID: CGWindowID, language: String, pid: pid_t) {
        self.windowID = windowID
        self.language = language
        self.pid = pid
    }
}

class WindowLRUCache {
    private let capacity: Int
    private var cache: [CGWindowID: WindowNode] = [:]
    private var pidIndex: [pid_t: Set<CGWindowID>] = [:]

    private let head = WindowNode(windowID: 0, language: "", pid: 0)
    private let tail = WindowNode(windowID: 0, language: "", pid: 0)

    init(capacity: Int = 200) {
        self.capacity = capacity
        head.next = tail
        tail.prev = head
    }

    func getLanguage(for windowID: CGWindowID) -> (language: String, pid: pid_t)? {
        guard let node = cache[windowID] else { return nil }
        moveToHead(node)
        return (node.language, node.pid)
    }

    func setLanguage(_ language: String, pid: pid_t, for windowID: CGWindowID) {
        if let existingNode = cache[windowID] {
            existingNode.language = language
            if existingNode.pid != pid {
                pidIndex[existingNode.pid]?.remove(windowID)
                if pidIndex[existingNode.pid]?.isEmpty == true { pidIndex.removeValue(forKey: existingNode.pid) }
                existingNode.pid = pid
                pidIndex[pid, default: []].insert(windowID)
            }
            moveToHead(existingNode)
        } else {
            let newNode = WindowNode(windowID: windowID, language: language, pid: pid)
            cache[windowID] = newNode
            addNode(newNode)
            pidIndex[pid, default: []].insert(windowID)
            if cache.count > capacity {
                if let tailNode = popTail() {
                    cache.removeValue(forKey: tailNode.windowID)
                    pidIndex[tailNode.pid]?.remove(tailNode.windowID)
                    if pidIndex[tailNode.pid]?.isEmpty == true { pidIndex.removeValue(forKey: tailNode.pid) }
                }
            }
        }
    }

    func removeWindow(_ windowID: CGWindowID) {
        guard let node = cache[windowID] else { return }
        removeNode(node)
        cache.removeValue(forKey: windowID)
        pidIndex[node.pid]?.remove(windowID)
        if pidIndex[node.pid]?.isEmpty == true { pidIndex.removeValue(forKey: node.pid) }
    }

    func removeWindowsForPID(_ pid: pid_t) {
        guard let windowIDs = pidIndex.removeValue(forKey: pid) else { return }
        windowIDs.forEach { windowID in
            if let node = cache[windowID] {
                removeNode(node)
                cache.removeValue(forKey: windowID)
            }
        }
    }

    func clear() {
        cache.removeAll()
        pidIndex.removeAll()
        head.next = tail
        tail.prev = head
    }

    private func addNode(_ node: WindowNode) {
        node.prev = head; node.next = head.next
        head.next?.prev = node; head.next = node
    }

    private func removeNode(_ node: WindowNode) {
        let prev = node.prev; let next = node.next
        prev?.next = next; next?.prev = prev
    }

    private func moveToHead(_ node: WindowNode) {
        removeNode(node); addNode(node)
    }

    private func popTail() -> WindowNode? {
        let res = tail.prev
        if res === head { return nil }
        if let res = res { removeNode(res) }
        return res
    }
}
