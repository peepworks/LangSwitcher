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
import SwiftUI // 🌟 @AppStorage를 사용하기 위해 추가

class UpdateManager: ObservableObject {
    static let shared = UpdateManager()
    
    @Published var isChecking = false
    @Published var showUpdateAlert = false
    @Published var showUpToDateAlert = false
    @Published var latestVersion: String = ""
    @Published var releaseURL: URL?

    // 🌟 사용자 설정: 자동 업데이트 확인 여부 (기본값: true)
    @AppStorage("isAutoUpdateEnabled") var isAutoUpdateEnabled: Bool = true
    // 🌟 마지막으로 업데이트를 확인한 시간 (Unix Timestamp 저장)
    @AppStorage("lastUpdateCheckDate") var lastUpdateCheckDate: Double = 0

    private let apiURL = "https://api.github.com/repos/peepworks/LangSwitcher/releases/latest"
    private var timer: Timer?

    // 🌟 앱 실행 시 백그라운드 체크 시작
    func setupAutoUpdateCheck() {
        // 앱을 켤 때 24시간이 지났는지 즉시 확인
        checkIfAutoUpdateNeeded()
        
        // 이후 1시간(3600초)마다 타이머를 돌면서 24시간 경과 여부를 백그라운드에서 체크
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.checkIfAutoUpdateNeeded()
        }
    }

    private func checkIfAutoUpdateNeeded() {
        guard isAutoUpdateEnabled else { return }
        
        let now = Date().timeIntervalSince1970
        let twentyFourHours: TimeInterval = 24 * 60 * 60 // 24시간 (초 단위)
        
        // 마지막 체크 이후 24시간이 지났다면
        if now - lastUpdateCheckDate >= twentyFourHours {
            checkForUpdates(isAutomatic: true)
        }
    }

    // 🌟 isAutomatic 파라미터를 추가하여 수동/자동 여부 구분
    func checkForUpdates(isAutomatic: Bool = false) {
        guard !isChecking else { return }
        isChecking = true
        
        guard let url = URL(string: apiURL) else {
            isChecking = false
            return
        }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isChecking = false
                
                guard let data = data, error == nil else {
                    print("Update check failed: \(error?.localizedDescription ?? "Unknown error")")
                    return
                }
                
                do {
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
                    
                    self?.latestVersion = fetchedVersion
                    self?.releaseURL = URL(string: release.htmlUrl)
                    
                    // 🌟 체크 성공 시, 마지막 확인 시간을 현재 시간으로 갱신
                    self?.lastUpdateCheckDate = Date().timeIntervalSince1970
                    
                    if fetchedVersion.compare(currentVersion, options: .numeric) == .orderedDescending {
                        // 업데이트 있음! (자동/수동 상관없이 알림창을 띄움)
                        self?.showUpdateAlert = true
                    } else {
                        // 최신 버전임! (수동으로 눌렀을 때만 '최신 버전' 알림을 띄우고, 자동 체크 시에는 조용히 넘어감)
                        if !isAutomatic {
                            self?.showUpToDateAlert = true
                        }
                    }
                    
                } catch {
                    print("Failed to parse GitHub response: \(error)")
                }
            }
        }.resume()
    }
}
