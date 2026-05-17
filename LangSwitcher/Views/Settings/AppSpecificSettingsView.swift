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

struct AppSpecificSettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared
    
    // 🌟 [수정] 현재 활성화된 프로필 페이로드 내부의 customApps를 검사하도록 수정
    var hasIncomplete: Bool {
        settings.activeProfile.payload.customApps.contains { $0.targetLanguage.isEmpty }
    }

    // 🌟 [추가] 구조체 연산 프로퍼티 내 캡슐화된 데이터 바인딩 통로 우회 구축
    private var payload: Binding<ProfileSettingsPayload> {
        Binding(
            get: { settings.activeProfile.payload },
            set: { settings.activeProfile.payload = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 🌟 1. 전역 프로필 컨텍스트 제어 헤더 추가
            ProfileHeaderView()

            // 🌟 2. 마스터 스위치 영역
            HStack {
                Text(String(localized: "App-Specific Keyboards")).font(.title2.bold())
                Spacer()
                // 🌟 [수정] 프로필 페이로드 내부 변수로 바인딩 대상 교체
                Toggle("", isOn: payload.isAppSpecificEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
            }.padding(.horizontal, 30).padding(.top, 15).padding(.bottom, 10)

            // 🌟 3. 스위치 상태에 따라 활성/비활성되는 영역
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Text(String(localized: "Automatically switch to a specific language when an app becomes active."))
                        .font(.subheadline).foregroundColor(.secondary)
                    Spacer()
                    Button(action: selectApp) {
                        Image(systemName: "plus.app.fill").foregroundColor(hasIncomplete ? .secondary.opacity(0.5) : .green)
                        Text(String(localized: "Add App")).foregroundColor(hasIncomplete ? .secondary.opacity(0.5) : .primary)
                    }.buttonStyle(.plain).disabled(hasIncomplete)
                }

                ScrollView {
                    VStack(spacing: 4) {
                        // 🌟 [수정] 현재 활성 프로필 기준으로 비어있는지 체크
                        if settings.activeProfile.payload.customApps.isEmpty {
                            Text(String(localized: "No apps configured.")).font(.subheadline).foregroundColor(.secondary).padding(.vertical, 20)
                        }

                        // 🌟 [수정] 안전하게 구조화된 프로필 Payload Binding 트리 구조 배열을 전달
                        ForEach(payload.customApps) { $app in
                            CustomAppRow(customApp: $app)
                        }
                    }.padding(15).frame(maxWidth: .infinity, alignment: .top)
                }
                .background(Color(NSColor.textBackgroundColor)).cornerRadius(8).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
            }
            .padding(.horizontal, 30).padding(.bottom, 30)
            // 🌟 [수정] 상태 종속성 타겟을 활성 프로필 내부 스위치 상태로 수정
            .opacity(settings.activeProfile.payload.isAppSpecificEnabled ? 1.0 : 0.5)
            .disabled(!settings.activeProfile.payload.isAppSpecificEnabled)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func selectApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.canChooseFiles = true

        if panel.runModal() == .OK, let url = panel.url {
            guard let bundle = Bundle(url: url), let bundleId = bundle.bundleIdentifier else { return }
            
            // 🌟 [수정] 중복 추가 방지 검사 및 추가 타겟을 활성 프로필 내부 배열로 이관
            if !settings.activeProfile.payload.customApps.contains(where: { $0.bundleIdentifier == bundleId }) {
                settings.activeProfile.payload.customApps.append(CustomApp(bundleIdentifier: bundleId, appName: url.deletingPathExtension().lastPathComponent, targetLanguage: ""))
            }
        }
    }
}

struct CustomAppRow: View {
    @Binding var customApp: CustomApp
    @ObservedObject private var settings = SettingsManager.shared
    @State private var appIcon: NSImage? = nil
    @State private var currentIconLoadID = UUID()

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                if let icon = appIcon {
                    Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                } else {
                    Image(systemName: "app.dashed").resizable().frame(width: 20, height: 20).foregroundColor(.secondary)
                }
                Text(customApp.appName).lineLimit(1)
            }
            Spacer()
            Picker("", selection: $customApp.targetLanguage) {
                Text(String(localized: "Select Language...")).tag("")
                ForEach(InputSourceManager.shared.availableKeyboards) { keyboard in Text(keyboard.name).tag(keyboard.id) }
            }.pickerStyle(.menu).labelsHidden().frame(width: 140)
            
            // 🌟 [수정] 삭제 타겟 경로를 활성 프로필의 페이로드 내부 인스턴스로 바인딩 변경
            Button(action: { settings.activeProfile.payload.customApps.removeAll { $0.id == customApp.id } }) {
                Image(systemName: "trash").foregroundColor(.red)
            }
            .buttonStyle(.plain).padding(.leading, 5)
        }
        .padding(.horizontal, 10).padding(.vertical, 2)
        .onAppear { loadIcon() }
        .onChange(of: customApp.bundleIdentifier) { _ in loadIcon() }
    }

    private func loadIcon() {
        let bundleID = customApp.bundleIdentifier
        guard !bundleID.isEmpty else { return }
        
        let loadID = UUID()
        self.currentIconLoadID = loadID
        
        DispatchQueue.global(qos: .userInitiated).async {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            
            DispatchQueue.main.async {
                if self.currentIconLoadID == loadID {
                    self.appIcon = icon
                }
            }
        }
    }
}
