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

// 🌟 [최종 수복: Swift 6 전역 격리 수립]
@MainActor
class UpdateManager: ObservableObject {
    static let shared = UpdateManager()

    @Published var isChecking = false
    @Published var activeAlert: UpdateAlertItem?
    
    @AppStorage("isAutoUpdateEnabled") var isAutoUpdateEnabled: Bool = true
    @AppStorage("lastUpdateCheckDate") var lastUpdateCheckDate: Double = 0

    private let apiURL = "https://api.github.com/repos/peepworks/LangSwitcher/releases/latest"
    
    // 🌟 [최종 수복: RunLoop 종속성 타이머 탈출]
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

    /// 앱 실행 시 백그라운드 영구 순환 체크 엔진을 가동합니다.
    func setupAutoUpdateCheck() {
        updateCheckTask?.cancel() // 중복 실행 원천 차단
        
        updateCheckTask = Task {
            while !Task.isCancelled {
                self.checkIfAutoUpdateNeeded()
                
                do {
                    // 1시간(3600초)마다 스레드 블로킹 없이 정밀 대기
                    try await Task.sleep(nanoseconds: 3600 * 1_000_000_000)
                } catch {
                    // 외부 가드 취소(App 종료 등) 시에만 루프를 깔끔하게 브레이크
                    break
                }
            }
        }
    }

    /// 예약되어 있던 업데이트 감시 태스크를 완전히 소각합니다.
    func stopAutoUpdateCheck() {
        updateCheckTask?.cancel()
        updateCheckTask = nil
        #if DEBUG
        dprint("✅ [UpdateManager] Auto update task successfully cancelled.")
        #endif
    }

    private func checkIfAutoUpdateNeeded() {
        guard isAutoUpdateEnabled else { return }

        let now = Date().timeIntervalSince1970
        let twentyFourHours: TimeInterval = 24 * 60 * 60

        if now - lastUpdateCheckDate >= twentyFourHours {
            checkForUpdates(isAutomatic: true)
        }
    }

    /// GitHub Releases 코어를 통해 최신 릴리즈 정보를 분석합니다.
    func checkForUpdates(isAutomatic: Bool = false) {
        guard !isChecking else { return }
        
        self.isChecking = true
        if !isAutomatic { self.activeAlert = nil }

        guard let url = URL(string: apiURL) else {
            self.isChecking = false
            if !isAutomatic { self.activeAlert = .error("Invalid URL") }
            return
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        
        // 🌟 [최종 수복: async/await 네트워크 파이프라인 전치]
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                
                self.isChecking = false

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 403 {
                    if !isAutomatic { self.activeAlert = .error("GitHub API rate limit exceeded. Please try again later.") }
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
                let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"

                self.lastUpdateCheckDate = Date().timeIntervalSince1970
                guard let releaseURL = URL(string: release.htmlUrl) else { return }

                if fetchedVersion.compare(currentVersion, options: .numeric) == .orderedDescending {
                    self.activeAlert = .updateAvailable(version: fetchedVersion, url: releaseURL)
                } else {
                    if !isAutomatic { self.activeAlert = .upToDate }
                }
                
            } catch {
                self.isChecking = false
                #if DEBUG
                dprint("Update check failed: \(error.localizedDescription)")
                #endif
                
                if let httpError = error as? URLError, httpError.code != .cancelled {
                    if !isAutomatic { self.activeAlert = .error(error.localizedDescription) }
                } else if !isAutomatic {
                    self.activeAlert = .error("Failed to fetch or parse GitHub release data.")
                }
            }
        }
    }
}
