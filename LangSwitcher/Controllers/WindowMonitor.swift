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
import Foundation

typealias AXUIElementGetWindowFunc = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

@MainActor // 🌟 클래스 전체를 메인 액터로 격리하여 수동 배리어 동시성 큐를 전면 제거합니다.
class WindowMonitor {
    static let shared = WindowMonitor()

    private let windowMemory = WindowLRUCache(capacity: 200)
    
    private var axObserver: AXObserver?
    private var observerRunLoop: CFRunLoop?
    
    var currentPID: pid_t = 0
    var activeWindowElement: AXUIElement?

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

    func observeApp(pid: pid_t) {
            // 1차 방어선: 메인 액터 큐 대기 도중 취소된 좀비 태스크 입구 컷
            guard !Task.isCancelled else {
                dprint("🛑 [WindowMonitor] 진입 전 태스크 취소 감지. (PID: \(pid))")
                return
            }
            
            let snapshot = SettingsManager.shared.snapshot
            guard snapshot.isWindowMemoryEnabled ||
                  snapshot.isAppSpecificEnabled ||
                  snapshot.isBrowserTabMemoryEnabled ||
                  snapshot.isBrowserDomainModeEnabled else { return }

            guard self.currentPID != pid else { return }
            self.currentPID = pid

            // 기존 옵저버 자원이 있다면 메인 런루프에서 퇴출 및 해제 (.commonModes 규격 맞춤)
            if let observer = self.axObserver, let rl = self.observerRunLoop {
                CFRunLoopRemoveSource(rl, AXObserverGetRunLoopSource(observer), .commonModes)
                self.axObserver = nil
                self.observerRunLoop = nil
            }

            var observer: AXObserver?
            let callback: AXObserverCallback = { (obs, el, notif, ref) in
                guard let ref = ref else { return }
                MainActor.assumeIsolated {
                    let mon = Unmanaged<WindowMonitor>.fromOpaque(ref).takeUnretainedValue()
                    let nsNotif = notif as String
                    if nsNotif == kAXFocusedWindowChangedNotification as String { mon.handleWindowFocusChanged(element: el) }
                    else if nsNotif == kAXTitleChangedNotification as String { mon.handleWindowTitleChanged(element: el) }
                    else if nsNotif == kAXUIElementDestroyedNotification as String { mon.handleWindowDestroyed(element: el) }
                }
            }

            if AXObserverCreate(pid, callback, &observer) == .success, let newObs = observer {
                
                guard !Task.isCancelled, self.currentPID == pid else {
                    dprint("⚠️ [WindowMonitor] 옵저버 생성 후 취소 감지.")
                    return
                }

                // 🌟 [치명적 누락 원인 수복 완료!]
                // 생성된 옵저버 엔진에 구체적으로 어떤 실시간 커널 이벤트를 가로챌지 바인딩 명세를 명시합니다.
                // 이 세 줄이 수립되어야 비로소 브라우저의 탭 변경(Title Changed) 신호가 파이프라인을 타고 흐릅니다.
                let appElement = AXUIElementCreateApplication(pid)
                let refCon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
                
                AXObserverAddNotification(newObs, appElement, kAXFocusedWindowChangedNotification as CFString, refCon)
                AXObserverAddNotification(newObs, appElement, kAXTitleChangedNotification as CFString, refCon)
                AXObserverAddNotification(newObs, appElement, kAXUIElementDestroyedNotification as CFString, refCon)

                self.axObserver = newObs
                let mainRunLoop = CFRunLoopGetMain()
                
                // 🌟 [.defaultMode ➔ .commonModes 격상]
                // 유저가 macOS 메뉴바 팝업을 열고 있는 마우스 트래킹 순간에도
                // 백그라운드 탭 감시 인터럽트가 멈추지 않고 100% 실행되도록 보장합니다.
                CFRunLoopAddSource(mainRunLoop, AXObserverGetRunLoopSource(newObs), .commonModes)
                self.observerRunLoop = mainRunLoop

                dprint("🎯 [WindowMonitor] PID \(pid) 알림 명세 구독 및 commonModes 런루프 최종 등록 성공")
            }

            // 포커스 윈도우 추적을 위한 초기 딜레이 트리거
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self = self else { return }
                guard self.currentPID == pid else { return }

                let appElement = AXUIElementCreateApplication(pid)
                var focusedWindow: CFTypeRef?
                if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow) == .success,
                   let windowRef = focusedWindow, CFGetTypeID(windowRef) == AXUIElementGetTypeID() {
                    self.handleWindowFocusChanged(element: windowRef as! AXUIElement)
                }
            }
        }

    // MARK: - 윈도우 메모리 & 앱 특정 규칙 제어 비즈니스 코어

    @MainActor
    func handleWindowFocusChanged(element: AXUIElement) {
        let snapshot = SettingsManager.shared.snapshot
        guard snapshot.isAppSpecificEnabled || snapshot.isWindowMemoryEnabled else { return }

        self.activeWindowElement = element
        guard let windowID = getWindowID(from: element) else { return }

        let latestAppID = AppMonitor.shared.activeAppBundleID
        let latestInputSource = self.getCurrentInputSourceID() ?? ""
        let pid = self.currentPID

        var targetLang: String? = nil
        var traceToRecord: DecisionTrace? = nil

        if let data = self.windowMemory.getLanguage(for: windowID) {
            // 1. 이미 장부에 기록이 있는 창인 경우 복구 또는 앱 규칙 분기 실행
            if snapshot.isWindowMemoryEnabled {
                targetLang = data.language
                traceToRecord = TraceFactory.create(event: .restore, result: .restored, reason: .windowRestore, appName: latestAppID)
            } else if snapshot.isAppSpecificEnabled,
                      let appLang = snapshot.customApps.first(where: { $0.bundleIdentifier == latestAppID })?.targetLanguage {
                targetLang = appLang
                traceToRecord = TraceFactory.create(event: .languageSwitch, result: .switched, reason: .appRule(appName: latestAppID), appName: latestAppID)
            }
        } else {
            // 2. 처음 발견된 새로운 창인 경우 앱 특정 규칙이 있는지 우선 대입
            if snapshot.isAppSpecificEnabled,
               let appLang = snapshot.customApps.first(where: { $0.bundleIdentifier == latestAppID })?.targetLanguage {
                targetLang = appLang
                traceToRecord = TraceFactory.create(event: .languageSwitch, result: .switched, reason: .appRule(appName: latestAppID), appName: latestAppID)
            }

            // O(1) 성능 캐시 장부에 안전하게 단독 노드 신규 등록
            self.windowMemory.setLanguage(targetLang ?? latestInputSource, pid: pid, for: windowID)
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
        self.windowMemory.removeWindow(windowID)
    }

    func handleWindowTitleChanged(element: AXUIElement) {
        let snapshot = SettingsManager.shared.snapshot
        // 🌟 [버그 수복] 브라우저 탭 장부 메모리 혹은 도메인 모드가 켜져있을 때 모두 신호가 통과하도록 라우터를 개방합니다.
        if snapshot.isBrowserTabMemoryEnabled || snapshot.isBrowserDomainModeEnabled {
            if let app = NSRunningApplication(processIdentifier: self.currentPID),
               let bundleID = app.bundleIdentifier, let appName = app.localizedName {
                BrowserTabManager.shared.handleBrowserTabChanged(bundleID: bundleID, appName: appName)
            }
        }
    }

    @objc private func inputSourceChanged() {
        guard let element = activeWindowElement, let windowID = getWindowID(from: element),
              let latestID = self.getCurrentInputSourceID() else { return }

        let currentPID = self.currentPID
        if self.windowMemory.getLanguage(for: windowID) != nil {
            self.windowMemory.setLanguage(latestID, pid: currentPID, for: windowID)
        }
    }

    @objc private func appTerminated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        let terminatedPID = app.processIdentifier
        self.windowMemory.removeWindowsForPID(terminatedPID)
    }

    func clearMemory() {
        self.windowMemory.clear()
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

    private func getCurrentInputSourceID() -> String? {
        guard let currentSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(currentSource, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }
}

// MARK: - 완벽한 O(1) 성능 보장 구조적 연결 컴포넌트 레이어

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
                if pidIndex[existingNode.pid]?.isEmpty == true {
                    pidIndex.removeValue(forKey: existingNode.pid)
                }
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
                    if pidIndex[tailNode.pid]?.isEmpty == true {
                        pidIndex.removeValue(forKey: tailNode.pid)
                    }
                }
            }
        }
    }

    func removeWindow(_ windowID: CGWindowID) {
        guard let node = cache[windowID] else { return }
        removeNode(node)
        cache.removeValue(forKey: windowID)

        pidIndex[node.pid]?.remove(windowID)
        if pidIndex[node.pid]?.isEmpty == true {
            pidIndex.removeValue(forKey: node.pid)
        }
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
        node.prev = head
        node.next = head.next
        head.next?.prev = node
        head.next = node
    }

    private func removeNode(_ node: WindowNode) {
        let prev = node.prev
        let next = node.next
        prev?.next = next
        next?.prev = prev
    }

    private func moveToHead(_ node: WindowNode) {
        removeNode(node)
        addNode(node)
    }

    private func popTail() -> WindowNode? {
        let res = tail.prev
        if res === head { return nil }
        if let res = res { removeNode(res) }
        return res
    }
}
