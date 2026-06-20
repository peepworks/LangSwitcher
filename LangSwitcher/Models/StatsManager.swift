//
//  StatsManager.swift
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
import Combine
import AppKit

// 차트 렌더링을 위한 개별 통계 모델 (텍스트 대치 축 확장)
struct DailyStat: Codable, Identifiable, Equatable, Sendable {
    var id: String { dateString }
    let dateString: String // "yyyy-MM-dd"
    var languageSwitches: Int
    var typoCorrections: Int
    var textExpansions: Int // 🌟 [수복 추가] 텍스트 대치 누적 카운트 필드 신설
}

@MainActor // 명시적 전역 액터 격리를 통해 인메모리 장부의 데이터 레이스를 원천 차단합니다.
class StatsManager: ObservableObject {
    static let shared = StatsManager()

    nonisolated private static let encoder = JSONEncoder()
    nonisolated private static let decoder = JSONDecoder()

    // UI 바인딩용 데이터 (메인 스레드 격리)
    @Published var dailyStats: [DailyStat] = []
    @Published var statsDict: [String: DailyStat] = [:]
    @Published private(set) var filteredStatsCache: [DailyStat] = []

    // 인메모리 누적 딕셔너리 (메인 액터의 완벽한 보호막 아래 상주)
    private var internalStatsDict: [String: DailyStat] = [:]

    private var saveTimer: Timer?
    private let defaultsKey = "LangSwitcher_DailyStats"

    private var isDirty: Bool = false

    // Swift 6 사양의 취소 가능한 비동기 Task 구조로 고성능 디바운스 래퍼를 대체합니다.
    private var publishTask: Task<Void, Never>?

    private init() {
        loadStats()
        startBatchSaveTimer()

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.forceSave()
            }
        }
    }

    // MARK: - 비동기 이벤트 훅 (Event Hooks)

    func incrementLanguageSwitch() {
        let dateKey = todayKey()
        var stat = internalStatsDict[dateKey] ?? DailyStat(dateString: dateKey, languageSwitches: 0, typoCorrections: 0, textExpansions: 0)
        stat.languageSwitches += 1
        internalStatsDict[dateKey] = stat
        isDirty = true
        self.schedulePublishUpdate()
    }

    func incrementTypoCorrection() {
        let dateKey = todayKey()
        var stat = internalStatsDict[dateKey] ?? DailyStat(dateString: dateKey, languageSwitches: 0, typoCorrections: 0, textExpansions: 0)
        stat.typoCorrections += 1
        internalStatsDict[dateKey] = stat
        isDirty = true
        self.schedulePublishUpdate()
    }

    // 🌟 [수복 추가] 타건 코어 엔티티에서 찌를 수 있는 텍스트 대치 트랜잭션 훅 개설
    func incrementTextExpansion() {
        let dateKey = todayKey()
        var stat = internalStatsDict[dateKey] ?? DailyStat(dateString: dateKey, languageSwitches: 0, typoCorrections: 0, textExpansions: 0)
        stat.textExpansions += 1
        internalStatsDict[dateKey] = stat
        isDirty = true
        self.schedulePublishUpdate()
    }

    // MARK: - 주기적 저장 로직 (Batch Saving)

    private func startBatchSaveTimer() {
        saveTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.forceSave()
            }
        }
    }

    @MainActor
    func forceSave() {
        guard isDirty else { return }

        let statsArray = Array(self.internalStatsDict.values).sorted { $0.dateString < $1.dateString }
        let key = defaultsKey

        Task.detached(priority: .background) { [weak self] in
            guard let data = try? Self.encoder.encode(statsArray) else {
                await MainActor.run { [weak self] in
                    self?.isDirty = true
                }
                return
            }

            UserDefaults.standard.set(data, forKey: key)

            await MainActor.run { [weak self] in
                self?.isDirty = false
                dprint("💾 [StatsManager] 디스크 저장 물리적 완수 확인. 트랜잭션 커밋 승인 완료.")
            }
        }
    }

    private func loadStats() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? Self.decoder.decode([DailyStat].self, from: data) {

            var tempDict: [String: DailyStat] = [:]
            for stat in decoded {
                internalStatsDict[stat.dateString] = stat
                tempDict[stat.dateString] = stat
            }
            self.dailyStats = decoded.sorted { $0.dateString < $1.dateString }
            self.statsDict = tempDict
        }
    }

    private func publishUpdate() {
        let snapshotArray = Array(internalStatsDict.values).sorted { $0.dateString < $1.dateString }
        self.dailyStats = snapshotArray
        self.statsDict = internalStatsDict
    }

    private func schedulePublishUpdate() {
        publishTask?.cancel()

        publishTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                try await Task.sleep(for: .seconds(0.3))
                guard !Task.isCancelled else { return }
                self.publishUpdate()
            } catch {}
        }
    }

    private static let todayFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withYear, .withMonth, .withDay, .withDashSeparatorInDate]
        formatter.timeZone = .current
        return formatter
    } ()

    private func todayKey() -> String {
        return Self.todayFormatter.string(from: Date())
    }

    // MARK: - 운영 및 관리 기능 (초기화 및 내보내기)

    func resetStats() {
        internalStatsDict.removeAll()
        isDirty = false
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        self.publishUpdate()
    }

    func exportToCSV(to url: URL, completion: @escaping @MainActor (Bool, Error?) -> Void) {
        let snapshot = internalStatsDict

        Task.detached(priority: .userInitiated) {
            do {
                var csvString = "Date,Type,Count\n"
                for (dateKey, dailyStats) in snapshot {
                    csvString += "\(dateKey),LanguageSwitch,\(dailyStats.languageSwitches)\n"
                    csvString += "\(dateKey),TypoCorrection,\(dailyStats.typoCorrections)\n"
                    csvString += "\(dateKey),TextExpansion,\(dailyStats.textExpansions)\n" // 🌟 CSV 오퍼레이션 라인 추가
                }

                try csvString.write(to: url, atomically: true, encoding: .utf8)
                await completion(true, nil)
            } catch {
                await completion(false, error)
            }
        }
    }

    // MARK: - 필터링 및 차트 렌더링 데이터 가공 엔진
    @MainActor
    func updateFilteredStats(for range: TimeRange) {
        let calendar = Calendar.current
        let today = Date()

        let daysToFetch: Int
        switch range {
        case .week: daysToFetch = 7
        case .month: daysToFetch = 30
        case .all:
            let dates = internalStatsDict.keys.compactMap { Self.todayFormatter.date(from: $0) }
            if let firstDate = dates.min() {
                daysToFetch = max(1, calendar.dateComponents([.day], from: firstDate, to: today).day ?? 1) + 1
            } else { daysToFetch = 7 }
        }

        var result: [DailyStat] = []
        result.reserveCapacity(daysToFetch)

        let snapshot = internalStatsDict

        for i in (0..<daysToFetch).reversed() {
            if let date = calendar.date(byAdding: .day, value: -i, to: today) {
                let dateString = Self.todayFormatter.string(from: date)
                if let existingStat = snapshot[dateString] {
                    result.append(existingStat)
                } else {
                    result.append(DailyStat(dateString: dateString, languageSwitches: 0, typoCorrections: 0, textExpansions: 0))
                }
            }
        }

        self.filteredStatsCache = result
    }
}
