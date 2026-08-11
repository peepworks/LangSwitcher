//
//  TypoExceptionSettingsView.swift
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
import AppKit
import UniformTypeIdentifiers

struct TypoExceptionSettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared
    
    @State private var showingAddSheet = false
    @AppStorage("isTypoExceptionEnabled") private var isTypoExceptionEnabled: Bool = true
    
    private var payload: Binding<ProfileSettingsPayload> {
        Binding(
            get: { settings.activeProfile.payload },
            set: { settings.activeProfile.payload = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProfileHeaderView()

            HStack {
                Text(String(localized: "Typo Exception Words")).font(.title2.bold())
                Spacer()
                Toggle("", isOn: $isTypoExceptionEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
            }
            .padding(.horizontal, 30)
            .padding(.top, 15)
            .padding(.bottom, 10)

            Text(String(localized: "Register words to exclude from smart auto typo correction. Prevents terminal commands (e.g., sudo, vi) from being converted by mistake."))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.horizontal, 30)
                .padding(.bottom, 15)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(String(localized: "Registered Exception Words")).font(.headline)
                    Spacer()
                    Button(action: {
                        showingAddSheet = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill").foregroundColor(.blue)
                            Text(String(localized: "Add Word")).foregroundColor(.primary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                ScrollView {
                    VStack(spacing: 0) {
                        if settings.activeProfile.payload.typoExcludedWords.isEmpty {
                            Text(String(localized: "No registered exception words."))
                                .font(.subheadline).foregroundColor(.secondary).padding(.vertical, 40)
                                .frame(maxWidth: .infinity, alignment: .center)
                        } else {
                            ForEach(settings.activeProfile.payload.typoExcludedWords, id: \.self) { word in
                                HStack(spacing: 12) {
                                    Image(systemName: "text.alignleft").foregroundColor(.secondary)
                                    Text(word).font(.system(.body, design: .monospaced))
                                    Spacer()
                                    Button(action: {
                                        removeWord(word)
                                    }) {
                                        Image(systemName: "trash").foregroundColor(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)

                                if word != settings.activeProfile.payload.typoExcludedWords.last {
                                    Divider().padding(.horizontal, 15)
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
            
            Spacer()

            HStack(spacing: 16) {
                Spacer()

                Button(action: restoreDefaultWords) {
                    Label(String(localized: "Restore Defaults"), systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Button(action: importWords) {
                    Label(String(localized: "Import..."), systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Button(action: exportWords) {
                    Label(String(localized: "Export..."), systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 15)
            .opacity(isTypoExceptionEnabled ? 1.0 : 0.5)
            .disabled(!isTypoExceptionEnabled)
            
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(isPresented: $showingAddSheet) {
            TypoExceptionEditSheet { newWord in
                addWord(newWord)
            }
        }
    }

    // MARK: - Actions

    private func addWord(_ word: String) {
        let cleanWord = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanWord.isEmpty else { return }
        
        if !settings.activeProfile.payload.typoExcludedWords.contains(cleanWord) {
            settings.beginBatchUpdate()
            var profile = settings.activeProfile
            profile.payload.typoExcludedWords.append(cleanWord)
            profile.payload.typoExcludedWords.sort()
            
            // 🌟 싱글톤 장부 동기화
            TypoExceptionManager.shared.excludedWords = profile.payload.typoExcludedWords
            
            settings.activeProfile = profile
            settings.endBatchUpdate()
        }
    }

    private func removeWord(_ word: String) {
        settings.beginBatchUpdate()
        var profile = settings.activeProfile
        profile.payload.typoExcludedWords.removeAll { $0 == word }
        
        // 🌟 싱글톤 장부 동기화
        TypoExceptionManager.shared.excludedWords = profile.payload.typoExcludedWords
        
        settings.activeProfile = profile
        settings.endBatchUpdate()
    }

    private func restoreDefaultWords() {
        let defaultWords = [
            "apt", "brew", "cat", "cd", "chmod", "chown", "clear", "cp", "curl",
            "docker", "git", "grep", "history", "kill", "ls", "mkdir", "mv",
            "mysql", "node", "npm", "ping", "pip", "python", "rm", "ssh", "sudo", "tar", "vi", "vim"
        ].sorted()
        
        settings.beginBatchUpdate()
        var profile = settings.activeProfile
        profile.payload.typoExcludedWords = defaultWords
        
        // 🌟 싱글톤 장부 동기화
        TypoExceptionManager.shared.excludedWords = profile.payload.typoExcludedWords
        
        settings.activeProfile = profile
        settings.endBatchUpdate()
    }

    private func exportWords() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        
        if let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            panel.directoryURL = docsURL
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmm"
        panel.nameFieldStringValue = "LangSwitcher_TypoExceptions_\(formatter.string(from: Date())).json"
        
        NSApp.activate(ignoringOtherApps: true)
        
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let data = try JSONEncoder().encode(settings.activeProfile.payload.typoExcludedWords)
                try data.write(to: url)
                dprint("✅ [TypoExceptions] 예외 단어 목록 내보내기 성공.")
            } catch {
                dprint("❌ [TypoExceptions] 내보내기 실패: \(error.localizedDescription)")
            }
        }
    }

    private func importWords() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        
        NSApp.activate(ignoringOtherApps: true)
        
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let data = try Data(contentsOf: url)
                let importedWords = try JSONDecoder().decode([String].self, from: data)
                
                settings.beginBatchUpdate()
                var profile = settings.activeProfile
                
                let mergedSet = Set(profile.payload.typoExcludedWords).union(importedWords)
                profile.payload.typoExcludedWords = Array(mergedSet).sorted()
                
                // 🌟 싱글톤 장부 동기화
                TypoExceptionManager.shared.excludedWords = profile.payload.typoExcludedWords
                
                settings.activeProfile = profile
                settings.endBatchUpdate()
                dprint("✅ [TypoExceptions] 예외 단어 목록 가져오기 성공 (\(importedWords.count)개 병합).")
            } catch {
                dprint("❌ [TypoExceptions] 가져오기 실패: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Add Word Sheet (Modal)
struct TypoExceptionEditSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var newWord: String = ""
    var onSave: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text(String(localized: "Add Exception Word"))
                .font(.headline)
                .padding(.top, 20)
                .padding(.bottom, 15)

            Form {
                Section {
                    TextField(String(localized: "Enter word (e.g., sudo, git):"), text: $newWord)
                        .textFieldStyle(.roundedBorder)
                        .disableAutocorrection(true)
                        .onSubmit {
                            submitWord()
                        }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)

            HStack {
                Spacer()
                Button(String(localized: "Cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(String(localized: "Add")) {
                    submitWord()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(20)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 380, height: 180)
    }
    
    private func submitWord() {
        if !newWord.trimmingCharacters(in: .whitespaces).isEmpty {
            onSave(newWord)
            dismiss()
        }
    }
}
