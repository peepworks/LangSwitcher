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
    var hasIncomplete: Bool { settings.activeProfile.payload.customShortcuts.contains { $0.displayString.isEmpty || $0.targetLanguage.isEmpty } }

    private var payload: Binding<ProfileSettingsPayload> {
        Binding(
            get: { settings.activeProfile.payload },
            set: { settings.activeProfile.payload = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProfileHeaderView() // 🌟 헤더 추가
            
            HStack {
                Text(String(localized: "Custom Shortcuts")).font(.title2.bold())
                Spacer()
                Toggle("", isOn: $settings.isCustomShortcutsEnabled) // 🌟 전역 변수 유지
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
            }.padding(.horizontal, 30).padding(.top, 15).padding(.bottom, 10)

            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Text(String(localized: "Assign specific keyboard layouts to custom shortcut keys."))
                        .font(.subheadline).foregroundColor(.secondary)
                    Spacer()
                    Button(action: { if !hasIncomplete { settings.activeProfile.payload.customShortcuts.append(CustomShortcut(keyCode: 0, modifierFlags: 0, displayString: "", targetLanguage: "")) } }) {
                        Image(systemName: "plus.circle.fill").foregroundColor(hasIncomplete ? .secondary.opacity(0.5) : .blue)
                        Text(String(localized: "Add")).foregroundColor(hasIncomplete ? .secondary.opacity(0.5) : .primary)
                    }.buttonStyle(.plain).disabled(hasIncomplete)
                }

                ScrollView {
                    VStack(spacing: 4) {
                        if settings.activeProfile.payload.customShortcuts.isEmpty {
                            Text(String(localized: "No custom shortcuts added.")).font(.subheadline).foregroundColor(.secondary).padding(.vertical, 20)
                        }

                        ForEach(payload.customShortcuts) { $shortcut in
                            CustomShortcutRow(shortcut: $shortcut)
                        }
                    }.padding(15).frame(maxWidth: .infinity, alignment: .top)
                }
                .background(Color(NSColor.textBackgroundColor)).cornerRadius(8).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
            }
            .padding(.horizontal, 30).padding(.bottom, 30)
            .opacity(settings.isCustomShortcutsEnabled ? 1.0 : 0.5)
            .disabled(!settings.isCustomShortcutsEnabled)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

