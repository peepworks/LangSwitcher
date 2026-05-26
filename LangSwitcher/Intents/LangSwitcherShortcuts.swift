//
//  LangSwitcherShortcuts.swift
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

import AppIntents

struct LangSwitcherShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        
        // 🌟 SetInputSourceIntent는 필수 파라미터가 필요하므로 자동 추천 목록에서 제외합니다.
        
        AppShortcut(
            intent: ToggleTypoCorrectionIntent(),
            phrases: [
                "Toggle Typo Correction in \(.applicationName)"
            ],
            shortTitle: "Toggle Typo Correction",
            systemImageName: "text.cursor"
        )
        
        AppShortcut(
            intent: ToggleBrowserTabMemoryIntent(),
            phrases: [
                "Toggle Browser Tab Memory in \(.applicationName)"
            ],
            shortTitle: "Toggle Tab Memory",
            systemImageName: "safari"
        )
        
        AppShortcut(
            intent: ToggleExceptionAppsModeIntent(),
            phrases: [
                "Toggle Exception Apps in \(.applicationName)"
            ],
            shortTitle: "Toggle Exception Apps",
            systemImageName: "nosign.app.fill"
        )
    }
}
