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
import AppKit

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
    var characterRange: NSRange = NSRange(location: 0, length: 0)
    
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
            let nsRange = NSRange(match.range, in: rule.replacement)
            
            while tokenIdx < tokens.count {
                let t = tokens[tokenIdx]
                tokenIdx += 1
                if case .text = t { continue }
                var idToken = IdentifiedToken(rawText: rawStr, token: t)
                idToken.characterRange = nsRange
                list.append(idToken)
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
                                Button(action: { self.insertSyntax("{{date:yyyy-MM-dd}}") }) { Label(String(localized: "Full Date (yyyy-MM-dd)"), systemImage: "calendar") }
                                Button(action: { self.insertSyntax("{{date:yyyy}}") }) { Label(String(localized: "Year (yyyy)"), systemImage: "calendar.badge.clock") }
                                Button(action: { self.insertSyntax("{{date:MM}}") }) { Label(String(localized: "Month (MM)"), systemImage: "calendar.badge.plus") }
                                Button(action: { self.insertSyntax("{{date:dd}}") }) { Label(String(localized: "Day (dd)"), systemImage: "calendar.badge.checkmark") }
                            }
                            Menu(String(localized: "Time")) {
                                Button(action: { self.insertSyntax("{{time:HH:mm}}") }) { Label(String(localized: "Hour:Minute (HH:mm)"), systemImage: "clock") }
                                Button(action: { self.insertSyntax("{{time:HH:mm:ss}}") }) { Label(String(localized: "Hour:Minute:Second (HH:mm:ss)"), systemImage: "clock.fill") }
                            }
                            Button(action: { self.insertSyntax("{{clipboard}}") }) { Label(String(localized: "Clipboard Contents"), systemImage: "doc.on.clipboard") }
                            Button(action: { self.insertSyntax("${selectedText}") }) { Label(String(localized: "Selected Text"), systemImage: "doc.text.magnifyingglass") }
                        }
                        
                        Menu(String(localized: "Input Fields")) {
                            Button(action: { self.insertSyntax("{{input:FieldName|defaultValue}}") }) { Label(String(localized: "Single-line Field"), systemImage: "rectangle.and.pencil.and.ellipsis") }
                            Button(action: { self.insertSyntax("{{textarea:FieldName|defaultValue}}") }) { Label(String(localized: "Multi-line Field"), systemImage: "text.justify.left") }
                            Button(action: { self.insertSyntax("{{select:FieldName[Option1,Option2]|Option1}}") }) { Label(String(localized: "Dropdown Menu"), systemImage: "list.bullet.rectangle") }
                            Divider()
                            Button(action: { self.insertSyntax("{{checkbox:FieldName[Included Content]|true}}") }) { Label(String(localized: "Checkbox Option"), systemImage: "checkmark.square") }
                            Button(action: { self.insertSyntax("{{radio:FieldName[Opt1,Opt2]|Opt1}}") }) { Label(String(localized: "Radio Buttons"), systemImage: "largecircle.fill.and.checkmark") }
                            Button(action: { self.insertSyntax("{{datepicker:FieldName|yyyy-MM-dd}}") }) { Label(String(localized: "Date Picker Field"), systemImage: "calendar.badge.plus") }
                        }
                        
                        Menu(String(localized: "Template Control")) {
                            Button(action: { self.insertSyntax("{{optional:BlockName[Content Text]}}") }) { Label(String(localized: "Optional Block"), systemImage: "uiwindow.split.2x1") }
                            Button(action: { self.insertSyntax("{{cursor}}") }) { Label(String(localized: "Cursor Position"), systemImage: "character.cursor.line") }
                            Button(action: { self.insertSyntax("${1:default}") }) { Label(String(localized: "Tab Stop"), systemImage: "character.textbox") }
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

                TokenMacroTextEditor(text: $rule.replacement, tokens: reactiveInspectorTokens) { targetToken, action in
                    self.executeTokenAction(token: targetToken, action: action)
                }
                .frame(height: 120)
                .cornerRadius(5)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.2), lineWidth: 1))

                if !reactiveInspectorTokens.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "Click elements below to edit properties:"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
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
                                    .contextMenu {
                                        Button(String(localized: "Edit Properties...")) {
                                            selectedTokenForPropertyEdit = identifiedToken
                                        }
                                        Button(String(localized: "Duplicate Element")) {
                                            self.executeTokenAction(token: identifiedToken, action: .duplicate)
                                        }
                                        Divider()
                                        Button(String(localized: "Delete Element"), role: .destructive) {
                                            self.executeTokenAction(token: identifiedToken, action: .delete)
                                        }
                                    }
                                }
                            }
                            .padding(.trailing, 10)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
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

    private func executeTokenAction(token: IdentifiedToken, action: TokenAction) {
        switch action {
        case .edit:
            self.selectedTokenForPropertyEdit = token
        case .duplicate:
            if let range = rule.replacement.range(of: token.rawText) {
                rule.replacement.insert(contentsOf: " " + token.rawText, at: range.upperBound)
            }
        case .delete:
            if let range = rule.replacement.range(of: token.rawText) {
                rule.replacement.removeSubrange(range)
            }
        }
    }
}

// MARK: - 🌟 📟 AppKit 고성능 하이브리드 인라인 토큰 에디터
// [수복 정산] 오타였던 TokenMacroAction을 TokenAction으로 완전 변경하여 컴파일러 크래시 라인을 원천 소각했습니다.
enum TokenAction: Sendable { case edit, duplicate, delete }

struct TokenMacroTextEditor: NSViewRepresentable {
    @Binding var text: String
    var tokens: [IdentifiedToken]
    var onTokenAction: @MainActor (IdentifiedToken, TokenAction) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        
        let textView = MacroTextView()
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = context.coordinator
        textView.actionHandler = onTokenAction
        
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? MacroTextView else { return }
        context.coordinator.isUpdating = true
        textView.tokenMap = tokens
        
        if textView.string != text {
            textView.string = text
        }
        
        if let textStorage = textView.textStorage {
            let baseRange = NSRange(location: 0, length: textStorage.length)
            textStorage.removeAttribute(.foregroundColor, range: baseRange)
            textStorage.removeAttribute(.backgroundColor, range: baseRange)
            textStorage.removeAttribute(.underlineStyle, range: baseRange)
            textStorage.addAttribute(.foregroundColor, value: NSColor.textColor, range: baseRange)
            
            for token in tokens {
                if token.characterRange.location + token.characterRange.length <= textStorage.length {
                    textStorage.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: token.characterRange)
                    textStorage.addAttribute(.backgroundColor, value: NSColor.systemBlue.withAlphaComponent(0.12), range: token.characterRange)
                    textStorage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: token.characterRange)
                }
            }
        }
        context.coordinator.isUpdating = false
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TokenMacroTextEditor
        var isUpdating = false

        init(_ parent: TokenMacroTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

// MARK: - 🧱 로우레벨 마우스 인터랙션 집행 뷰
class MacroTextView: NSTextView {
    var tokenMap: [IdentifiedToken] = []
    var actionHandler: (@MainActor (IdentifiedToken, TokenAction) -> Void)?

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let charIndex = layoutManager?.characterIndex(for: point, in: textContainer!, fractionOfDistanceBetweenInsertionPoints: nil) {
            if let matchedToken = tokenMap.first(where: { NSLocationInRange(charIndex, $0.characterRange) }) {
                
                if event.clickCount == 2 {
                    if let handler = actionHandler {
                        DispatchQueue.main.async { MainActor.assumeIsolated { handler(matchedToken, .edit) } }
                    }
                    return
                } else if event.clickCount == 1 {
                    if let handler = actionHandler {
                        DispatchQueue.main.async { MainActor.assumeIsolated { handler(matchedToken, .edit) } }
                    }
                }
            }
        }
        super.mouseDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        if let charIndex = layoutManager?.characterIndex(for: point, in: textContainer!, fractionOfDistanceBetweenInsertionPoints: nil) {
            if let matchedToken = tokenMap.first(where: { NSLocationInRange(charIndex, $0.characterRange) }) {
                
                let customMenu = NSMenu(title: "Token Context")
                
                let editItem = NSMenuItem(title: String(localized: "Edit Properties..."), action: #selector(contextMenuEditAction(_:)), keyEquivalent: "")
                editItem.representedObject = matchedToken
                customMenu.addItem(editItem)
                
                let duplicateItem = NSMenuItem(title: String(localized: "Duplicate Element"), action: #selector(contextMenuDuplicateAction(_:)), keyEquivalent: "")
                duplicateItem.representedObject = matchedToken
                customMenu.addItem(duplicateItem)
                
                customMenu.addItem(NSMenuItem.separator())
                
                let deleteItem = NSMenuItem(title: String(localized: "Delete Element"), action: #selector(contextMenuDeleteAction(_:)), keyEquivalent: "")
                deleteItem.representedObject = matchedToken
                customMenu.addItem(deleteItem)
                
                return customMenu
            }
        }
        return super.menu(for: event)
    }

    @objc private func contextMenuEditAction(_ sender: NSMenuItem) {
        guard let token = sender.representedObject as? IdentifiedToken, let handler = actionHandler else { return }
        DispatchQueue.main.async { MainActor.assumeIsolated { handler(token, .edit) } }
    }

    @objc private func contextMenuDuplicateAction(_ sender: NSMenuItem) {
        guard let token = sender.representedObject as? IdentifiedToken, let handler = actionHandler else { return }
        DispatchQueue.main.async { MainActor.assumeIsolated { handler(token, .duplicate) } }
    }

    @objc private func contextMenuDeleteAction(_ sender: NSMenuItem) {
        guard let token = sender.representedObject as? IdentifiedToken, let handler = actionHandler else { return }
        DispatchQueue.main.async { MainActor.assumeIsolated { handler(token, .delete) } }
    }
}

// MARK: - 🌟 정밀 속성 제어 및 가이드 툴팁 통합 팝오버 뷰
struct PropertyEditorPopoverView: View {
    let identifiedToken: IdentifiedToken
    var onSave: (String) -> Void

    @State private var fieldName: String = ""
    @State private var defaultValue: String = ""
    @State private var optionsString: String = ""
    @State private var isChecked: Bool = true
    
    @State private var placeholder: String = ""
    @State private var isRequired: Bool = false
    @State private var fieldSize: String = ""
    @State private var syncByName: Bool = true
    @State private var showAtTop: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(String(localized: "Edit Properties"))
                    .font(.headline)
                    .foregroundColor(.secondary)
                Spacer()
                Text(getUsageTooltipText())
                    .font(.caption2)
                    .foregroundColor(.blue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(4)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 10) {
                switch getTokenTypeString() {
                case "input", "textarea":
                    VStack(alignment: .leading, spacing: 5) {
                        Text(String(localized: "Field Name")).font(.caption).foregroundColor(.secondary)
                        TextField("", text: $fieldName).textFieldStyle(.roundedBorder)
                        
                        Text(String(localized: "Default Value")).font(.caption).foregroundColor(.secondary)
                        TextField("", text: $defaultValue).textFieldStyle(.roundedBorder)
                        
                        Text(String(localized: "Placeholder Text")).font(.caption).foregroundColor(.secondary)
                        TextField(String(localized: "e.g. Enter your name"), text: $placeholder).textFieldStyle(.roundedBorder)
                        
                        Text(getTokenTypeString() == "textarea" ? String(localized: "Field Height (lines)") : String(localized: "Field Width (px)")).font(.caption).foregroundColor(.secondary)
                        TextField(getTokenTypeString() == "textarea" ? String(localized: "e.g. 40") : "e.g. 120", text: $fieldSize).textFieldStyle(.roundedBorder)
                    }
                    
                case "select", "radio":
                    VStack(alignment: .leading, spacing: 5) {
                        Text(String(localized: "Field Name")).font(.caption).foregroundColor(.secondary)
                        TextField("", text: $fieldName).textFieldStyle(.roundedBorder)
                        
                        Text(String(localized: "Options (Comma-separated)")).font(.caption).foregroundColor(.secondary)
                        TextField(getTokenTypeString() == "radio" ? "e.g. High,Normal,Low" : "e.g. DHL,FedEx,UPS", text: $optionsString).textFieldStyle(.roundedBorder)
                        
                        Text(String(localized: "Default Choice")).font(.caption).foregroundColor(.secondary)
                        TextField("", text: $defaultValue).textFieldStyle(.roundedBorder)
                    }
                    
                case "checkbox":
                    VStack(alignment: .leading, spacing: 5) {
                        Text(String(localized: "Field Name")).font(.caption).foregroundColor(.secondary)
                        TextField("", text: $fieldName).textFieldStyle(.roundedBorder)
                        
                        Text(String(localized: "Included Block Text")).font(.caption).foregroundColor(.secondary)
                        TextField("", text: $defaultValue).textFieldStyle(.roundedBorder)
                        
                        Toggle(String(localized: "Checked by Default"), isOn: $isChecked)
                            .controlSize(.small)
                    }
                    
                case "datepicker":
                    VStack(alignment: .leading, spacing: 5) {
                        Text(String(localized: "Field Name")).font(.caption).foregroundColor(.secondary)
                        TextField("", text: $fieldName).textFieldStyle(.roundedBorder)
                        
                        Text(String(localized: "Date Format")).font(.caption).foregroundColor(.secondary)
                        TextField("yyyy-MM-dd", text: $defaultValue).textFieldStyle(.roundedBorder)
                    }
                    
                case "optional":
                    VStack(alignment: .leading, spacing: 5) {
                        Text(String(localized: "Block Name")).font(.caption).foregroundColor(.secondary)
                        TextField("", text: $fieldName).textFieldStyle(.roundedBorder)
                        
                        Text(String(localized: "Block Content")).font(.caption).foregroundColor(.secondary)
                        TextField("", text: $defaultValue).textFieldStyle(.roundedBorder)
                    }
                    
                default:
                    Text(String(localized: "This system element has no editable properties."))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 40, alignment: .center)
                }
                
                if isInputFieldToken() {
                    Divider().padding(.vertical, 4)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "Advanced Rules")).font(.caption.bold()).foregroundColor(.secondary)
                        
                        Toggle(String(localized: "Required Field"), isOn: $isRequired)
                        Toggle(String(localized: "Sync values with same field name"), isOn: $syncByName)
                        Toggle(String(localized: "Show at top summary panel"), isOn: $showAtTop)
                    }
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 2)
            
            HStack {
                Spacer()
                Button(String(localized: "Apply")) {
                    let compiledText = compileUpdatedSyntax()
                    onSave(compiledText)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(fieldName.isEmpty)
            }
            .padding(.top, 4)
        }
        .padding(15)
        .frame(width: 310)
        .onAppear { parseExistingMetaAttributes() }
    }

    private func isInputFieldToken() -> Bool {
        let type = getTokenTypeString()
        return ["input", "textarea", "select", "checkbox", "radio", "datepicker"].contains(type)
    }
    
    private func getTokenTypeString() -> String {
        let text = identifiedToken.rawText
        if text.contains("{{input:") { return "input" }
        if text.contains("{{textarea:") { return "textarea" }
        if text.contains("{{select:") { return "select" }
        if text.contains("{{checkbox:") { return "checkbox" }
        if text.contains("{{radio:") { return "radio" }
        if text.contains("{{datepicker:") { return "datepicker" }
        if text.contains("{{optional:") { return "optional" }
        return "system"
    }
    
    private func getUsageTooltipText() -> String {
        switch getTokenTypeString() {
        case "input": return String(localized: "Single-line Input")
        case "textarea": return String(localized: "Multi-line Area")
        case "select": return String(localized: "Dropdown Menu")
        case "checkbox": return String(localized: "On/Off Toggle")
        case "radio": return String(localized: "Mutual Exclusive (2-4 items)")
        case "datepicker": return String(localized: "Manual Date Selection")
        case "optional": return String(localized: "Conditional Paragraph")
        default: return String(localized: "System Value")
        }
    }

    private func parseExistingMetaAttributes() {
        var cleanText = identifiedToken.rawText
        if cleanText.hasPrefix("{{") { cleanText = String(cleanText.dropFirst(2)) }
        if cleanText.hasSuffix("}}") { cleanText = String(cleanText.dropLast(2)) }
        
        let typeComponents = cleanText.components(separatedBy: ":")
        guard typeComponents.count >= 2 else { return }
        let type = typeComponents[0]
        let body = typeComponents[1...].joined(separator: ":")
        
        let parts = body.components(separatedBy: "|")
        let firstPart = parts[0]
        
        if let openBracketIndex = firstPart.firstIndex(of: "["),
           let closeBracketIndex = firstPart.lastIndex(of: "]"),
           openBracketIndex < closeBracketIndex {
            fieldName = String(firstPart[..<openBracketIndex])
            let bracketContent = String(firstPart[firstPart.index(after: openBracketIndex)..<closeBracketIndex])
            optionsString = bracketContent
            if type == "checkbox" || type == "optional" {
                defaultValue = bracketContent
            }
        } else {
            fieldName = firstPart
            optionsString = ""
            defaultValue = ""
        }
        
        if parts.count > 1 {
            let secondPart = parts[1]
            if type == "checkbox" {
                isChecked = (secondPart == "true")
            } else if type != "optional" {
                defaultValue = secondPart
            }
        }
        
        placeholder = ""
        isRequired = false
        fieldSize = ""
        syncByName = true
        showAtTop = false
        
        if parts.count > 2 {
            let metaStr = parts[2]
            let queryItems = metaStr.components(separatedBy: "&")
            for item in queryItems {
                let pair = item.components(separatedBy: "=")
                guard pair.count == 2 else { continue }
                let key = pair[0], val = pair[1]
                
                switch key {
                case "placeholder": placeholder = val
                case "required": isRequired = (val == "true")
                case "size": fieldSize = val
                case "sync": syncByName = (val == "true")
                case "top": showAtTop = (val == "true")
                default: break
                }
            }
        }
    }

    private func compileUpdatedSyntax() -> String {
        let type = getTokenTypeString()
        var coreSyntax = ""
        
        switch type {
        case "input":
            coreSyntax = defaultValue.isEmpty ? "{{input:\(fieldName)}}" : "{{input:\(fieldName)|\(defaultValue)}}"
        case "textarea":
            coreSyntax = defaultValue.isEmpty ? "{{textarea:\(fieldName)}}" : "{{textarea:\(fieldName)|\(defaultValue)}}"
        case "select":
            let cleanOptions = optionsString.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: ",")
            coreSyntax = defaultValue.isEmpty ? "{{select:\(fieldName)[\(cleanOptions)]}}" : "{{select:\(fieldName)[\(cleanOptions)]|\(defaultValue)}}"
        case "checkbox":
            coreSyntax = "{{checkbox:\(fieldName)[\(defaultValue)]|\(isChecked ? "true" : "false")}}"
        case "radio":
            let cleanOptions = optionsString.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: ",")
            coreSyntax = defaultValue.isEmpty ? "{{radio:\(fieldName)[\(cleanOptions)]}}" : "{{radio:\(fieldName)[\(cleanOptions)]|\(defaultValue)}}"
        case "datepicker":
            coreSyntax = "{{datepicker:\(fieldName)|\(defaultValue)}}"
        case "optional":
            return "{{optional:\(fieldName)[\(defaultValue)]}}"
        default:
            return identifiedToken.rawText
        }
        
        if isInputFieldToken() {
            var metaParams: [String] = []
            if !placeholder.isEmpty { metaParams.append("placeholder=\(placeholder)") }
            if isRequired { metaParams.append("required=true") }
            if !fieldSize.isEmpty { metaParams.append("size=\(fieldSize)") }
            if !syncByName { metaParams.append("sync=false") }
            if showAtTop { metaParams.append("top=true") }
            
            if !metaParams.isEmpty {
                let metaString = metaParams.joined(separator: "&")
                coreSyntax = coreSyntax.replacingOccurrences(of: "}}", with: "|\(metaString)}}")
            }
        }
        
        return coreSyntax
    }
}
enum EditAction {
    case save, delete, cancel
}
