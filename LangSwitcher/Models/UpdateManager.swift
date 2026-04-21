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

import Foundation
import AppKit
import Combine
import SwiftUI

// 🌟 SwiftUI 알럿 충돌을 방지하기 위한 단일 상태 정의
enum UpdateAlertItem: Identifiable {
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

class UpdateManager: ObservableObject {
    static let shared = UpdateManager()

    @Published var isChecking = false
    @Published var activeAlert: UpdateAlertItem? // 🌟 알럿 상태를 하나로 통합하여 씹힘 방지
    
    // 🌟 사용자 설정: 자동 업데이트 확인 여부
    @AppStorage("isAutoUpdateEnabled") var isAutoUpdateEnabled: Bool = true
    // 🌟 마지막으로 업데이트를 확인한 시간 (Unix Timestamp)
    @AppStorage("lastUpdateCheckDate") var lastUpdateCheckDate: Double = 0

    private let apiURL = "https://api.github.com/repos/peepworks/LangSwitcher/releases/latest"
    private var timer: Timer?

    private init() {}

    // 앱 실행 시 백그라운드 체크 시작
    func setupAutoUpdateCheck() {
        checkIfAutoUpdateNeeded()

        // 1시간(3600초)마다 타이머를 돌면서 24시간 경과 여부 체크
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.checkIfAutoUpdateNeeded()
        }
    }

    // 🌟 [리뷰 반영] 앱 종료 시 RunLoop에서 타이머를 안전하게 제거하여 자원을 반환하는 함수
    func stopAutoUpdateCheck() {
        timer?.invalidate()
        timer = nil
        print("✅ [UpdateManager] Auto update timer invalidated.")
    }

    // 🌟 [안전장치] 만약의 경우를 대비한 deinit에서의 자원 정리
    deinit {
        stopAutoUpdateCheck()
    }

    private func checkIfAutoUpdateNeeded() {
        guard isAutoUpdateEnabled else { return }

        let now = Date().timeIntervalSince1970
        let twentyFourHours: TimeInterval = 24 * 60 * 60 // 24시간

        if now - lastUpdateCheckDate >= twentyFourHours {
            checkForUpdates(isAutomatic: true)
        }
    }

    // isAutomatic 파라미터로 수동/자동 여부 구분
    func checkForUpdates(isAutomatic: Bool = false) {
        guard !isChecking else { return }
        
        DispatchQueue.main.async {
            self.isChecking = true
            if !isAutomatic { self.activeAlert = nil } // 수동 체크 시 기존 알럿 초기화
        }

        guard let url = URL(string: apiURL) else {
            DispatchQueue.main.async {
                self.isChecking = false
                if !isAutomatic { self.activeAlert = .error("Invalid URL") }
            }
            return
        }

        // 🌟 캐시를 무시하고 항상 최신 상태를 강제 확인
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isChecking = false

                if let error = error {
                    print("Update check failed: \(error.localizedDescription)")
                    if !isAutomatic { self?.activeAlert = .error(error.localizedDescription) }
                    return
                }
                
                // GitHub API 호출 제한 에러 처리
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 403 {
                    if !isAutomatic { self?.activeAlert = .error("GitHub API rate limit exceeded. Please try again later.") }
                    return
                }

                guard let data = data else { return }

                do {
                    struct GitHubRelease: Codable {
                        let tagName: String
                        let htmlUrl: String

                        enum CodingKeys: String, CodingKey {
                            case tagName = "tag_name"
                            case htmlUrl = "html_url"
                        }
                    }

                    // 정상적인 릴리즈 데이터 파싱
                    let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                    let fetchedVersion = release.tagName.replacingOccurrences(of: "v", with: "")
                    let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"

                    // 체크 성공 시 시간 갱신
                    self?.lastUpdateCheckDate = Date().timeIntervalSince1970
                    guard let releaseURL = URL(string: release.htmlUrl) else { return }

                    if fetchedVersion.compare(currentVersion, options: .numeric) == .orderedDescending {
                        // 업데이트 있음! (자동/수동 모두 알림창 띄움)
                        self?.activeAlert = .updateAvailable(version: fetchedVersion, url: releaseURL)
                    } else {
                        // 최신 버전임! (수동으로 눌렀을 때만 알림)
                        if !isAutomatic {
                            self?.activeAlert = .upToDate
                        }
                    }
                } catch {
                    // GitHub에서 릴리즈 정보 대신 에러 메시지(Not Found 등)를 보냈을 경우
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let message = json["message"] as? String {
                        if !isAutomatic { self?.activeAlert = .error("GitHub API: \(message)") }
                    } else {
                        if !isAutomatic { self?.activeAlert = .error("Failed to parse GitHub response.") }
                    }
                }
            }
        }.resume()
    }
}
