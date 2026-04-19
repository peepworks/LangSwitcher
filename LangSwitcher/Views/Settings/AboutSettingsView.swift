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

//
//  AboutSettingsView.swift
//  LangSwitcher
//
//  Copyright (C) 2026 peepboy
//

import SwiftUI
import UniformTypeIdentifiers

struct AboutSettingsView: View {
    @StateObject private var accManager = AccessibilityManager.shared
    @ObservedObject private var updateManager = UpdateManager.shared // 🌟 알럿 씹힘 방지를 위한 ObservedObject 유지
    @StateObject private var settings = SettingsManager.shared

    var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                Text(String(localized: "About & Support")).font(.title2.bold())

                // 1. 앱 정보 및 업데이트 확인 섹션 (🌟 배경 및 그림자 디자인 복구 완료)
                VStack(alignment: .center, spacing: 10) {
                    if let appIcon = NSImage(named: NSImage.applicationIconName) {
                        Image(nsImage: appIcon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 80, height: 80)
                            .padding(.bottom, 10)
                            .shadow(color: Color.black.opacity(0.2), radius: 5, x: 0, y: 3)
                    } else {
                        Image(systemName: "keyboard.macwindow")
                            .font(.system(size: 50))
                            .foregroundColor(.blue)
                            .padding(.bottom, 10)
                    }
                    
                    Text("LangSwitcher").font(.title.bold())
                    Text("Version \(appVersion)").font(.subheadline).foregroundColor(.secondary)
                    
                    Button(action: {
                        updateManager.checkForUpdates()
                    }) {
                        if updateManager.isChecking {
                            ProgressView().controlSize(.small).frame(width: 130)
                        } else {
                            Text(String(localized: "Check for Updates...")).frame(width: 130)
                        }
                    }
                    .padding(.top, 5)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(Color.secondary.opacity(0.05)) // 🌟 배경색 복구
                .cornerRadius(12) // 🌟 둥근 모서리 복구

                // 2. Permissions 섹션
                VStack(alignment: .leading, spacing: 10) {
                    Text(String(localized: "Permissions")).font(.headline)
                    HStack {
                        if accManager.isTrusted {
                            Label(String(localized: "Accessibility Granted"), systemImage: "checkmark.shield.fill")
                                .foregroundColor(.green)
                        } else {
                            Label(String(localized: "Accessibility Required"), systemImage: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                        }
                        Spacer()
                        Button(String(localized: "Open System Settings")) {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)
                }

                // 3. Debug Logs 섹션
                VStack(alignment: .leading, spacing: 10) {
                    Text(String(localized: "Debug")).font(.headline)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(String(localized: "If you encounter issues, please download the debug logs and share them with the developer."))
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Button(action: downloadDebugLogs) {
                            Label(String(localized: "Download Debug Logs"), systemImage: "doc.text.below.ecg")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(settings.recentLogs.isEmpty)
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)
                }
            }
            .padding(30)
            // 🌟 단일 알럿 상태 관찰 (절대 씹히지 않음)
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
                    return Alert(
                        title: Text("Update Check Failed"),
                        message: Text(message),
                        dismissButton: .default(Text("OK"))
                    )
                }
            }
        }
    }

    // 🌟 로그 파일 생성 및 저장 함수
    private func downloadDebugLogs() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmm"
        savePanel.nameFieldStringValue = "LangSwitcher_DebugLog_\(formatter.string(from: Date())).txt"
        savePanel.prompt = String(localized: "Save")

        if savePanel.runModal() == .OK, let url = savePanel.url {
            let logHeader = "LangSwitcher Debug Log\nGenerated: \(Date().description)\nApp Version: \(appVersion)\n----------------------------------\n\n"

            let logEntries = settings.recentLogs.map { log in
                let timeStr = formatter.string(from: log.timestamp)
                let resultMark = log.result == .success ? "✅" : "❌"
                return "[\(timeStr)] \(resultMark) Rule: \(log.appliedRule) | Target: \(log.targetApp) | Output: \(log.finalInputSource) | Reason: \(log.failureReason.rawValue)"
            }.joined(separator: "\n")

            let fullLogContent = logHeader + logEntries

            do {
                try fullLogContent.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                print("Failed to save debug logs: \(error)")
            }
        }
    }
}
