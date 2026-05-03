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
    
    // 🌟 300초(5분)마다 모아둔 통계 데이터를 안전하게 디스크에 저장하는 타이머
    private func startBatchSaveTimer() {
        // ⚠️ 수정됨: 백그라운드 스레드에서 초기화되더라도, 타이머 생성은 무조건 메인 런루프에서 돌도록 강제합니다.
        DispatchQueue.main.async {
            self.saveTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
                self?.forceSave() // 5분마다 실행될 저장 로직
            }
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
    
    // 🌟 1. 앱 수명 주기 동안 단 한 번만 생성되고 재사용되는 정적(Static) 포매터
    private static let todayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current // 현재 사용자의 타임존을 명확히 지정
        return formatter
    }()

    // 🌟 2. 매번 생성하는 대신, 위에 만들어둔 포매터를 그대로 가져다 씁니다.
    private func todayKey() -> String {
        return Self.todayFormatter.string(from: Date())
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
    
    // 🌟 통계 데이터를 CSV 파일로 내보내는 함수
    func exportToCSV(to url: URL, completion: @escaping (Bool, Error?) -> Void) {
        
        // 1. [핵심 수정] 상태 큐에서는 오직 '안전한 복사본(Snapshot)'만 0.001초 만에 빠르게 가져옵니다.
        let snapshot = stateQueue.sync {
            return self._statsDict
        }
        
        // 2. CSV로 변환하고 파일에 쓰는 '무거운 작업'은 상태 큐를 괴롭히지 않고 일반 백그라운드 스레드에서 진행합니다.
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                var csvString = "Date,Type,Count\n"
                
                // 🌟 원본(_statsDict)이 아닌, 안전하게 복사된 snapshot을 가지고 작업합니다.
                // 🌟 원본(_statsDict)이 아닌, 안전하게 복사된 snapshot을 가지고 작업합니다.
                for (dateKey, dailyStats) in snapshot {
                    
                    // ✅ DailyStat 구조체에 정의된 진짜 이름으로 완벽 매칭!
                    let switchCount = dailyStats.languageSwitches
                    let typoCount = dailyStats.typoCorrections
                    
                    // 문자열 결합
                    csvString += "\(dateKey),LanguageSwitch,\(switchCount)\n"
                    csvString += "\(dateKey),TypoCorrection,\(typoCount)\n"
                }
                
                // 파일 저장
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
