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

@MainActor
final class DecisionTraceManager: ObservableObject {
    static let shared = DecisionTraceManager()
    
    // 🌟 UI에 즉각 표시될 로그 배열 (가장 최신이 0번 인덱스)
    @Published private(set) var recentTraces: [DecisionTrace] = []
    
    // 로깅 기능 On/Off (사용자가 설정에서 끄면 리소스 절약)
    @AppStorage("isTraceLoggingEnabled") var isTraceLoggingEnabled: Bool = true
    
    private let maxTraceCount = 200

    private init() {}

    /// 새로운 실행 결과를 기록합니다.
    func record(_ trace: DecisionTrace) {
        guard isTraceLoggingEnabled else { return }
        
        recentTraces.insert(trace, at: 0)
        
        // 제한 개수를 넘어가면 과거 기록 삭제 (메모리 보호)
        if recentTraces.count > maxTraceCount {
            recentTraces.removeLast(recentTraces.count - maxTraceCount)
        }
        
        #if DEBUG
        print("🔍 [Trace] \(trace.eventType.rawValue): \(trace.reasonMessage)")
        #endif
    }

    /// 모든 기록을 삭제합니다.
    func clear() {
        recentTraces.removeAll()
    }
}
