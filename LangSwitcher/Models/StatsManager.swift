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
    
    // MARK: - 비동기 이벤트 훅 (Event Hooks)
    
    func incrementLanguageSwitch() {
        let dateKey = todayKey()
        
        // 🌟 [1단계: 쓰기] barrier 안에서는 오직 데이터 변경만 하고 잽싸게 빠져나옵니다.
        stateQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            // 🌟 [수정됨] self.internalStatsDict 사용 및 DailyStat 초기화 파라미터 이름 매칭
            var stat = self.internalStatsDict[dateKey] ?? DailyStat(dateString: dateKey, languageSwitches: 0, typoCorrections: 0)
            
            // 🌟 [수정됨] switchCount 대신 languageSwitches 사용
            stat.languageSwitches += 1
            
            self.internalStatsDict[dateKey] = stat
            self.isDirty = true
        } // 🚪 여기서 독방 문이 열립니다!
        
        // 🌟 [2단계: 부수 효과] 문을 열고 나온 뒤에, 독립적으로 UI 갱신을 요청합니다.
        DispatchQueue.main.async { [weak self] in
            self?.publishUpdate()
        }
    }
    
    func incrementTypoCorrection() {
        let dateKey = todayKey()
        
        // 🌟 [1단계: 쓰기] 여기도 동일하게 barrier 안에서 쓰기만 처리합니다.
        stateQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            var stat = self.internalStatsDict[dateKey] ?? DailyStat(dateString: dateKey, languageSwitches: 0, typoCorrections: 0)
            stat.typoCorrections += 1
            self.internalStatsDict[dateKey] = stat
            self.isDirty = true
        } // 🚪 독방 문 개방
        
        // 🌟 [2단계: 부수 효과] 중첩 제거 및 독립적 스케줄링
        DispatchQueue.main.async { [weak self] in
            self?.publishUpdate()
        }
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
                
                #if DEBUG
                print("StatsManager: 변경된 통계 데이터가 백그라운드에서 저장되었습니다.")
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
}
