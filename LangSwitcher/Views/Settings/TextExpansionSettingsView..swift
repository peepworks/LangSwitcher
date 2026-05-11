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

struct TextExpansionSettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    @State private var selectedRuleForEdit: TextExpansionRule?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 🌟 1. 마스터 스위치 영역 (기존 스타일 준수)
            HStack {
                Text(String(localized: "Text Expansion")).font(.title2.bold())
                Spacer()
                Toggle("", isOn: $settings.isTextExpansionEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
            }
            .padding(.horizontal, 30).padding(.top, 30).padding(.bottom, 10)
            
            // 🌟 2. 설정 내용 영역
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Text(String(localized: "Type short triggers to quickly insert long phrases or dynamic values.\nExample: Type ';em' and press Space → 'my.email@gmail.com'"))
                        .font(.subheadline).foregroundColor(.secondary)
                    
                    Spacer()
                    
                    // 추가 버튼
                    Button(action: {
                        selectedRuleForEdit = TextExpansionRule(trigger: ";", replacement: "")
                    }) {
                        Image(systemName: "plus.circle.fill").foregroundColor(.blue)
                        Text(String(localized: "Add")).foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                }
                
                // 🌟 3. 둥근 테두리 리스트 상자
                ScrollView {
                    VStack(spacing: 0) {
                        // 헤더 영역
                        HStack {
                            Text(String(localized: "Active")).frame(width: 45, alignment: .center)
                            Text(String(localized: "Trigger")).frame(width: 80, alignment: .leading)
                            Text(String(localized: "Replacement Text")).frame(maxWidth: .infinity, alignment: .leading)
                            Text(String(localized: "Manage")).frame(width: 90, alignment: .center)
                        }
                        .font(.caption).foregroundColor(.secondary).padding(.bottom, 8)
                        
                        Divider()
                        
                        if settings.textExpansionRules.isEmpty {
                            Text(String(localized: "No text expansion rules added."))
                                .font(.subheadline).foregroundColor(.secondary).padding(.vertical, 30)
                        }
                        
                        // 규칙 리스트
                        ForEach(settings.textExpansionRules) { rule in
                            VStack(spacing: 0) {
                                HStack(spacing: 0) {
                                    Toggle("", isOn: binding(for: rule).isEnabled)
                                        .labelsHidden().frame(width: 45, alignment: .center)
                                    
                                    Text(rule.trigger)
                                        .font(.system(.body, design: .monospaced))
                                        .frame(width: 80, alignment: .leading)
                                    
                                    Text(rule.replacement)
                                        .lineLimit(1).truncationMode(.tail)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .foregroundColor(.secondary)
                                    
                                    // 🌟 4. 관리 영역: 편집 버튼 + 휴지통 아이콘 (일관된 디자인)
                                    HStack(spacing: 12) {
                                        Button(String(localized: "Edit")) {
                                            selectedRuleForEdit = rule
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                        
                                        Button(action: {
                                            withAnimation {
                                                settings.textExpansionRules.removeAll { $0.id == rule.id }
                                            }
                                        }) {
                                            Image(systemName: "trash")
                                                .foregroundColor(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .frame(width: 90, alignment: .center)
                                }
                                .padding(.vertical, 8)
                                
                                if rule.id != settings.textExpansionRules.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                    .padding(15)
                }
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
            }
            .padding(.horizontal, 30).padding(.bottom, 30)
            .opacity(settings.isTextExpansionEnabled ? 1.0 : 0.5)
            .disabled(!settings.isTextExpansionEnabled)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(item: $selectedRuleForEdit) { rule in
            TextExpansionEditView(rule: rule) { resultRule, action in
                if action == .save, let updated = resultRule {
                    if let index = settings.textExpansionRules.firstIndex(where: { $0.id == updated.id }) {
                        settings.textExpansionRules[index] = updated
                    } else {
                        settings.textExpansionRules.append(updated)
                    }
                }
                selectedRuleForEdit = nil
            }
        }
    }
    
    private func binding(for rule: TextExpansionRule) -> Binding<TextExpansionRule> {
        guard let index = settings.textExpansionRules.firstIndex(where: { $0.id == rule.id }) else {
            return .constant(rule)
        }
        return $settings.textExpansionRules[index]
    }
}

// 🌟 편집 뷰 (하단 삭제 버튼 제거 버전)
struct TextExpansionEditView: View {
    @Environment(\.dismiss) var dismiss
    @State var rule: TextExpansionRule
    var onComplete: (TextExpansionRule?, EditAction) -> Void
    @FocusState private var isTriggerFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(rule.trigger == ";" ? String(localized: "New Text Expansion Rule") : String(localized: "Edit Rule"))
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "Trigger")).font(.caption).foregroundColor(.secondary)
                TextField(String(localized: "Trigger (e.g., ;em)"), text: $rule.trigger)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .focused($isTriggerFocused)
                
                Text(String(localized: "Replacement Text")).font(.caption).foregroundColor(.secondary)
                TextEditor(text: $rule.replacement)
                    .font(.body)
                    .frame(height: 120)
                    .padding(4)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(5)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
            }
            .frame(width: 360)
            
            HStack {
                Spacer()
                Button(String(localized: "Cancel")) {
                    onComplete(nil, .cancel)
                    dismiss()
                }
                Button(String(localized: "Save")) {
                    onComplete(rule, .save)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(rule.trigger.isEmpty || rule.trigger == ";" || rule.replacement.isEmpty)
            }
        }
        .padding(25)
        .onAppear { isTriggerFocused = true }
    }
}
enum EditAction {
    case save, delete, cancel
}
