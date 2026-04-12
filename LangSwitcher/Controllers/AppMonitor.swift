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

    func start() {
        if observer != nil { return }
        
        // 🌟 macOS에서 앱이 활성화(최상단으로 올라옴)될 때마다 알림을 받습니다.
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            // 활성화된 앱의 정보와 Bundle ID(예: com.google.Chrome)를 가져옵니다.
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleID = app.bundleIdentifier else { return }

            let settings = SettingsManager.shared
            
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
    }
}
