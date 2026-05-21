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
import Cocoa
import ApplicationServices
import Combine


// MARK: - CursorHUD 상태 모델
final class CursorHUDModel: ObservableObject {
    @Published var symbol: String = ""
    @Published var name: String = ""
}


// MARK: - HUDManager

class HUDManager {
    static let shared = HUDManager()

    // 1. 중앙 HUD
    private var centerHUDWindow: NSPanel?
    private var centerHideTimer: Timer?

    // 2. 커서 미니 HUD
    private var cursorHUDWindow: NSWindow?
    private var cursorHideTimer: Timer?

    // ✅ 뷰 재생성 방지: 모델 + HostingView를 1회만 생성
    private var cursorHUDModel = CursorHUDModel()
    private var cursorHUDHostingView: NSHostingView<CursorHUDView>?

    // ✅ 타이머 completionHandler 경쟁 방지용 세대 카운터
    private var hideGeneration: UInt = 0


    // MARK: - 진입점

    func showHUD(languageName: String) {
        let snapshot = SettingsManager.shared.snapshot

        print("📍 HUD Debug: 호출됨! [HUDEnabled: \(snapshot.showVisualFeedback)] [MiniEnabled: \(snapshot.isCursorHUDEnabled)]")

        guard snapshot.showVisualFeedback else {
            print("📍 HUD Debug: 시각적 피드백 옵션이 꺼져있어 종료합니다.")
            return
        }

        DispatchQueue.main.async {
            if snapshot.isCursorHUDEnabled {
                if let cursorRect = self.getCursorRect() {
                    self.showCursorMiniHUD(text: languageName, at: cursorRect)
                } else {
                    print("📍 HUD Debug: [실패] 커서 좌표를 구할 수 없어 중앙 HUD로 Fallback 합니다.")
                    self.showCenterHUD(languageName: languageName)
                }
            } else {
                print("📍 HUD Debug: 미니 플래그 옵션이 꺼져있어 중앙 HUD를 표시합니다.")
                self.showCenterHUD(languageName: languageName)
            }
        }
    }


    // MARK: - 중앙 HUD

    private func showCenterHUD(languageName: String) {
        if self.centerHUDWindow == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
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
            self.centerHUDWindow = panel
        }

        self.centerHUDWindow?.contentView = NSHostingView(rootView: HUDView(languageName: languageName))

        if let screen = NSScreen.main {
            let x = screen.frame.midX - 100
            let y = screen.frame.midY - 100
            self.centerHUDWindow?.setFrameOrigin(NSPoint(x: x, y: y))
        }

        self.centerHUDWindow?.alphaValue = 0
        self.centerHUDWindow?.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            self.centerHUDWindow?.animator().alphaValue = 1.0
        }

        self.centerHideTimer?.invalidate()
        self.centerHideTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
            self.hideCenterHUD()
        }
    }

    private func hideCenterHUD() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            self.centerHUDWindow?.animator().alphaValue = 0.0
        }, completionHandler: {
            self.centerHUDWindow?.orderOut(nil)
        })
    }


    // MARK: - 커서 위치 추적 (AX API)

    private func getCursorRect() -> CGRect? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?

        let error = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        if error != .success {
            print("📍 HUD Debug: [실패] 포커스된 텍스트 입력창을 찾을 수 없음 (Error: \(error.rawValue))")
            return nil
        }
        guard let element = focusedElement as! AXUIElement? else { return nil }

        var selectedRangeValue: CFTypeRef?
        let rangeError = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRangeValue)
        if rangeError != .success {
            print("📍 HUD Debug: [실패] 텍스트 커서(SelectedRange)를 찾을 수 없음.")
            return nil
        }

        var boundsValue: CFTypeRef?
        let boundsError = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            selectedRangeValue!,
            &boundsValue
        )

        guard boundsError == .success, let unwrappedBounds = boundsValue else {
            print("📍 HUD Debug: [실패] 커서의 화면 좌표(Bounds)를 계산할 수 없음.")
            return nil
        }

        var bounds: CGRect = .zero
        let axValue = unwrappedBounds as! AXValue
        guard AXValueGetValue(axValue, .cgRect, &bounds) else {
            print("📍 HUD Debug: [실패] 좌표값 형변환 실패")
            return nil
        }

        if bounds.height <= 0 || bounds.width > 100 {
            print("📍 HUD Debug: [무시됨] 커서 크기가 비정상적임 (width: \(bounds.width), height: \(bounds.height))")
            return nil
        }

        print("📍 HUD Debug: [성공!] 커서 좌표 획득 완료 -> \(bounds)")
        return bounds
    }


    // MARK: - 커서 미니 HUD

    private func showCursorMiniHUD(text: String, at rect: CGRect) {
        // 1. 심볼 계산
        let lowerText = text.lowercased()
        let shortText: String
        if lowerText.contains("u.s.") || lowerText.contains("abc") || lowerText.contains("english") {
            shortText = "A"
        } else if lowerText.contains("두벌식") || lowerText.contains("세벌식") || lowerText.contains("korean") || lowerText.contains("한글") {
            shortText = "한"
        } else {
            shortText = String(text.prefix(1)).uppercased()
        }

        // 2. 모델 업데이트 (뷰 재생성 없이 텍스트만 교체)
        cursorHUDModel.symbol = shortText
        cursorHUDModel.name = text

        // 3. 창 및 HostingView 최초 1회 생성
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

            // ✅ NSHostingView 1회 생성 후 재사용
            let hostingView = NSHostingView(rootView: CursorHUDView(model: cursorHUDModel))
            window.contentView = hostingView
            cursorHUDHostingView = hostingView
            cursorHUDWindow = window
        }

        // 4. 위치 계산
        // intrinsicContentSize: 이미 렌더된 경우 정확한 크기 반환.
        // 최초 호출 시엔 0일 수 있으므로 최솟값으로 보호.
        let screenHeight = CGDisplayBounds(CGMainDisplayID()).height
        let viewSize = cursorHUDHostingView?.intrinsicContentSize ?? NSSize(width: 120, height: 36)
        let finalWidth  = max(viewSize.width,  80)
        let finalHeight = max(viewSize.height, 30)

        let windowX = rect.maxX + 6
        let windowY = screenHeight - rect.maxY - finalHeight - 2

        // ✅ setFrame 먼저, contentView 교체는 하지 않음 (이미 hostingView 재사용 중)
        cursorHUDWindow?.setFrame(
            NSRect(x: windowX, y: windowY, width: finalWidth, height: finalHeight),
            display: false
        )

        // 5. 표시 — makeKeyAndOrderFront 사용 금지
        // borderless + ignoresMouseEvents 창은 canBecomeKeyWindow == false
        cursorHUDWindow?.alphaValue = 0
        cursorHUDWindow?.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            self.cursorHUDWindow?.animator().alphaValue = 1.0
        }

        // 6. 타이머 — 세대(generation) 카운터로 completionHandler 경쟁 방지
        let currentGeneration = hideGeneration &+ 1
        hideGeneration = currentGeneration

        cursorHideTimer?.invalidate()
        cursorHideTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            guard let self = self, self.hideGeneration == currentGeneration else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.3
                self.cursorHUDWindow?.animator().alphaValue = 0.0
            }, completionHandler: { [weak self] in
                // ✅ 새 전환이 발생했으면 숨기지 않음
                guard let self = self, self.hideGeneration == currentGeneration else { return }
                self.cursorHUDWindow?.orderOut(nil)
            })
        }
    }

    func hideCursorMiniHUD() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // ✅ 세대 증가 → 진행 중인 타이머 completionHandler를 무효화
            self.hideGeneration = self.hideGeneration &+ 1
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.1
                self.cursorHUDWindow?.animator().alphaValue = 0.0
            }, completionHandler: { [weak self] in
                self?.cursorHUDWindow?.orderOut(nil)
            })
        }
    }
}


// MARK: - SwiftUI Views

struct HUDView: View {
    var languageName: String

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "keyboard")
                .font(.system(size: 60))
                .foregroundColor(Color.primary.opacity(0.8))
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)

            Text(languageName)
                .font(.title2.bold())
                .foregroundColor(Color.primary.opacity(0.9))
                .lineLimit(1)
                .padding(.horizontal, 10)
        }
        .frame(width: 200, height: 200)
        .background(VisualEffectView().clipShape(RoundedRectangle(cornerRadius: 18)))
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
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        // ✅ 원래의 디자인으로 복구: 반투명한 어두운 배경 + 그림자 + 테두리
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
