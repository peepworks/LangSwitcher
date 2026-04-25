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
            
            // 🌟 [추가된 코드] 활성 앱의 PID를 넘겨서 윈도우 감지기 연결!
            WindowMonitor.shared.observeApp(pid: app.processIdentifier)

            let settings = SettingsManager.shared
            
            // 🌟 이 코드를 추가하여 기능이 꺼져있으면 여기서 즉시 연산을 중단!
            guard settings.isAppSpecificEnabled else { return }
            
            // 사용자가 등록해둔 앱 목록에 이 앱이 있는지 검사합니다.
            if let customApp = settings.customApps.first(where: { $0.bundleIdentifier == bundleID }) {
                // 지정된 언어가 있다면 해당 언어로 전환합니다.
                if !customApp.targetLanguage.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        InputSourceManager.shared.switchLanguage(to: customApp.targetLanguage)
                    }
                }
            }
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
