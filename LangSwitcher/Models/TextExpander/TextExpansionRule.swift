//
//  TextExpansionRule.swift
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

struct TextExpansionRule: Codable, Identifiable, Equatable {
    var id = UUID()
    var trigger: String         // 예: ";em"
    var replacement: String     // 예: "my.email@gmail.com" 또는 ";date"
    var isEnabled: Bool = true
    
    // 특정 앱에서만 동작하거나 제외할 수 있는 옵션 (심층 리서치 반영)
    var targetAppBundleIDs: [String] = []
    var isExcludeMode: Bool = true // true면 targetApps 제외, false면 targetApps에서만 동작
}
