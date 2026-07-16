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

@MainActor
class WindowMonitor {
    static let shared = WindowMonitor()

    private let windowMemory = WindowLRUCache(capacity: 200)
    
    // ── 🌟 [멱등성 윈도우 세션 추적 장부 백킹 필드] ──
    private var trackedWindowIDs = Set<CGWindowID>()

    private var axObserver: AXObserver?
    private var observerRunLoop: CFRunLoop?

    var currentPID: pid_t = 0
    var activeWindowElement: AXUIElement?

    private static let axGetWindowFunc: AXUIElementGetWindowFunc? = {
        let implDefault = UnsafeMutableRawPointer(bitPattern: -2)
        if let handle = dlsym(implDefault, "_AXUIElementGetWindow") {
            return unsafeBitCast(handle, to: AXUIElementGetWindowFunc.self)
        }
        return nil
    }()

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
        if let getWindow = Self.axGetWindowFunc {
            if getWindow(element, &windowID) == .success { return windowID }
        }
        return CGWindowID(element.hashValue)
    }

    @objc private func appTerminated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        let terminatedPID = app.processIdentifier

        self.windowMemory.removeWindowsForPID(terminatedPID)
    }

    func handleWindowFocusChanged(element: AXUIElement) {
        let snapshot = SettingsManager.shared.snapshot
        guard snapshot.isAppSpecificEnabled || snapshot.isWindowMemoryEnabled else { return }

        self.activeWindowElement = element
        guard let windowID = getWindowID(from: element) else { return }

        let latestAppID = WorkspaceAppTracker.shared.activeBundleID // 🌟 앞서 수복한 WorkspaceTracker 적용으로 무효 지연 해결

        if (snapshot.isBrowserTabMemoryEnabled || snapshot.isBrowserDomainModeEnabled) &&
            BrowserTabManager.shared.supportedBrowserBundleIDs.contains(latestAppID) {
            if let app = NSRunningApplication(processIdentifier: self.currentPID), let appName = app.localizedName {
                BrowserTabManager.shared.handleBrowserTabChanged(bundleID: latestAppID, appName: appName)
            }
            return
        }

        let latestInputSource = InputSourceManager.shared.currentInputSourceID()
        let pid = self.currentPID

        var targetLang: String? = nil
        var traceToRecord: DecisionTrace? = nil

        let cachedData = self.windowMemory.getLanguage(for: windowID)

        if let data = cachedData, snapshot.isWindowMemoryEnabled {
            targetLang = data.language
            traceToRecord = TraceFactory.create(event: .restore, result: .restored, reason: .windowRestore, appName: latestAppID)
        } else {
            if snapshot.isAppSpecificEnabled,
               let appLang = snapshot.customApps.first(where: { $0.bundleIdentifier == latestAppID })?.targetLanguage {
                targetLang = appLang
                traceToRecord = TraceFactory.create(event: .languageSwitch, result: .switched, reason: .appRule(appName: latestAppID), appName: latestAppID)
            }

            if cachedData == nil {
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
            DecisionTraceManager.shared.record(trace)
        }
    }

    func handleWindowDestroyed(element: AXUIElement) {
        guard let windowID = getWindowID(from: element) else { return }
        
        self.trackedWindowIDs.remove(windowID)
        self.windowMemory.removeWindow(windowID)
        dprint("🧹 [WindowMonitor] 창 파괴 실시간 감지 성공. WindowID: \(windowID) 분쇄 완료.")
    }

    @objc private func inputSourceChanged() {
        guard let element = activeWindowElement, let windowID = getWindowID(from: element) else { return }

        let latestID = InputSourceManager.shared.currentInputSourceID()
        let latestAppID = WorkspaceAppTracker.shared.activeBundleID // 🌟 수복된 추적기 적용
        let snapshot = SettingsManager.shared.snapshot

        if (snapshot.isBrowserTabMemoryEnabled || snapshot.isBrowserDomainModeEnabled) &&
            BrowserTabManager.shared.supportedBrowserBundleIDs.contains(latestAppID) {
            BrowserTabManager.shared.updateManualLanguageChange(latestID)
            return
        }

        let currentPID = self.currentPID
        if self.windowMemory.getLanguage(for: windowID) != nil {
            self.windowMemory.setLanguage(latestID, pid: currentPID, for: windowID)
        }
    }

    func clearMemory() {
        self.windowMemory.clear()
        self.trackedWindowIDs.removeAll()
    }

    private func registerWindowDestructionObserver(window: AXUIElement, observer: AXObserver) {
        guard let windowID = getWindowID(from: window) else { return }
        
        guard !trackedWindowIDs.contains(windowID) else { return }
        trackedWindowIDs.insert(windowID)
        
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let err = AXObserverAddNotification(observer, window, kAXUIElementDestroyedNotification as CFString, refcon)
        
        if err != .success && err != .notificationAlreadyRegistered {
            #if DEBUG
            dprint("⚠️ [WindowMonitor] 윈도우 파괴 알림 가입 실패 (에러코드: \(err.rawValue))")
            #endif
        }
    }

    func observeApp(pid: pid_t) {
        let snapshot = SettingsManager.shared.snapshot
        guard snapshot.isWindowMemoryEnabled || snapshot.isAppSpecificEnabled || snapshot.isBrowserTabMemoryEnabled else { return }

        guard self.currentPID != pid else { return }
        self.currentPID = pid
        
        self.trackedWindowIDs.removeAll()

        // 🌟 [수복] 기존 옵저버 해제 시에도 공통 모드(.commonModes)에서 소스를 확실히 정리하도록 정산
        if let observer = self.axObserver, let rl = self.observerRunLoop {
            CFRunLoopRemoveSource(rl, AXObserverGetRunLoopSource(observer), .commonModes)
            self.axObserver = nil
            self.observerRunLoop = nil
        }

        var observer: AXObserver?
        
        let callback: AXObserverCallback = { (obs, el, notif, ref) in
            guard let ref = ref else { return }
            let mon = Unmanaged<WindowMonitor>.fromOpaque(ref).takeUnretainedValue()
            let nsNotif = notif as String

            MainActor.assumeIsolated {
                if nsNotif == kAXFocusedWindowChangedNotification as String { mon.handleWindowFocusChanged(element: el) }
                else if nsNotif == kAXTitleChangedNotification as String { mon.handleWindowTitleChanged(element: el) }
                else if nsNotif == kAXUIElementDestroyedNotification as String { mon.handleWindowDestroyed(element: el) }
                else if nsNotif == kAXWindowCreatedNotification as String {
                    mon.registerWindowDestructionObserver(window: el, observer: obs)
                }
            }
        }

        if AXObserverCreate(pid, callback, &observer) == .success, let newObs = observer {
            self.axObserver = newObs
            let appRef = AXUIElementCreateApplication(pid)
            let refcon = Unmanaged.passUnretained(self).toOpaque()

            let mainRunLoop = CFRunLoopGetMain()
            
            // 🌟 [수복] 런루프 소스를 등록할 때 kCFRunLoopCommonModes(.commonModes)로 격상 이식!
            // 이로써 마우스 스크롤 휠 홀딩, 창 드래깅, 메뉴바 진입 등의 모드 상태 변경 시에도 윈도우 통로가 상시 작동합니다.
            CFRunLoopAddSource(mainRunLoop, AXObserverGetRunLoopSource(newObs), .commonModes)
            self.observerRunLoop = mainRunLoop

            AXObserverAddNotification(newObs, appRef, kAXFocusedWindowChangedNotification as CFString, refcon)
            AXObserverAddNotification(newObs, appRef, kAXTitleChangedNotification as CFString, refcon)
            AXObserverAddNotification(newObs, appRef, kAXWindowCreatedNotification as CFString, refcon)

            var windowList: CFTypeRef?
            if AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowList) == .success,
               let windows = windowList as? [AXUIElement] {
                for window in windows {
                    self.registerWindowDestructionObserver(window: window, observer: newObs)
                }
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

// MARK: - LRU Cache Infrastructure

@MainActor
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

@MainActor
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
