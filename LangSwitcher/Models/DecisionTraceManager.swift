//
//  DecisionTraceManager.swift
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

import Foundation
import Combine
import SwiftUI

// 🌟 [핵심] 클래스 전체를 메인 스레드에서 지켜주는 안전장치입니다. 반드시 살려두어야 합니다!
@MainActor
final class DecisionTraceManager: ObservableObject {
    static let shared = DecisionTraceManager()
    
    // 🌟 변수 중복을 제거하고 하나로 깔끔하게 정리했습니다.
    @Published private(set) var recentTraces: [DecisionTrace] = []
    
    @AppStorage("isTraceLoggingEnabled") var isTraceLoggingEnabled: Bool = true
    
    // 최대 로깅 개수 최적화 (O(n) 부하 최소화)
    private let maxTraceCount = 50

    private init() {}

    /// 새로운 실행 결과를 기록합니다.
    func record(_ trace: DecisionTrace) {
        guard isTraceLoggingEnabled else { return }
        
        // 🌟 클래스 위에 @MainActor가 있으므로, DispatchQueue로 감쌀 필요 없이
        // 여기서 곧바로 배열을 수정해도 SwiftUI가 100% 안전하게 UI를 업데이트합니다.
        self.recentTraces.insert(trace, at: 0)
                
        if self.recentTraces.count > self.maxTraceCount {
            self.recentTraces.removeLast()
        }
        
        dprint("🔍 [Trace] \(trace.eventType.rawValue): \(trace.reasonMessage)")
    }

    /// 모든 기록을 삭제합니다.
    func clear() {
        // 🌟 여기도 마찬가지로 DispatchQueue.main.async를 싹 지워버려도 됩니다.
        self.recentTraces.removeAll()
    }
}
