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

struct TypoExceptionSettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared
    @State private var isShowingAddAlert = false
    @State private var newWord: String = ""

    // 🌟 데이터 일원화: 프로필 페이로드의 typoExcludedWords에 직접 접근하는 양방향 바인딩
    private var payload: Binding<ProfileSettingsPayload> {
        Binding(
            get: { settings.activeProfile.payload },
            set: { settings.activeProfile.payload = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 1. 프로필 관리 상단 헤더 고정
            ProfileHeaderView()
            
            // 2. 중앙 컨텐츠 영역
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    
                    // 타이틀 및 활성화 토글 라인
                    HStack(alignment: .center) {
                        Text(String(localized: "Typo Correction Exceptions")).font(.title2.bold())
                        Spacer()
                        Toggle("", isOn: $settings.activeProfile.payload.isAutoTypoCorrectionEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .controlSize(.small)
                            .onChange(of: settings.activeProfile.payload.isAutoTypoCorrectionEnabled) { _ in
                                settings.updateSnapshot()
                                settings.scheduleSave()
                            }
                    }

                    Text(String(localized: "List words that should be ignored by the smart auto-correction. This prevents terminal commands (e.g., sudo, vi) from being converted into Korean (녀애, 퍄)."))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 10)

                    // 3. 예외 단어 관리 카드 구역
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(String(localized: "Active Exceptions")).font(.headline)
                            Spacer()
                            
                            // 단어 추가 버튼
                            Button(action: {
                                newWord = ""
                                isShowingAddAlert = true
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus.circle.fill").foregroundColor(.blue)
                                    Text(String(localized: "Add Word")).font(.body)
                                }.foregroundColor(.primary)
                            }
                            .buttonStyle(.plain)
                            .help(String(localized: "Add Exception Word"))
                            .disabled(!settings.activeProfile.payload.isAutoTypoCorrectionEnabled)
                            .popover(isPresented: $isShowingAddAlert, arrowEdge: .bottom) {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(String(localized: "Add Exception Word"))
                                        .font(.headline)
                                    
                                    TextField(String(localized: "e.g., kubectl"), text: $newWord)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                        .frame(width: 200)
                                        .onSubmit { addNewWord() }
                                    
                                    HStack {
                                        Spacer()
                                        Button(String(localized: "Cancel")) { isShowingAddAlert = false }
                                            .keyboardShortcut(.escape, modifiers: [])
                                        Button(String(localized: "Add")) { addNewWord() }
                                            .buttonStyle(.borderedProminent)
                                            .keyboardShortcut(.defaultAction)
                                    }
                                }
                                .padding()
                            }
                        }

                        // 4. 예외 단어 동적 행렬 리스트 박스
                        VStack(spacing: 0) {
                            if settings.activeProfile.payload.typoExcludedWords.isEmpty {
                                Text(String(localized: "No exception words registered. Auto-correction works for all words."))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, 30)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            } else {
                                // 🌟 강제 새로고침 안정성을 위해 id: \.self 대신 인덱스 기반 순회 구조로 변경하여 무결성 수복
                                ForEach(0..<settings.activeProfile.payload.typoExcludedWords.count, id: \.self) { index in
                                    let word = settings.activeProfile.payload.typoExcludedWords[index]
                                    
                                    HStack(spacing: 8) {
                                        Image(systemName: "text.quote")
                                            .resizable()
                                            .frame(width: 12, height: 12)
                                            .foregroundColor(.secondary)
                                            .padding(.leading, 6)
                                        
                                        Text(word)
                                            .font(.body)
                                            .lineLimit(1)
                                        
                                        Spacer()
                                        
                                        // 🌟 단어 삭제 클릭 시 프로필 페이로드 배열에서 직접 삭제하고 원자적 저장 및 스냅샷 즉시 반영
                                        Button(action: {
                                            settings.activeProfile.payload.typoExcludedWords.remove(at: index)
                                            // 실시간 엔진 스냅샷과 메모리 매니저를 동시 하이드레이션
                                            TypoExceptionManager.shared.excludedWords = settings.activeProfile.payload.typoExcludedWords
                                            settings.updateSnapshot()
                                            settings.scheduleSave()
                                        }) {
                                            Image(systemName: "trash").foregroundColor(.red)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    
                                    if index < settings.activeProfile.payload.typoExcludedWords.count - 1 {
                                        Divider().padding(.horizontal, 15).padding(.vertical, 4)
                                    }
                                }
                            }
                        }
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                    }
                    .opacity(settings.activeProfile.payload.isAutoTypoCorrectionEnabled ? 1.0 : 0.5)
                    
                    Spacer()
                }
                .padding(.horizontal, 25)
                .padding(.vertical, 15)
            }
            
            // 5. 하단 툴바 구역 (기본값 원복)
            HStack {
                Spacer()
                Button(action: {
                    // 기본값 매니저의 원복 세트를 프로필 장부에 덮어쓰고 강제 플러시
                    TypoExceptionManager.shared.resetToDefaults()
                    settings.activeProfile.payload.typoExcludedWords = TypoExceptionManager.shared.excludedWords
                    settings.updateSnapshot()
                    settings.scheduleSave()
                }) {
                    Text(String(localized: "Reset to Defaults"))
                        .font(.body)
                }
                .buttonStyle(.borderless)
                .disabled(!settings.activeProfile.payload.isAutoTypoCorrectionEnabled)
            }
            .padding(.horizontal, 25)
            .padding(.vertical, 16)
            .background(Color(NSColor.windowBackgroundColor))
        }
    }

    private func addNewWord() {
        let cleanWord = newWord.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanWord.isEmpty else { return }
        
        // 🌟 프로필 데이터 배열에 직접 주입
        if !settings.activeProfile.payload.typoExcludedWords.contains(cleanWord) {
            settings.activeProfile.payload.typoExcludedWords.append(cleanWord)
            settings.activeProfile.payload.typoExcludedWords.sort()
            
            // 실시간 메모리 매니저 동기화 및 엔진 스냅샷 반영 정산
            TypoExceptionManager.shared.excludedWords = settings.activeProfile.payload.typoExcludedWords
            settings.updateSnapshot()
            settings.scheduleSave()
        }
        isShowingAddAlert = false
    }
}
