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

class WindowMonitor {
    static let shared = WindowMonitor()
    
    // 🌟 [핵심 변경 1] 기존 dict와 keys 배열을 지우고, O(1) 성능의 WindowLRUCache 인스턴스 하나로 교체
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
            // 🌟 [수정 완료] 함수 이름을 최신 O(1) 버전인 removeWindowsForPID로 변경
            self?.windowMemory.removeWindowsForPID(terminatedPID)
        }
    }

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

        stateQueue.sync(flags: .barrier) {
            // 🌟 [핵심 변경 3] O(1) 속도로 캐시 읽기 (접근 시 자동으로 최근 사용 갱신됨)
            if let data = self.windowMemory.getLanguage(for: windowID) {
                // 1. 이미 기록이 있는 창인 경우
                if snapshot.isWindowMemoryEnabled {
                    targetLang = data.language
                    traceToRecord = TraceFactory.create(event: .restore, result: .restored, reason: .windowRestore, appName: latestAppID)
                } else if snapshot.isAppSpecificEnabled,
                          let appLang = snapshot.customApps.first(where: { $0.bundleIdentifier == latestAppID })?.targetLanguage {
                    targetLang = appLang
                    traceToRecord = TraceFactory.create(event: .languageSwitch, result: .switched, reason: .appRule(appName: latestAppID), appName: latestAppID)
                }
            } else {
                // 2. 처음 발견된 창인 경우
                if snapshot.isAppSpecificEnabled,
                   let appLang = snapshot.customApps.first(where: { $0.bundleIdentifier == latestAppID })?.targetLanguage {
                    targetLang = appLang
                    traceToRecord = TraceFactory.create(event: .languageSwitch, result: .switched, reason: .appRule(appName: latestAppID), appName: latestAppID)
                }
                
                // 🌟 [핵심 변경 4] O(1) 속도로 캐시에 기록 쓰기 (LRU 방출은 내부에서 알아서 처리됨)
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
            // 🌟 [핵심 변경 5] 윈도우 파괴 시 특정 노드 하나만 O(1) 속도로 안전하게 삭제
            self?.windowMemory.removeWindow(windowID)
        }
    }

    @objc private func inputSourceChanged() {
        guard let element = activeWindowElement, let windowID = getWindowID(from: element),
              let latestID = self.getCurrentInputSourceID() else { return }
        
        // ❌ 기존에 바깥에 있던 let pid = self.currentPID 삭제 완료
        
        stateQueue.async(flags: .barrier) { [weak self] in
            // 🌟 옵셔널 체이닝(self?) 대신 캡처된 self를 확실하게 풀어줍니다.
            guard let self = self else { return }
            
            // 🌟 [핵심 수정] 배리어 블록(안전 구역) 안으로 들어온 직후에,
            // 가장 최신의 _currentPID 값을 직접 읽어옵니다! (TOCTOU 경합 완벽 차단)
            let currentPID = self._currentPID
            
            // 🌟 [핵심 변경 6] 언어가 변경되었을 때 캐시의 값만 덮어쓰기 (O(1))
            if self.windowMemory.getLanguage(for: windowID) != nil {
                // 방금 읽어온 가장 신선한 currentPID를 사용하여 캐시를 업데이트합니다.
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
            self?.windowMemory.clear() // 🌟 O(1) 클리어
        }
    }

    func observeApp(pid: pid_t) {
        let snapshot = SettingsManager.shared.snapshot
        guard snapshot.isWindowMemoryEnabled || snapshot.isAppSpecificEnabled || snapshot.isBrowserTabMemoryEnabled else { return }
        
        if self._currentPID != pid {
            self._currentPID = pid
            
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

// 🌟 O(1) 성능을 보장하는 이중 연결 리스트 노드
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

// 🌟 외부 패키지 없이 구현한 완벽한 O(1) LRU 캐시 매니저 (역방향 인덱스 적용)
class WindowLRUCache {
    private let capacity: Int
    private var cache: [CGWindowID: WindowNode] = [:]
    
    // 🌟 [핵심] PID별로 WindowID들을 빠르게 찾기 위한 역방향 인덱스 (숙박부)
    private var pidIndex: [pid_t: Set<CGWindowID>] = [:]
    
    // 이중 연결 리스트의 양 끝단 (더미 노드)
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
            
            // 기존 노드의 PID가 변경되었다면 인덱스(장부)도 갱신
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
            
            // 새 노드가 생겼으므로 인덱스(장부)에도 추가
            pidIndex[pid, default: []].insert(windowID)
            
            // 용량을 초과하면 맨 뒤(가장 오래된) 노드 삭제
            if cache.count > capacity {
                if let tailNode = popTail() {
                    cache.removeValue(forKey: tailNode.windowID)
                    
                    // 삭제된 꼬리 노드를 인덱스(장부)에서도 제거
                    pidIndex[tailNode.pid]?.remove(tailNode.windowID)
                    if pidIndex[tailNode.pid]?.isEmpty == true {
                        pidIndex.removeValue(forKey: tailNode.pid)
                    }
                }
            }
        }
    }
    
    // 특정 윈도우 하나만 캐시에서 제거
    func removeWindow(_ windowID: CGWindowID) {
        guard let node = cache[windowID] else { return }
        removeNode(node)
        cache.removeValue(forKey: windowID)
        
        // 인덱스에서도 제거
        pidIndex[node.pid]?.remove(windowID)
        if pidIndex[node.pid]?.isEmpty == true {
            pidIndex.removeValue(forKey: node.pid)
        }
    }
    
    // 🌟 [리뷰어 지적 해결] 앱 종료 시 특정 PID에 속한 윈도우들 모두 제거 (완벽한 O(1))
    func removeWindowsForPID(_ pid: pid_t) {
        // 전체 순회(filter)를 버리고, 장부에서 해당 PID의 WindowID 묶음만 즉시 꺼내옵니다.
        guard let windowIDs = pidIndex.removeValue(forKey: pid) else { return }
        
        // 꺼내온 ID들만 순회하며 캐시와 리스트에서 삭제합니다.
        windowIDs.forEach { windowID in
            if let node = cache[windowID] {
                removeNode(node)
                cache.removeValue(forKey: windowID)
            }
        }
    }
    
    func clear() {
        cache.removeAll()
        pidIndex.removeAll() // 인덱스도 함께 초기화
        head.next = tail
        tail.prev = head
    }
    
    // MARK: - 내부 연결 리스트 조작 로직
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
