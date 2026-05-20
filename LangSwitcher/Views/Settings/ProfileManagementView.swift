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

struct ProfileManagementView: View {
    @ObservedObject var settings = SettingsManager.shared
    @State private var selection: UUID?
    
    var body: some View {
        HStack(spacing: 0) {
            
            // ── 좌측: 프로필 목록 ──────────────────────────────
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(settings.profiles) { profile in
                            VStack(alignment: .leading, spacing: 5) {
                                
                                // 🌟 1. "현재 사용 중" 배지를 이름 위로 단독 배치하여 좌우 쏠림 해결
                                if profile.id == settings.activeProfileID {
                                    Text(String(localized: "Currently Active"))
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color.blue)
                                        .foregroundColor(.white)
                                        .cornerRadius(4)
                                }
                                
                                Text(profile.name)
                                    .font(.body).bold()
                                
                                // 프로필 설명 및 밀도 보강 (규칙 요약)
                                VStack(alignment: .leading, spacing: 2) {
                                    if !profile.note.isEmpty {
                                        Text(profile.note)
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                    } else {
                                        Text(String(localized: "No description"))
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary).opacity(0.5)
                                    }
                                    
                                    // 규칙 수 요약 (앱과 웹사이트 규칙 포함)
                                    let payload = profile.payload
                                    let stats = String(format: String(localized: "Apps %d · Web %d · Shortcuts %d · Snippets %d · Excluded %d"), payload.customApps.count, payload.domainRules.count, payload.customShortcuts.count, payload.textExpansionRules.count, payload.excludedApps.count)
                                    
                                    Text(stats)
                                        .font(.system(size: 10))
                                        .foregroundColor(selection == profile.id ? .white.opacity(0.8) : .secondary.opacity(0.8))
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(selection == profile.id ? Color(.selectedControlColor) : Color.clear)
                            .foregroundColor(selection == profile.id ? .white : .primary)
                            .cornerRadius(6)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selection = profile.id
                            }
                        }
                    }
                    .padding(10)
                }
                
                Divider()
                
                // 하단 +/- 버튼
                HStack(spacing: 0) {
                    Button(action: addProfile) {
                        Image(systemName: "plus")
                            .frame(width: 28, height: 22)
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "Create New Profile"))

                    Divider().frame(height: 16)

                    Button(action: removeProfile) {
                        Image(systemName: "minus")
                            .frame(width: 28, height: 22)
                    }
                    .buttonStyle(.plain)
                    .disabled(settings.profiles.count <= 1 || selection == nil)
                    .help(String(localized: "Delete Selected Profile"))

                    Spacer()
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))
            }
            .frame(width: 240)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // ── 우측: 프로필 상세 ──────────────────────────────
            Group {
                if let selection = selection,
                   let index = settings.profiles.firstIndex(where: { $0.id == selection }) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            Form {
                                Section(header: Text(String(localized: "Profile Details")).font(.headline)) {
                                    TextField(String(localized: "Profile Name"), text: $settings.profiles[index].name)
                                        .textFieldStyle(.roundedBorder)
                                    TextField(String(localized: "Description"), text: $settings.profiles[index].note)
                                        .textFieldStyle(.roundedBorder)
                                }
                                
                                Spacer().frame(height: 25)
                                
                                Section {
                                    // 🌟 2. Form 오버플로우 방지: 상태 라벨과 버튼 그룹을 수직(VStack)으로 명확히 분리
                                    VStack(alignment: .leading, spacing: 14) {
                                        if settings.activeProfileID == settings.profiles[index].id {
                                            Label(String(localized: "Currently Active"), systemImage: "checkmark.circle.fill")
                                                .font(.body.bold())
                                                .foregroundColor(.green)
                                        } else {
                                            Button(String(localized: "Switch to this Profile")) {
                                                settings.activeProfileID = settings.profiles[index].id
                                            }
                                            .buttonStyle(.borderedProminent)
                                        }
                                        
                                        HStack(spacing: 12) {
                                            Button(String(localized: "Duplicate Profile")) {
                                                duplicateProfile(index: index)
                                            }
                                            
                                            Button(String(localized: "New Profile")) {
                                                addProfile()
                                            }
                                        }
                                    }
                                }
                            }
                            .padding()
                            
                            Spacer().frame(height: 20)
                            
                            // 하단 안내 문구
                            VStack(alignment: .leading, spacing: 8) {
                                Divider()
                                Text(String(localized: "About Profiles"))
                                    .font(.caption).bold()
                                
                                Text(String(localized: "This profile includes app-specific keyboards, website rules, text expansion, excluded apps, and custom shortcuts."))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                
                                Text(String(localized: "App operational settings like startup options, auto-update, and cloud sync apply globally across all profiles."))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding()
                            .background(Color(NSColor.textBackgroundColor).opacity(0.3))
                        }
                    }
                } else {
                    Text(String(localized: "Select a profile to edit"))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if selection == nil { selection = settings.activeProfileID }
        }
    }
    
    // MARK: - Actions
    private func addProfile() {
        let newPayload = settings.activeProfile.payload
        let newProfile = SettingsProfile(
            id: UUID(), name: String(localized: "New Profile"), note: "", isDefault: false,
            createdAt: Date(), updatedAt: Date(), payload: newPayload
        )
        settings.profiles.append(newProfile)
        selection = newProfile.id
        settings.activeProfileID = newProfile.id
    }
    
    private func removeProfile() {
        guard let id = selection, settings.profiles.count > 1 else { return }
        if id == settings.activeProfileID {
            if let firstOther = settings.profiles.first(where: { $0.id != id }) {
                settings.activeProfileID = firstOther.id
            }
        }
        settings.profiles.removeAll(where: { $0.id == id })
        selection = settings.activeProfileID
    }
    
    private func duplicateProfile(index: Int) {
        // 1. 기존 프로필을 값 복사하여 새로운 프로필 생성 (기존 로직 유지)
        var newProfile = settings.profiles[index]
        newProfile.id = UUID() // 새로운 고유 ID 부여
        newProfile.name = "\(newProfile.name) (Copy)"
        
        // 🌟 [핵심 수정] 연쇄 저장을 막기 위해 '일괄 업데이트' 모드 켜기
        settings.isBatchUpdating = true
        
        // 🌟 3가지 상태 변경을 한 번에 진행 (이때는 자동 저장이 무시됨)
        settings.profiles.append(newProfile)
        self.selection = newProfile.id // (View에 selection state가 있다면)
        settings.activeProfileID = newProfile.id
        
        // 🌟 '일괄 업데이트' 모드 끄기
        settings.isBatchUpdating = false
        
        // 🌟 모든 상태 변경이 끝났으므로, 마지막에 딱 한 번만 저장하고 스냅샷을 갱신!
        settings.saveAll()
        
        // (참고: SettingsManager의 구조에 따라 updateSnapshot()이 saveAll() 내부에
        // 포함되어 있다면 아래 줄은 생략해도 됩니다. 포함되어 있지 않다면 명시적으로 호출하세요.)
        DispatchQueue.main.async {
            settings.updateSnapshot()
        }
    }
}
