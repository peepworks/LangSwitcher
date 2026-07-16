//
//  WorkspaceAppTracker.swift
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

import AppKit
import Foundation

/// 🌟 [수복] macOS 시스템 콜 오버헤드를 O(1) 캐시로 격파하는 고속 추적기
public final class WorkspaceAppTracker: Sendable {
    public static let shared = WorkspaceAppTracker()
    
    // 스레드 안전한 조회를 위한 락 잠금 장치
    private let lock = NSLock()
    
    private var _activeBundleID: String = ""
    private var _activeAppName: String = ""
    
    /// 실시간 캐싱된 활성 앱의 Bundle Identifier
    public var activeBundleID: String {
        lock.lock()
        defer { lock.unlock() }
        return _activeBundleID
    }
    
    /// 실시간 캐싱된 활성 앱의 이름
    public var activeAppName: String {
        lock.lock()
        defer { lock.unlock() }
        return _activeAppName
    }
    
    private init() {
        // 최초 앱 기동 시점의 활성 앱 선제 캐싱
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            _activeBundleID = frontApp.bundleIdentifier ?? ""
            _activeAppName = frontApp.localizedName ?? ""
        }
        
        // 🌟 macOS 워크스페이스 알림 구독 수립
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(workspaceDidActivateApplication(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }
    
    @objc private func workspaceDidActivateApplication(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        
        lock.lock()
        _activeBundleID = app.bundleIdentifier ?? ""
        _activeAppName = app.localizedName ?? ""
        lock.unlock()
        
        #if DEBUG
        dprint("📱 [WorkspaceTracker] Active App Changed -> Name: \(_activeAppName), ID: \(_activeBundleID)")
        #endif
    }
}
