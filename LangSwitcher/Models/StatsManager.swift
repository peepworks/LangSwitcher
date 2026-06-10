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
    
    // 🌟 [10번 리뷰 수복 완료] 레거시 GCD DispatchWorkItem을 전면 적출하고
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
    func forceSave() {
        // 1. 변경된 장부가 없다면 불필요한 디스크 파일 I/O 시스템 콜을 원천 차단
        guard isDirty else { return }

        // 현재 시점까지 누적된 청정 인메모리 통계 데이터를 값 복사(CoW) 사양으로 완벽히 스냅샷을 굽습니다.
        let statsArray = Array(self.internalStatsDict.values).sorted { $0.dateString < $1.dateString }
        let key = defaultsKey

        // 2. 무거운 인코딩 및 디스크 파일 쓰기를 백그라운드 독립 스레드로 격리 위임
        Task.detached(priority: .background) { [weak self] in
            guard let data = try? Self.encoder.encode(statsArray) else {
                // 만에 하나 데이터 인코딩 예외 발생 시, 장부를 의도적으로 더티(true) 상태로 유지하여 차기 세션 때 재시도 유도
                await MainActor.run { [weak self] in
                    self?.isDirty = true
                }
                dprint("🚨 [StatsManager] 통계 데이터 JSON 인코딩 실패. 차기 저장을 위해 장부 잠금을 유효화합니다.")
                return
            }
            
            // 물리적인 UserDefaults 디스크 저장 집행
            UserDefaults.standard.set(data, forKey: key)
            
            // 커널 레이어에 파일 쓰기가 100% 무사히 안착했음이 확약된 바로 이 시점에만
            // 메인 액터 요새로 안전하게 복귀하여 장부 자물쇠를 공식 컴밋(isDirty = false)합니다.
            await MainActor.run { [weak self] in
                self?.isDirty = false
                dprint("💾 [StatsManager] 디스크 저장 물리적 완수 확인. 트랜잭션 커밋 승인 및 isDirty = false 정산 완료.")
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
        
        // 2. 순정 비동기 슬립 구조로 주기를 제어합니다.
        publishTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                // UI 스팸 및 리렌더링 버벅임을 방어하기 위해 0.3초간 청정 비동기 대기
                try await Task.sleep(for: .seconds(0.3))
                
                // 슬립 도중 사용자가 글자를 또 쳐서 새로운 취소 신호가 인입되었다면 즉시 하단 연산 차단
                guard !Task.isCancelled else { return }
                
                // 🌟 [우주 방어 수복 포인트: UI 단절 트랩 소각]
                // 0.3초간 아무런 방해가 없었던 최종 진정 시점에 진짜 인메모리 장부를 퍼블릭 UI 바인딩 자산으로 갱신 배포합니다.
                // @Published 프로퍼티 체인이 교체되므로 수동 objectWillChange 무단 방출 없이 완벽하게 실시간 그래프가 춤추게 됩니다.
                self.publishUpdate()
                
                dprint("📊 [StatsManager] 통계 디바운스 최종 확약 — UI 장부 밀어내기 및 리렌더링 전파 완결.")
            } catch {
                // Task.sleep 취소 예외 발생 시 부작용 없이 조용히 스킵 후 복귀
            }
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
