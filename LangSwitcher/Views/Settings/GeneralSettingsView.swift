//
//  GeneralSettingsView.swift
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
import ServiceManagement

struct GeneralSettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var updateManager = UpdateManager.shared
    
    // 🌟 [수복 포인트 1] 초기화 시점에 SMAppService 동기 커널 시스템 콜을 절대 호출하지 않도록 분리 선언
    @State private var isAutoLaunchEnabled: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "General")).font(.title2.bold())

                // 1. 시작 및 옵션 섹션
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Startup & Options")).font(.headline)
                    VStack(spacing: 0) {
                        // 로그인 시 자동 실행
                        SettingToggleRow(title: String(localized: "Launch at login"), isOn: $isAutoLaunchEnabled)
                            .onChange(of: isAutoLaunchEnabled) { newValue in
                                // 🌟 [수복 포인트 2] 스위치 변경 시 시스템 콜 오버헤드를 백그라운드 분기 처리하여 프리즈 원천 차단
                                DispatchQueue.global(qos: .userInitiated).async {
                                    do {
                                        if newValue {
                                            try SMAppService.mainApp.register()
                                        } else {
                                            try SMAppService.mainApp.unregister()
                                        }
                                        dprint("🚀 [SMAppService] 로그인 시 자동 실행 상태가 성공적으로 정산되었습니다: \(newValue)")
                                    } catch {
                                        dprint("❌ [SMAppService] 자동 실행 등록/해제 집행 실패: \(error)")
                                        // 실패 시 UI 롤백을 위해 메인 스레드로 홉
                                        DispatchQueue.main.async {
                                            self.isAutoLaunchEnabled = (SMAppService.mainApp.status == .enabled)
                                        }
                                    }
                                }
                            }

                        Divider().padding(.horizontal, 15)

                        // 자동 업데이트 확인
                        SettingToggleRow(title: String(localized: "Automatically check for updates"), isOn: $updateManager.isAutoUpdateEnabled)

                        Divider().padding(.horizontal, 15)

                        // 시각적 피드백 (화면 중앙 큰 알림)
                        SettingToggleRow(
                            title: String(localized: "Show visual feedback on center"),
                            isOn: $settings.showVisualFeedback
                        )

                        Divider().padding(.horizontal, 15)

                        // 커서 위치 미니 플래그
                        SettingToggleRow(
                            title: String(localized: "Show mini flag near text cursor"),
                            isOn: $settings.isCursorHUDEnabled
                        )

                        Divider().padding(.horizontal, 15)

                        // 노치 엣지 글로우 옵션
                        SettingToggleRow(
                            title: String(localized: "Enable Notch Edge Glow"),
                            isOn: $settings.isEdgeGlowEnabled
                        )

                        Text(String(localized: "Displays a brief overlay indicating the new language."))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineSpacing(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 15)
                            .padding(.bottom, 12)
                            .padding(.top, -2)

                        // 사운드 및 햅틱 피드백 토글 스위치
                        Divider().padding(.horizontal, 15)

                        SettingToggleRow(title: String(localized: "Play sound on switch"), isOn: $settings.isSoundFeedbackEnabled)

                        Divider().padding(.horizontal, 15)

                        SettingToggleRow(title: String(localized: "Haptic feedback on switch"), isOn: $settings.isHapticFeedbackEnabled)

                        Divider().padding(.horizontal, 15)

                        // 규칙 테스트 모드
                        SettingToggleRow(title: String(localized: "Rule Test"), isOn: $settings.isTestMode)
                    }
                    .background(Color(NSColor.textBackgroundColor)).cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                }

                // 2. 입력 소스 전환 키 섹션
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Input Source Toggle Key")).font(.headline)
                    VStack(spacing: 0) {
                        ToggleShortcutRow()
                    }
                    .background(Color(NSColor.textBackgroundColor)).cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                }

                // 3. 기본 단축키 섹션
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Default Shortcuts")).font(.headline)
                    VStack(spacing: 0) {
                        LanguageRow(title: "⌃ Control + Space", isActive: $settings.isCtrlActive, selection: $settings.ctrlLang)
                        Divider().padding(.horizontal, 15)
                        LanguageRow(title: "⌘ Command + Space", isActive: $settings.isCmdActive, selection: $settings.cmdLang)
                        Divider().padding(.horizontal, 15)
                        LanguageRow(title: "⌥ Option + Space", isActive: $settings.isOptActive, selection: $settings.optLang)
                    }
                    .background(Color(NSColor.textBackgroundColor)).cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                }

            }
            .padding(.horizontal, 25)
            .padding(.vertical, 12)
        }
        // 🌟 [수복 포인트 3] 뷰가 화면에 안착하여 스레드가 진정된 시점에 안전하게 넌블로킹으로 자동 실행 상태 인출 기입
        .onAppear {
            let status = SMAppService.mainApp.status
            self.isAutoLaunchEnabled = (status == .enabled)
            dprint("ℹ️ [GeneralSettingsView] 자동 실행 커널 등록 상태 안착 정산 완료: \(isAutoLaunchEnabled)")
        }
    }
}

struct LanguageRow: View {
    let title: String
    @Binding var isActive: Bool
    @Binding var selection: String
    @ObservedObject private var inputManager = InputSourceManager.shared

    var body: some View {
        HStack {
            Toggle("", isOn: $isActive)
                .toggleStyle(.checkbox) // 네모난 체크박스 스타일
                .labelsHidden()
            
            Text(title).font(.body).padding(.leading, 5)
            Spacer(minLength: 20)

            ZStack(alignment: .trailing) {
                if isActive {
                    Picker("", selection: $selection) {
                        if selection.isEmpty { Text(String(localized: "Select Keyboard")).tag("") }
                        ForEach(inputManager.availableKeyboards) { kb in Text(kb.name).tag(kb.id) }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                } else {
                    Text(String(localized: "Disabled")).font(.subheadline).foregroundColor(.secondary).padding(.trailing, 16)
                }
            }
            .frame(width: 130, alignment: .trailing)
            .padding(.trailing, -3)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 6)
    }
}
