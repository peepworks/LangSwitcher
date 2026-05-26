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

// 차트 렌더링을 위한 개별 통계 모델 (스냅샷 간 전송을 위해 Sendable 추가)
struct DailyStat: Codable, Identifiable, Equatable, Sendable {
    var id: String { dateString }
    let dateString: String // "yyyy-MM-dd"
    var languageSwitches: Int
    var typoCorrections: Int
}

@MainActor
class StatsManager: ObservableObject {
    static let shared = StatsManager()
    
    // 디스크 쓰기 전용 백그라운드 직렬 큐 하나만 유지하여 UI 스레드를 지켜냅니다.
    private let saveQueue = DispatchQueue(label: "com.peepworks.langswitcher.stats.save", qos: .background)
    
    // UI 바인딩용 데이터 (메인 스레드 격리)
    @Published var dailyStats: [DailyStat] = []
    
    // 🌟 [수복 완료] 경고 문법 준수 및 외부 세터 충돌 방지를 위해 빈 딕셔너리 명세를 명확히 고정합니다.
    @Published var statsDict: [String: DailyStat] = [:]
    @Published private(set) var filteredStatsCache: [DailyStat] = []
    
    // 인메모리 누적 딕셔너리
    private var internalStatsDict: [String: DailyStat] = [:]
    
    private var saveTimer: Timer?
    private let defaultsKey = "LangSwitcher_DailyStats"
    
    private var isDirty: Bool = false
    private var publishWorkItem: DispatchWorkItem?
    
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
        
        var stat = internalStatsDict[dateKey] ?? DailyStat(dateString: dateKey, languageSwitches: 0, typoCorrections: 0)
        stat.languageSwitches += 1
        internalStatsDict[dateKey] = stat
        isDirty = true
        
        self.schedulePublishUpdate()
    }

    func incrementTypoCorrection() {
        let dateKey = todayKey()
        
        var stat = internalStatsDict[dateKey] ?? DailyStat(dateString: dateKey, languageSwitches: 0, typoCorrections: 0)
        stat.typoCorrections += 1
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
    private func forceSave() {
        guard isDirty else { return }
        
        // Zero-Capture 아키텍처 사양
        let snapshot = self.internalStatsDict
        let key = defaultsKey
        self.isDirty = false
        
        saveQueue.async {
            let statsArray = Array(snapshot.values).sorted { $0.dateString < $1.dateString }
            if let data = try? JSONEncoder().encode(statsArray) {
                UserDefaults.standard.set(data, forKey: key)
                #if DEBUG
                dprint("💾 [StatsManager] 백그라운드에서 self 간섭 없이 통계 데이터를 안전하게 저장했습니다.")
                #endif
            }
        }
    }
    
    private func loadStats() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([DailyStat].self, from: data) {
            
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
        // 🌟 [수복 완료] 원자적 대입문 매칭 수정
        let snapshotArray = Array(internalStatsDict.values).sorted { $0.dateString < $1.dateString }
        self.dailyStats = snapshotArray
        self.statsDict = internalStatsDict
    }
    
    private func schedulePublishUpdate() {
        publishWorkItem?.cancel()
        
        let item = DispatchWorkItem { [weak self] in
            self?.publishUpdate()
        }
        
        publishWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    // 통계 날짜 정합성 추출 포매터 (메인 액터 전용 격리 상주)
    private static let todayFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withYear, .withMonth, .withDay, .withDashSeparatorInDate]
        formatter.timeZone = .current
        return formatter
    }()

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
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                var csvString = "Date,Type,Count\n"
                for (dateKey, dailyStats) in snapshot {
                    csvString += "\(dateKey),LanguageSwitch,\(dailyStats.languageSwitches)\n"
                    csvString += "\(dateKey),TypoCorrection,\(dailyStats.typoCorrections)\n"
                }
                
                try csvString.write(to: url, atomically: true, encoding: .utf8)
                
                DispatchQueue.main.async { completion(true, nil) }
            } catch {
                DispatchQueue.main.async { completion(false, error) }
            }
        }
    }
    
    // 🌟 [수복 완료] 기존에 존재하는 TimeRange 프로젝트 사양을 온전하게 상속하여 연동합니다.
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
                    result.append(DailyStat(dateString: dateString, languageSwitches: 0, typoCorrections: 0))
                }
            }
        }
        
        self.filteredStatsCache = result
    }
}
