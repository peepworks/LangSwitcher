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
// 🌟 [4번 리뷰 수복 포인트 1: 활성 앱 글로벌 무격리 추적자 (Nonisolated Tracker)]
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
    
    // 🌟 기존의 var activeAppBundleID: String = "" 변수를 완전히 소각했습니다!

    private init() {} // 싱글톤 보호

    func start() {
        if observer != nil { return }
        
        // 시동 시 메모리 자동 치유 타이머 가동
        MemoryMonitor.shared.startMonitoring()
        
        // 🌟 [수복] 메인 액터 변수 대신 글로벌 무격리 트래커에 값을 직결 락온합니다.
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

                // 🌟 [수복] 앱이 전환되는 즉시 글로벌 장부에 최신 ID를 갱신합니다.
                globalActiveAppTracker.set(bundleID)
                
                let appDelay = SettingsManager.shared.snapshot.appDelays.first(where: { $0.bundleIdentifier == bundleID })?.delay ?? 0.3
                            
                AppMonitor.shared.pendingObservationTask?.cancel()
                
                AppMonitor.shared.pendingObservationTask = Task {
                    try? await Task.sleep(nanoseconds: UInt64(appDelay * 1_000_000_000))
                    
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
        
        // 🌟 [수복] 모니터 정지 시 글로벌 트래커의 장부도 청정하게 초기화합니다.
        globalActiveAppTracker.set("")
    }
}

@MainActor
class MemoryMonitor {
    static let shared = MemoryMonitor()
    private var timer: Timer?
    
    private let thresholdInBytes: UInt64 = 200_000_000
    
    private init() {} // 싱글톤 보호
    
    func startMonitoring() {
        // 혹시라도 잔존해 있을지 모르는 이전 세대 타이머를 런루프에서 확실하게 소각하고 초기화합니다.
        timer?.invalidate()
        timer = nil
        
        // 🌟 [7번 리뷰 수복 포인트: RunLoop Mode 프리패스 연동]
        // scheduledTimer 대신 생성자 메서드로 타이머 인스턴스를 날것으로 분리 생성합니다.
        let newTimer = Timer(timeInterval: 300, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.checkMemoryUsage()
            }
        }
        
        // 🌟 메인 런루프의 .common 마스터 모드에 등록합니다.
        // 이로써 사용자가 창을 드래그하거나 모달 패널을 띄우는 특수 스레드 루프 상황에서도
        // 타이머가 얼어붙지 않고 5분 정시 가동성을 완벽하게 확약받습니다.
        RunLoop.main.add(newTimer, forMode: .common)
        self.timer = newTimer

        dprint("🧠 [MemoryMonitor] 무중단 .common 모드 메모리 감시 타이머 안착 완료.")
    }

    // 🌟 [추가 수복 포트] 메인 감시망 중단 시 커널 런루프에서 타이머를 안전하게 철거시키는 오퍼레이션
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        dprint("🧠 [MemoryMonitor] 메모리 자동 치유 타이머 자원을 클린하게 해제 정산했습니다.")
    }

    // MARK: - 능동적 메모리 자기치유 커널 (즉시 동기 집행 사양)

    private func checkMemoryUsage() {
        // 통합 조율된 청정 SSOT 계통 함수를 다이렉트로 라우팅합니다.
        guard let currentMemory = Self.getCurrentPhysicalFootprint() else { return }
    
        if currentMemory > thresholdInBytes {
            let memoryInMB = currentMemory / 1024 / 1024
            dprint("🚨 [MemoryMonitor] 임계값 초과 감지: \(memoryInMB) MB. 즉각적인 자기치유(Self-Healing)를 집행합니다.")
    
            let log = ActionLog(
                timestamp: Date(),
                targetApp: "LangSwitcher System",
                appliedRule: "Memory Alert",
                finalInputSource: "\(memoryInMB) MB",
                result: .success, // 시스템 치유 동작의 성공 기록이므로 정합성 수정
                failureReason: .none
            )
            SettingsManager.shared.addLog(log)
    
            BrowserTabManager.shared.clearMemory()
            DecisionTraceManager.shared.clear()
            SettingsManager.shared.clearLogs()
    
            dprint("🧹 [MemoryMonitor] 메인 액터 동기 결속 영역 내에서 모든 캐시 퍼지가 지연 없이 즉시 완료되었습니다.")
        }
    }

    // 전형적인 하드코딩 4바이트 정산 오류를 스위프트 표준 타입 메모리 레이아웃으로 완벽히 개조하고,
    // 외부 UI 뷰(AboutSettingsView)에서도 공용 참조할 수 있도록 public 전역 계산 창구로 격상 노출합니다.
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
        
        return info.phys_footprint // 가상 주소가 완전히 배제된 macOS 공인 순수 물리 RSS 반환
    }
}
