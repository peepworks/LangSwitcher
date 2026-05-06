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
import AppKit
import Combine

// 🌟 [핵심 1] 뷰를 새로 만들지 않고 색상만 교체하기 위한 상태 통
class EdgeGlowState: ObservableObject {
    @Published var color: Color = .clear
}

// 🌟 [핵심 2] 클래스 전체를 메인 스레드에 격리하여 완벽한 UI 안전성 보장
@MainActor
class EdgeGlowManager {
    static let shared = EdgeGlowManager()
    
    private var glowWindow: NSWindow?
    private var currentGlowID = UUID()
    
    // 현재 빛이 켜져 있는 상태인지 추적하는 변수
    private var isCurrentlyGlowing: Bool = false
    
    private let glowState = EdgeGlowState()
    
    private init() {}

    private func getOrCreateWindow() -> NSWindow {
        if let existing = glowWindow {
            return existing
        }
        
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        window.isReleasedWhenClosed = false
        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.ignoresMouseEvents = true
        
        let contentView = NSHostingView(rootView: EdgeGlowView(state: glowState))
        window.contentView = contentView
        
        self.glowWindow = window
        return window
    }

    func showGlow(forLanguage id: String) {
        guard SettingsManager.shared.snapshot.isEdgeGlowEnabled else { return }
        
        // 새로운 타자 입력이 들어왔으므로 ID 갱신 (기존의 꺼짐 타이머 취소용)
        let myID = UUID()
        self.currentGlowID = myID
        
        let window = getOrCreateWindow()
        
        if let mainScreen = NSScreen.main {
            let screenFrame = mainScreen.frame
            let visibleFrame = mainScreen.visibleFrame
            
            let notchHeight: CGFloat = screenFrame.height - visibleFrame.maxY
            let windowHeight: CGFloat = max(notchHeight + 10, 44)
            
            window.setFrame(NSRect(x: 0, y: screenFrame.height - windowHeight, width: screenFrame.width, height: windowHeight), display: true)
        }
        
        // 🌟 [핵심 3] 빛이 꺼져 있을 때만 색상을 새로 정하고 페이드인을 시작합니다!
        // (이미 켜져 있는 상태에서 타자를 칠 때는 이 블록을 건너뛰어 번쩍거림 방지)
        if !isCurrentlyGlowing {
            isCurrentlyGlowing = true
            
            let isKorean = id.lowercased().contains("ko") || id.contains("Hangul") || id.contains("두벌식") || id.contains("세벌식")
            let randomHue: Double
            
            if isKorean {
                randomHue = Double.random(in: 0.5...0.8) // 한글: 푸른색/보라색
            } else {
                let warmTones = [Double.random(in: 0.0...0.1), Double.random(in: 0.9...1.0)]
                randomHue = warmTones.randomElement() ?? 0.1 // 영어: 주황색/분홍색
            }
                    
            glowState.color = Color(hue: randomHue, saturation: 0.85, brightness: 1.0)
            
            window.alphaValue = 0.0
            window.orderFrontRegardless()
            
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                window.animator().alphaValue = 1.0
            }
        }
        
        // 🌟 [핵심 4] 타자를 칠 때마다 이 '꺼짐 예약'이 계속 새로 세팅됩니다.
        // 0.8초 동안 아무 입력이 없어야 비로소 애니메이션이 실행되며 꺼집니다.
        // 🌟 [핵심 4] 타자를 칠 때마다 이 '꺼짐 예약'이 계속 새로 세팅됩니다.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard self.currentGlowID == myID else { return }
            
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                window.animator().alphaValue = 0
            } completionHandler: {
                // 🌟 [수정됨] 컴파일러의 Strict Concurrency 에러를 해결하기 위해
                // 메인 큐로 다시 한번 확실하게 감싸줍니다!
                DispatchQueue.main.async {
                    guard self.currentGlowID == myID else { return }
                    self.isCurrentlyGlowing = false
                    window.orderOut(nil)
                }
            }
        }
    }
}

// 뷰는 그대로 사용!
struct EdgeGlowView: View {
    @ObservedObject var state: EdgeGlowState
    
    var body: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [state.color.opacity(0.6), state.color.opacity(0.1), .clear]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 30)
                .blur(radius: 15)
            
            Rectangle()
                .fill(state.color)
                .frame(height: 2)
                .opacity(0.8)
        }
    }
}
