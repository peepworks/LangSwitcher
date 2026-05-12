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

struct TextExpansionSettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    @State private var selectedRuleForEdit: TextExpansionRule?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 마스터 스위치 영역
            HStack {
                Text(String(localized: "Text Expansion")).font(.title2.bold())
                Spacer()
                Toggle("", isOn: $settings.isTextExpansionEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
            }
            .padding(.horizontal, 30).padding(.top, 30).padding(.bottom, 10)
            
            // 설정 내용 영역
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Text(String(localized: "Type short triggers to quickly insert long phrases or dynamic values.\nExample 1: ;em → my.email@gmail.com\nExample 2: ;date → {{date:yyyy-MM-dd}}\nExample 3: ;clip → {{clipboard}}"))
                        .font(.subheadline).foregroundColor(.secondary)
                        .font(.subheadline).foregroundColor(.secondary)
                    
                    Spacer()
                    
                    // 상단에는 "추가" 버튼만 남김
                    Button(action: {
                        selectedRuleForEdit = TextExpansionRule(trigger: ";", replacement: "")
                    }) {
                        Image(systemName: "plus.circle.fill").foregroundColor(.blue)
                        Text(String(localized: "Add")).foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                }
                
                // 둥근 테두리 리스트 상자
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
                
                // 🌟 리스트 상자 우측 하단 백업/복원 버튼 영역
                HStack(spacing: 10) {
                    Spacer()
                    
                    // 🌟 기본값 복원 버튼 추가
                    Button(action: {
                        let defaultRules = [
                            TextExpansionRule(trigger: ";date", replacement: "{{date:yyyy-MM-dd}}", isEnabled: true),
                            TextExpansionRule(trigger: ";time", replacement: "{{date:HH:mm}}", isEnabled: true),
                            TextExpansionRule(trigger: ";now", replacement: "{{date:yyyy-MM-dd HH:mm}}", isEnabled: true),
                            TextExpansionRule(trigger: ";day", replacement: "{{date:EEEE}}", isEnabled: true),
                            TextExpansionRule(trigger: ";clip", replacement: "{{clipboard}}", isEnabled: true)
                        ]
                        
                        // 기존 목록에 없는 트리거만 안전하게 추가 (병합)
                        for rule in defaultRules {
                            if !settings.textExpansionRules.contains(where: { $0.trigger == rule.trigger }) {
                                settings.textExpansionRules.append(rule)
                            }
                        }
                    }) {
                        Image(systemName: "arrow.counterclockwise")
                        Text(String(localized: "Restore Defaults"))
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.secondary)

                    Button(action: importRules) {
                        Image(systemName: "square.and.arrow.down")
                        Text(String(localized: "Import..."))
                    }
                    .buttonStyle(.borderless) // 테두리 없이 깔끔하게 텍스트+아이콘만 표시
                    .foregroundColor(.secondary)
                    
                    Button(action: exportRules) {
                        Image(systemName: "square.and.arrow.up")
                        Text(String(localized: "Export..."))
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.secondary)
                }
                .padding(.top, 4) // 리스트 상자와의 약간의 간격
                
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
    
    // MARK: - Import / Export File Panel Actions
    
    private func exportRules() {
        // 🌟 [보안 추가] 내보내기 전 사용자에게 평문 저장에 대한 경고 표시
        let alert = NSAlert()
        alert.messageText = String(localized: "Security Warning")
        alert.informativeText = String(localized: "Exported backup files contain your text expansion rules in plain text. Please keep this file safe and do not share it if it contains sensitive information like passwords or API keys.")
        alert.addButton(withTitle: String(localized: "Continue Export"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        
        // 사용자가 'Continue Export'를 누르지 않으면 취소
        if alert.runModal() != .alertFirstButtonReturn {
            return
        }
        
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.json]
        panel.nameFieldStringValue = "LangSwitcher_Snippets.json"
        panel.title = String(localized: "Export Text Expansion Rules")
        
        if let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            panel.directoryURL = documentsURL
        }
        
        if panel.runModal() == .OK, let url = panel.url {
            settings.exportTextExpansionRules(to: url) { success, error in
                if success {
                    print("Export successful!")
                } else if let error = error {
                    print("Export failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func importRules() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = String(localized: "Import Text Expansion Rules")
        
        if let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            panel.directoryURL = documentsURL
        }
        
        if panel.runModal() == .OK, let url = panel.url {
            settings.importTextExpansionRules(from: url) { success, error in
                if success {
                    print("Import successful!")
                } else if let error = error {
                    print("Import failed: \(error.localizedDescription)")
                }
            }
        }
    }
}

struct TextExpansionEditView: View {
    @Environment(\.dismiss) var dismiss
    @State var rule: TextExpansionRule
    var onComplete: (TextExpansionRule?, EditAction) -> Void
    @FocusState private var isTriggerFocused: Bool
    @ObservedObject var settings = SettingsManager.shared
    
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
                // TextExpansionEditView 구조체 내부의 Save 버튼 부분 수정

                Button(String(localized: "Save")) {
                    // 🌟 [안정성] 중복 트리거 검사
                    let isDuplicate = settings.textExpansionRules.contains {
                        $0.trigger == rule.trigger && $0.id != rule.id
                    }
                    
                    if isDuplicate {
                        let alert = NSAlert()
                        alert.messageText = String(localized: "Duplicate Trigger")
                        alert.informativeText = String(localized: "This trigger is already in use. Please use a unique trigger.")
                        alert.addButton(withTitle: String(localized: "OK"))
                        alert.runModal()
                    } else {
                        onComplete(rule, .save)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                // 기존 비활성화 조건에 중복 검사 추가 가능
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
