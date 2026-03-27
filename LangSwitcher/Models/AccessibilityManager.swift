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
    private var timer: Timer? // 상태를 주기적으로 감지할 타이머

    init() {
        self.isTrusted = AXIsProcessTrusted()
    }

    @discardableResult
    func checkPermission(prompt: Bool = false) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt]
        let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        DispatchQueue.main.async {
            // UI 업데이트
            if self.isTrusted != trusted {
                self.isTrusted = trusted
            }
            
            if trusted {
                // ✅ 권한이 확인되는 순간 즉시 키보드 이벤트 모니터 시작!
                EventMonitor.shared.start()
                self.stopMonitoring() // 감지 타이머 종료
            } else {
                // ❌ 권한이 없으면 사용자가 켤 때까지 1초마다 백그라운드에서 감지
                self.startMonitoring()
            }
        }
        return trusted
    }
    
    private func startMonitoring() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            // 시스템 창을 띄우지 않고 조용히 권한만 확인
            self?.checkPermission(prompt: false)
        }
    }
    
    private func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
}
