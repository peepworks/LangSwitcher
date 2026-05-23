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
import Foundation

class AppMonitor {
    static let shared = AppMonitor()
    
    private var observer: NSObjectProtocol?
    // 🌟 [핵심 1] 앱이 백그라운드로 밀려나는 것을 감지할 새로운 옵저버
    private var deactivateObserver: NSObjectProtocol?
    
    private let stateQueue = DispatchQueue(label: "com.peepworks.langswitcher.appmonitor", attributes: .concurrent)
    private var _activeAppBundleID: String = ""
    var activeAppBundleID: String {
        get { stateQueue.sync { _activeAppBundleID } }
        set { stateQueue.async(flags: .barrier) { self._activeAppBundleID = newValue } }
    }

    private init() {} // 싱글톤 보호

    func start() {
        if observer != nil { return }
        
        // 🌟 앱 모니터가 시작될 때 메모리 모니터도 함께 백그라운드에서 돌기 시작하도록 호출해 줍니다.
        MemoryMonitor.shared.startMonitoring()
        
        activeAppBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        
        // ----------------------------------------------------
        // 1. 앱 활성화(Activate) 감지 - (기존 코드 유지)
        // ----------------------------------------------------
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleID = app.bundleIdentifier else { return }

            AppMonitor.shared.activeAppBundleID = bundleID
            
            let appDelay = SettingsManager.shared.snapshot.appDelays.first(where: { $0.bundleIdentifier == bundleID })?.delay ?? 0.3
            
            Task {
                try? await Task.sleep(nanoseconds: UInt64(appDelay * 1_000_000_000))
                guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID else { return }
                
                // Swift 6: await 키워드를 통한 비동기 위임
                await WindowMonitor.shared.observeApp(pid: app.processIdentifier)
            }
        }
        
        // ----------------------------------------------------
        // 2. 앱 비활성화(Deactivate) 감지
        // ----------------------------------------------------
        deactivateObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleID = app.bundleIdentifier else { return }

            // 🌟 [추가됨] 앱이 비활성화되는 순간 미니 플래그를 즉시 숨깁니다.
            HUDManager.shared.hideCursorMiniHUD()

            // 브라우저에서 다른 앱으로 빠져나가는 순간인지 확인
            let browserIDs = ["com.apple.Safari", "com.google.Chrome", "com.microsoft.edgemac", "com.brave.Browser"]
            
            if browserIDs.contains(bundleID) {
                Task { @MainActor in
                    BrowserTabManager.shared.handleBrowserDeactivated()
                }
            }
        }
    }

    func stop() {
        // 🌟 [개선됨] 모든 옵저버를 배열로 묶어 nil을 안전하게 제거한 뒤, 한 번에 해제합니다.
        [observer, deactivateObserver].compactMap { $0 }.forEach {
            NSWorkspace.shared.notificationCenter.removeObserver($0)
        }
    
        // 메모리에서 완전히 비워줍니다.
        observer = nil
        deactivateObserver = nil
        activeAppBundleID = ""
    }
}

class MemoryMonitor {
    static let shared = MemoryMonitor()
    private var timer: Timer?
    
    // 🌟 1. 리뷰어의 권장대로 임계값을 200MB로 대폭 낮춥니다.
    private let thresholdInBytes: UInt64 = 200_000_000
    
    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.checkMemoryUsage()
        }
    }
    
    private func checkMemoryUsage() {
        guard let currentMemory = reportMemoryUsage() else { return }
        
        if currentMemory > thresholdInBytes {
            let memoryInMB = currentMemory / 1024 / 1024
            dprint("🚨 [경고] 메모리 초과: \(memoryInMB) MB. 능동적 해제(Self-Healing)를 시작합니다.")
            
            let log = ActionLog(
                timestamp: Date(),
                targetApp: "LangSwitcher System",
                appliedRule: "Memory Alert",
                finalInputSource: "\(memoryInMB) MB",
                result: .failure,
                failureReason: .unknown
            )
            SettingsManager.shared.addLog(log)
            
            // 🌟 2. [핵심] 경고에 그치지 않고, 메인 스레드에서 즉시 메모리를 청소합니다.
            DispatchQueue.main.async {
                // (1) 브라우저 탭 메모리 등 무거운 캐시 초기화
                BrowserTabManager.shared.clearMemory()
                
                // (2) 디버그 트레이스나 잉여 데이터가 있다면 초기화
                // DecisionTraceManager.shared.clear() // 해당 클래스가 존재할 경우 주석 해제
                
                // (3) SettingsManager 내부의 로그 배열이 너무 크다면 강제 다이어트
                // SettingsManager.shared.recentLogs.removeAll(keepingCapacity: false)
            }
        }
    }

    // 현재 앱의 실제 메모리 풋프린트(활성 상태 보기와 동일한 수치)를 가져오는 함수
    private func reportMemoryUsage() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size) / 4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            // 🌟 resident_size 대신 phys_footprint를 사용합니다.
            return info.phys_footprint
        }
        return nil
    }
}
