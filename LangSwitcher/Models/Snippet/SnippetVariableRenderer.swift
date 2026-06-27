//
//  SnippetVariableRenderer.swift
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

@MainActor
struct SnippetVariableRenderer {
    private static var formatterCache: [String: DateFormatter] = [:]

    static func render(tokens: [SnippetToken], selectedText: String?) -> RenderedSnippet {
        var buffer = ""
        var tabStops: [SnippetTabStop] = []
        var finalCaret: Int? = nil
        let currentDate = Date()
        
        for token in tokens {
            switch token {
            case .text(let plain):
                buffer += plain
                
            case .date(let format), .time(let format):
                let formatter = getCachedFormatter(for: format)
                buffer += formatter.string(from: currentDate)
                
            case .clipboard:
                if let clip = ClipboardProvider.getString() {
                    buffer += clip
                }
                
            case .selection:
                if let selectionText = selectedText {
                    buffer += selectionText
                }
                
            case .finalCaret:
                let offset = buffer.count
                finalCaret = offset
                
            case .tabStop(let index, let defaultValue):
                let startOffset = buffer.count
                let stringToInsert = defaultValue ?? ""
                buffer += stringToInsert
                let endOffset = buffer.count
                
                let targetRange = NSRange(location: startOffset, length: endOffset - startOffset)
                tabStops.append(SnippetTabStop(rangeId: UUID(), index: index, range: targetRange, defaultValue: defaultValue))
                
            // 🌟 [신설 컴포넌트 프리뷰 가동선] 렌더링 안정성 확보 및 런타임 롤백 대비
            case .input(let name, let defaultValue):
                buffer += defaultValue ?? "[\(name)]"
            case .textarea(let name, let defaultValue):
                buffer += defaultValue ?? "[\(name)]"
            case .select(let name, let options):
                buffer += options.first ?? "[\(name)]"
            case .optionalBlock(_, let content):
                buffer += content
            }
        }
        
        tabStops.sort { $0.index < $1.index }
        
        return RenderedSnippet(text: buffer, tabStops: tabStops, finalCaretOffset: finalCaret)
    }

    private static func getCachedFormatter(for format: String) -> DateFormatter {
        if let cached = formatterCache[format] { return cached }
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatterCache[format] = formatter
        return formatter
    }
}
