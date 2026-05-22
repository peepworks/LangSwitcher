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
    @State private var selectedDateString: String? = nil
    @State private var animateChart = false
    
    // 🌟 [핵심 개선] computed property 연산을 완전히 제거하고,
    // StatsManager가 계산해둔 캐시를 즉시 참조합니다.
    private var filteredStats: [DailyStat] {
        return statsManager.filteredStatsCache
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
        // 🌟 [추가] 뷰 라이프사이클 및 상태 변경 시 캐시 업데이트 트리거
        .onAppear {
            statsManager.updateFilteredStats(for: selectedRange)
        }
        .onChange(of: selectedRange) { newValue in
            statsManager.updateFilteredStats(for: newValue)
        }
        .onChange(of: statsManager.dailyStats) { _ in
            statsManager.updateFilteredStats(for: selectedRange)
        }
    }
    
    // MARK: - 차트 렌더링 뷰
    private var chartView: some View {
        Chart(filteredStats) { stat in
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
        .chartXScale(domain: .automatic)
        .chartYScale(domain: 0...yDomainMax)
        .chartXAxis {
            let step = selectedRange == .week ? 1 : (selectedRange == .month ? 5 : max(1, filteredStats.count / 6))
            let xValues: [String] = stride(from: filteredStats.count - 1, through: 0, by: -step)
                .map { filteredStats[$0].dateString }
                .reversed()
            
            AxisMarks(values: xValues) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let str = value.as(String.self) {
                        Text(formatAxisDate(parseDate(str)))
                            .font(.caption2)
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
        .padding(.trailing, 10)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
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
                    
                    if let selectedDateString,
                       let stat = filteredStats.first(where: { $0.dateString == selectedDateString }),
                       let xPosition = proxy.position(forX: selectedDateString) {
                        
                        let tooltipWidth: CGFloat = 120
                        let plotWidth = geometry[proxy.plotAreaFrame].width
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
    
    // 🌟 [최적화] 매 렌더링마다 생성되던 무거운 DateFormatter를 정적 변수로 빼내어 재사용합니다.
    private static let axisDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter
    }()
    
    private static let parseDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter
    }()
    
    private func formatAxisDate(_ date: Date) -> String {
        return Self.axisDateFormatter.string(from: date)
    }

    private func parseDate(_ dateString: String) -> Date {
        return Self.parseDateFormatter.date(from: dateString) ?? Date()
    }
    
    private func exportData() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "LangSwitcher_Stats.csv"
        
        if panel.runModal() == .OK, let url = panel.url {
            statsManager.exportToCSV(to: url) { success, error in
                if !success, let err = error {
                    dprint("CSV Export Failed: \(err)")
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
        
        if let appIcon = NSImage(named: NSImage.applicationIconName) {
            alert.icon = appIcon
        }
        
        NSApp.activate(ignoringOtherApps: true)
        
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
