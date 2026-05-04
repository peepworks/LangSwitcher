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
    
    // 인메모리 누적 딕셔너리
    private var _statsDict: [String: DailyStat] = [:]
    
    private var saveTimer: Timer?
    private let defaultsKey = "LangSwitcher_DailyStats"
    
    private init() {
        loadStats()
        startBatchSaveTimer()
        
        // 🌟 [수정됨] 앱 종료 시 디스크 기록 옵저버를 안전한 모던 블록 API로 교체
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
        stateQueue.async(flags: .barrier) {
            var stat = self._statsDict[dateKey] ?? DailyStat(dateString: dateKey, languageSwitches: 0, typoCorrections: 0)
            stat.languageSwitches += 1
            self._statsDict[dateKey] = stat
            self.publishUpdate()
        }
    }
    
    func incrementTypoCorrection() {
        let dateKey = todayKey()
        stateQueue.async(flags: .barrier) {
            var stat = self._statsDict[dateKey] ?? DailyStat(dateString: dateKey, languageSwitches: 0, typoCorrections: 0)
            stat.typoCorrections += 1
            self._statsDict[dateKey] = stat
            self.publishUpdate()
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
    
    // 🌟 [수정됨] @objc 키워드 삭제 (순수 Swift 함수로 사용)
    private func forceSave() {
        var snapshot: [String: DailyStat] = [:]
        stateQueue.sync { snapshot = self._statsDict }
        
        saveQueue.async {
            let statsArray = Array(snapshot.values).sorted { $0.dateString < $1.dateString }
            if let data = try? JSONEncoder().encode(statsArray) {
                UserDefaults.standard.set(data, forKey: self.defaultsKey)
            }
        }
    }
    
    private func loadStats() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([DailyStat].self, from: data) {
            for stat in decoded {
                _statsDict[stat.dateString] = stat
            }
            self.dailyStats = decoded.sorted { $0.dateString < $1.dateString }
        }
    }
    
    private func publishUpdate() {
        let snapshot = Array(self._statsDict.values).sorted { $0.dateString < $1.dateString }
        DispatchQueue.main.async {
            self.dailyStats = snapshot
        }
    }
    
    private static let todayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()

    private func todayKey() -> String {
        return Self.todayFormatter.string(from: Date())
    }
    
    // MARK: - 운영 및 관리 기능 (초기화 및 내보내기)
    
    func resetStats() {
        stateQueue.async(flags: .barrier) {
            self._statsDict.removeAll()
            self.publishUpdate()
            
            UserDefaults.standard.removeObject(forKey: self.defaultsKey)
        }
    }
    
    func exportToCSV(to url: URL, completion: @escaping (Bool, Error?) -> Void) {
        
        let snapshot = stateQueue.sync {
            return self._statsDict
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
