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

import SwiftUI

struct CustomShortcutsSettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared
    var hasIncomplete: Bool { settings.customShortcuts.contains { $0.displayString.isEmpty || $0.targetLanguage.isEmpty } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(String(localized: "Custom Shortcuts")).font(.title2.bold())
                Spacer()
                Button(action: { if !hasIncomplete { settings.customShortcuts.append(CustomShortcut(keyCode: 0, modifierFlags: 0, displayString: "", targetLanguage: "")) } }) {
                    Image(systemName: "plus.circle.fill").foregroundColor(hasIncomplete ? .secondary.opacity(0.5) : .blue)
                    Text(String(localized: "Add")).foregroundColor(hasIncomplete ? .secondary.opacity(0.5) : .primary)
                }.buttonStyle(.plain).disabled(hasIncomplete)
            }.padding(.horizontal, 30).padding(.top, 30).padding(.bottom, 15)
            
            ScrollView {
                VStack(spacing: 4) {
                    if settings.customShortcuts.isEmpty {
                        Text(String(localized: "No custom shortcuts added.")).font(.subheadline).foregroundColor(.secondary).padding(.vertical, 20)
                    }
                    
                    // 🌟 에러 해결: 꼬리표처럼 붙어있던 삭제 클로저 로직을 제거했습니다.
                    ForEach($settings.customShortcuts) { $shortcut in
                        CustomShortcutRow(shortcut: $shortcut)
                    }
                }.padding(15).frame(maxWidth: .infinity, alignment: .top)
            }
            .background(Color(NSColor.textBackgroundColor)).cornerRadius(8).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
            .padding(.horizontal, 30).padding(.bottom, 30)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
