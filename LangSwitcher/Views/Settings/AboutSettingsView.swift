//
//  AboutSettingsView.swift
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
import UniformTypeIdentifiers

struct AboutSettingsView: View {
    private static let debugLogFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    } ()
    
    @ObservedObject private var accManager = AccessibilityManager.shared
    @ObservedObject private var updateManager = UpdateManager.shared
    @ObservedObject private var settings = SettingsManager.shared

    var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown" }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 15) {
                Text(String(localized: "About & Support"))
                    .font(.title2.bold())

                // 1. 앱 정보 및 업데이트 확인 섹션
                VStack(alignment: .center, spacing: 8) {
                    if let appIcon = NSImage(named: NSImage.applicationIconName) {
                        Image(nsImage: appIcon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 70, height: 70)
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
                .padding(.vertical, 15)
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(12)

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
                    .padding(12)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)
                    
                    if settings.isBrowserTabMemoryEnabled {
                        VStack(spacing: 8) {
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
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 4)
                        }
                        .padding(12)
                        .background(Color.secondary.opacity(0.05))
                        .cornerRadius(8)
                    }
                }

                // 4. Debug Logs 섹션
                VStack(alignment: .leading, spacing: 8) {
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
                    .padding(12)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 30)
            .padding(.top, 10)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func downloadDebugLogs() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]
        savePanel.prompt = String(localized: "Save")

        savePanel.nameFieldStringValue = "LangSwitcher_DebugLog_\(Self.debugLogFormatter.string(from: Date())).txt"
        
        NSApp.activate(ignoringOtherApps: true)

        if savePanel.runModal() == .OK, let url = savePanel.url {
            let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
            let memoryUsage = getCurrentMemoryUsageMB()
            let memoryString = memoryUsage != nil ? String(format: "%.2f MB", memoryUsage!) : "Unknown"

            let logHeader = """
            ==================================
            LangSwitcher Debug Log
            ==================================
            Generated     : \(Date().description)
            App Version   : \(appVersion)
            macOS Version : \(osVersion)
            Memory Usage  : \(memoryString)
            ==================================\n\n
            """

            let logEntries = settings.recentLogs.map { log in
                let timeStr = Self.debugLogFormatter.string(from: log.timestamp)
                let resultMark = log.result == .success ? "✅" : "❌"
                
                return "[\(timeStr)] \(resultMark) Rule: \(log.appliedRule) | Target: \(log.targetApp) | Output: \(log.finalInputSource) | Reason: \(log.failureReason.rawValue)"
            }.joined(separator: "\n")

            let fullLogContent = logHeader + logEntries

            do {
                try fullLogContent.write(to: url, atomically: true, encoding: String.Encoding.utf8)
            } catch {
                dprint("Failed to save debug logs: \(error)")
            }
        }
    }

    // 🌟 [우주 방어 수복 완료]
    // 기존의 유령 가상 메모리가 합산되던 무겁고 왜곡된 MACH_TASK_BASIC_INFO 수식을 전면 철거(소각)하고,
    // MemoryMonitor가 Mach 커널로부터 직접 추출해 오는 공인 RSS 물리 풋프린트 계통과 칼같이 도킹 연동합니다.
    private func getCurrentMemoryUsageMB() -> Double? {
        guard let bytes = MemoryMonitor.getCurrentPhysicalFootprint() else { return nil }
        
        // 정밀 1024 이진 스케일링을 통해 macOS 활성 상태 보기 앱 수치와 100% 일치 정산
        return Double(bytes) / 1024.0 / 1024.0
    }
}
