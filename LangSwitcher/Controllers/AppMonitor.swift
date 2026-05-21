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
        // 🌟 2. [핵심 2] 앱 비활성화(Deactivate) 감지 추가!
        // ----------------------------------------------------
        deactivateObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleID = app.bundleIdentifier else { return }

            // 🌟 브라우저에서 다른 앱으로 빠져나가는 순간인지 확인합니다.
            let browserIDs = ["com.apple.Safari", "com.google.Chrome", "com.microsoft.edgemac", "com.brave.Browser"]
            
            if browserIDs.contains(bundleID) {
                Task { @MainActor in
                    // 🌟 브라우저 매니저에게 "현재 탭 정보를 저장하고 머릿속을 비워!" 라고 명령합니다.
                    // 이렇게 해야 다음에 다시 브라우저로 돌아왔을 때 규칙을 100% 재검사합니다.
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
