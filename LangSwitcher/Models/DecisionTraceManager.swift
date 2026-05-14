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

import Foundation
import Combine
import SwiftUI

// 💡 클래스 전체에 걸려있던 @MainActor를 제거하고, 필요한 곳에만 DispatchQueue를 적용합니다.
final class DecisionTraceManager: ObservableObject {
    static let shared = DecisionTraceManager()
    
    @Published private(set) var recentTraces: [DecisionTrace] = []
    
    @AppStorage("isTraceLoggingEnabled") var isTraceLoggingEnabled: Bool = true
    
    private let maxTraceCount = 200

    private init() {}

    /// 새로운 실행 결과를 기록합니다.
    func record(_ trace: DecisionTrace) {
        guard isTraceLoggingEnabled else { return }
        
        // 🌟 [핵심 수정] 외부에서 어떤 스레드로 호출하든 100% 안전하게 메인 스레드에서만 배열을 수정하도록 보장합니다.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.recentTraces.insert(trace, at: 0)
            
            // 제한 개수를 넘어가면 과거 기록 삭제 (메모리 보호)
            if self.recentTraces.count > self.maxTraceCount {
                self.recentTraces.removeLast(self.recentTraces.count - self.maxTraceCount)
            }
        }
        
        #if DEBUG
        print("🔍 [Trace] \(trace.eventType.rawValue): \(trace.reasonMessage)")
        #endif
    }

    /// 모든 기록을 삭제합니다.
    func clear() {
        // 배열을 비우는 작업도 UI 업데이트를 유발하므로 메인 스레드에서 실행합니다.
        DispatchQueue.main.async { [weak self] in
            self?.recentTraces.removeAll()
        }
    }
}
