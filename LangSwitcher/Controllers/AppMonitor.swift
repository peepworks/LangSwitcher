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
    
    // 🌟 클래스가 @MainActor이므로 복잡한 수동 DispatchQueue barrier를 완전히 도려냅니다.
    var activeAppBundleID: String = ""

    private init() {} // 싱글톤 보호

    func start() {
        if observer != nil { return }
        
        // 시동 시 메모리 자동 치유 타이머 가동
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

        // 🌟 [라이프사이클 완결 수복] 메인 모니터가 꺼질 때 상주형 메모리 타이머도 확실하게 소각 처리합니다.
        MemoryMonitor.shared.stopMonitoring()

        [observer, deactivateObserver].compactMap { $0 }.forEach {
            NSWorkspace.shared.notificationCenter.removeObserver($0)
        }
    
        observer = nil
        deactivateObserver = nil
        activeAppBundleID = ""
    }
}

@MainActor
class MemoryMonitor {
    static let shared = MemoryMonitor()
    private var timer: Timer?
    
    private let thresholdInBytes: UInt64 = 200_000_000
    
    private init() {} // 싱글톤 보호
    
    func startMonitoring() {
        // 혹시라도 잔존해 있을지 모르는 이전 세대 타이머를 런루프에서 확실하게 소각(invalidate)하고
        // 장부를 씻어낸 뒤 청정하게 새 타이머를 안착시킵니다.
        timer?.invalidate()
        timer = nil
        
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            // 🌟 [우주 방어 수복 포인트: 무격리 타이머 스코프 탈출]
            // 이 타이머는 메인 스레드 런루프에서 주행하므로, 컴파일러에게 런타임 보증서(assumeIsolated)를
            // 제출하여 메인 액터 메서드인 checkMemoryUsage()를 0ms 지연 없이 동기 직결 호출합니다.
            MainActor.assumeIsolated {
                self?.checkMemoryUsage()
            }
        }
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
