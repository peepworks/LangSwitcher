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

struct DomainRuleSettingsView: View {
    @ObservedObject var settings = SettingsManager.shared

    @State private var showingEditSheet = false
    @State private var editingRule: DomainRule? = nil

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
                Text(String(localized: "Website Keyboard Auto-Switching"))
                    .font(.title2.bold())
                Spacer()
                Toggle("", isOn: payload.isBrowserDomainModeEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
            }
            .padding(.horizontal, 30).padding(.top, 15).padding(.bottom, 10)

            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Text(String(localized: "Set the input source to automatically change when visiting specific domains."))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(action: {
                        editingRule = nil
                        showingEditSheet = true
                    }) {
                        Image(systemName: "plus.circle.fill").foregroundColor(.blue)
                        Text(String(localized: "Add")).foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                }

                ScrollView {
                    VStack(spacing: 0) {
                        if settings.activeProfile.payload.domainRules.isEmpty {
                            Text(String(localized: "No domain rules added."))
                                .font(.subheadline).foregroundColor(.secondary).padding(.vertical, 40)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(settings.activeProfile.payload.domainRules) { rule in
                                    DomainRuleRowView(
                                        rule: rule,
                                        onUpdate: { updatedRule in saveRule(updatedRule) },
                                        onDelete: { deleteRule(id: rule.id) },
                                        onEdit: { openEditSheet(for: rule) }
                                    )

                                    if rule.id != settings.activeProfile.payload.domainRules.last?.id {
                                        Divider().padding(.horizontal, 15)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 30)
            .opacity(settings.activeProfile.payload.isBrowserDomainModeEnabled ? 1.0 : 0.5)
            .disabled(!settings.activeProfile.payload.isBrowserDomainModeEnabled)

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(isPresented: $showingEditSheet) {
            DomainRuleEditSheet(ruleToEdit: editingRule) { newRule in
                saveRule(newRule)
            }
        }
    }

    private func openEditSheet(for rule: DomainRule) {
        editingRule = rule
        showingEditSheet = true
    }

    private func saveRule(_ rule: DomainRule) {
        if let index = settings.activeProfile.payload.domainRules.firstIndex(where: { $0.id == rule.id }) {
            settings.activeProfile.payload.domainRules[index] = rule
        } else {
            settings.activeProfile.payload.domainRules.append(rule)
        }
    }

    private func deleteRule(id: UUID) {
        settings.activeProfile.payload.domainRules.removeAll { $0.id == id }
    }
}

// MARK: - Row View (리스트 내 개별 항목)
struct DomainRuleRowView: View {
    let rule: DomainRule
    let onUpdate: (DomainRule) -> Void
    let onDelete: () -> Void
    let onEdit: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { val in
                    var newRule = rule; newRule.isEnabled = val; onUpdate(newRule)
                }
            ))
            .labelsHidden()
            
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.domain)
                    .font(.system(.body, design: .monospaced))
                
                if rule.includeSubdomains {
                    Text(String(localized: "Includes subdomains"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .onTapGesture(count: 2) { onEdit() }
            
            Spacer()
            
            Picker("", selection: Binding(
                get: { rule.targetInputSourceID },
                set: { val in
                    var newRule = rule; newRule.targetInputSourceID = val; onUpdate(newRule)
                }
            )) {
                ForEach(InputSourceManager.shared.availableKeyboards, id: \.id) { keyboard in
                    Text(keyboard.name).tag(keyboard.id)
                }
            }
            .frame(width: 140)
            .labelsHidden()
            
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

// MARK: - Edit Sheet (팝업)
// MARK: - Edit Sheet (팝업)
struct DomainRuleEditSheet: View {
    @Environment(\.dismiss) var dismiss
    
    let ruleToEdit: DomainRule?
    let onSave: (DomainRule) -> Void
    
    @State private var domain: String = ""
    @State private var includeSubdomains: Bool = true
    @State private var selectedLanguageID: String = ""
    
    // 라벨 너비 고정 (좌측 정렬선 완벽 일치용)
    private let labelWidth: CGFloat = 140
    
    // 🌟 [추가] 유효성 검사 프로퍼티: 도메인에 경로(/)가 포함되어 있는지 실시간 확인
    private var hasInvalidPath: Bool {
        return domain.contains("/")
    }
    
    var body: some View {
        VStack(spacing: 0) {
            
            Text(ruleToEdit == nil ? String(localized: "Add New Domain Rule") : String(localized: "Edit Domain Rule"))
                .font(.headline)
                .padding(.top, 20)
                .padding(.bottom, 10)
            
            Form {
                Section {
                    // 1. 도메인 입력 영역
                    HStack(alignment: .top, spacing: 12) {
                        Text(String(localized: "Domain:"))
                            .frame(width: labelWidth, alignment: .trailing)
                            .padding(.top, 5) // 텍스트 필드 높이와 라벨 텍스트 높이 보정
                        
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("", text: $domain)
                                .textFieldStyle(.roundedBorder)
                                .disableAutocorrection(true)
                                .labelsHidden()
                                .frame(maxWidth: .infinity)
                            
                            // 🌟 [핵심 개선] 입력값에 따라 안내 문구 또는 에러 문구 동적 표시
                            if hasInvalidPath {
                                Text(String(localized: "Paths (/) are not allowed. Please enter only the root domain."))
                                    .font(.caption)
                                    .foregroundColor(.red) // 에러는 빨간색으로 시선 집중!
                            } else {
                                Text(String(localized: "e.g., github.com"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.vertical, 4)
                    
                    // 2. 서브도메인 토글 영역
                    HStack(alignment: .center, spacing: 12) {
                        Text(String(localized: "Include Subdomains:"))
                            .frame(width: labelWidth, alignment: .trailing)
                        
                        Toggle("", isOn: $includeSubdomains)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .labelsHidden()
                        
                        Spacer()
                    }
                    .padding(.bottom, 4)
                    
                } header: {
                    Text(String(localized: "Matching Condition"))
                }
                
                Section {
                    // 3. 키보드 동작(입력 소스) 영역
                    HStack(alignment: .center, spacing: 12) {
                        Text(String(localized: "Input Source:"))
                            .frame(width: labelWidth, alignment: .trailing)
                        
                        Picker("", selection: $selectedLanguageID) {
                            ForEach(InputSourceManager.shared.availableKeyboards, id: \.id) { keyboard in
                                Text(keyboard.name).tag(keyboard.id)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 4)
                    
                } header: {
                    Text(String(localized: "Keyboard Action"))
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            
            // 하단 버튼부
            HStack {
                Spacer()
                
                Button(String(localized: "Cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Button(ruleToEdit == nil ? String(localized: "Add") : String(localized: "Save")) {
                    let cleanDomain = DomainRuleManager.normalize(urlOrDomain: domain) ?? domain
                    let newRule = DomainRule(
                        id: ruleToEdit?.id ?? UUID(),
                        browserBundleID: nil, // 전체 브라우저 적용으로 수정됨
                        domain: cleanDomain,
                        includeSubdomains: includeSubdomains,
                        targetInputSourceID: selectedLanguageID,
                        isEnabled: ruleToEdit?.isEnabled ?? true
                    )
                    onSave(newRule)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                // 🌟 [핵심 개선] 슬래시(/)가 포함되어 있으면 강제로 저장(Save) 버튼을 비활성화
                .disabled(domain.trimmingCharacters(in: .whitespaces).isEmpty || selectedLanguageID.isEmpty || hasInvalidPath)
            }
            .padding(20)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 500, height: 380)
        .onAppear {
            if let rule = ruleToEdit {
                domain = rule.domain
                includeSubdomains = rule.includeSubdomains
                selectedLanguageID = rule.targetInputSourceID
            } else if let firstLang = InputSourceManager.shared.availableKeyboards.first {
                selectedLanguageID = firstLang.id
            }
        }
    }
}
