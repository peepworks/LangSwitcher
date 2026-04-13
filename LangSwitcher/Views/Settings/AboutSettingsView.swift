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

struct AboutSettingsView: View {
    @StateObject private var accManager = AccessibilityManager.shared
    @StateObject private var updateManager = UpdateManager.shared
    var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                Text(String(localized: "About & Support")).font(.title2.bold())
                VStack(alignment: .center, spacing: 10) {
                    if let appIcon = NSImage(named: NSImage.applicationIconName) {
                        Image(nsImage: appIcon).resizable().scaledToFit().frame(width: 80, height: 80).padding(.bottom, 10).shadow(color: Color.black.opacity(0.2), radius: 5, x: 0, y: 3)
                    } else {
                        Image(systemName: "keyboard.macwindow").font(.system(size: 50)).foregroundColor(.blue).padding(.bottom, 10)
                    }
                    Text("LangSwitcher").font(.title.bold())
                    Text("Version \(appVersion)").font(.subheadline).foregroundColor(.secondary)
                    
                    Button(action: { updateManager.checkForUpdates() }) { if updateManager.isChecking { ProgressView().controlSize(.small).frame(width: 100) } else { Text(String(localized: "Check for Updates...")).frame(width: 130) } }.padding(.top, 5)
                    .alert(Text(String(localized: "Update Available")), isPresented: $updateManager.showUpdateAlert) {
                        Button(String(localized: "Download"), role: .none) { if let url = updateManager.releaseURL { NSWorkspace.shared.open(url) } }
                        Button(String(localized: "Later"), role: .cancel) { }
                    } message: { Text("A new version (\(updateManager.latestVersion)) of LangSwitcher is available!") }
                    .alert(Text(String(localized: "Up to Date")), isPresented: $updateManager.showUpToDateAlert) { Button("OK", role: .cancel) { } } message: { Text(String(localized: "You are running the latest version of LangSwitcher.")) }
                }.frame(maxWidth: .infinity).padding(.vertical, 20).background(Color.secondary.opacity(0.05)).cornerRadius(12)
                
                VStack(alignment: .leading, spacing: 15) {
                    Text(String(localized: "Permissions")).font(.headline)
                    HStack {
                        if accManager.isTrusted { Label(String(localized: "Accessibility Granted"), systemImage: "checkmark.shield.fill").foregroundColor(.green) } else { Label(String(localized: "Accessibility Required"), systemImage: "exclamationmark.triangle.fill").foregroundColor(.orange) }
                        Spacer()
                        Button(String(localized: "Open System Settings")) { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!) }
                    }.padding().background(Color.secondary.opacity(0.05)).cornerRadius(8)
                }
            }.padding(30)
        }
    }
}
