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

// 🌟 [핵심 1] 뷰를 새로 만들지 않고 색상만 교체하기 위한 상태 통(ObservableObject)
class EdgeGlowState: ObservableObject {
    @Published var color: Color = .clear
}

class EdgeGlowManager {
    static let shared = EdgeGlowManager()
    
    private var glowWindow: NSWindow?
    private var currentGlowID = UUID()
    
    // 상태를 관리할 객체 인스턴스
    private let glowState = EdgeGlowState()
    
    private init() {}

    @MainActor
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
        
        // 🌟 [핵심 2] 윈도우 생성 시 최초 1번만 NSHostingView를 할당합니다.
        let contentView = NSHostingView(rootView: EdgeGlowView(state: glowState))
        window.contentView = contentView
        
        self.glowWindow = window
        return window
    }

    @MainActor
    func showGlow(forLanguage id: String) {
        guard SettingsManager.shared.snapshot.isEdgeGlowEnabled else { return }
        
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
        
        // 🌟 [핵심 수정] 언어 ID를 활용하면서도 다채로운 랜덤성을 부여합니다.
        let isKorean = id.lowercased().contains("ko") || id.contains("Hangul") || id.contains("두벌식") || id.contains("세벌식")
                
        let randomHue: Double
        if isKorean {
            // 한글: 푸른색/보라색 계열 (Hue 0.5 ~ 0.8 사이 랜덤)
            randomHue = Double.random(in: 0.5...0.8)
        } else {
            // 영어: 주황색/분홍색 계열 (Hue 0.0 ~ 0.1 또는 0.9 ~ 1.0 사이 랜덤)
            let warmTones = [Double.random(in: 0.0...0.1), Double.random(in: 0.9...1.0)]
            randomHue = warmTones.randomElement() ?? 0.1
        }
                
        let glowColor = Color(hue: randomHue, saturation: 0.85, brightness: 1.0)
        
        // 🌟 [핵심 3] 무거운 뷰를 다시 만들지 않고, 상태 객체의 색상만 업데이트합니다!
        glowState.color = glowColor
        
        // 🌟 [최적화] SwiftUI의 onAppear를 대체하여, 창 자체가 서서히 나타나게 만듭니다. (깜빡임 방지)
        window.alphaValue = 0.0
        window.makeKeyAndOrderFront(nil)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            window.animator().alphaValue = 1.0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard self.currentGlowID == myID else { return }
            
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                window.animator().alphaValue = 0
            } completionHandler: {
                DispatchQueue.main.async {
                    guard self.currentGlowID == myID else { return }
                    window.orderOut(nil)
                }
            }
        }
    }
}

// 🌟 [수정됨] opacity 애니메이션을 덜어내어 훨씬 가벼워진 SwiftUI 뷰
struct EdgeGlowView: View {
    @ObservedObject var state: EdgeGlowState // 전달받은 상태를 구독
    
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
        // SwiftUI의 .opacity()와 .onAppear()는 제거되었습니다. (AppKit이 담당)
    }
}
