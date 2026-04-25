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

struct AdvancedSettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                Text(String(localized: "Advanced Features")).font(.title2.bold())

                // 1. 하드웨어 키보드 제어 (Hyper Key)
                GroupBox {
                    VStack(alignment: .leading, spacing: 0) {
                        SettingToggleRow(
                            title: String(localized: "Caps Lock to Hyper Key & Input Source Switcher"),
                            isOn: $settings.isHyperKeyEnabled
                        )
                        Text(String(localized: "Mapped instantly in the background. Short press toggles input source, long press acts as Hyper Key."))
                            .font(.caption).foregroundColor(.secondary).lineSpacing(2)
                            .padding(.horizontal, 15).padding(.bottom, 12).padding(.top, -2)
                    }
                } label: {
                    Text(String(localized: "Hardware Keyboard")).font(.headline)
                }

                // 2. 창(Window) 단위 메모리 관리
                GroupBox {
                    VStack(alignment: .leading, spacing: 0) {
                        SettingToggleRow(
                            title: String(localized: "Remember input source per window"),
                            isOn: $settings.isWindowMemoryEnabled
                        )
                        Text(String(localized: "Remembers the language state for each individual window and auto-restores it when focused."))
                            .font(.caption).foregroundColor(.secondary).lineSpacing(2)
                            .padding(.horizontal, 15).padding(.bottom, 12).padding(.top, -2)

                        Divider().padding(.horizontal, 15)

                        SettingToggleRow(
                            title: String(localized: "Clear window records when app exits"),
                            isOn: $settings.isWindowMemoryCleanupEnabled
                        )
                        Text(String(localized: "Automatically clears stored window language data when the application is closed to optimize memory."))
                            .font(.caption).foregroundColor(.secondary).lineSpacing(2)
                            .padding(.horizontal, 15).padding(.bottom, 12).padding(.top, -2)
                    }
                } label: {
                    Text(String(localized: "Window Focus Management")).font(.headline)
                }
                
                // 3. 🌟 iCloud 동기화 섹션
                /*
                GroupBox {
                    VStack(alignment: .leading, spacing: 0) {
                        SettingToggleRow(
                            title: String(localized: "Sync settings via iCloud"),
                            isOn: $settings.isCloudSyncEnabled
                        )
                        Text(String(localized: "Automatically synchronizes your shortcuts, excluded apps, and preferences across all your Mac devices using iCloud."))
                            .font(.caption).foregroundColor(.secondary).lineSpacing(2)
                            .padding(.horizontal, 15).padding(.bottom, 12).padding(.top, -2)
                        
                        // 동기화가 켜져 있을 때만 '지금 동기화' 버튼 표시
                        if settings.isCloudSyncEnabled {
                            HStack {
                                Spacer()
                                Button(String(localized: "Sync Now")) {
                                    SettingsManager.shared.syncToCloud()
                                }
                                .buttonStyle(.link)
                                .font(.caption)
                                .padding(.trailing, 15)
                                .padding(.bottom, 10)
                            }
                        }
                    }
                } label: {
                    Text(String(localized: "Cloud Sync")).font(.headline)
                }
                 */
                
                Spacer()
            }
            .padding()
        }
    }
}
