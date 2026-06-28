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

// MARK: - 🌟 스니펫 오토마타 파싱 토큰 열거형 (문서 자동 조립기 스펙)
enum SnippetToken: Equatable, Sendable {
    case text(String)               // 일반 정적 문자열
    case date(format: String)       // {{date:yyyy-MM-dd}}
    case time(format: String)       // {{time:HH:mm}}
    case clipboard                  // {{clipboard}}
    case selection                  // ${selectedText} 문맥 흡수
    case finalCaret                 // {{cursor}} 최종 정착 위치
    case tabStop(index: Int, defaultValue: String?) // ${1:default} 포커스 점프
    
    // 📦 사용자 입력 필드군 (동일 name을 가지면 런타임에 동기화 재사용됩니다)
    case input(name: String, defaultValue: String?)                     // {{input:Name|defaultValue}}
    case textarea(name: String, defaultValue: String?)                  // {{textarea:Memo|defaultValue}}
    case select(name: String, options: [String], defaultValue: String?) // {{select:Signature[Opt1,Opt2]|default}}
    
    // 🌟 [보강] 선택 방식 다양화 및 동적 날짜 컴포넌트 자산
    case checkbox(name: String, content: String, isCheckedByDefault: Bool) // {{checkbox:IncludePS[P.S. 내용]|true}}
    case radio(name: String, options: [String], defaultValue: String?)     // {{radio:Urgency[High,Normal]|Normal}}
    case datePicker(name: String, format: String)                          // {{datepicker:Deadline|yyyy-MM-dd}}
    
    // ⚙️ 템플릿 제어군
    case optionalBlock(name: String, content: String)                   // {{optional:Disclaimer[Maturity text]}}
}

// MARK: - 🌟 최종 렌더링 결과물 장부
struct RenderedSnippet: Sendable {
    let text: String
    let tabStops: [SnippetTabStop]
    let finalCaretOffset: Int?
}

// MARK: - 🌟 개별 플레이스홀더 점프 보초 맵
struct SnippetTabStop: Identifiable, Hashable, Sendable {
    var id: UUID { rangeId }
    let rangeId: UUID
    let index: Int
    let range: NSRange
    let defaultValue: String?
}

// MARK: - 🌟 하드웨어 탭 점프 제어용 액티브 세션 상태 장부
@MainActor
final class ActiveSnippetSession {
    let id = UUID()
    let targetPID: pid_t
    let initialCaretLocation: NSRange
    var tabStops: [SnippetTabStop]
    var currentPointer: Int = 0
    let createdAt = Date()
    
    var finalCaretOffset: Int? = nil
    
    init(targetPID: pid_t, initialCaretLocation: NSRange, tabStops: [SnippetTabStop]) {
        self.targetPID = targetPID
        self.initialCaretLocation = initialCaretLocation
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
        return Date().timeIntervalSince(createdAt) > 15.0
    }
}
