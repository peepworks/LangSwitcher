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

import Foundation

// 🌟 사용자가 설정 화면에서 추가할 개별 도메인 규칙 모델
struct DomainRule: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var browserBundleID: String?     // nil이면 모든 브라우저에 적용
    var domain: String               // 정규화된 도메인 (예: "github.com")
    var includeSubdomains: Bool      // 서브도메인(예: gist.github.com) 포함 여부
    var targetInputSourceID: String  // 목표 언어 ID
    var isEnabled: Bool              // 규칙 활성화 여부
}
