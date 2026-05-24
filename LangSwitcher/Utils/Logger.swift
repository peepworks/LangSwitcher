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

/// 디버그 모드에서만 출력되는 커스텀 프린트 함수
/// nonisolated 수식어를 통해 백그라운드 차트 연산이나 스레드 무관하게 어디서든 안전하게 호출됩니다.
nonisolated func dprint(_ items: Any..., file: String = #file, line: Int = #line) {
    #if DEBUG
    let fileName = (file as NSString).lastPathComponent
    let output = items.map { "\($0)" }.joined(separator: " ")
    print("🐞 [\(fileName):\(line)] \(output)")
    #endif
}
