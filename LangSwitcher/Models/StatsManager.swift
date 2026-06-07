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

@MainActor // 🌟 명시적 전역 액터 격리를 통해 인메모리 장부의 데이터 레이스를 원천 차단합니다.
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
    
    // 🌟 [최종 최적화 수복] 레거시 GCD DispatchWorkItem을 전면 적출하고
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
        // 1차 방어선: 바뀐 데이터가 없다면 무의미한 I/O를 발생시키지 않고 즉시 리턴
        guard isDirty else { return }

        // 🌟 [우주 방어 수복 포인트 1] 백그라운드로 유기하기 직전,
        // 현재 시점의 깨끗한 인메모리 장부 데이터를 CoW 사양으로 완벽하게 스냅샷을 구워냅니다.
        let statsArray = Array(self.internalStatsDict.values).sorted { $0.dateString < $1.dateString }
        let key = defaultsKey

        // 🚨 기존 코드의 'self.isDirty = false' 선행 해제 라인은 완전히 제거(소각)합니다.

        Task.detached(priority: .background) {
            if let data = try? Self.encoder.encode(statsArray) {
                UserDefaults.standard.set(data, forKey: key)
                
                // 🌟 [수복 포인트 2] 디스크에 물리적으로 파일 쓰기가 100% 완료된 시점에만
                // 메인 액터 요새로 안전하게 홉(Hop)하여 저장 자물쇠를 공식 해제(Commit)합니다.
                await MainActor.run {
                    StatsManager.shared.isDirty = false
                    dprint("💾 [StatsManager] 디스크 저장 완료 확인. 트랜잭션 커밋을 승인하고 isDirty를 false로 정산했습니다.")
                }
            } else {
                // 인코딩 실패 시에는 안전하게 장부를 더티 상태로 유지하여 다음 타이머 때 재시도 유도
                await MainActor.run {
                    StatsManager.shared.isDirty = true
                }
                dprint("🚨 [StatsManager] 통계 데이터 인코딩 실패. 차기 저장을 위해 더티 상태를 강제 유지합니다.")
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
    
    // MARK: - 고성능 Modern Swift Concurrency 디바운스 엔진
    private func schedulePublishUpdate() {
        // 1. 타이핑 연타 시 이전 예약되어 있던 발행 태스크를 빛의 속도로 취소시킵니다.
        publishTask?.cancel()
        
        // 2. 🌟 [수복 완료] 레거시 C 기반의 asyncAfter를 지우고 순정 비동기 슬립 구조로 주기를 제어합니다.
        // 클로저 캡처 부하와 무단 스레드 배리어 우회 현상이 완벽하게 치료됩니다.
        publishTask = Task {
            // 0.3초 디바운스 대기 집행
            try? await Task.sleep(nanoseconds: 300_000_000)
            
            // 대기하는 도중 유저가 다음 타건을 쳐서 취소 신호가 내려왔다면 즉시 처형(Exit)
            guard !Task.isCancelled else { return }
            
            self.publishUpdate()
        }
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
        
        Task.detached(priority: .userInitiated) {
            do {
                var csvString = "Date,Type,Count\n"
                for (dateKey, dailyStats) in snapshot {
                    csvString += "\(dateKey),LanguageSwitch,\(dailyStats.languageSwitches)\n"
                    csvString += "\(dateKey),TypoCorrection,\(dailyStats.typoCorrections)\n"
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
                    result.append(DailyStat(dateString: dateString, languageSwitches: 0, typoCorrections: 0))
                }
            }
        }
        
        self.filteredStatsCache = result
    }
}
