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

struct ProfileHeaderView: View {
    @ObservedObject var settings = SettingsManager.shared
    
    var body: some View {
        HStack(spacing: 12) {
            Text(String(localized: "Current Profile:"))
                .font(.headline)
            
            Picker("", selection: $settings.activeProfileID) {
                ForEach(settings.profiles) { profile in
                    Text(profile.name).tag(profile.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 180)
            
            // 🌟 [추가] 빠른 액션 버튼 그룹
            HStack(spacing: 8) {
                Button(action: {
                    let newProfile = SettingsProfile(
                        id: UUID(), name: String(localized: "New Profile"), note: "", isDefault: false,
                        createdAt: Date(), updatedAt: Date(), payload: settings.activeProfile.payload
                    )
                    settings.profiles.append(newProfile)
                    settings.activeProfileID = newProfile.id
                }) {
                    Image(systemName: "plus.app")
                }
                .buttonStyle(.plain)
                .help(String(localized: "Create New Profile"))
                
                Button(action: {
                    var newProfile = settings.activeProfile
                    newProfile.id = UUID()
                    newProfile.name = "\(newProfile.name) (Copy)"
                    settings.profiles.append(newProfile)
                    settings.activeProfileID = newProfile.id
                }) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .help(String(localized: "Duplicate Current Profile"))
                
                Button(action: {
                    settings.selectedTab = .profiles
                }) {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .help(String(localized: "Manage Profiles"))
            }
            .foregroundColor(.secondary)
            
            Spacer()
            
            Text(String(localized: "Changes are saved to this profile."))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 15)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
        .padding(.bottom, 10)
    }
}
