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
import UniformTypeIdentifiers

struct AppLaunchSettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared
    var hasIncomplete: Bool { settings.appLaunchShortcuts.contains { $0.displayString.isEmpty || $0.bundleIdentifier.isEmpty } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(String(localized: "App Launch Shortcuts")).font(.title2.bold())
                Spacer()
                Button(action: { if !hasIncomplete { settings.appLaunchShortcuts.append(AppLaunchShortcut(keyCode: 0, modifierFlags: 0, displayString: "", bundleIdentifier: "", appName: "")) } }) {
                    Image(systemName: "plus.circle.fill").foregroundColor(hasIncomplete ? .secondary.opacity(0.5) : .purple)
                    Text(String(localized: "Add")).foregroundColor(hasIncomplete ? .secondary.opacity(0.5) : .primary)
                }.buttonStyle(.plain).disabled(hasIncomplete)
            }.padding(.horizontal, 30).padding(.top, 30).padding(.bottom, 15)
            
            ScrollView {
                VStack(spacing: 4) {
                    if settings.appLaunchShortcuts.isEmpty {
                        Text(String(localized: "No app launch shortcuts added.")).font(.subheadline).foregroundColor(.secondary).padding(.vertical, 20)
                    }
                    // 🌟 에러 해결: AppLaunchShortcutRow가 내부에서 삭제를 처리하므로 뒤의 꼬리(클로저)를 제거했습니다.
                    ForEach($settings.appLaunchShortcuts) { $shortcut in
                        AppLaunchShortcutRow(shortcut: $shortcut)
                    }
                }.padding(15).frame(maxWidth: .infinity, alignment: .top)
            }
            .background(Color(NSColor.textBackgroundColor)).cornerRadius(8).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
            .padding(.horizontal, 30).padding(.bottom, 30)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
