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

// MARK: - 🌟 스니펫 오토마타 파싱 토큰 열거형 (문서 조립 도구형 확장 버전)
enum SnippetToken: Equatable, Sendable {
    case text(String)               // 일반 정적 문자열
    case date(format: String)       // {{date:yyyy-MM-dd}}
    case time(format: String)       // {{time:HH:mm}}
    case clipboard                  // {{clipboard}}
    case selection                  // ${selection} 또는 ${selectedText}
    case finalCaret                 // {{cursor}} 또는 ${0} 최종 정착 위치
    case tabStop(index: Int, defaultValue: String?) // ${1:default} 형태
    
    // 🌟 [신설] 동적 사용자 입력 및 템플릿 제어 요소 자산
    case input(name: String, defaultValue: String?)                     // {{input:Name|defaultValue}}
    case textarea(name: String, defaultValue: String?)                  // {{textarea:Memo|defaultValue}}
    case select(name: String, options: [String])                        // {{select:Team[Option1,Option2]}}
    case optionalBlock(name: String, content: String)                   // {{optional:PS[Included Content]}}
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
