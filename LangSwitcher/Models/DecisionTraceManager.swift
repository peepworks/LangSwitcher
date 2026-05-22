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
    
    // 🌟 [수정 포인트] 리뷰어의 권장 사항에 따라 최대 로깅 개수를 200에서 50으로 줄입니다.
    // 배열 크기가 작아지면서 insert(at: 0) 시 발생하는 메모리 이동(O(n)) 부하가 사실상 0이 됩니다.
    private let maxTraceCount = 50

    private init() {}

    /// 새로운 실행 결과를 기록합니다.
    func record(_ trace: DecisionTrace) {
        guard isTraceLoggingEnabled else { return }
        
        // 🌟 외부에서 어떤 스레드로 호출하든 100% 안전하게 메인 스레드에서만 배열을 수정하도록 보장합니다.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.recentTraces.insert(trace, at: 0)
            
            // 제한 개수를 넘어가면 과거 기록 삭제 (메모리 보호 및 SwiftUI 렌더링 최적화)
            if self.recentTraces.count > self.maxTraceCount {
                // 한 번에 하나씩만 초과하므로 removeLast()로 단일 삭제하는 것이 더 빠르고 깔끔합니다.
                self.recentTraces.removeLast()
            }
        }
        
        dprint("🔍 [Trace] \(trace.eventType.rawValue): \(trace.reasonMessage)")
    }

    /// 모든 기록을 삭제합니다.
    func clear() {
        // 배열을 비우는 작업도 UI 업데이트를 유발하므로 메인 스레드에서 실행합니다.
        DispatchQueue.main.async { [weak self] in
            self?.recentTraces.removeAll()
        }
    }
}
