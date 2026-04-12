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
import Combine

class AccessibilityManager: ObservableObject {
    static let shared = AccessibilityManager()
    
    @Published var isTrusted: Bool = false
    private var timer: Timer?

    init() {
        self.isTrusted = AXIsProcessTrusted()
    }

    @discardableResult
    func checkPermission(prompt: Bool = false) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt]
        let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        DispatchQueue.main.async {
            if self.isTrusted != trusted {
                self.isTrusted = trusted
            }
            
            if trusted {
                EventMonitor.shared.start()
                AppMonitor.shared.start() // 🌟 앱 활성화 감지 모니터 시작!
                self.stopMonitoring()
            } else {
                self.startMonitoring()
            }
        }
        return trusted
    }
    
    private func startMonitoring() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkPermission(prompt: false)
        }
    }
    
    private func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
}
