//
//  TextExpansionSettingsView.swift
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

import SwiftUI
import UniformTypeIdentifiers

struct TextExpansionSettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    @State private var selectedRuleForEdit: TextExpansionRule? = nil

    private var payload: Binding<ProfileSettingsPayload> {
        Binding(
            get: { settings.activeProfile.payload },
            set: { newValue in
                settings.activeProfile.payload = newValue
                guard !settings.isBatchUpdating else { return }
                settings.updateSnapshot()
                settings.scheduleSave()
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProfileHeaderView()
            
            HStack {
                Text(String(localized: "Text Expansion")).font(.title2.bold())
                Spacer()
                Toggle("", isOn: payload.isTextExpansionEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
            }
            .padding(.horizontal, 30).padding(.top, 15).padding(.bottom, 10)

            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Text(String(localized: "Type short triggers to quickly insert long phrases or dynamic values.\nExample 1: ;em → my.email@gmail.com\nExample 2: ;date → {{date:yyyy-MM-dd}}\nExample 3: ;clip → {{clipboard}}"))
                        .font(.subheadline).foregroundColor(.secondary)

                    Spacer()

                    Button(action: {
                        selectedRuleForEdit = TextExpansionRule(trigger: ";", replacement: "")
                    }) {
                        Image(systemName: "plus.circle.fill").foregroundColor(.blue)
                        Text(String(localized: "Add")).foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                }

                ScrollView {
                    VStack(spacing: 0) {
                        HStack {
                            Text(String(localized: "Active")).frame(width: 45, alignment: .center)
                            Text(String(localized: "Trigger")).frame(width: 80, alignment: .leading)
                            Text(String(localized: "Replacement Text")).frame(maxWidth: .infinity, alignment: .leading)
                            Text(String(localized: "Manage")).frame(width: 90, alignment: .center)
                        }
                        .font(.caption).foregroundColor(.secondary).padding(.bottom, 8)

                        Divider()

                        if settings.activeProfile.payload.textExpansionRules.isEmpty {
                            Text(String(localized: "No text expansion rules added."))
                                .font(.subheadline).foregroundColor(.secondary).padding(.vertical, 30)
                        }

                        ForEach(settings.activeProfile.payload.textExpansionRules) { rule in
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
                                                settings.activeProfile.payload.textExpansionRules.removeAll { $0.id == rule.id }
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

                                if rule.id != settings.activeProfile.payload.textExpansionRules.last?.id {
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

                HStack(spacing: 10) {
                    Spacer()

                    Button(action: {
                        let defaultRules = [
                            TextExpansionRule(trigger: ";date", replacement: "{{date:yyyy-MM-dd}}", isEnabled: true),
                            TextExpansionRule(trigger: ";time", replacement: "{{time:HH:mm}}", isEnabled: true),
                            TextExpansionRule(trigger: ";clip", replacement: "{{clipboard}}", isEnabled: true),
                            TextExpansionRule(trigger: ";info", replacement: "{{date:yyyy-MM-dd}} {{time:HH:mm}} | {{clipboard}}", isEnabled: true),
                            TextExpansionRule(trigger: ";hello", replacement: "Hello {{cursor}} World", isEnabled: true)
                        ]
                        for rule in defaultRules {
                            if !settings.activeProfile.payload.textExpansionRules.contains(where: { $0.trigger == rule.trigger }) {
                                settings.activeProfile.payload.textExpansionRules.append(rule)
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
                    .buttonStyle(.borderless)
                    .foregroundColor(.secondary)

                    Button(action: exportRules) {
                        Image(systemName: "square.and.arrow.up")
                        Text(String(localized: "Export..."))
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.secondary)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 30).padding(.bottom, 30)
            .opacity(settings.activeProfile.payload.isTextExpansionEnabled ? 1.0 : 0.5)
            .disabled(!settings.activeProfile.payload.isTextExpansionEnabled)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(item: $selectedRuleForEdit) { rule in
            TextExpansionEditView(rule: rule) { resultRule, action in
                if action == .save, let updated = resultRule {
                    if let index = settings.activeProfile.payload.textExpansionRules.firstIndex(where: { $0.id == updated.id }) {
                        settings.activeProfile.payload.textExpansionRules[index] = updated
                    } else {
                        settings.activeProfile.payload.textExpansionRules.append(updated)
                    }
                }
                selectedRuleForEdit = nil
            }
        }
    }

    private func binding(for rule: TextExpansionRule) -> Binding<TextExpansionRule> {
        guard let index = settings.activeProfile.payload.textExpansionRules.firstIndex(where: { $0.id == rule.id }) else {
            return .constant(rule)
        }
        return payload.textExpansionRules[index]
    }

    private func exportRules() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Security Warning")
        alert.informativeText = String(localized: "Exported backup files contain your text expansion rules in plain text. Please keep this file safe and do not share it if it contains sensitive information like passwords or API keys.")
        alert.addButton(withTitle: String(localized: "Continue Export"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        if alert.runModal() != .alertFirstButtonReturn { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.json]
        panel.nameFieldStringValue = "LangSwitcher_Snippets.json"
        panel.title = String(localized: "Export Text Expansion Rules")
        if let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            panel.directoryURL = documentsURL
        }
        if panel.runModal() == .OK, let url = panel.url {
            settings.exportTextExpansionRules(to: url) { _, _ in }
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
            settings.importTextExpansionRules(from: url) { _, _ in }
        }
    }
}

struct IdentifiedToken: Identifiable {
    let id = UUID()
    let rawText: String
    let token: SnippetToken
    
    var displayName: String {
        switch token {
        case .input(let name, _): return "Input: \(name)"
        case .textarea(let name, _): return "Textarea: \(name)"
        case .select(let name, _, _): return "Dropdown: \(name)"
        case .checkbox(let name, _, _): return "Checkbox: \(name)"
        case .radio(let name, _, _): return "Radio: \(name)"
        case .datePicker(let name, _): return "DatePicker: \(name)"
        case .optionalBlock(let name, _): return "Optional: \(name)"
        case .date(let fmt): return "Date (\(fmt))"
        case .time(let fmt): return "Time (\(fmt))"
        case .clipboard: return "Clipboard"
        case .selection: return "SelectedText"
        case .finalCaret: return "Cursor Position"
        case .tabStop(let idx, _): return "TabStop [\(idx)]"
        default: return rawText
        }
    }
}

struct TextExpansionEditView: View {
    @Environment(\.dismiss) var dismiss
    @State var rule: TextExpansionRule
    var onComplete: (TextExpansionRule?, EditAction) -> Void
    @FocusState private var isTriggerFocused: Bool
    @ObservedObject var settings = SettingsManager.shared

    @State private var selectedTokenForPropertyEdit: IdentifiedToken? = nil

    private var reactiveInspectorTokens: [IdentifiedToken] {
        let regex = #/(?:\{\{(date|time|clipboard|cursor|input|textarea|select|optional|checkbox|radio|datepicker)(?::([^\[\}|]+))?(?:\[([^\]]+)\])?(?:\|([^}]+))?\}\})|(?:\$\{(selection|selectedText|0|([1-9]\d*)(?::([^\}]+))?)\})/#
        let matches = rule.replacement.matches(of: regex)
        var list: [IdentifiedToken] = []
        let tokens = SnippetTemplateParser.parse(template: rule.replacement)
        
        var tokenIdx = 0
        for match in matches {
            let rawStr = String(rule.replacement[match.range])
            while tokenIdx < tokens.count {
                let t = tokens[tokenIdx]
                tokenIdx += 1
                if case .text = t { continue }
                list.append(IdentifiedToken(rawText: rawStr, token: t))
                break
            }
        }
        return list
    }

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

                HStack {
                    Text(String(localized: "Replacement Text"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Menu {
                        Menu(String(localized: "System Values")) {
                            Menu(String(localized: "Date")) {
                                Button(action: { insertSyntax("{{date:yyyy-MM-dd}}") }) { Label(String(localized: "Full Date (yyyy-MM-dd)"), systemImage: "calendar") }
                                Button(action: { insertSyntax("{{date:yyyy}}") }) { Label(String(localized: "Year (yyyy)"), systemImage: "calendar.badge.clock") }
                                Button(action: { insertSyntax("{{date:MM}}") }) { Label(String(localized: "Month (MM)"), systemImage: "calendar.badge.plus") }
                                Button(action: { insertSyntax("{{date:dd}}") }) { Label(String(localized: "Day (dd)"), systemImage: "calendar.badge.checkmark") }
                            }
                            Menu(String(localized: "Time")) {
                                Button(action: { insertSyntax("{{time:HH:mm}}") }) { Label(String(localized: "Hour:Minute (HH:mm)"), systemImage: "clock") }
                                Button(action: { insertSyntax("{{time:HH:mm:ss}}") }) { Label(String(localized: "Hour:Minute:Second (HH:mm:ss)"), systemImage: "clock.fill") }
                            }
                            Button(action: { insertSyntax("{{clipboard}}") }) { Label(String(localized: "Clipboard Contents"), systemImage: "doc.on.clipboard") }
                            Button(action: { insertSyntax("${selectedText}") }) { Label(String(localized: "Selected Text"), systemImage: "doc.text.magnifyingglass") }
                        }
                        
                        Menu(String(localized: "Input Fields")) {
                            Button(action: { insertSyntax("{{input:FieldName|defaultValue}}") }) { Label(String(localized: "Single-line Field"), systemImage: "rectangle.and.pencil.and.ellipsis") }
                            Button(action: { insertSyntax("{{textarea:FieldName|defaultValue}}") }) { Label(String(localized: "Multi-line Field"), systemImage: "text.justify.left") }
                            Button(action: { insertSyntax("{{select:FieldName[Option1,Option2]|Option1}}") }) { Label(String(localized: "Dropdown Menu"), systemImage: "list.bullet.rectangle") }
                            Divider()
                            Button(action: { insertSyntax("{{checkbox:FieldName[Included Content]|true}}") }) { Label(String(localized: "Checkbox Option"), systemImage: "checkmark.square") }
                            Button(action: { insertSyntax("{{radio:FieldName[Opt1,Opt2]|Opt1}}") }) { Label(String(localized: "Radio Buttons"), systemImage: "largecircle.fill.and.checkmark") }
                            Button(action: { insertSyntax("{{datepicker:FieldName|yyyy-MM-dd}}") }) { Label(String(localized: "Date Picker Field"), systemImage: "calendar.badge.plus") }
                        }
                        
                        Menu(String(localized: "Template Control")) {
                            Button(action: { insertSyntax("{{optional:BlockName[Content Text]}}") }) { Label(String(localized: "In/Out Block (Optional)"), systemImage: "uiwindow.split.2x1") }
                            Button(action: { insertSyntax("{{cursor}}") }) { Label(String(localized: "Next Input Position"), systemImage: "character.cursor.line") }
                            Button(action: { insertSyntax("${1:default}") }) { Label(String(localized: "Jump Placeholder"), systemImage: "character.textbox") }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle")
                            Text(String(localized: "Insert Element"))
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 130)
                }
                .padding(.top, 5)

                TextEditor(text: $rule.replacement)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 120)
                    .padding(4)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(5)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.2), lineWidth: 1))

                // ------------------------------------------------------
                // 🌟 [수복 정산 완료] Reactive Token Inspector Panel Layout
                // ------------------------------------------------------
                if !reactiveInspectorTokens.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "Click elements below to edit properties:"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        // maxWidth 및축 정렬 정밀 결속으로 우측 잘림 버그 영구 박멸
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(reactiveInspectorTokens) { identifiedToken in
                                    Button(action: {
                                        selectedTokenForPropertyEdit = identifiedToken
                                    }) {
                                        HStack(spacing: 4) {
                                            Text(identifiedToken.displayName)
                                            Image(systemName: "slider.horizontal.3")
                                                .font(.system(size: 9))
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.blue.opacity(0.15))
                                        .foregroundColor(.blue)
                                        .cornerRadius(4)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.trailing, 10) // 우측 패딩 마진 추가로 스크롤 호흡 확보
                        }
                        .frame(maxWidth: .infinity, alignment: .leading) // 🌟 스크롤 뷰가 가로 전체를 채우도록 강제 결속
                    }
                    .padding(.top, 4)
                    .popover(item: $selectedTokenForPropertyEdit) { identifiedToken in
                        PropertyEditorPopoverView(identifiedToken: identifiedToken) { updatedRawText in
                            if let range = rule.replacement.range(of: identifiedToken.rawText) {
                                rule.replacement.replaceSubrange(range, with: updatedRawText)
                            }
                            selectedTokenForPropertyEdit = nil
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)

            HStack {
                Spacer()
                Button(String(localized: "Cancel")) {
                    onComplete(nil, .cancel)
                    dismiss()
                }

                Button(String(localized: "Save")) {
                    let isDuplicate = settings.activeProfile.payload.textExpansionRules.contains {
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
                .disabled(rule.trigger.isEmpty || rule.trigger == ";" || rule.replacement.isEmpty)
            }
        }
        .padding(25)
        .frame(width: 450)
        .onAppear { isTriggerFocused = true }
    }

    private func insertSyntax(_ syntax: String) {
        if rule.replacement.isEmpty {
            rule.replacement = syntax
        } else {
            if rule.replacement.hasSuffix(" ") || rule.replacement.hasSuffix("\n") {
                rule.replacement += syntax
            } else {
                rule.replacement += " " + syntax
            }
        }
    }
}

struct PropertyEditorPopoverView: View {
    let identifiedToken: IdentifiedToken
    var onSave: (String) -> Void

    @State private var fieldName: String = ""
    @State private var defaultValue: String = ""
    @State private var optionsString: String = ""
    @State private var isChecked: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Edit Properties"))
                .font(.headline)
                .foregroundColor(.secondary)
            
            Divider()
            
            Group {
                switch identifiedToken.token {
                case .input(let name, let def):
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "Field Name")).font(.caption)
                        TextField("", text: $fieldName).textFieldStyle(.roundedBorder)
                        
                        Text(String(localized: "Default Value")).font(.caption)
                        TextField("", text: $defaultValue).textFieldStyle(.roundedBorder)
                    }
                    .onAppear { fieldName = name; defaultValue = def ?? "" }
                    
                case .textarea(let name, let def):
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "Field Name")).font(.caption)
                        TextField("", text: $fieldName).textFieldStyle(.roundedBorder)
                        
                        Text(String(localized: "Default Value")).font(.caption)
                        TextField("", text: $defaultValue).textFieldStyle(.roundedBorder)
                    }
                    .onAppear { fieldName = name; defaultValue = def ?? "" }
                    
                case .select(let name, let options, let def):
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "Field Name")).font(.caption)
                        TextField("", text: $fieldName).textFieldStyle(.roundedBorder)
                        
                        Text(String(localized: "Options (Comma-separated)")).font(.caption)
                        TextField("e.g. DHL,FedEx,UPS", text: $optionsString).textFieldStyle(.roundedBorder)
                        
                        Text(String(localized: "Default Choice")).font(.caption)
                        TextField("", text: $defaultValue).textFieldStyle(.roundedBorder)
                    }
                    .onAppear { fieldName = name; optionsString = options.joined(separator: ","); defaultValue = def ?? "" }
                    
                case .checkbox(let name, let content, let checked):
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "Field Name")).font(.caption)
                        TextField("", text: $fieldName).textFieldStyle(.roundedBorder)
                        
                        Text(String(localized: "Included Block Text")).font(.caption)
                        TextField("", text: $defaultValue).textFieldStyle(.roundedBorder)
                        
                        Toggle(String(localized: "Checked by Default"), isOn: $isChecked)
                            .controlSize(.small)
                    }
                    .onAppear { fieldName = name; defaultValue = content; isChecked = checked }
                    
                case .radio(let name, let options, let def):
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "Field Name")).font(.caption)
                        TextField("", text: $fieldName).textFieldStyle(.roundedBorder)
                        
                        Text(String(localized: "Options (Comma-separated)")).font(.caption)
                        TextField("e.g. High,Normal,Low", text: $optionsString).textFieldStyle(.roundedBorder)
                        
                        Text(String(localized: "Default Choice")).font(.caption)
                        TextField("", text: $defaultValue).textFieldStyle(.roundedBorder)
                    }
                    .onAppear { fieldName = name; optionsString = options.joined(separator: ","); defaultValue = def ?? "" }
                    
                case .datePicker(let name, let fmt):
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "Field Name")).font(.caption)
                        TextField("", text: $fieldName).textFieldStyle(.roundedBorder)
                        
                        Text(String(localized: "Date Format")).font(.caption)
                        TextField("yyyy-MM-dd", text: $defaultValue).textFieldStyle(.roundedBorder)
                    }
                    .onAppear { fieldName = name; defaultValue = fmt }
                    
                case .optionalBlock(let name, let content):
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "Block Name")).font(.caption)
                        TextField("", text: $fieldName).textFieldStyle(.roundedBorder)
                        
                        Text(String(localized: "Block Content")).font(.caption)
                        TextField("", text: $defaultValue).textFieldStyle(.roundedBorder)
                    }
                    .onAppear { fieldName = name; defaultValue = content }
                    
                default:
                    Text(String(localized: "This system element has no editable properties."))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(height: 60)
                }
            }
            
            HStack {
                Spacer()
                Button(String(localized: "Apply")) {
                    let compiledText = compileUpdatedSyntax()
                    onSave(compiledText)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.top, 4)
        }
        .padding(15)
        .frame(width: 280)
    }

    private func compileUpdatedSyntax() -> String {
        switch identifiedToken.token {
        case .input:
            return defaultValue.isEmpty ? "{{input:\(fieldName)}}" : "{{input:\(fieldName)|\(defaultValue)}}"
        case .textarea:
            return defaultValue.isEmpty ? "{{textarea:\(fieldName)}}" : "{{textarea:\(fieldName)|\(defaultValue)}}"
        case .select:
            let cleanOptions = optionsString.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: ",")
            return defaultValue.isEmpty ? "{{select:\(fieldName)[\(cleanOptions)]}}" : "{{select:\(fieldName)[\(cleanOptions)]|\(defaultValue)}}"
        case .checkbox:
            return "{{checkbox:\(fieldName)[\(defaultValue)]|\(isChecked ? "true" : "false")}}"
        case .radio:
            let cleanOptions = optionsString.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: ",")
            return defaultValue.isEmpty ? "{{radio:\(fieldName)[\(cleanOptions)]}}" : "{{radio:\(fieldName)[\(cleanOptions)]|\(defaultValue)}}"
        case .datePicker:
            return "{{datepicker:\(fieldName)|\(defaultValue)}}"
        case .optionalBlock:
            return "{{optional:\(fieldName)[\(defaultValue)]}}"
        default:
            return identifiedToken.rawText
        }
    }
}
enum EditAction {
    case save, delete, cancel
}
