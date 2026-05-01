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

import SwiftUI
import Charts
import UniformTypeIdentifiers

enum TimeRange: String, CaseIterable, Identifiable {
    case week = "week"
    case month = "month"
    case all = "all"
    var id: String { self.rawValue }
    
    var localizedName: String {
        switch self {
        case .week: return String(localized: "Last 7 Days")
        case .month: return String(localized: "Last 30 Days")
        case .all: return String(localized: "All Time")
        }
    }
}

struct StatsSettingsView: View {
    @ObservedObject private var statsManager = StatsManager.shared
    
    @State private var selectedRange: TimeRange = .week
    @State private var showSwitches: Bool = true
    @State private var showTypos: Bool = true
    // 🌟 [수정됨] Date 객체 대신 String을 사용하여 카테고리 매칭에 사용합니다.
    @State private var selectedDateString: String? = nil
    @State private var animateChart = false
    
    var filteredStats: [DailyStat] {
        var result: [DailyStat] = []
        let calendar = Calendar.current
        let today = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        let daysToFetch: Int
        switch selectedRange {
        case .week: daysToFetch = 7
        case .month: daysToFetch = 30
        case .all:
            let sorted = statsManager.dailyStats.sorted { $0.dateString < $1.dateString }
            if let first = sorted.first, let firstDate = formatter.date(from: first.dateString) {
                daysToFetch = max(1, calendar.dateComponents([.day], from: firstDate, to: today).day ?? 1) + 1
            } else {
                daysToFetch = 7
            }
        }
        
        for i in (0..<daysToFetch).reversed() {
            if let date = calendar.date(byAdding: .day, value: -i, to: today) {
                let dateString = formatter.string(from: date)
                if let existingStat = statsManager.dailyStats.first(where: { $0.dateString == dateString }) {
                    result.append(existingStat)
                } else {
                    result.append(DailyStat(dateString: dateString, languageSwitches: 0, typoCorrections: 0))
                }
            }
        }
        return result
    }
    
    var todayStats: DailyStat { filteredStats.last ?? DailyStat(dateString: "", languageSwitches: 0, typoCorrections: 0) }
    var yesterdayStats: DailyStat { filteredStats.dropLast().last ?? DailyStat(dateString: "", languageSwitches: 0, typoCorrections: 0) }
    var totalSwitches: Int { filteredStats.reduce(0) { $0 + $1.languageSwitches } }
    var totalTypos: Int { filteredStats.reduce(0) { $0 + $1.typoCorrections } }
    var isEmptyState: Bool { totalSwitches == 0 && totalTypos == 0 }
    
    var yDomainMax: Int {
        let maxSwitches = filteredStats.map { $0.languageSwitches }.max() ?? 0
        let maxTypos = filteredStats.map { $0.typoCorrections }.max() ?? 0
        let highest = max(maxSwitches, maxTypos)
        return highest < 5 ? 5 : Int(Double(highest) * 1.3)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 25) {
            HStack {
                Text(String(localized: "Usage Statistics")).font(.title2.bold())
                Spacer()
                Picker("", selection: $selectedRange) {
                    ForEach(TimeRange.allCases) { range in
                        Text(range.localizedName).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 250)
            }
            
            HStack(spacing: 20) {
                StatCard(
                    title: String(localized: "Language Switches"),
                    count: todayStats.languageSwitches,
                    previousCount: yesterdayStats.languageSwitches,
                    icon: "globe",
                    color: .blue,
                    tooltip: String(localized: "Includes both manual shortcut uses and app-specific/window-memory auto switches.")
                )
                StatCard(
                    title: String(localized: "Typos Corrected"),
                    count: todayStats.typoCorrections,
                    previousCount: yesterdayStats.typoCorrections,
                    icon: "text.cursor",
                    color: .green,
                    tooltip: String(localized: "Counts both manual shortcut corrections and smart auto-corrections (English → Korean).")
                )
            }
            
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Text(String(localized: "Trend Analysis")).font(.headline)
                    Spacer()
                    HStack(spacing: 12) {
                        Toggle(String(localized: "Switches"), isOn: $showSwitches)
                            .toggleStyle(.checkbox)
                            .tint(.blue)
                        Toggle(String(localized: "Typos"), isOn: $showTypos)
                            .toggleStyle(.checkbox)
                            .tint(.green)
                    }
                    .font(.subheadline)
                }
                
                if isEmptyState {
                    EmptyStateView()
                } else {
                    chartView
                }
            }
            .padding(20)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
            
            HStack {
                Spacer()
                Button(action: exportData) {
                    Label(String(localized: "Export to CSV..."), systemImage: "square.and.arrow.up")
                }
                .controlSize(.small)
                
                Button(role: .destructive, action: resetData) {
                    Label(String(localized: "Reset Stats"), systemImage: "trash")
                        .foregroundColor(.red)
                }
                .controlSize(.small)
            }
            
            Spacer()
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    
    // MARK: - 차트 렌더링 뷰
    private var chartView: some View {
        Chart(filteredStats) { stat in
            // 🌟 [핵심 1] Date 대신 String(stat.dateString)을 카테고리로 사용하여 막대 정중앙 정렬 완벽 보장
            if showSwitches {
                BarMark(
                    x: .value(String(localized: "Date"), stat.dateString),
                    y: .value(String(localized: "Switches"), animateChart ? stat.languageSwitches : 0)
                )
                .foregroundStyle(by: .value(String(localized: "Category"), String(localized: "Switches")))
                .position(by: .value(String(localized: "Category"), String(localized: "Switches")))
                .cornerRadius(4)
            }
            
            if showTypos {
                BarMark(
                    x: .value(String(localized: "Date"), stat.dateString),
                    y: .value(String(localized: "Typos"), animateChart ? stat.typoCorrections : 0)
                )
                .foregroundStyle(by: .value(String(localized: "Category"), String(localized: "Typos")))
                .position(by: .value(String(localized: "Category"), String(localized: "Typos")))
                .cornerRadius(4)
            }
            
            // 🌟 [핵심 2] 마우스 오버 시 표시할 점선 (annotation 삭제됨)
            if let selectedDateString, stat.dateString == selectedDateString {
                RuleMark(x: .value(String(localized: "Date"), stat.dateString))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                    .foregroundStyle(Color.secondary)
            }
        }
        .chartForegroundStyleScale([
            String(localized: "Switches"): Color.blue.gradient,
            String(localized: "Typos"): Color.green.gradient
        ])
        .chartXScale(domain: .automatic) // 텍스트 스케일 자동 정렬 유지
        .chartYScale(domain: 0...yDomainMax)
        .chartXAxis {
            // 🌟 [핵심 수정] 데이터 개수에 따라 X축 라벨을 그릴 간격(step)을 동적으로 계산합니다.
            let step = selectedRange == .week ? 1 : (selectedRange == .month ? 5 : max(1, filteredStats.count / 6))
            
            // 항상 오늘(마지막 인덱스)을 기준으로 역순으로 계산하여 최신 날짜가 라벨에서 누락되지 않게 합니다.
            let xValues: [String] = stride(from: filteredStats.count - 1, through: 0, by: -step)
                .map { filteredStats[$0].dateString }
                .reversed()
            
            // 명시적으로 계산된 xValues만 AxisMarks에 전달하여 겹침을 방지합니다.
            AxisMarks(values: xValues) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let str = value.as(String.self) {
                        Text(formatAxisDate(parseDate(str)))
                            .font(.caption2) // 🌟 좁은 공간에서도 예쁘게 보이도록 폰트 크기를 한 단계 낮춥니다.
                            // 🌟 [핵심 수정 1] 공간이 좁아도 "..."으로 생략되지 않도록 실제 크기를 강제로 보장합니다.
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Color.secondary.opacity(0.2))
                AxisValueLabel {
                    if let intValue = value.as(Int.self) {
                        Text(intValue, format: .number.notation(.compactName))
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .frame(height: 250)
        .padding(.top, 50)
        // 🌟 [핵심 수정 2] 차트 우측 끝에 10pt의 여백을 주어 마지막 날짜 라벨이 숨 쉴 공간을 확보합니다.
        .padding(.trailing, 10)
        // 🌟 [핵심 3] 툴팁을 차트 시스템과 완전히 분리된 오버레이(Overlay)에 그려서 흔들림 원천 차단
        .chartOverlay { proxy in
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    // 1. 마우스 이벤트 감지용 투명 패널
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                let xPosition = location.x - geometry[proxy.plotAreaFrame].origin.x
                                if let dateStr: String = proxy.value(atX: xPosition) {
                                    self.selectedDateString = dateStr
                                }
                            case .ended:
                                self.selectedDateString = nil
                            }
                        }
                    
                    // 2. 커스텀 툴팁 뷰 렌더링
                    if let selectedDateString,
                       let stat = filteredStats.first(where: { $0.dateString == selectedDateString }),
                       let xPosition = proxy.position(forX: selectedDateString) {
                        
                        let tooltipWidth: CGFloat = 120
                        let plotWidth = geometry[proxy.plotAreaFrame].width
                        // 툴팁이 차트 밖으로 잘리지 않도록 X 좌표 안전 영역 계산
                        let adjustedX = min(max(xPosition, tooltipWidth / 2), plotWidth - tooltipWidth / 2)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(formatAxisDate(parseDate(stat.dateString))).font(.caption.bold())
                            if showSwitches { Text("\(String(localized: "Switches")): \(stat.languageSwitches)").font(.caption).foregroundColor(.blue) }
                            if showTypos { Text("\(String(localized: "Typos")): \(stat.typoCorrections)").font(.caption).foregroundColor(.green) }
                        }
                        .padding(8)
                        .frame(width: tooltipWidth)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                        .shadow(radius: 3)
                        // 차트 바깥(Top Padding 영역)으로 띄워 올림
                        .position(x: adjustedX, y: -20)
                    }
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                    animateChart = true
                }
            }
        }
        .onDisappear {
            animateChart = false
        }
    }
    
    // MARK: - Actions
    
    private func formatAxisDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }

    private func parseDate(_ dateString: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.date(from: dateString) ?? Date()
    }
    
    private func exportData() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "LangSwitcher_Stats.csv"
        
        if panel.runModal() == .OK, let url = panel.url {
            statsManager.exportToCSV(to: url) { success, error in
                if !success, let err = error {
                    print("CSV Export Failed: \(err)")
                }
            }
        }
    }
    
    private func resetData() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Reset Statistics")
        alert.informativeText = String(localized: "Are you sure you want to delete all recorded statistics? This action cannot be undone.")
        alert.addButton(withTitle: String(localized: "Reset"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.alertStyle = .warning
        
        if alert.runModal() == .alertFirstButtonReturn {
            statsManager.resetStats()
        }
    }
}

// MARK: - Subviews

struct StatCard: View {
    let title: String
    let count: Int
    let previousCount: Int
    let icon: String
    let color: Color
    let tooltip: String // 🌟 [추가됨]
    
    var trendRatio: Double {
        if previousCount == 0 { return count > 0 ? 1.0 : 0.0 }
        return Double(count - previousCount) / Double(previousCount)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top) {
                Image(systemName: icon)
                    .font(.title3.bold())
                    .foregroundColor(color)
                    .frame(width: 36, height: 36)
                    .background(color.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                Spacer()
                
                if count > 0 || previousCount > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: trendRatio >= 0 ? "arrow.up.right" : "arrow.down.right")
                        Text(abs(trendRatio), format: .percent.precision(.fractionLength(0)))
                    }
                    .font(.caption.bold())
                    .foregroundColor(trendRatio >= 0 ? .green : .red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(trendRatio >= 0 ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                    .clipShape(Capsule())
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("\(count)")
                    .contentTransition(.numericText())
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                
                HStack(spacing: 4) {
                    Text(title).font(.subheadline).foregroundColor(.secondary)
                    // 🌟 [추가됨] 작은 정보 아이콘에 툴팁 연결
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.5))
                        .help(tooltip)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.5))
            Text(String(localized: "No data available yet."))
                .font(.headline)
                .foregroundColor(.primary)
            Text(String(localized: "Your statistics will appear here once you start typing."))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 250)
    }
}
