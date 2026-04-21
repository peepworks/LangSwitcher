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
import AppKit
import UniformTypeIdentifiers

struct ExcludedAppsSettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                
                // 타이틀 및 설명 영역
                VStack(alignment: .leading, spacing: 5) {
                    Text(String(localized: "Excluded Apps")).font(.title2.bold())
                    Text(String(localized: "LangSwitcher will be completely disabled while using these apps. Useful for games or heavy software to prevent shortcut conflicts and input lag."))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 10)

                // 예외 앱 리스트 영역
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(String(localized: "Active Exclusions")).font(.headline)
                        Spacer()
                        Button(action: addExcludedApp) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .buttonStyle(.plain)
                        .padding(4)
                        .background(Color.secondary.opacity(0.2))
                        .clipShape(Circle())
                        .help(String(localized: "Add Application"))
                    }
                    
                    VStack(spacing: 0) {
                        if settings.excludedApps.isEmpty {
                            Text(String(localized: "No apps excluded. LangSwitcher is active everywhere."))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 20)
                                .frame(maxWidth: .infinity, alignment: .center)
                        } else {
                            ForEach(settings.excludedApps) { app in
                                // 🌟 기존 호출 방식 그대로 사용
                                ExcludedAppRow(app: app) {
                                    settings.excludedApps.removeAll { $0.id == app.id }
                                }
                                if app.id != settings.excludedApps.last?.id {
                                    Divider().padding(.horizontal, 15)
                                }
                            }
                        }
                    }
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                }
                
                Spacer()
            }
            .padding(.horizontal, 25)
            .padding(.vertical, 15)
        }
    }
    
    // 앱 선택 다이얼로그 호출
    private func addExcludedApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.prompt = String(localized: "Exclude")
        
        if panel.runModal() == .OK, let url = panel.url {
            guard let bundle = Bundle(url: url), let bundleId = bundle.bundleIdentifier else { return }
            let appName = url.deletingPathExtension().lastPathComponent
            
            // 중복 추가 방지
            if !settings.excludedApps.contains(where: { $0.bundleIdentifier == bundleId }) {
                settings.excludedApps.append(ExcludedApp(bundleIdentifier: bundleId, appName: appName))
            }
        }
    }
}

// 🌟 에러 해결: 구버전 macOS에서도 안전한 DispatchQueue 백그라운드 로딩으로 변경
struct ExcludedAppRow: View {
    let app: ExcludedApp
    let onDelete: () -> Void
    
    @State private var appIcon: NSImage? = nil

    var body: some View {
        HStack {
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: "app.dashed")
                    .resizable()
                    .frame(width: 24, height: 24)
                    .foregroundColor(.secondary)
            }
            
            Text(app.appName)
            Spacer()
            Button(action: onDelete) {
                Image(systemName: "trash").foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 10)
        .onAppear {
            loadIcon()
        }
    }
    
    // 백그라운드 스레드에서 아이콘을 안전하게 불러오는 함수
    private func loadIcon() {
        let bundleID = app.bundleIdentifier
        DispatchQueue.global(qos: .userInitiated).async {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            
            DispatchQueue.main.async {
                self.appIcon = icon
            }
        }
    }
}
