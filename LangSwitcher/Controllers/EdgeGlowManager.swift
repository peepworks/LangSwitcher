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

class EdgeGlowManager {
    static let shared = EdgeGlowManager()
    private var glowWindow: NSWindow?
    
    // 현재 실행 중인 글로우 효과의 고유 ID (타이머 충돌 방지용)
    private var currentGlowID = UUID()
    
    private init() {}

    @MainActor // 메인 스레드 실행 강제 보장
    func showGlow(forLanguage id: String) {
        guard SettingsManager.shared.snapshot.isEdgeGlowEnabled else { return }
        
        // 이번 글로우 효과에 대한 고유 번호표 발급
        let myID = UUID()
        self.currentGlowID = myID
        
        // 1. 기존 창이 있으면 닫기 (중복 방지)
        glowWindow?.close()
        
        // 2. 화면 크기 계산 (노치 영역 고려)
        guard let mainScreen = NSScreen.main else { return }
        let screenFrame = mainScreen.frame
        let visibleFrame = mainScreen.visibleFrame
        
        // 노치 높이 계산 (일반적으로 32~36pt)
        let notchHeight: CGFloat = screenFrame.height - visibleFrame.maxY
        let windowHeight: CGFloat = max(notchHeight + 10, 44) // 노치보다 살짝 여유 있게
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: screenFrame.height - windowHeight, width: screenFrame.width, height: windowHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        window.isReleasedWhenClosed = false
        window.level = .screenSaver // 최상단 레이어
        window.backgroundColor = .clear
        window.isOpaque = false
        window.ignoresMouseEvents = true // 클릭 통과
        
        // 언어에 따른 색상 (한글: 파랑, 영어: 주황)
        let isKorean = id.lowercased().contains("ko") || id.contains("Hangul") || id.contains("두벌식") || id.contains("세벌식")
        let glowColor = isKorean ? Color.blue : Color.orange
        
        let contentView = NSHostingView(rootView: EdgeGlowView(color: glowColor))
        window.contentView = contentView
        
        self.glowWindow = window
        window.makeKeyAndOrderFront(nil)
        
        // 0.8초 후 자동으로 사라짐
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            // 0.8초가 지나는 동안 새로운 글로우가 켜졌다면,
            // 현재 타이머는 구버전이므로 남의 창을 건드리지 않고 조용히 종료합니다.
            guard self.currentGlowID == myID else { return }
            
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                window.animator().alphaValue = 0
            } completionHandler: {
                // 🌟 [핵심 방어 로직 적용]
                // 콜백이 비정상적인 스레드에서 떨어지더라도 UI 작업은 무조건 메인 스레드에서 처리되도록 강제 보장합니다.
                DispatchQueue.main.async {
                    // 애니메이션이 끝나는 0.3초 사이에도 새 창이 뜰 수 있으므로 다시 한번 꼼꼼하게 검사
                    guard self.currentGlowID == myID else { return }
                    window.close()
                    self.glowWindow = nil
                }
            }
        }
    }
}

// SwiftUI 글로우 뷰
struct EdgeGlowView: View {
    let color: Color
    @State private var opacity: Double = 0
    
    var body: some View {
        ZStack(alignment: .top) {
            // 노치 주변 또는 상단 테두리에 은은한 그라데이션 광원
            Rectangle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [color.opacity(0.6), color.opacity(0.1), .clear]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 30)
                .blur(radius: 15) // 빛이 번지는 효과
            
            // 아주 얇은 상단 선 (디테일)
            Rectangle()
                .fill(color)
                .frame(height: 2)
                .opacity(0.8)
        }
        .opacity(opacity)
        .onAppear {
            withAnimation(.easeOut(duration: 0.2)) {
                opacity = 1.0
            }
        }
    }
}
