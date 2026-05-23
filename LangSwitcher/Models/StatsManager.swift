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

// 차트 렌더링을 위한 개별 통계 모델
struct DailyStat: Codable, Identifiable, Equatable {
    var id: String { dateString }
    let dateString: String // "yyyy-MM-dd"
    var languageSwitches: Int
    var typoCorrections: Int
}

class StatsManager: ObservableObject {
    static let shared = StatsManager()
    
    // 🌟 스레드 안전성을 위한 동시성 큐
    private let stateQueue = DispatchQueue(label: "com.peepworks.langswitcher.stats", attributes: .concurrent)
    private let saveQueue = DispatchQueue(label: "com.peepworks.langswitcher.stats.save", qos: .background)
    
    // 🌟 UI 바인딩용 데이터 (메인 스레드에서만 업데이트)
    @Published var dailyStats: [DailyStat] = []
    
    // 🌟 [핵심 수정 1] 뷰(View)가 매번 딕셔너리를 생성하지 않고 O(1)로 바로 꺼내 쓸 수 있도록 공개하는 캐시 변수
    @Published private(set) var statsDict: [String: DailyStat] = [:]
    
    // 인메모리 누적 딕셔너리
    private var internalStatsDict: [String: DailyStat] = [:]
    
    private var saveTimer: Timer?
    private let defaultsKey = "LangSwitcher_DailyStats"
    
    // 🌟 데이터가 변경되었는지 추적하는 포스트잇(플래그)
    private var isDirty: Bool = false
    
    private init() {
        loadStats()
        startBatchSaveTimer()
        
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.forceSave()
        }
    }
    
    private var publishWorkItem: DispatchWorkItem?
    
    // MARK: - 비동기 이벤트 훅 (Event Hooks)
    
    func incrementLanguageSwitch() {
        let dateKey = todayKey()
        
        // 1. [데이터 쓰기] 독방(Barrier) 안에서는 오직 데이터만 수정하고 가장 빠르게 빠져나옵니다.
        stateQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            var stat = self.internalStatsDict[dateKey] ?? DailyStat(dateString: dateKey, languageSwitches: 0, typoCorrections: 0)
            stat.languageSwitches += 1
            self.internalStatsDict[dateKey] = stat
            self.isDirty = true
        } // 🚪 여기서 독방 문이 열리고 Lock이 해제됩니다!
        
        // 2. [UI 갱신 예약] 독방에서 완전히 빠져나온 안전한 상태에서 디바운서를 호출합니다.
        self.schedulePublishUpdate()
    }

    func incrementTypoCorrection() {
        let dateKey = todayKey()
        
        // 1. [데이터 쓰기]
        stateQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            var stat = self.internalStatsDict[dateKey] ?? DailyStat(dateString: dateKey, languageSwitches: 0, typoCorrections: 0)
            stat.typoCorrections += 1
            self.internalStatsDict[dateKey] = stat
            self.isDirty = true
        }
        
        // 2. [UI 갱신 예약] 이전의 불안전한 직접 호출을 지우고, 여기서도 통일된 디바운서를 사용합니다.
        self.schedulePublishUpdate()
    }
    
    // MARK: - 주기적 저장 로직 (Batch Saving)
    
    private func startBatchSaveTimer() {
        DispatchQueue.main.async {
            self.saveTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
                self?.forceSave() // 5분마다 실행될 저장 로직
            }
        }
    }
    
    // 🌟 [수정됨] 무의미한 복사를 막는 더티 플래그(Dirty Flag) 패턴 적용
    private func forceSave() {
        var shouldSave = false
        var snapshot: [String: DailyStat] = [:]
        
        // 🌟 [핵심 수정] isDirty = false 라는 '쓰기' 작업이 포함되어 있으므로,
        // 반드시 flags: .barrier를 추가하여 다른 스레드의 접근을 완벽히 차단해야 합니다.
        stateQueue.sync(flags: .barrier) {
            if self.isDirty {
                shouldSave = true
                snapshot = self.internalStatsDict
                self.isDirty = false // 쓰기 작업이 이제 완벽하게 안전해졌습니다.
            }
        }
        
        guard shouldSave else { return }
        
        saveQueue.async {
            let statsArray = Array(snapshot.values).sorted { $0.dateString < $1.dateString }
            if let data = try? JSONEncoder().encode(statsArray) {
                UserDefaults.standard.set(data, forKey: self.defaultsKey)
                
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
                tempDict[stat.dateString] = stat // 🌟 임시 딕셔너리에 수집
            }
            self.dailyStats = decoded.sorted { $0.dateString < $1.dateString }
            
            // 🌟 [핵심 수정 3] 최초 로드 시점에도 뷰를 위한 캐시 데이터를 주입합니다.
            self.statsDict = tempDict
        }
    }
    
    // 🌟 [개선됨] 정확한 시점의 데이터를 캡처하기 위해 동기(sync) 방식 적용
    private func publishUpdate() {
        // 1. sync를 사용하여 '호출된 정확히 그 순간'의 딕셔너리를 즉시 복사해옵니다. (매우 빠름)
        let dictSnapshot = stateQueue.sync {
            return self.internalStatsDict
        }
        
        // 2. 무거운 정렬(sorted) 작업은 메인 스레드나 백그라운드에서 별도로 진행하여 UI 병목을 막습니다.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let snapshotArray = Array(dictSnapshot.values).sorted { $0.dateString < $1.dateString }
            
            // 3. 완성된 데이터를 메인 스레드로 전달합니다.
            DispatchQueue.main.async {
                self?.dailyStats = snapshotArray
                self?.statsDict = dictSnapshot
            }
        }
    }
    
    // 🌟 [새로 추가] UI 업데이트 요청을 0.3초 동안 모아서 한 번만 실행하는 디바운스 엔진
    private func schedulePublishUpdate() {
        // 이미 예약된 업데이트 작업이 있다면 쿨하게 취소합니다. (연속 요청 씹기)
        publishWorkItem?.cancel()
        
        // 0.3초 뒤에 실행할 새로운 UI 갱신 작업을 만듭니다.
        let item = DispatchWorkItem { [weak self] in
            self?.publishUpdate()
        }
        
        publishWorkItem = item
        
        // 메인 큐에서 0.3초 뒤에 실행하도록 예약합니다.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    // 🌟 [수정됨] 멀티스레드에서 수천 번 동시에 접근해도 절대 뻗지 않는 안전한 포매터 도입!
    private static let todayFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        // "yyyy-MM-dd" 형식으로만 뽑아내기 위한 옵션 설정
        formatter.formatOptions = [.withYear, .withMonth, .withDay, .withDashSeparatorInDate]
        formatter.timeZone = .current
        return formatter
    }()

    private func todayKey() -> String {
        return Self.todayFormatter.string(from: Date())
    }
    
    // MARK: - 운영 및 관리 기능 (초기화 및 내보내기)
    
    func resetStats() {
        // 🌟 [1단계: 쓰기] barrier 안에서는 오직 데이터 삭제만 하고 잽싸게 빠져나옵니다.
        stateQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            self.internalStatsDict.removeAll()
            self.isDirty = false
            UserDefaults.standard.removeObject(forKey: self.defaultsKey)
        } // 🚪 여기서 독방 문이 열립니다!
        
        // 🌟 [2단계: 부수 효과] 문을 열고 나온 뒤에, 독립적으로 UI 갱신을 요청합니다.
        DispatchQueue.main.async { [weak self] in
            self?.publishUpdate()
        }
    }
    
    func exportToCSV(to url: URL, completion: @escaping (Bool, Error?) -> Void) {
        
        let snapshot = stateQueue.sync {
            return self.internalStatsDict
        }
        
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
                DispatchQueue.main.async {
                    completion(false, error)
                }
            }
        }
    }
    
    // 🌟 [추가] 필터링/정렬된 데이터를 보관할 캐시 프로퍼티
    @Published private(set) var filteredStatsCache: [DailyStat] = []
    
    // 🌟 [추가] 뷰에서 호출할 최적화된 데이터 가공 메서드
    func updateFilteredStats(for range: TimeRange) {
        let calendar = Calendar.current
        let today = Date()
        
        // 🌟 저장된 internalStatsDict를 활용하여 효율적으로 계산
        let daysToFetch: Int
        switch range {
        case .week: daysToFetch = 7
        case .month: daysToFetch = 30
        case .all:
            // internalStatsDict의 모든 키(날짜) 중 가장 오래된 날짜를 추출
            let dates = internalStatsDict.keys.compactMap { Self.todayFormatter.date(from: $0) }
            if let firstDate = dates.min() {
                daysToFetch = max(1, calendar.dateComponents([.day], from: firstDate, to: today).day ?? 1) + 1
            } else { daysToFetch = 7 }
        }
        
        var result: [DailyStat] = []
        result.reserveCapacity(daysToFetch)
        
        // 🌟 stateQueue.sync를 사용하여 가장 최신 스냅샷에서 데이터를 안전하게 가져옴
        let snapshot = stateQueue.sync { internalStatsDict }
        
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
        
        // 메인 스레드에 최종 결과 전달 (UI 갱신 트리거)
        DispatchQueue.main.async {
            self.filteredStatsCache = result
        }
    }
}
