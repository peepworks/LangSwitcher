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

struct RulePriorityView: View {
    
    // 우선순위 데이터 모델
    struct PriorityItem: Identifiable {
        let id = UUID()
        let rank: String
        let title: String // 🌟 키가 아닌 이미 번역된 String을 담습니다.
        let desc: String  // 🌟 키가 아닌 이미 번역된 String을 담습니다.
        let iconName: String
        let iconColor: Color
    }
    
    // 🌟 배열 선언 시점에 String(localized:)를 직접 사용하여 Xcode가 인식할 수 있게 합니다.
    var priorities: [PriorityItem] {
        [
            PriorityItem(
                rank: "0",
                title: String(localized: "Secure Input & Pause"),
                desc: String(localized: "Password fields and manual pause completely block all LangSwitcher interventions."),
                iconName: "lock.shield.fill",
                iconColor: .red
            ),
            PriorityItem(
                rank: "1",
                title: String(localized: "Excluded Apps"),
                desc: String(localized: "No typing or switching rules are applied in user-excluded applications."),
                iconName: "nosign",
                iconColor: .orange
            ),
            PriorityItem(
                rank: "2",
                title: String(localized: "Website / Domain Rules"),
                desc: String(localized: "Specific website rules in browsers take precedence over app rules."),
                iconName: "globe",
                iconColor: .blue
            ),
            PriorityItem(
                rank: "3",
                title: String(localized: "Window & Tab Memory"),
                desc: String(localized: "Restores the specific language used in the current window or browser tab."),
                iconName: "macwindow",
                iconColor: .cyan
            ),
            PriorityItem(
                rank: "4",
                title: String(localized: "App-Specific Keyboards"),
                desc: String(localized: "Applies the default language set for the entire application."),
                iconName: "app.badge.fill",
                iconColor: .indigo
            ),
            PriorityItem(
                rank: "5",
                title: String(localized: "Text Expansion (Snippets)"),
                desc: String(localized: "Evaluated first during typing. Triggers are expanded immediately."),
                iconName: "text.badge.plus",
                iconColor: .green
            ),
            PriorityItem(
                rank: "6",
                title: String(localized: "Auto Typo Correction"),
                desc: String(localized: "Evaluated after text expansion for general typing correction."),
                iconName: "textformat.abc.dottedunderline",
                iconColor: .purple
            )
        ]
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            
            HStack {
                Image(systemName: "list.number")
                    .foregroundColor(.secondary)
                Text(String(localized: "LangSwitcher Rule Priority"))
                    .font(.headline)
            }
            .padding(.bottom, 5)
            
            Text(String(localized: "When multiple rules overlap, LangSwitcher strictly applies them in the following order to ensure a predictable and reliable experience."))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 10)
            
            // 우선순위 리스트 카드
            VStack(spacing: 0) {
                ForEach(Array(priorities.enumerated()), id: \.element.id) { index, item in
                    HStack(alignment: .top, spacing: 16) {
                        // 순위 숫자
                        Text(item.rank)
                            .font(.system(.subheadline, design: .monospaced).weight(.bold))
                            .foregroundColor(item.iconColor)
                            .frame(width: 24, height: 24)
                            .background(item.iconColor.opacity(0.15))
                            .clipShape(Circle())
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: item.iconName)
                                    .foregroundColor(item.iconColor)
                                // 🌟 이미 번역된 텍스트이므로 그냥 Text()에 넣습니다.
                                Text(item.title)
                                    .font(.system(.body, design: .default).weight(.semibold))
                            }
                            
                            // 🌟 이미 번역된 텍스트이므로 그냥 Text()에 넣습니다.
                            Text(item.desc)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    
                    if index < priorities.count - 1 {
                        Divider()
                            .padding(.leading, 56) // 아이콘 뒤부터 줄 긋기
                    }
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
        }
    }
}

// 🌟 사이드바에서 클릭했을 때 열릴 메인 화면
struct RulePrioritySettingsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(String(localized: "Rule Priority"))
                    .font(.title2.bold())
                
                // 기존에 만들었던 알맹이 뷰를 여기서 호출
                RulePriorityView()
            }
            .padding(30) // 화면 전체 여백
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}
