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
    
    nonisolated private static let encoder = JSONEncoder()
    nonisolated private static let decoder = JSONDecoder()
    
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
        
        // 1. 🌟 [핵심 수복] 딕셔너리 원본을 넘기지 않고, 메인 액터 안전 구역 내에서
        // 완전히 독립된 메모리 버퍼를 가지는 일반 고정 배열([DailyStat])로 전치 및 정렬을 끝마칩니다.
        // 이 순간, 백그라운드 태스크는 internalStatsDict의 내부 공유 버퍼를 절대 참조할 수 없게 됩니다.
        let statsArray = Array(self.internalStatsDict.values).sorted { $0.dateString < $1.dateString }
        let key = defaultsKey
        self.isDirty = false
        
        // 2. 이제 딕셔너리와 완벽하게 절연된 statsArray만 들고 백그라운드로 떠납니다.
        Task.detached(priority: .background) {
            // statsArray는 완벽하게 독립된 값 타입 배열이므로,
            // 메인 스레드에서 타이핑 연타로 internalStatsDict가 조작되든 말든 100% 안전합니다.
            if let data = try? Self.encoder.encode(statsArray) {
                UserDefaults.standard.set(data, forKey: key)
                dprint("💾 [StatsManager] CoW 데이터 레이스를 원천 차단하며 백그라운드 저장을 완료했습니다.")
            } else {
                await MainActor.run {
                    StatsManager.shared.isDirty = true
                }
                dprint("🚨 [StatsManager] 통계 데이터 인코딩 실패로 인해 isDirty 상태를 롤백했습니다.")
            }
        }
    }
    
    private func loadStats() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           // 🌟 [수복 2] 아직 남아있던 일회용 JSONDecoder()를 Self.decoder로 완벽하게 짝맞춤 교체!
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
        
        // 🌟 [수복 완료] 무거운 문자열 조작 및 디스크 파일 I/O를 메인 스레드 스올(Stall) 없이 백그라운드 태스크로 유기합니다.
        Task.detached(priority: .userInitiated) {
            do {
                var csvString = "Date,Type,Count\n"
                for (dateKey, dailyStats) in snapshot {
                    csvString += "\(dateKey),LanguageSwitch,\(dailyStats.languageSwitches)\n"
                    csvString += "\(dateKey),TypoCorrection,\(dailyStats.typoCorrections)\n"
                }
                
                try csvString.write(to: url, atomically: true, encoding: .utf8)
                
                // 🌟 콜백 함수가 이미 @MainActor 격리 사양이므로, await 호출 한 방으로
                // DispatchQueue.main 없이 메인 스레드에 안전하게 정렬 배달됩니다.
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
        
        // 메인 액터 격리가 명시되었으므로 안전하게 인메모리 장부 참조
        let snapshot = internalStatsDict
        
        // 🌟 순정 역순 루프 사양 보존 ((0..<daysToFetch).reversed() 구조 유지)
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
        
        // @Published UI 바인딩 변수에 최종 원자적 안착
        self.filteredStatsCache = result
    }
}
