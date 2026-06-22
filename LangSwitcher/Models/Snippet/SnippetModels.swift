//
//  SnippetModels.swift
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

// MARK: - 🌟 스니펫 오토마타 파싱 토큰 열거형
enum SnippetToken: Equatable, Sendable {
    case text(String)               // 일반 정적 문자열
    case date(format: String)       // {{date:yyyy-MM-dd}}
    case time(format: String)       // {{time:HH:mm}}
    case clipboard                  // {{clipboard}}
    case selection                  // ${selection} 또는 ${selectedText}
    case finalCaret                 // ${0} 최종 정착 커서 위치
    case tabStop(index: Int, defaultValue: String?) // ${1:name} 또는 ${2} 형태
}

// MARK: - 🌟 최종 렌더링 오프셋 결과물
struct RenderedSnippet: Sendable {
    let text: String
    let tabStops: [SnippetTabStop]
    let finalCaretOffset: Int?
}

// MARK: - 🌟 개별 플레이스홀더 점프 보초 맵
struct SnippetTabStop: Identifiable, Hashable, Sendable {
    var id: UUID { rangeId }
    let rangeId: UUID
    let index: Int           // 1, 2, 3... (점프 순번 오름차순)
    let range: NSRange       // 최종 조립 문자열 내의 절대 위치 오프셋
    let defaultValue: String?
}

// MARK: - 🌟 [수복 핵심] 하드웨어 탭 점프 제어용 액티브 세션 상태 장부
@MainActor
final class ActiveSnippetSession {
    let id = UUID()
    let targetPID: pid_t             // 윈도우 문맥 붕괴 감지용 PID 보초
    let initialCaretLocation: NSRange // 삽입 시점 기저선
    var tabStops: [SnippetTabStop]    // 오름차순 정렬된 탭 스톱 가이드 배열
    var currentPointer: Int = 0      // 현재 머물러 있는 가이드 인덱스
    let createdAt = Date()
    
    // 🌟 [수복 완결] finalCaretOffset 데이터 파이프라인 결속 완료!
    var finalCaretOffset: Int? = nil
    
    init(targetPID: pid_t, initialCaretLocation: NSRange, tabStops: [SnippetTabStop]) {
        self.targetPID = targetPID
        self.initialCaretLocation = initialCaretLocation
        // 🌟 0번 인덱스(${0})는 배열에서 완전 독립시켰으므로 순수 오름차순 정렬만 집행합니다.
        self.tabStops = tabStops.sorted { $0.index < $1.index }
    }
    
    var currentTabStop: SnippetTabStop? {
        guard currentPointer < tabStops.count else { return nil }
        return tabStops[currentPointer]
    }
    
    func advance() -> SnippetTabStop? {
        currentPointer += 1
        return currentTabStop
    }
    
    var isExpired: Bool {
        return Date().timeIntervalSince(createdAt) > 15.0 // 보수적 15초 타임아웃 마감선
    }
}
