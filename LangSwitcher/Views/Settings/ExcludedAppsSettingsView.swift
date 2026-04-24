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
                
                // 타이틀 및 토글 스위치 영역
                HStack(alignment: .center) {
                    Text(String(localized: "Excluded Apps")).font(.title2.bold())
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { settings.isExcludedAppsEnabled },
                        set: { settings.isExcludedAppsEnabled = $0 }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                }
                
                // 설명 텍스트
                Text(String(localized: "LangSwitcher will be completely disabled while using these apps. Useful for games or heavy software to prevent shortcut conflicts and input lag."))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 10)
                
                // 예외 앱 리스트 영역
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(String(localized: "Active Exclusions")).font(.headline)
                        Spacer()
                        
                        // 추가 버튼
                        Button(action: addExcludedApp) {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.blue)
                                Text(String(localized: "Add App"))
                                    .font(.body)
                            }
                            .foregroundColor(.primary)
                        }
                        .buttonStyle(.plain)
                        .help(String(localized: "Add Application"))
                        .disabled(!settings.isExcludedAppsEnabled)
                    }
                    
                    VStack(spacing: 0) {
                        if settings.excludedApps.isEmpty {
                            Text(String(localized: "No apps excluded. LangSwitcher is active everywhere."))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 20)
                                .frame(maxWidth: .infinity, alignment: .center)
                        } else {
                            ForEach($settings.excludedApps) { $app in
                                ExcludedAppRow(excludedApp: $app)
                                
                                if app.id != settings.excludedApps.last?.id {
                                    // 🌟 [수정됨] 구분선(Divider) 위아래 여백을 2에서 4로 늘림
                                    Divider()
                                        .padding(.horizontal, 15)
                                        .padding(.vertical, 4)
                                }
                            }
                        }
                    }
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                }
                .opacity(settings.isExcludedAppsEnabled ? 1.0 : 0.5)
                
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

struct ExcludedAppRow: View {
    @Binding var excludedApp: ExcludedApp
    @ObservedObject private var settings = SettingsManager.shared
    @State private var appIcon: NSImage? = nil
    
    // 현재 진행 중인 아이콘 로드 작업을 식별하는 고유 ID
    @State private var currentIconLoadID = UUID()

    var body: some View {
        HStack(spacing: 8) {
            if let icon = appIcon {
                Image(nsImage: icon).resizable().frame(width: 20, height: 20)
            } else {
                Image(systemName: "app.dashed").resizable().frame(width: 20, height: 20).foregroundColor(.secondary)
            }
            Text(excludedApp.appName).lineLimit(1)
            Spacer()
            
            Button(action: { settings.excludedApps.removeAll { $0.id == excludedApp.id } }) {
                Image(systemName: "trash").foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        // 🌟 [수정됨] 행(Row) 자체의 위아래 여백을 5에서 8로 늘려 더욱 쾌적하게 확보
        .padding(.horizontal, 10).padding(.vertical, 8)
        .onAppear { loadIcon() }
        .onChange(of: excludedApp.bundleIdentifier) { _ in loadIcon() }
    }

    private func loadIcon() {
        let bundleID = excludedApp.bundleIdentifier
        guard !bundleID.isEmpty else { return }
        
        // 매 호출마다 새로운 고유 ID(번호표) 발급 및 저장
        let loadID = UUID()
        self.currentIconLoadID = loadID
        
        DispatchQueue.global(qos: .userInitiated).async {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            
            DispatchQueue.main.async {
                // 현재 저장된 최신 ID와 내 ID가 일치할 때만 UI 업데이트 (덮어쓰기 방어)
                if self.currentIconLoadID == loadID {
                    self.appIcon = icon
                }
            }
        }
    }
}
