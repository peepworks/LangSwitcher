//
//  DebuggerSettingsView.swift
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

struct DebuggerSettingsView: View {
    @ObservedObject var traceManager = DecisionTraceManager.shared
    
    // 🌟 [수정됨] 뷰 안에서 자를 때는 'traceManager.'을 꼭 붙여줘야 합니다.
    var historyTraces: [DecisionTrace] {
        return Array(traceManager.recentTraces.dropFirst().prefix(20))
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                
                // 1. Header & Options
                HStack {
                    Text(String(localized: "Rule Debugger")).font(.title2.bold())
                    Spacer()
                    Button(role: .destructive, action: {
                        traceManager.clear()
                    }) {
                        Text(String(localized: "Clear Logs"))
                    }
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    SettingToggleRow(title: String(localized: "Enable Execution Logging"), isOn: $traceManager.isTraceLoggingEnabled)
                    Text(String(localized: "Logs the reasons for automatic language switching and text expansion. No sensitive text is saved."))
                        .font(.caption).foregroundColor(.secondary).lineSpacing(2)
                        .padding(.horizontal, 15).padding(.bottom, 12).padding(.top, -2)
                }
                
                Divider()
                
                // 2. Latest Execution Card (최근 실행 카드)
                if let latest = traceManager.recentTraces.first {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "Last Execution")).font(.headline)
                        
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(latest.eventType.rawValue.capitalized)
                                    .font(.caption.bold())
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Color.accentColor.opacity(0.2))
                                    .cornerRadius(6)
                                
                                Text(latest.resultType.rawValue.capitalized)
                                    .font(.caption.bold())
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(resultColor(for: latest.resultType).opacity(0.2))
                                    .foregroundColor(resultColor(for: latest.resultType))
                                    .cornerRadius(6)
                                
                                Spacer()
                                Text(latest.timestamp, style: .time).font(.caption).foregroundColor(.secondary)
                            }
                            
                            Text(latest.reasonMessage)
                                .font(.body.weight(.medium))
                            
                            if let appName = latest.appName {
                                Text("\(String(localized: "Target App")): \(appName)")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                    }
                }
                
                // 3. Recent History List (최근 기록 리스트)
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "Recent History")).font(.headline)
                    
                    if traceManager.recentTraces.isEmpty {
                        Text(String(localized: "No logs available."))
                            .foregroundColor(.secondary)
                            .padding(.vertical, 10)
                    } else {
                        
                        LazyVStack(spacing: 0) {
                            
                            // 🌟 [수정됨] 위에서 만든 historyTraces 변수를 직접 사용합니다. (traceManager. 빼기)
                            ForEach(historyTraces, id: \.id) { trace in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(trace.reasonMessage).font(.subheadline)
                                        Text(trace.eventType.rawValue).font(.caption).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text(trace.resultType.rawValue.capitalized)
                                            .font(.caption.bold())
                                            .foregroundColor(resultColor(for: trace.resultType))
                                        Text(trace.timestamp, style: .time).font(.caption2).foregroundColor(.secondary)
                                    }
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 15)
                                
                                Divider()
                            }
                        }
                        .background(Color(NSColor.textBackgroundColor)).cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                    }
                }
            }
            .padding(25)
        }
    }
    
    // 결과에 따른 상태 색상 매핑
    private func resultColor(for result: DecisionTrace.ResultType) -> Color {
        switch result {
        case .switched, .expanded, .restored: return .green
        case .kept, .skipped, .blocked: return .orange
        case .failed: return .red
        }
    }
}
