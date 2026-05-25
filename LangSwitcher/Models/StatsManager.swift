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
    
    // 🌟 [최적화] 수동 스레드 경합을 막던 비효율적인 stateQueue 배리어 자물쇠를 전면 삭제합니다.
    // 디스크 쓰기 전용 백그라운드 직렬 큐 하나만 유지하여 UI 스레드를 지켜냅니다.
    private let saveQueue = DispatchQueue(label: "com.peepworks.langswitcher.stats.save", qos: .background)
    
    // UI 바인딩용 데이터 (메인 스레드 격리)
    @Published var dailyStats: [DailyStat] = []
    @Published private(set) var statsDict: [String: DailyStat] = [:]
    
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
            // 알림 수신 시 즉시 메인 액터 격리 지표 확보
            MainActor.assumeIsolated {
                self?.forceSave()
            }
        }
    }
    
    // MARK: - 비동기 이벤트 훅 (Event Hooks)
    
    func incrementLanguageSwitch() {
        let dateKey = todayKey()
        
        // 🌟 [최적화] 메인 액터 격리 공간이므로 락 없이 비용 0%로 즉시 쓰기 수행
        var stat = internalStatsDict[dateKey] ?? DailyStat(dateString: dateKey, languageSwitches: 0, typoCorrections: 0)
        stat.languageSwitches += 1
        internalStatsDict[dateKey] = stat
        isDirty = true
        
        // UI 디바운서 호출
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
    
    // v0.9.1 코어 아키텍처의 작동 순서
    @MainActor
    private func forceSave() {
        guard isDirty else { return }
        
        // 🌟 Step 1 (메인 스레드 보장 구역):
        // Swift 딕셔너리는 구조체(struct)이므로 이 순간 완벽한 '값 복사(Copy)'가 일어납니다.
        let snapshot = self.internalStatsDict
        self.isDirty = false
        
        let key = defaultsKey
        
        // 🌟 Step 2 (백그라운드 스레드 이관):
        // 메인 스레드와 완전히 분리된 독립된 복사본(snapshot)만 큐에 실어서 던집니다.
        saveQueue.async {
            let statsArray = Array(snapshot.values).sorted { $0.dateString < $1.dateString }
            if let data = try? JSONEncoder().encode(statsArray) {
                UserDefaults.standard.set(data, forKey: key)
                dprint("StatsManager: 변경된 통계 데이터가 백그라운드에서 저장되었습니다.")
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
        // 메인 스레드에 상주 중이므로 락 프리 복사 캡처 수행
        let dictSnapshot = internalStatsDict
        
        // 무거운 정렬(sorted) 작업만 메인 스레드가 아닌 인텔리전트 글로벌 큐로 위임
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let snapshotArray = Array(dictSnapshot.values).sorted { $0.dateString < $1.dateString }
            
            // 렌더링 준비 완료 시점에 다시 메인 팩터로 바인딩
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.dailyStats = snapshotArray
                self.statsDict = dictSnapshot
            }
        }
    }
    
    private func schedulePublishUpdate() {
        publishWorkItem?.cancel()
        
        let item = DispatchWorkItem { [weak self] in
            self?.publishUpdate()
        }
        
        publishWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    // 통계 날짜 정합성 추출 포매터 (메인 액터 전용 격리 상주시켜 컴파일러 위협 무력화)
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
    
    func exportToCSV(to url: URL, completion: @escaping @Sendable (Bool, Error?) -> Void) {
        let snapshot = internalStatsDict
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                var csvString = "Date,Type,Count\n"
                
                for (dateKey, dailyStats) in snapshot {
                    let switchCount = dailyStats.languageSwitches
                    let typoCount = dailyStats.typoCorrections
                    
                    csvString += "\(dateKey),LanguageSwitch,\(switchCount)\n"
                    csvString += "\(dateKey),TypoCorrection,\(typoCount)\n"
                }
                
                try csvString.write(to: url, atomically: true, encoding: .utf8)
                
                DispatchQueue.main.async {
                    completion(true, nil)
                }
            } catch {
                DispatchQueue.global(qos: .userInitiated).async {
                    completion(false, error)
                }
            }
        }
    }
    
    // 필터링/정렬된 데이터를 보관할 캐시 프로퍼티
    @Published private(set) var filteredStatsCache: [DailyStat] = []
    
    // 뷰에서 호출할 최적화된 데이터 가공 메서드
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
        
        // 🌟 [최적화] 불필요한 스레드 대기 연산(.sync)을 완전히 삭제하고, 메모리에서 직렬 다이렉트 처리
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
