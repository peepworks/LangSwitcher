//
//  EdgeGlowManager.swift
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
import AppKit
import Combine

class EdgeGlowState: ObservableObject {
    @Published var color: Color = .clear
}

@MainActor
class EdgeGlowManager {
    static let shared = EdgeGlowManager()

    private var glowWindow: NSWindow?
    private var currentGlowID = UUID()
    private var isCurrentlyGlowing: Bool = false
    private let glowState = EdgeGlowState()

    private init() {}

    private func getOrCreateWindow() -> NSWindow {
        if let existing = glowWindow { return existing }

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

        if !isCurrentlyGlowing {
            isCurrentlyGlowing = true

            // 🌟 [4번 리뷰 수복 포인트] 지저분했던 자체 파싱 문자열을 소각하고 중앙 표준 토큰 라인을 연결합니다.
            let language = InputLanguage.determine(from: id)
            let randomHue: Double

            if language == .korean {
                randomHue = Double.random(in: 0.5...0.8)
            } else {
                let warmTones = [Double.random(in: 0.0...0.1), Double.random(in: 0.9...1.0)]
                randomHue = warmTones.randomElement() ?? 0.1
            }

            glowState.color = Color(hue: randomHue, saturation: 0.85, brightness: 1.0)

            window.alphaValue = 0.0
            window.orderFrontRegardless()

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                window.animator().alphaValue = 1.0
            }
        }

        Task { @MainActor [weak self] in
            // 0.8초 대기
            try? await Task.sleep(nanoseconds: 800_000_000)

            guard let self = self, self.currentGlowID == myID else { return }

            // CheckedContinuation 안전 가드 구역 유지
            do {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    var isResumed = false
                    
                    NSAnimationContext.runAnimationGroup({ context in
                        context.duration = 0.3
                        window.animator().alphaValue = 0
                    }, completionHandler: {
                        MainActor.assumeIsolated {
                            guard !isResumed else { return }
                            isResumed = true
                            continuation.resume()
                        }
                    })
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        guard !isResumed else { return }
                        isResumed = true
                        continuation.resume(throwing: NSError(domain: "EdgeGlowManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "AppKit animation completion skipped safely via timeout safety net."]))
                    }
                }
            } catch {
                dprint("👻 [EdgeGlowManager] AppKit 애니메이션 완료 콜백 유실 감지: 세이프티 가드가 대기 스레드를 강제 구출했습니다.")
                window.alphaValue = 0
            }

            guard self.currentGlowID == myID else { return }
            self.isCurrentlyGlowing = false
            window.orderOut(nil)
        }
    }
}

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
