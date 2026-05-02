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
    @ObservedObject private var accManager = AccessibilityManager.shared
    @ObservedObject private var updateManager = UpdateManager.shared
    @ObservedObject private var settings = SettingsManager.shared

    var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown" }

    var body: some View {
        ScrollView(showsIndicators: false) {
            // 🌟 [핵심 수정 1] 전체 간격을 20 -> 15로 줄여 수직 공간을 확보합니다.
            VStack(alignment: .leading, spacing: 15) {
                Text(String(localized: "About & Support"))
                    .font(.title2.bold())
                    // 상하단 패딩 조정은 VStack 밖에서 일괄 처리하므로 -10 패딩은 제거했습니다.

                // 1. 앱 정보 및 업데이트 확인 섹션
                VStack(alignment: .center, spacing: 8) { // 간격 10 -> 8
                    if let appIcon = NSImage(named: NSImage.applicationIconName) {
                        Image(nsImage: appIcon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 70, height: 70) // 🌟 [핵심 수정 2] 아이콘 크기 80 -> 70
                            .padding(.bottom, 8)
                            .shadow(color: Color.black.opacity(0.2), radius: 5, x: 0, y: 3)
                    } else {
                        Image(systemName: "keyboard.macwindow")
                            .font(.system(size: 45))
                            .foregroundColor(.blue)
                            .padding(.bottom, 8)
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
                .padding(.vertical, 15) // 내부 상하 여백 20 -> 15
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(12)

                // 2. Permissions 섹션
                VStack(alignment: .leading, spacing: 10) {
                    Text(String(localized: "Permissions")).font(.headline)
                    
                    // --- 1. 접근성(Accessibility) 권한 ---
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
                    .padding(12) // 16(기본) -> 12
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)
                    
                    // --- 2. 브라우저 자동화(Automation) 권한 ---
                    if settings.isBrowserTabMemoryEnabled {
                        VStack(spacing: 8) { // 12 -> 8
                            
                            // Chrome 자동화
                            HStack {
                                if accManager.isChromeAutomationTrusted {
                                    Label(String(localized: "Chrome Automation Granted"), systemImage: "checkmark.shield.fill")
                                        .foregroundColor(.green)
                                } else {
                                    Label(String(localized: "Chrome Automation Required"), systemImage: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                }
                                Spacer()
                                Button(String(localized: "Open System Settings")) {
                                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
                                }
                            }
                            
                            Divider()
                            
                            // Safari 자동화
                            HStack {
                                if accManager.isSafariAutomationTrusted {
                                    Label(String(localized: "Safari Automation Granted"), systemImage: "checkmark.shield.fill")
                                        .foregroundColor(.green)
                                } else {
                                    Label(String(localized: "Safari Automation Required"), systemImage: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                }
                                Spacer()
                                Button(String(localized: "Open System Settings")) {
                                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
                                }
                            }
                            
                            Text(String(localized: "In System Settings -> Automation, expand 'LangSwitcher' and turn on Chrome/Safari. If they are not visible, please try switching tabs in your browser first."))
                                .font(.caption2) // 🌟 폰트 사이즈를 조금 줄임
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 4)
                        }
                        .padding(12) // 16(기본) -> 12
                        .background(Color.secondary.opacity(0.05))
                        .cornerRadius(8)
                    }
                }

                // 3. Debug Logs 섹션
                VStack(alignment: .leading, spacing: 8) { // 10 -> 8
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
                    .padding(12) // 16(기본) -> 12
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)
                }
            }
            // 🌟 [핵심 수정 3] 기존 .padding(30)을 방향별로 나누어 상단 여백을 극적으로 줄였습니다.
            .padding(.horizontal, 30) // 좌우 여백은 기존 유지
            .padding(.bottom, 30)     // 하단 여백 유지
            .padding(.top, 10)        // 상단 여백을 30 -> 10으로 줄임
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
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
                    title: Text(String(localized: "Update Check Failed")),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

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
