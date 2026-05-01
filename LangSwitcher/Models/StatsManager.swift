//
//  HyperKeyManager.swift
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
        
        // 🌟 앱 종료 시 누락 없이 디스크에 기록하도록 옵저버 등록
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(forceSave),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
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
        saveTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.forceSave()
        }
    }
    
    @objc private func forceSave() {
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
    
    private func todayKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
    // MARK: - 운영 및 관리 기능 (초기화 및 내보내기)
    
    func resetStats() {
        stateQueue.async(flags: .barrier) {
            self._statsDict.removeAll()
            self.publishUpdate()
            
            // 디스크 데이터도 함께 날림
            UserDefaults.standard.removeObject(forKey: self.defaultsKey)
        }
    }
    
    func exportToCSV(to url: URL, completion: @escaping (Bool, Error?) -> Void) {
        stateQueue.async {
            let statsArray = Array(self._statsDict.values).sorted { $0.dateString < $1.dateString }
            
            var csvString = "Date,Language Switches,Typo Corrections\n"
            for stat in statsArray {
                csvString += "\(stat.dateString),\(stat.languageSwitches),\(stat.typoCorrections)\n"
            }
            
            do {
                try csvString.write(to: url, atomically: true, encoding: .utf8)
                DispatchQueue.main.async { completion(true, nil) }
            } catch {
                DispatchQueue.main.async { completion(false, error) }
            }
        }
    }
}
