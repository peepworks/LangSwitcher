//
//  HUDManager.swift
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
import Cocoa
import ApplicationServices
import Combine

// MARK: - CursorHUD 상태 모델
@MainActor
final class CursorHUDModel: ObservableObject {
    @Published var symbol: String = ""
    @Published var name: String = ""
}

@MainActor
final class CenterHUDModel: ObservableObject {
    @Published var languageName: String = ""
}

// MARK: - HUDManager
@MainActor
final class HUDManager {
    static let shared = HUDManager()

    // 1. 중앙 HUD
    private var centerHUDWindow: NSPanel?
    private var centerHideTimer: Timer?
    private var centerHideGeneration: UInt = 0

    // 2. 커서 미니 HUD
    private var cursorHUDWindow: NSWindow?

    // 뷰 재생성 방지: 모델 + HostingView를 1회만 생성
    private var cursorHUDModel = CursorHUDModel()
    private var cursorHUDHostingView: NSHostingView<CursorHUDView>?

    // 타이머 completionHandler 경쟁 방지용 세대 카운터
    private var hideGeneration: UInt = 0
    
    // 중앙 HUD용 뷰 및 모델 인스턴스 (최초 1회만 생성)
    private let centerHUDModel = CenterHUDModel()
    private var centerHUDHostingView: NSHostingView<HUDView>?
    
    private var centerHUDTask: Task<Void, Never>?

    private init() {}

    // MARK: - 진입점

    func showHUD(languageName: String) {
        let snapshot = SettingsManager.shared.snapshot

        dprint("📍 HUD Debug: 호출됨! [CenterEnabled: \(snapshot.showVisualFeedback)] [MiniEnabled: \(snapshot.isCursorHUDEnabled)]")

        guard snapshot.showVisualFeedback || snapshot.isCursorHUDEnabled else {
            dprint("📍 HUD Debug: 모든 시각적 피드백 옵션이 꺼져있어 종료합니다.")
            return
        }

        // 1. 중앙 HUD 처리 (독립 실행)
        if snapshot.showVisualFeedback {
            self.showCenterHUD(languageName: languageName)
        }

        // 2. 커서 미니 HUD 처리 (독립 실행)
        if snapshot.isCursorHUDEnabled {
            if let cursorRect = self.getCursorRect() {
                self.showCursorMiniHUD(text: languageName, at: cursorRect)
            } else {
                if !snapshot.showVisualFeedback {
                    dprint("📍 HUD Debug: [Fallback] 미니 플래그 실패로 중앙 HUD를 대체 표시합니다.")
                    self.showCenterHUD(languageName: languageName)
                }
            }
        }
    }

    // MARK: - 화면 하단 정사각형 HUD 엔진 (간섭 버그 완전 해결본)

    private func showCenterHUD(languageName: String) {
        centerHUDModel.languageName = languageName

        let panelWidth: CGFloat = 200
        let panelHeight: CGFloat = 200

        if self.centerHUDWindow == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .statusBar
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            
            let hostingView = NSHostingView(rootView: HUDView(model: centerHUDModel))
            panel.contentView = hostingView
            self.centerHUDHostingView = hostingView
            self.centerHUDWindow = panel
        }

        if let screen = NSScreen.main {
            let x = screen.frame.midX - (panelWidth / 2)
            let y = screen.frame.minY + 120
            
            self.centerHUDWindow?.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
        }

        self.centerHUDWindow?.alphaValue = 0
        self.centerHUDWindow?.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            self.centerHUDWindow?.animator().alphaValue = 1.0
        }

        self.centerHideTimer?.invalidate()
        
        // 🌟 [수복 핵심] 미니 HUD와 간섭하지 않는 '중앙 HUD 전용' 장부 사용
        centerHideGeneration &+= 1
        let currentGeneration = centerHideGeneration

        self.centerHideTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                // 중앙 전용 장부 검사
                guard let self = self, self.centerHideGeneration == currentGeneration else { return }
                self.hideCenterHUD(for: currentGeneration)
            }
        }
    }

    private func hideCenterHUD(for generation: UInt) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            self.centerHUDWindow?.animator().alphaValue = 0.0
        }, completionHandler: {
            Task { @MainActor [weak self] in
                // 중앙 전용 장부 검사
                guard let self = self, self.centerHideGeneration == generation else { return }
                self.centerHUDWindow?.orderOut(nil)
            }
        })
    }

    // MARK: - 커서 위치 추적 (AX API)
    private func getCursorRect() -> CGRect? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?

        let error = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        if error != .success {
            dprint("📍 HUD Debug: [실패] 포커스된 텍스트 입력창을 찾을 수 없음")
            return getMouseFallbackRect("포커스된 텍스트 입력창 찾을 수 없음")
        }
        guard let element = focusedElement as! AXUIElement? else {
            return getMouseFallbackRect("AXUIElement 형변환 실패")
        }

        var selectedRangeValue: CFTypeRef?
        let rangeError = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRangeValue)
        if rangeError != .success {
            dprint("📍 HUD Debug: [실패] 텍스트 커서(SelectedRange)를 찾을 수 없음.")
            return getMouseFallbackRect("텍스트 커서(SelectedRange) 속성 없음")
        }

        var boundsValue: CFTypeRef?
        let boundsError = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            selectedRangeValue!,
            &boundsValue
        )

        guard boundsError == .success, let unwrappedBounds = boundsValue else {
            dprint("📍 HUD Debug: [실패] 커서의 화면 좌표(Bounds)를 계산할 수 없음.")
            return getMouseFallbackRect("화면 좌표(Bounds) 계산 실패")
        }

        var bounds: CGRect = .zero
        let axValue = unwrappedBounds as! AXValue
        guard AXValueGetValue(axValue, .cgRect, &bounds) else {
            dprint("📍 HUD Debug: [실패] 좌표값 형변환 실패")
            return getMouseFallbackRect("좌표값(AXValue) 형변환 실패")
        }

        if bounds.height <= 0 {
            if bounds.origin.x > 0 || bounds.origin.y > 0 {
                dprint("📍 HUD Debug: [보정됨] 커서 크기가 0이지만 좌표가 유효하여 강제 보정합니다. (origin: \(bounds.origin))")
                bounds.size.height = 18.0
                bounds.size.width = 1.0
            } else {
                dprint("📍 HUD Debug: [실패] 커서 크기와 좌표가 모두 0입니다 -> \(bounds)")
                return getMouseFallbackRect("커서 크기와 좌표가 모두 0")
            }
        } else if bounds.width > 200 {
            dprint("📍 HUD Debug: [무시됨] 커서 폭이 비정상적으로 큼 -> \(bounds)")
            return getMouseFallbackRect("비정상적인 커서 크기 (width > 200)")
        }

        dprint("📍 HUD Debug: [성공] 텍스트 커서 좌표 획득 -> \(bounds)")
        return bounds
    }

    private func getMouseFallbackRect(_ reason: String) -> CGRect {
        dprint("📍 HUD Debug: [마우스 Fallback 발동] \(reason)")

        let mouseLoc = NSEvent.mouseLocation
        let screenHeight = CGDisplayBounds(CGMainDisplayID()).height
        let flippedY = screenHeight - mouseLoc.y

        return CGRect(x: mouseLoc.x + 2, y: flippedY - 18, width: 1.0, height: 18.0)
    }

    // MARK: - 커서 미니 HUD

    private func showCursorMiniHUD(text: String, at rect: CGRect) {
        let lowerText = text.lowercased()
            let shortText: String
            if lowerText.contains("u.s.") || lowerText.contains("abc") || lowerText.contains("english") {
                shortText = "A"
            } else if lowerText.contains("두벌식") || lowerText.contains("세벌식") || lowerText.contains("korean") || lowerText.contains("한글") {
                shortText = "한"
            } else {
                shortText = String(text.prefix(1)).uppercased()
            }

            cursorHUDModel.symbol = shortText
            cursorHUDModel.name = text

            if cursorHUDWindow == nil {
                let window = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: 50, height: 30),
                    styleMask: [.borderless],
                    backing: .buffered,
                    defer: false
                )
                window.isOpaque = false
                window.backgroundColor = .clear
                window.level = .screenSaver
                window.ignoresMouseEvents = true
                window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

                let hostingView = NSHostingView(rootView: CursorHUDView(model: cursorHUDModel))
                window.contentView = hostingView
                cursorHUDHostingView = hostingView
                window.orderOut(nil)
                cursorHUDWindow = window
            }

            let screenHeight = CGDisplayBounds(CGMainDisplayID()).height
            
            cursorHUDHostingView?.layoutSubtreeIfNeeded()
            let viewSize = cursorHUDHostingView?.intrinsicContentSize ?? NSSize(width: 80, height: 30)
            
            let windowX = rect.maxX + 6
            let windowY = screenHeight - rect.maxY - viewSize.height - 2

            cursorHUDWindow?.setFrame(
                NSRect(x: windowX, y: windowY, width: viewSize.width, height: viewSize.height),
                display: false
            )

        cursorHUDWindow?.alphaValue = 0
        cursorHUDWindow?.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            self.cursorHUDWindow?.animator().alphaValue = 1.0
        }

        // ✅ Timer 완전 제거 — Task.sleep으로 교체
        hideGeneration &+= 1
        let generation = hideGeneration

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard self.hideGeneration == generation else { return }

            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.3
                self.cursorHUDWindow?.animator().alphaValue = 0.0
            }, completionHandler: {
                // completionHandler는 @Sendable — MainActor 프로퍼티 접근 불가
                // ✅ 별도 Task로 분리
                Task { @MainActor [weak self] in
                    guard let self, self.hideGeneration == generation else { return }
                    self.cursorHUDWindow?.orderOut(nil)
                }
            })
        }
    }

    func hideCursorMiniHUD() {
        hideGeneration &+= 1

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            self.cursorHUDWindow?.animator().alphaValue = 0.0
        }, completionHandler: {
            // ✅ completionHandler 내부는 항상 별도 Task로 분리
            Task { @MainActor [weak self] in
                self?.cursorHUDWindow?.orderOut(nil)
            }
        })
    }
}

// MARK: - SwiftUI Views

struct HUDView: View {
    @ObservedObject var model: CenterHUDModel

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "keyboard")
                .font(.system(size: 60))
                .foregroundColor(Color.primary.opacity(0.8))
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)

            Text(model.languageName)
                .font(.title2.bold())
                .foregroundColor(Color.primary.opacity(0.9))
                .lineLimit(1)
                .padding(.horizontal, 10)
        }
        .frame(width: 200, height: 200) // 완벽한 정사각형!
        .background(VisualEffectView().clipShape(RoundedRectangle(cornerRadius: 18)))
        .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 4)
    }
}

// 빌드 에러 방지용 가벼운 뷰 확장
extension View {
    func dropShadow() -> some View {
        self.shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)
    }
}

struct CursorHUDView: View {
    @ObservedObject var model: CursorHUDModel

    var body: some View {
        HStack(spacing: 8) {
            Text(model.symbol)
                .font(.system(size: 13, weight: .bold, design: .default))
                .foregroundColor(.black)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.white)
                .cornerRadius(4)

            Text(model.name)
                .font(.system(size: 15, weight: .semibold, design: .default))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(white: 0.1, opacity: 0.85))
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .fixedSize()
    }
}

struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
