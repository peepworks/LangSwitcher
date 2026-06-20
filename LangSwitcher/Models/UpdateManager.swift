//
//  UpdateManager.swift
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

import Foundation
import AppKit
import Combine
import SwiftUI

// SwiftUI 알럿 충돌을 방지하기 위한 단일 상태 정의
enum UpdateAlertItem: Identifiable, Equatable {
    case updateAvailable(version: String, url: URL)
    case upToDate
    case error(String)

    var id: String {
        switch self {
        case .updateAvailable(let v, _): return "available_\(v)"
        case .upToDate: return "uptodate"
        case .error(let m): return "error_\(m)"
        }
    }
}

@MainActor
class UpdateManager: ObservableObject {
    static let shared = UpdateManager()

    @Published var isChecking = false

    @AppStorage("isAutoUpdateEnabled") var isAutoUpdateEnabled: Bool = true
    @AppStorage("lastUpdateCheckDate") var lastUpdateCheckDate: Double = 0

    private let apiURL = "https://api.github.com/repos/peepworks/LangSwitcher/releases/latest"
    private var updateCheckTask: Task<Void, Never>?

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }

    @objc private func appWillTerminate() {
        stopAutoUpdateCheck()
    }

    func setupAutoUpdateCheck() {
        updateCheckTask?.cancel()

        updateCheckTask = Task {
            dprint("🚀 [UpdateManager] 백그라운드 자동 업데이트 루프 가동 준비 (프로덕션 모드).")
            
            do {
                // 앱 시동 직후 메인 UI 안착을 위한 0.8초 안전 지연선
                try await Task.sleep(for: .seconds(0.8))
            } catch {
                return
            }

            while !Task.isCancelled {
                self.checkIfAutoUpdateNeeded()

                do {
                    // 🌟 [프로덕션 세팅] 백그라운드 스레드를 1시간(3600초) 단위로 재우며 쿨다운을 유지합니다.
                    try await Task.sleep(for: .seconds(3600))
                } catch {
                    dprint("🛑 [UpdateManager] 취소 시그널 수신으로 인해 비동기 슬립 루프가 해제되었습니다.")
                    break
                }
            }
        }
    }

    func stopAutoUpdateCheck() {
        updateCheckTask?.cancel()
        updateCheckTask = nil
        dprint("✅ [UpdateManager] Auto update task successfully cancelled.")
    }

    private func checkIfAutoUpdateNeeded() {
        guard isAutoUpdateEnabled else { return }

        let now = Date().timeIntervalSince1970
        let twentyFourHours: TimeInterval = 24 * 60 * 60

        // 🌟 [프로덕션 세팅] 24시간 장부 가드 복구 완료
        if now - lastUpdateCheckDate >= twentyFourHours {
            checkForUpdates(isAutomatic: true)
        } else {
            #if DEBUG
            let remainingTime = twentyFourHours - (now - lastUpdateCheckDate)
            dprint("ℹ️ [UpdateManager] 24시간 대기열 유지 중. (잔여 시간: \(Int(remainingTime))초)")
            #endif
        }
    }

    func checkForUpdates(isAutomatic: Bool = false) {
        guard !isChecking else { return }

        self.isChecking = true

        guard let url = URL(string: apiURL) else {
            self.isChecking = false
            self.displaySystemAlert(for: .error("Invalid URL Blueprint"), isAutomatic: isAutomatic)
            return
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let appName = "LangSwitcher"
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let userAgentString = "\(appName)/\(currentVersion) (Macintosh; Intel Mac OS X)"

        request.setValue(userAgentString, forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

        Task {
            do {
                dprint("📡 [UpdateManager] GitHub Releases 원격 저장소 패킷 요청...")
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    self.isChecking = false
                    self.displaySystemAlert(for: .error("Invalid Network Response Spec"), isAutomatic: isAutomatic)
                    return
                }

                if httpResponse.statusCode == 403 {
                    self.isChecking = false
                    dprint("🚨 [UpdateManager] GitHub API Rate Limit (403).")
                    self.displaySystemAlert(for: .error("GitHub API access restricted (403)."), isAutomatic: isAutomatic)
                    return
                }

                guard httpResponse.statusCode == 200 else {
                    self.isChecking = false
                    dprint("🚨 [UpdateManager] Status code: \(httpResponse.statusCode)")
                    self.displaySystemAlert(for: .error("Unexpected response (Status: \(httpResponse.statusCode))."), isAutomatic: isAutomatic)
                    return
                }

                struct GitHubRelease: Codable {
                    let tagName: String
                    let htmlUrl: String
                    enum CodingKeys: String, CodingKey {
                        case tagName = "tag_name"
                        case htmlUrl = "html_url"
                    }
                }

                let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                let fetchedVersion = release.tagName.replacingOccurrences(of: "v", with: "")

                self.lastUpdateCheckDate = Date().timeIntervalSince1970
                self.isChecking = false
                
                guard let releaseURL = URL(string: release.htmlUrl) else { return }

                // 🌟 [프로덕션 세팅] 버전 정밀 비교 로직 복구 완료
                if fetchedVersion.compare(currentVersion, options: .numeric) == .orderedDescending {
                    dprint("✨ [UpdateManager] New version available: \(fetchedVersion) (Current: \(currentVersion))")
                    self.displaySystemAlert(for: .updateAvailable(version: fetchedVersion, url: releaseURL), isAutomatic: isAutomatic)
                } else {
                    dprint("✅ [UpdateManager] LangSwitcher is up to date. (Current: \(currentVersion))")
                    if !isAutomatic { self.displaySystemAlert(for: .upToDate, isAutomatic: isAutomatic) }
                }

            } catch {
                self.isChecking = false
                dprint("❌ [UpdateManager] Update check failed: \(error.localizedDescription)")
                self.displaySystemAlert(for: .error("Failed to fetch or parse GitHub release data."), isAutomatic: isAutomatic)
            }
        }
    }
    
    // 🌟 AppKit 네이티브 알럿 렌더러 (상태 의존성 탈출 완료본)
    private func displaySystemAlert(for item: UpdateAlertItem, isAutomatic: Bool) {
        if isAutomatic {
            if case .upToDate = item { return }
            if case .error = item { return }
        }

        let alert = NSAlert()
        alert.messageText = ""
        alert.informativeText = ""
        alert.icon = NSImage(size: NSSize(width: 1, height: 1))

        let title: String
        let message: String
        var downloadURL: URL? = nil

        switch item {
        case .updateAvailable(let version, let url):
            title = String(localized: "Update Available")
            message = String(localized: "A new version (\(version)) of LangSwitcher is available!")
            downloadURL = url
            alert.addButton(withTitle: String(localized: "Download"))
            alert.addButton(withTitle: String(localized: "Later"))

        case .upToDate:
            title = String(localized: "Up to Date")
            message = String(localized: "You are running the latest version of LangSwitcher.")
            alert.addButton(withTitle: String(localized: "OK"))

        case .error(let msg):
            title = String(localized: "Update Check Failed")
            message = msg
            alert.addButton(withTitle: String(localized: "OK"))
        }

        for button in alert.buttons {
            button.focusRingType = .none
        }

        let rootView = VStack(spacing: 12) {
            if let appIcon = NSImage(named: NSImage.applicationIconName) {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 64, height: 64)
            }
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, -80)
        .padding(.bottom, 10)
        .frame(width: 280)

        let hostingController = NSHostingController(rootView: rootView)
        let targetSize = hostingController.sizeThatFits(in: NSSize(width: 280, height: 1000))
        hostingController.view.frame = NSRect(origin: .zero, size: targetSize)
        alert.accessoryView = hostingController.view

        NSApp.activate(ignoringOtherApps: true)

        let targetWindow = NSApp.windows.first { $0.title.contains("LangSwitcher Settings") } ?? NSApp.keyWindow

        if let window = targetWindow, window.isVisible {
            alert.beginSheetModal(for: window) { response in
                if response == .alertFirstButtonReturn, let url = downloadURL {
                    NSWorkspace.shared.open(url)
                }
            }
        } else {
            if alert.runModal() == .alertFirstButtonReturn, let url = downloadURL {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
