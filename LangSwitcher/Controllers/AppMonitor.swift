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

// ====================================================================
// 메인 액터(@MainActor) 요새 외부에 독립적인 Sendable 구조체를 신설합니다.
// 이제 EventMonitor의 백그라운드 CGEvent 콜백 스레드에서도 아무런 런타임 크래시 위협이나
// await 지연 없이 0ms 만에 즉각적으로 현재 앱 ID를 조회할 수 있습니다.
// ====================================================================
struct ActiveAppTracker: Sendable {
    private final class Storage: @unchecked Sendable {
        let lock = NSLock()
        var bundleID: String = ""
    }
    private let storage = Storage()
    
    func set(_ id: String) {
        storage.lock.lock(); defer { storage.lock.unlock() }
        storage.bundleID = id
    }
    
    func get() -> String {
        storage.lock.lock(); defer { storage.lock.unlock() }
        return storage.bundleID
    }
}

// 앱 전역에서 락 없이 자유롭게 찌를 수 있는 글로벌 장부 인스턴스 개설
let globalActiveAppTracker = ActiveAppTracker()

// ====================================================================

@MainActor
class AppMonitor {
    static let shared = AppMonitor()
    
    private var observer: NSObjectProtocol?
    private var deactivateObserver: NSObjectProtocol?
    
    private var pendingObservationTask: Task<Void, Never>?

    private init() {} // 싱글톤 보호

    func start() {
        if observer != nil { return }
        
        // 시동 시 메모리 자동 치유 타이머 가동
        MemoryMonitor.shared.startMonitoring()
        
        let initialBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        globalActiveAppTracker.set(initialBundleID)
        
        // ----------------------------------------------------
        // 1. 앱 활성화(Activate) 감지
        // ----------------------------------------------------
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            
            MainActor.assumeIsolated {
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      let bundleID = app.bundleIdentifier else { return }

                globalActiveAppTracker.set(bundleID)
                
                let appDelay = SettingsManager.shared.snapshot.appDelays.first(where: { $0.bundleIdentifier == bundleID })?.delay ?? 0.3
                            
                AppMonitor.shared.pendingObservationTask?.cancel()
                
                AppMonitor.shared.pendingObservationTask = Task {
                    try? await Task.sleep(for: .seconds(appDelay))
                    
                    guard !Task.isCancelled else { return }
                    guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID else { return }
                    
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

            MainActor.assumeIsolated {
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      let bundleID = app.bundleIdentifier else { return }

                HUDManager.shared.hideCursorMiniHUD()

                let registeredBrowsers = BrowserTabManager.shared.supportedBrowserBundleIDs

                if registeredBrowsers.contains(bundleID) {
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

        MemoryMonitor.shared.stopMonitoring()

        [observer, deactivateObserver].compactMap { $0 }.forEach {
            NSWorkspace.shared.notificationCenter.removeObserver($0)
        }
    
        observer = nil
        deactivateObserver = nil
        
        globalActiveAppTracker.set("")
    }
}

@MainActor
class MemoryMonitor {
    static let shared = MemoryMonitor()
    private var timer: Timer?
    
    private let thresholdInBytes: UInt64 = 200_000_000
    
    // ─── 🌟 [수복: 자가 치유 주기적 관측성 영구 장부 필드] ───
    private var memoryRecoveryCount: Int {
        get { UserDefaults.standard.integer(forKey: "memoryRecoveryCount") }
        set { UserDefaults.standard.set(newValue, forKey: "memoryRecoveryCount") }
    }
    
    private var lastMemoryRecoveryAt: Double {
        get { UserDefaults.standard.double(forKey: "lastMemoryRecoveryAt") }
        set { UserDefaults.standard.set(newValue, forKey: "lastMemoryRecoveryAt") }
    }
    // ────────────────────────────────────────────────────────
    
    private init() {} // 싱글톤 보호
    
    func startMonitoring() {
        timer?.invalidate()
        timer = nil
        
        let newTimer = Timer(timeInterval: 300, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.checkMemoryUsage()
            }
        }
        
        RunLoop.main.add(newTimer, forMode: .common)
        self.timer = newTimer

        dprint("🧠 [MemoryMonitor] 무중단 .common 모드 메모리 감시 타이머 안착 완료.")
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        dprint("🧠 [MemoryMonitor] 메모리 자동 치유 타이머 자원을 클린하게 해제 정산했습니다.")
    }

    // MARK: - 능동적 메모리 자기치유 커널 (즉시 동기 집행 및 로그 관측 사양)

    private func checkMemoryUsage() {
        guard let currentMemory = Self.getCurrentPhysicalFootprint() else { return }
    
        if currentMemory > thresholdInBytes {
            let memoryInMB = currentMemory / 1024 / 1024
            dprint("🚨 [MemoryMonitor] 임계값 초과 감지: \(memoryInMB) MB. 즉각적인 자기치유(Self-Healing)를 집행합니다.")
            
            // 🌟 [수복 핵심] 메모리 퍼지 시점에 관측성 카운터 가산 및 타임스탬프 영구 박제
            self.memoryRecoveryCount += 1
            self.lastMemoryRecoveryAt = Date().timeIntervalSince1970
            
            #if DEBUG
            dprint("📊 [Observability] 누적 자가 치유 횟수: \(self.memoryRecoveryCount)회, 최근 청소 시각: \(Date())")
            #endif
    
            let log = ActionLog(
                timestamp: Date(),
                targetApp: "LangSwitcher System",
                appliedRule: "Memory Alert",
                finalInputSource: "Purged at \(memoryInMB) MB (Total: \(self.memoryRecoveryCount)연속)",
                result: .success,
                failureReason: .none
            )
            SettingsManager.shared.addLog(log)
    
            // 실제 메모리 소각 집행 구역
            BrowserTabManager.shared.clearMemory()
            DecisionTraceManager.shared.clear()
            SettingsManager.shared.clearLogs()
            
            // 필요 시 창 메모리 캐시도 함께 동기 정산 연동 가능
            WindowMonitor.shared.clearMemory()
    
            dprint("🧹 [MemoryMonitor] 메인 액터 동기 결속 영역 내에서 모든 캐시 퍼지가 지연 없이 즉시 완료되었습니다.")
        }
    }

    public static func getCurrentPhysicalFootprint() -> UInt64? {
        var info = task_vm_info()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info>.size / MemoryLayout<integer_t>.size)
        
        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        
        guard kerr == KERN_SUCCESS else {
            return nil
        }
        
        return info.phys_footprint
    }
}
