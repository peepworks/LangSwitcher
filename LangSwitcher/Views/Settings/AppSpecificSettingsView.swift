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

struct AppSpecificSettingsView: View {
    @StateObject private var settings = SettingsManager.shared
    var hasIncomplete: Bool { settings.customApps.contains { $0.targetLanguage.isEmpty } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(String(localized: "App-Specific Keyboards")).font(.title2.bold())
                Spacer()
                Button(action: selectApp) {
                    Image(systemName: "plus.app.fill").foregroundColor(hasIncomplete ? .secondary.opacity(0.5) : .green)
                    Text(String(localized: "Add App")).foregroundColor(hasIncomplete ? .secondary.opacity(0.5) : .primary)
                }.buttonStyle(.plain).disabled(hasIncomplete)
            }.padding(.horizontal, 30).padding(.top, 30).padding(.bottom, 15)
            
            ScrollView {
                VStack(spacing: 10) {
                    if settings.customApps.isEmpty { Text(String(localized: "No apps configured.")).font(.subheadline).foregroundColor(.secondary).padding(.vertical, 20) }
                    ForEach($settings.customApps) { $app in CustomAppRow(customApp: $app) { settings.customApps.removeAll { $0.id == app.id } } }
                }.padding(15).frame(maxWidth: .infinity, alignment: .top)
            }
            .background(Color(NSColor.textBackgroundColor)).cornerRadius(8).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
            .padding(.horizontal, 30).padding(.bottom, 30)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    
    private func selectApp() {
        let panel = NSOpenPanel(); panel.directoryURL = URL(fileURLWithPath: "/Applications"); panel.allowedContentTypes = [.application]; panel.canChooseFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            guard let bundle = Bundle(url: url), let bundleId = bundle.bundleIdentifier else { return }
            if !settings.customApps.contains(where: { $0.bundleIdentifier == bundleId }) { settings.customApps.append(CustomApp(bundleIdentifier: bundleId, appName: url.deletingPathExtension().lastPathComponent, targetLanguage: "")) }
        }
    }
}
