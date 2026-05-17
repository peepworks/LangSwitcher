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
                List(selection: $selection) {
                    ForEach(settings.profiles) { profile in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(profile.name)
                                    .font(.body).bold()
                                Spacer()
                                if profile.id == settings.activeProfileID {
                                    Text(String(localized: "Currently Active"))
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Color.blue)
                                        .foregroundColor(.white)
                                        .cornerRadius(4)
                                }
                            }
                            if !profile.note.isEmpty {
                                Text(profile.note)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                        .padding(.vertical, 4)
                        .tag(profile.id)
                    }
                }
                .listStyle(.plain)

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
            .frame(width: 220)  // ✅ 고정폭: HSplitView 대신 frame으로 크기 고정
            .background(Color(NSColor.controlBackgroundColor))

            Divider() // ✅ 좌우 구분선

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

                                Spacer().frame(height: 20)

                                Section {
                                    HStack(spacing: 15) {
                                        if settings.activeProfileID == settings.profiles[index].id {
                                            Label(String(localized: "Currently Active"), systemImage: "checkmark.circle.fill")
                                                .font(.body.bold())
                                                .foregroundColor(.green)
                                                .padding(.vertical, 4)
                                        } else {
                                            Button(String(localized: "Switch to this Profile")) {
                                                settings.activeProfileID = settings.profiles[index].id
                                            }
                                            .buttonStyle(.borderedProminent)
                                        }

                                        Button(String(localized: "Duplicate Profile")) {
                                            duplicateProfile(index: index)
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
                                Text(String(localized: "This profile includes your custom shortcuts, app/website specific keyboards, text expansion rules, typo correction settings, and excluded apps."))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(String(localized: "Startup options, cloud sync, and UI preferences are applied globally across all profiles."))
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
        // ✅ 부모 NavigationSplitView의 detail 패널을 꽉 채움
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
        var newProfile = settings.profiles[index]
        newProfile.id = UUID()
        newProfile.name = "\(newProfile.name) (Copy)"
        newProfile.createdAt = Date()
        newProfile.updatedAt = Date()
        newProfile.isDefault = false
        settings.profiles.append(newProfile)
        selection = newProfile.id
        settings.activeProfileID = newProfile.id
    }
}
