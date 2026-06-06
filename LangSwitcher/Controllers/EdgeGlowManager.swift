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

            let isKorean = id.lowercased().contains("ko") || id.contains("Hangul") || id.contains("두벌식") || id.contains("세벌식")
            let randomHue: Double

            if isKorean {
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

            // 🌟 [최종 최적화 수복 구역]
            // CheckedContinuation의 이중 호출 크래시 및 영구 프리즈 트랩을 방어하기 위해
            // 원자적 격리 플래그와 낙하산 타임아웃 레이싱 아키텍처를 결합 구축합니다.
            do {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    // 메인 스레드 상주 이중 정산 방어 자물쇠
                    var isResumed = false
                    
                    // 경로 A: AppKit 정상 애니메이션 완료 핸들러 진입점
                    NSAnimationContext.runAnimationGroup({ context in
                        context.duration = 0.3
                        window.animator().alphaValue = 0
                    }, completionHandler: {
                        MainActor.assumeIsolated {
                            // 타임아웃 가드가 먼저 스레드를 깨웠다면 중복 resume 없이 생략 퇴근합니다.
                            guard !isResumed else { return }
                            isResumed = true
                            continuation.resume()
                        }
                    })
                    
                    // 경로 B: AppKit 완료 콜백 유실 방지용 0.5초 비상 타임아웃 가드
                    // 애니메이션 시간(0.3초) 보다 약간의 버퍼를 둔 뒤, 런타임이 영구 동결되는 것을 막습니다.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        guard !isResumed else { return }
                        isResumed = true
                        
                        continuation.resume(throwing: NSError(domain: "EdgeGlowManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "AppKit animation completion skipped safely via timeout safety net."]))
                    }
                }
            } catch {
                // OS 환경 변수로 완료 핸들러가 누락되었을 때 도달하는 안전지대
                dprint("👻 [EdgeGlowManager] AppKit 애니메이션 완료 콜백 유실 감지: 세이프티 가드가 대기 스레드를 강제 구출했습니다.")
                window.alphaValue = 0 // 창 투명도를 강제로 정산하여 물리적 연산 마무리
            }

            // 애니메이션이 무사히 끝난 후 메인 액터 보장 안전지대에서 최종 자원 반납
            guard self.currentGlowID == myID else { return }
            self.isCurrentlyGlowing = false
            window.orderOut(nil)
        }
    }
}

// 노치 글로우 컴포넌트 뷰 레이어 유지
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
