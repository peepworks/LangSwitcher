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

final class CenterHUDModel: ObservableObject {
    @Published var languageName: String = ""
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
    
    // 중앙 HUD용 뷰 및 모델 인스턴스 (최초 1회만 생성)
    private let centerHUDModel = CenterHUDModel()
    private var centerHUDHostingView: NSHostingView<HUDView>?


    // MARK: - 진입점

    func showHUD(languageName: String) {
        let snapshot = SettingsManager.shared.snapshot

        #if DEBUG
        print("📍 HUD Debug: 호출됨! [CenterEnabled: \(snapshot.showVisualFeedback)] [MiniEnabled: \(snapshot.isCursorHUDEnabled)]")
        #endif

        // 두 옵션이 모두 꺼져 있다면 아무것도 그리지 않고 즉시 종료합니다.
        guard snapshot.showVisualFeedback || snapshot.isCursorHUDEnabled else {
            #if DEBUG
            print("📍 HUD Debug: 모든 시각적 피드백 옵션이 꺼져있어 종료합니다.")
            #endif
            return
        }

        DispatchQueue.main.async {
            // 1. 중앙 HUD 처리 (독립 실행)
            if snapshot.showVisualFeedback {
                self.showCenterHUD(languageName: languageName)
            }

            // 2. 커서 미니 HUD 처리 (독립 실행)
            if snapshot.isCursorHUDEnabled {
                if let cursorRect = self.getCursorRect() {
                    self.showCursorMiniHUD(text: languageName, at: cursorRect)
                } else {
                    // 미니 플래그를 그려야 하는데 좌표 획득에 완전히 실패한 경우의 방어 로직
                    // (단, 중앙 HUD가 이미 켜져 있다면 중복해서 호출하지 않음)
                    if !snapshot.showVisualFeedback {
                        print("📍 HUD Debug: [Fallback] 미니 플래그 실패로 중앙 HUD를 대체 표시합니다.")
                        self.showCenterHUD(languageName: languageName)
                    }
                }
            }
        }
    }

    // MARK: - 중앙 HUD

    private func showCenterHUD(languageName: String) {
        // 1. 모델 데이터만 업데이트 (SwiftUI가 알아서 화면 갱신)
        centerHUDModel.languageName = languageName

        // 2. 윈도우 및 HostingView가 없는 경우에만 최초 1회 생성
        if self.centerHUDWindow == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            // ... (패널 설정 유지) ...
            panel.level = .statusBar
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            
            // 뷰 생성 및 저장
            let hostingView = NSHostingView(rootView: HUDView(model: centerHUDModel))
            panel.contentView = hostingView
            self.centerHUDHostingView = hostingView
            self.centerHUDWindow = panel
        }

        // 3. 위치 계산 및 표시 로직 (기존 유지)
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

        // 타이머 (기존 유지)
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

        // 🌟 [핵심 보정] 크롬 등에서 크기가 0이거나 비정상적인 값을 반환할 때
        if bounds.height <= 0 || bounds.width > 200 {
            return getMouseFallbackRect("앱이 비정상적인 커서 크기를 반환함 (w: \(bounds.width), h: \(bounds.height))")
        }

        print("📍 HUD Debug: [성공] 텍스트 커서 좌표 획득 -> \(bounds)")
        return bounds
    }

    // 🌟 텍스트 커서 위치 획득 실패 시 '마우스 포인터' 위치를 반환하는 최후의 방어선
    private func getMouseFallbackRect(_ reason: String) -> CGRect {
        print("📍 HUD Debug: [마우스 Fallback 발동] \(reason)")
        let mouseLoc = NSEvent.mouseLocation
        let screenHeight = CGDisplayBounds(CGMainDisplayID()).height
        
        // NSEvent는 화면 좌측 하단(Bottom-Left) 기준이고,
        // AX API는 좌측 상단(Top-Left) 기준이므로 Y축을 뒤집어 줍니다.
        let flippedY = screenHeight - mouseLoc.y
        
        // 마우스 포인터 바로 옆(우측 하단)에 위치하도록 가상의 커서 Rect 생성
        return CGRect(x: mouseLoc.x + 2, y: flippedY - 18, width: 1.0, height: 18.0)
    }

    // MARK: - 커서 미니 HUD

    private func showCursorMiniHUD(text: String, at rect: CGRect) {
        // 1. 심볼 계산 (로직 유지)
        let lowerText = text.lowercased()
        let shortText: String
        if lowerText.contains("u.s.") || lowerText.contains("abc") || lowerText.contains("english") {
            shortText = "A"
        } else if lowerText.contains("두벌식") || lowerText.contains("세벌식") || lowerText.contains("korean") || lowerText.contains("한글") {
            shortText = "한"
        } else {
            shortText = String(text.prefix(1)).uppercased()
        }

        // 2. 모델 업데이트 (데이터만 변경 -> SwiftUI가 알아서 리렌더링)
        cursorHUDModel.symbol = shortText
        cursorHUDModel.name = text

        // 3. 창 및 HostingView 최초 1회 생성 (이미 구현하신 부분)
        if cursorHUDWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 50, height: 30),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .screenSaver // 또는 .floating
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            let hostingView = NSHostingView(rootView: CursorHUDView(model: cursorHUDModel))
            window.contentView = hostingView
            cursorHUDHostingView = hostingView
            cursorHUDWindow = window
        }

        // 4. 위치 계산 (이제 뷰 재생성 없이 intrinsicContentSize 활용)
        let screenHeight = CGDisplayBounds(CGMainDisplayID()).height
        
        // 🌟 데이터가 바뀐 후 뷰가 레이아웃을 다시 잡을 시간을 줍니다.
        cursorHUDHostingView?.layoutSubtreeIfNeeded()
        let viewSize = cursorHUDHostingView?.intrinsicContentSize ?? NSSize(width: 80, height: 30)
        
        let windowX = rect.maxX + 6
        let windowY = screenHeight - rect.maxY - viewSize.height - 2

        // 5. 프레임 설정 (애니메이션 루프 방지를 위해 display: false)
        cursorHUDWindow?.setFrame(
            NSRect(x: windowX, y: windowY, width: viewSize.width, height: viewSize.height),
            display: false
        )

        // 6. 표시 및 애니메이션 로직 유지...
        cursorHUDWindow?.alphaValue = 0
        cursorHUDWindow?.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            self.cursorHUDWindow?.animator().alphaValue = 1.0
        }

        // 7. 타이머 — 세대(generation) 카운터로 completionHandler 경쟁 방지
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
    @ObservedObject var model: CenterHUDModel // 텍스트 대신 모델 구독

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "keyboard")
                .font(.system(size: 60))
                .foregroundColor(Color.primary.opacity(0.8))
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)

            Text(model.languageName) // 모델의 데이터 출력
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
        // 🌟 바로 여기 패딩 수치를 줄여줍니다! (원래 10, 8 이었음)
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
