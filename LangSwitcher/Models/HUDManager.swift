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

    // 1. 중앙 HUD 자산 및 마감 제어선
    private var centerHUDWindow: NSPanel?
    private var centerHUDTask: Task<Void, Never>?
    private var centerFadeTask: Task<Void, Never>?

    // 2. 커서 미니 HUD 자산 및 마감 제어선
    private var cursorHUDWindow: NSWindow?
    private var cursorHUDTask: Task<Void, Never>?
    private var cursorFadeTask: Task<Void, Never>?

    // 뷰 재생성 방지: 모델 + HostingView를 1회만 생성
    private var cursorHUDModel = CursorHUDModel()
    private var cursorHUDHostingView: NSHostingView<CursorHUDView>?

    // 중앙 HUD용 뷰 및 모델 인스턴스 (최초 1회만 생성)
    private let centerHUDModel = CenterHUDModel()
    private var centerHUDHostingView: NSHostingView<HUDView>?

    private var cancelTask: Task<Void, Never>?

    private init() {}

    // MARK: - 진입점

    func showHUD(languageName: String) {
        let snapshot = SettingsManager.shared.snapshot

        dprint("📍 HUD Debug: 호출됨! [CenterEnabled: \(snapshot.showVisualFeedback)] [MiniEnabled: \(snapshot.isCursorHUDEnabled)]")

        guard snapshot.showVisualFeedback || snapshot.isCursorHUDEnabled else {
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
                    self.showCenterHUD(languageName: languageName)
                }
            }
        }
    }

    // MARK: - 화면 하단 정사각형 HUD 엔진

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

        centerFadeTask?.cancel()
        centerFadeTask = nil

        if self.centerHUDWindow?.isVisible == false {
            self.centerHUDWindow?.alphaValue = 0
        }
        self.centerHUDWindow?.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            self.centerHUDWindow?.animator().alphaValue = 1.0
        }

        centerHUDTask?.cancel()
        centerHUDTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                try await Task.sleep(for: .seconds(1.2))
                guard !Task.isCancelled else { return }
                self.hideCenterHUD()
            } catch {}
        }
    }

    private func hideCenterHUD() {
        centerHUDTask?.cancel()
        centerFadeTask?.cancel()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            self.centerHUDWindow?.animator().alphaValue = 0.0
        }

        centerFadeTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                try await Task.sleep(for: .seconds(0.3))
                guard !Task.isCancelled else { return }

                self.centerHUDWindow?.orderOut(nil)
                self.centerFadeTask = nil
                dprint("🪟 [HUDManager] 중앙 HUD 안전 물리 탈거 완료.")
            } catch {}
        }
    }

    // MARK: - 커서 위치 추적 (AX API)
    private func getCursorRect() -> CGRect? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?

        let error = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        if error != .success {
            return getMouseFallbackRect("포커스된 텍스트 입력창 찾을 수 없음")
        }
        guard let element = focusedElement as! AXUIElement? else {
            return getMouseFallbackRect("AXUIElement 형변환 실패")
        }

        var selectedRangeValue: CFTypeRef?
        let rangeError = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRangeValue)
        if rangeError != .success {
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
            return getMouseFallbackRect("화면 좌표(Bounds) 계산 실패")
        }

        var bounds: CGRect = .zero
        let axValue = unwrappedBounds as! AXValue
        guard AXValueGetValue(axValue, .cgRect, &bounds) else {
            return getMouseFallbackRect("좌표값(AXValue) 형변환 실패")
        }

        if bounds.height <= 0 {
            if bounds.origin.x > 0 || bounds.origin.y > 0 {
                bounds.size.height = 18.0
                bounds.size.width = 1.0
            } else {
                return getMouseFallbackRect("커서 크기와 좌표가 모두 0")
            }
        } else if bounds.width > 200 {
            return getMouseFallbackRect("비정상적인 커서 크기 (width > 200)")
        }

        return bounds
    }

    private func getMouseFallbackRect(_ reason: String) -> CGRect {
        let mouseLoc = NSEvent.mouseLocation
        let screenHeight = CGDisplayBounds(CGMainDisplayID()).height
        let flippedY = screenHeight - mouseLoc.y

        return CGRect(x: mouseLoc.x + 2, y: flippedY - 18, width: 1.0, height: 18.0)
    }

    // MARK: - 커서 미니 HUD

    private func showCursorMiniHUD(text: String, at rect: CGRect) {
        let language = InputLanguage.determine(from: text)
        let shortText = language.shortLabel(fallbackText: text)

        cursorHUDModel.symbol = shortText
        cursorHUDModel.name = text

        if cursorHUDWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 85, height: 28), // 명시적 고정 기저 규격 스케일링
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

        // 🌟 [우주 방어 수복 포인트] 레거시 AppKit 무단 재귀 에러(`layoutSubtreeIfNeeded`)를 전면 소각합니다.
        // NSHostingView가 제공하는 독립 연산 창구인 fittingSize 자산을 다이렉트로 매핑하여, Layout 루프 간섭을 근본적으로 무력화합니다.
        let viewSize = cursorHUDHostingView?.fittingSize ?? NSSize(width: 85, height: 28)

        let windowX = rect.maxX + 6
        let windowY = screenHeight - rect.maxY - viewSize.height - 2

        cursorHUDWindow?.setFrame(
            NSRect(x: windowX, y: windowY, width: viewSize.width, height: viewSize.height),
            display: false
        )

        cursorFadeTask?.cancel()
        cursorFadeTask = nil

        if self.cursorHUDWindow?.isVisible == false {
            self.cursorHUDWindow?.alphaValue = 0
        }
        cursorHUDWindow?.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            self.cursorHUDWindow?.animator().alphaValue = 1.0
        }

        cursorHUDTask?.cancel()
        cursorHUDTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                try await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled else { return }

                self.hideCursorMiniHUD()
            } catch {}
        }
    }

    func hideCursorMiniHUD() {
        cursorHUDTask?.cancel()
        cursorFadeTask?.cancel()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            self.cursorHUDWindow?.animator().alphaValue = 0.0
        }

        cursorFadeTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                try await Task.sleep(for: .seconds(0.35))
                guard !Task.isCancelled else { return }

                self.cursorHUDWindow?.orderOut(nil)
                self.cursorFadeTask = nil
                dprint("🪟 [HUDManager] 미니 HUD 유령 상주 차단 및 orderOut 안전 완결.")
            } catch {}
        }
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
                .dropShadow()

            Text(model.languageName)
                .font(.title2.bold())
                .foregroundColor(Color.primary.opacity(0.9))
                .lineLimit(1)
                .padding(.horizontal, 10)
        }
        .frame(width: 200, height: 200)
        .background(VisualEffectView().clipShape(RoundedRectangle(cornerRadius: 18)))
        .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 4)
    }
}

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
