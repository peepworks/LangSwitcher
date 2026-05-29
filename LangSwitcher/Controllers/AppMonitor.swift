//
//  AppMonitor.swift
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
import Foundation

@MainActor
class AppMonitor {
    static let shared = AppMonitor()
    
    private var observer: NSObjectProtocol?
    private var deactivateObserver: NSObjectProtocol?
        
    private var pendingObservationTask: Task<Void, Never>?
        
    // 🌟 [최적화] 클래스가 @MainActor이므로 복잡한 수동 DispatchQueue barrier를 완전히 도려냅니다.
    // 컴파일러가 메인 액터 격리를 통해 이 변수의 동시성 안전성을 빌드 타임에 100% 보장합니다.
    var activeAppBundleID: String = ""

    private init() {} // 싱글톤 보호

    func start() {
        if observer != nil { return }
        
        MemoryMonitor.shared.startMonitoring()
        
        activeAppBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        
        // ----------------------------------------------------
        // 1. 앱 활성화(Activate) 감지
        // ----------------------------------------------------
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            
            // 🌟 Swift 6 가드: 알림 콜백 내부를 메인 액터 지대로 안전하게 바인딩
            MainActor.assumeIsolated {
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      let bundleID = app.bundleIdentifier else { return }

                AppMonitor.shared.activeAppBundleID = bundleID
                
                let appDelay = SettingsManager.shared.snapshot.appDelays.first(where: { $0.bundleIdentifier == bundleID })?.delay ?? 0.3
                            
                AppMonitor.shared.pendingObservationTask?.cancel()
                
                AppMonitor.shared.pendingObservationTask = Task {
                    try? await Task.sleep(nanoseconds: UInt64(appDelay * 1_000_000_000))
                    
                    guard !Task.isCancelled else { return }
                    guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID else { return }
                    
                    // observeApp이 동기 함수이므로 앞에 무의미한 await를 제거합니다.
                    WindowMonitor.shared.observeApp(pid: app.processIdentifier)
                }
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
            
            // 🌟 Swift 6 가드: 비활성화 콜백 영역 동시성 검증 통과
            MainActor.assumeIsolated {
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      let bundleID = app.bundleIdentifier else { return }

                HUDManager.shared.hideCursorMiniHUD()

                let browserIDs = ["com.apple.Safari", "com.google.Chrome", "com.microsoft.edgemac", "com.brave.Browser"]
                
                if browserIDs.contains(bundleID) {
                    Task { @MainActor in
                        BrowserTabManager.shared.handleBrowserDeactivated()
                    }
                }
            }
        }
    }

    func stop() {
        pendingObservationTask?.cancel()
        pendingObservationTask = nil

        [observer, deactivateObserver].compactMap { $0 }.forEach {
            NSWorkspace.shared.notificationCenter.removeObserver($0)
        }
    
        observer = nil
        deactivateObserver = nil
        activeAppBundleID = ""
    }
}

// 🌟 [최적화] 타이머 제어, 로그 추가, 셀프 힐링 메서드 호출은 모두 메인 스레드 기반이므로
// 클래스 전체를 @MainActor로 격리하여 싱글톤 shared 참조 에러를 깔끔하게 해결합니다.
@MainActor
class MemoryMonitor {
    static let shared = MemoryMonitor()
    private var timer: Timer?
    
    private let thresholdInBytes: UInt64 = 200_000_000
    
    private init() {} // 싱글톤 보호
    
    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            // 🌟 타이머 블록이 깨어날 때 메인 액터 격리 상태임을 증명
            MainActor.assumeIsolated {
                self?.checkMemoryUsage()
            }
        }
    }

    // MARK: - 능동적 메모리 자기치유 커널 (즉시 동기 집행 사양)

    @MainActor
    private func checkMemoryUsage() {
        guard let currentMemory = reportMemoryUsage() else { return }
    
        if currentMemory > thresholdInBytes {
            let memoryInMB = currentMemory / 1024 / 1024
            dprint("🚨 [MemoryMonitor] 임계값 초과 감지: \(memoryInMB) MB. 즉각적인 자기치유(Self-Healing)를 집행합니다.")
    
            let log = ActionLog(
                timestamp: Date(),
                targetApp: "LangSwitcher System",
                appliedRule: "Memory Alert",
                finalInputSource: "\(memoryInMB) MB",
                result: .failure,
                failureReason: .unknown
            )
            SettingsManager.shared.addLog(log)
    
            // ✅ 중첩 비동기 껍데기 완전 철거 완료! 지연 없이 즉시 동기 실행됩니다.
            BrowserTabManager.shared.clearMemory()
            DecisionTraceManager.shared.clear()
            SettingsManager.shared.clearLogs()
    
            dprint("🧹 [MemoryMonitor] 메인 액터 동기 결속 영역 내에서 모든 캐시 퍼지가 지연 없이 즉시 완료되었습니다.")
        }
    }

    // 시스템 내장 구조체를 읽는 가벼운 함수이므로 메인 스레드에서 동기식 실행해도 안전합니다.
    private func reportMemoryUsage() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size) / 4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            return info.phys_footprint
        }
        return nil
    }
}
