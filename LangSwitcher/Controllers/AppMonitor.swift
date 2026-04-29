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

class AppMonitor {
    static let shared = AppMonitor()
    private var observer: NSObjectProtocol?
    
    // 🌟 EventMonitor 등 외부에서 안전하게 읽을 수 있도록 동시성 큐와 공유 상태 추가
    private let stateQueue = DispatchQueue(label: "com.peepworks.langswitcher.appmonitor", attributes: .concurrent)
    private var _activeAppBundleID: String = ""
    var activeAppBundleID: String {
        get { stateQueue.sync { _activeAppBundleID } }
        set { stateQueue.async(flags: .barrier) { self._activeAppBundleID = newValue } }
    }

    private init() {} // 싱글톤 보호

    func start() {
        if observer != nil { return }
        
        // 시작 시점의 현재 활성 앱 정보 초기화
        activeAppBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        
        // 🌟 시스템 전체에서 오직 AppMonitor만 이 알림을 단일 구독합니다.
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleID = app.bundleIdentifier else { return }

            // 공유 상태 업데이트
            AppMonitor.shared.activeAppBundleID = bundleID
            
            // 🌟 [핵심] 불안정한 0.1초 하드코딩 딜레이를 모두 삭제하고,
            // 가장 정확한 타이밍을 아는 WindowMonitor에게 윈도우 감지 및 언어 전환 역할을 전적으로 위임합니다.
            WindowMonitor.shared.observeApp(pid: app.processIdentifier)
        }
    }

    func stop() {
        if let obs = observer {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            observer = nil
        }
        activeAppBundleID = ""
    }
}
