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

struct AboutSettingsView: View {
    @StateObject private var accManager = AccessibilityManager.shared
    
    // 🌟 에러 원인 해결: 싱글톤 인스턴스는 @ObservedObject로 관찰해야 합니다.
    @ObservedObject private var updateManager = UpdateManager.shared
    @StateObject private var settings = SettingsManager.shared

    var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                Text(String(localized: "About & Support")).font(.title2.bold())

                // 1. 앱 정보 및 업데이트 확인
                VStack(alignment: .center, spacing: 15) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 70, height: 70)
                    
                    VStack(spacing: 4) {
                        Text("LangSwitcher").font(.headline)
                        Text("Version \(appVersion)").font(.subheadline).foregroundColor(.secondary)
                    }
                    
                    Button(action: {
                        updateManager.checkForUpdates()
                    }) {
                        if updateManager.isChecking {
                            ProgressView().controlSize(.small).frame(width: 120)
                        } else {
                            Text(String(localized: "Check for Updates...")).frame(width: 120)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)

                // 2. Permissions 섹션 (이전 코드 동일)
                PermissionSection(accManager: accManager)

                // 3. Debug Logs 섹션 (이전 코드 동일)
                DebugLogSection(settings: settings, appVersion: appVersion)
            }
            .padding(25)
            // 🌟 뷰 최상단에 하나의 알럿만 바인딩 (절대 씹히지 않음)
            .alert(item: $updateManager.activeAlert) { item in
                switch item {
                case .updateAvailable(let version, let url):
                    return Alert(
                        title: Text(String(localized: "Update Available")),
                        message: Text("A new version (\(version)) of LangSwitcher is available!"),
                        primaryButton: .default(Text(String(localized: "Download"))) { NSWorkspace.shared.open(url) },
                        secondaryButton: .cancel(Text(String(localized: "Later")))
                    )
                case .upToDate:
                    return Alert(
                        title: Text(String(localized: "Up to Date")),
                        message: Text(String(localized: "You are running the latest version of LangSwitcher.")),
                        dismissButton: .default(Text("OK"))
                    )
                case .error(let message):
                    // 🌟 통신 실패 원인을 보여줍니다.
                    return Alert(
                        title: Text("Update Check Failed"),
                        message: Text(message),
                        dismissButton: .default(Text("OK"))
                    )
                }
            }
        }
    }
}

// MARK: - 서브 뷰 모듈화 (기존 코드 유지)

struct PermissionSection: View {
    @ObservedObject var accManager: AccessibilityManager
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Permissions")).font(.headline)
            HStack {
                Label(accManager.isTrusted ? String(localized: "Accessibility Granted") : String(localized: "Accessibility Required"),
                      systemImage: accManager.isTrusted ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(accManager.isTrusted ? .green : .orange)
                Spacer()
                Button(String(localized: "Open System Settings")) {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }.controlSize(.small)
            }.padding(12).background(Color.secondary.opacity(0.05)).cornerRadius(8)
        }
    }
}

struct DebugLogSection: View {
    @ObservedObject var settings: SettingsManager
    let appVersion: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Debug")).font(.headline)
            VStack(alignment: .leading, spacing: 8) {
                Button(action: downloadDebugLogs) {
                    Label(String(localized: "Download Debug Logs"), systemImage: "doc.text.below.ecg").frame(maxWidth: .infinity)
                }.buttonStyle(.bordered).disabled(settings.recentLogs.isEmpty)
                Text(String(localized: "※ The debug log includes application names for diagnosis.")).font(.system(size: 10)).foregroundColor(.secondary)
            }.padding(12).background(Color.secondary.opacity(0.05)).cornerRadius(8)
        }
    }
    
    private func downloadDebugLogs() {
        let savePanel = NSSavePanel(); savePanel.allowedContentTypes = [.plainText]
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let fileDateFormatter = DateFormatter(); fileDateFormatter.dateFormat = "yyyyMMdd_HHmm"
        savePanel.nameFieldStringValue = "LangSwitcher_Debug_\(fileDateFormatter.string(from: Date())).txt"
        
        if savePanel.runModal() == .OK, let url = savePanel.url {
            let header = "LangSwitcher Debug Log\nGenerated: \(formatter.string(from: Date()))\nVersion: \(appVersion)\n--------------------------\n\n"
            let logBody = settings.recentLogs.map { log in
                let time = formatter.string(from: log.timestamp)
                let result = log.result == .success ? "✅" : "❌"
                return "[\(time)] \(result) Rule: \(log.appliedRule) | App: \(log.targetApp) | Out: \(log.finalInputSource) | Reason: \(log.failureReason.rawValue)"
            }.joined(separator: "\n")
            do { try (header + logBody).write(to: url, atomically: true, encoding: .utf8) } catch { print(error) }
        }
    }
}
