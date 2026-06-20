//
//  StatsSettingsView.swift
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
    @State private var showExpansions: Bool = true // 🌟 [수복 추가] 텍스트 대치 차트 토글선
    @State private var selectedDateString: String? = nil
    @State private var animateChart = false

    private var filteredStats: [DailyStat] {
        return statsManager.filteredStatsCache
    }

    var todayStats: DailyStat { filteredStats.last ?? DailyStat(dateString: "", languageSwitches: 0, typoCorrections: 0, textExpansions: 0) }
    var yesterdayStats: DailyStat { filteredStats.dropLast().last ?? DailyStat(dateString: "", languageSwitches: 0, typoCorrections: 0, textExpansions: 0) }
    
    var totalSwitches: Int { filteredStats.reduce(0) { $0 + $1.languageSwitches } }
    var totalTypos: Int { filteredStats.reduce(0) { $0 + $1.typoCorrections } }
    var totalExpansions: Int { filteredStats.reduce(0) { $0 + $1.textExpansions } } // 🌟 누적 합산 추가
    var isEmptyState: Bool { totalSwitches == 0 && totalTypos == 0 && totalExpansions == 0 }

    // O(N) 단일 루프로 3개 축 전체의 최고 임계치 최대값 정산
    var yDomainMax: Int {
        let highest = filteredStats.reduce(0) { currentMax, stat in
            max(currentMax, max(stat.languageSwitches, max(stat.typoCorrections, stat.textExpansions)))
        }
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

            // 🌟 [스크린샷 2차원 대응 수복] 2열 레이아웃을 청정 3열 가로 스택 피드로 전치 확장
            HStack(spacing: 16) {
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
                    icon: "textformat.abc.dottedunderline",
                    color: .green,
                    tooltip: String(localized: "Counts both manual shortcut corrections and smart auto-corrections (English → Korean).")
                )
                StatCard(
                    title: String(localized: "Text Expansions"), // 🌟 3번 카드 안착
                    count: todayStats.textExpansions,
                    previousCount: yesterdayStats.textExpansions,
                    icon: "text.badge.plus",
                    color: .purple,
                    tooltip: String(localized: "Counts the number of snippets expanded instantly via preset keyword triggers.")
                )
            }

            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Text(String(localized: "Trend Analysis")).font(.headline)
                    Spacer()
                    HStack(spacing: 16) {
                        Toggle(String(localized: "Switches"), isOn: $showSwitches)
                            .toggleStyle(.checkbox).tint(.blue)
                        Toggle(String(localized: "Typos"), isOn: $showTypos)
                            .toggleStyle(.checkbox).tint(.green)
                        Toggle(String(localized: "Expansions"), isOn: $showExpansions) // 🌟 필터 토글 증설
                            .toggleStyle(.checkbox).tint(.purple)
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
        .onAppear {
            statsManager.updateFilteredStats(for: selectedRange)
        }
        .onChange(of: selectedRange) { newValue in
            statsManager.updateFilteredStats(for: newValue)
        }
        .onChange(of: statsManager.filteredStatsCache.count) { _ in
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

            if showExpansions { // 🌟 3차 축 차트 렌더링 구역 바인딩 보정
                BarMark(
                    x: .value(String(localized: "Date"), stat.dateString),
                    y: .value(String(localized: "Expansions"), animateChart ? stat.textExpansions : 0)
                )
                .foregroundStyle(by: .value(String(localized: "Category"), String(localized: "Expansions")))
                .position(by: .value(String(localized: "Category"), String(localized: "Expansions")))
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
            String(localized: "Typos"): Color.green.gradient,
            String(localized: "Expansions"): Color.purple.gradient // 🌟 보라색 테마 팔레트 결속
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

                        let tooltipWidth: CGFloat = 140
                        let plotWidth = geometry[proxy.plotAreaFrame].width
                        let adjustedX = min(max(xPosition, tooltipWidth / 2), plotWidth - tooltipWidth / 2)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(formatAxisDate(parseDate(stat.dateString))).font(.caption.bold())
                            if showSwitches { Text("\(String(localized: "Switches")): \(stat.languageSwitches)").font(.caption).foregroundColor(.blue) }
                            if showTypos { Text("\(String(localized: "Typos")): \(stat.typoCorrections)").font(.caption).foregroundColor(.green) }
                            if showExpansions { Text("\(String(localized: "Expansions")): \(stat.textExpansions)").font(.caption).foregroundColor(.purple) } // 🌟 툴팁 연동 완결
                        }
                        .padding(8)
                        .frame(width: tooltipWidth)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                        .shadow(radius: 3)
                        .position(x: adjustedX, y: -25)
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
        .onDisappear { animateChart = false }
    }

    // MARK: - Actions
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

    private func formatAxisDate(_ date: Date) -> String { Self.axisDateFormatter.string(from: date) }
    private func parseDate(_ dateString: String) -> Date { Self.parseDateFormatter.date(from: dateString) ?? Date() }

    private func exportData() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "LangSwitcher_Stats.csv"

        if panel.runModal() == .OK, let url = panel.url {
            statsManager.exportToCSV(to: url) { success, error in
                if !success, let err = error { dprint("CSV Export Failed: \(err)") }
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
        if let appIcon = NSImage(named: NSImage.applicationIconName) { alert.icon = appIcon }

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { statsManager.resetStats() }
    }
}

// MARK: - Subviews
struct StatCard: View {
    let title: String
    let count: Int
    let previousCount: Int
    let icon: String
    let color: Color
    let tooltip: String

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
            Text(String(localized: "Your statistics will appear here once you start typing."))
                .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 250)
    }
}
