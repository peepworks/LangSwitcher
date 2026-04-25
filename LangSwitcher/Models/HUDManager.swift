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
import ApplicationServices // 🌟 [추가] 접근성 API (AXUIElement) 사용을 위해 필수

class HUDManager {
    static let shared = HUDManager()
    
    // 1. 기존 중앙 HUD용 변수
    private var centerHUDWindow: NSPanel?
    private var centerHideTimer: Timer?
    
    // 2. 🌟 미니 플래그(Cursor Float)용 변수 추가
    private var cursorHUDWindow: NSWindow?
    private var cursorHideTimer: Timer?

    func showHUD(languageName: String) {
        let snapshot = SettingsManager.shared.snapshot
        
        // 시각적 피드백이 완전히 꺼져있으면 무시
        guard snapshot.showVisualFeedback else { return }

        DispatchQueue.main.async {
            // 🌟 1단계: 미니 플래그 설정이 켜져있다면 커서 위치 추적 시도
            if snapshot.isCursorHUDEnabled {
                if let cursorRect = self.getCursorRect() {
                    // 성공적으로 좌표를 찾았으면 미니 플래그 표시!
                    self.showCursorMiniHUD(text: languageName, at: cursorRect)
                    return
                }
            }
            
            // 🌟 2단계: 설정이 꺼져있거나, 커서 좌표를 못 구했다면 기존 중앙 HUD 표시 (Fallback)
            self.showCenterHUD(languageName: languageName)
        }
    }

    // MARK: - 기존 중앙 HUD 로직 (이름만 변경하여 그대로 유지)
    private func showCenterHUD(languageName: String) {
        if self.centerHUDWindow == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .floating
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            self.centerHUDWindow = panel
        }

        let hudView = HUDView(languageName: languageName)
        self.centerHUDWindow?.contentView = NSHostingView(rootView: hudView)

        if let screen = NSScreen.main {
            let x = screen.frame.midX - 100
            let y = screen.frame.midY - 100
            self.centerHUDWindow?.setFrameOrigin(NSPoint(x: x, y: y))
        }

        self.centerHUDWindow?.alphaValue = 0
        self.centerHUDWindow?.makeKeyAndOrderFront(nil)

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

    // MARK: - 🌟 커서 위치 추적 엔진 (AXAPI)
    private func getCursorRect() -> CGRect? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        
        // 현재 화면에서 포커스를 가진 텍스트 입력창 찾기
        let error = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        guard error == .success, let element = focusedElement as! AXUIElement? else { return nil }
        
        // 입력창 내에서 현재 커서(SelectedTextRange) 찾기
        var selectedRangeValue: CFTypeRef?
        let rangeError = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRangeValue)
        guard rangeError == .success else { return nil }
        
        // 커서 위치의 화면상 좌표(Bounds) 변환 요청
        var boundsValue: CFTypeRef?
        let boundsError = AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, selectedRangeValue!, &boundsValue)
        
        // 🌟 [수정된 부분 1] 값을 가져왔는지 안전하게 먼저 검사 (nil 방지)
        guard boundsError == .success, let unwrappedBounds = boundsValue else { return nil }
        
        var bounds: CGRect = .zero
        
        // 🌟 [수정된 부분 2] nil이 아님을 확신하므로 as! 로 강제 캐스팅하여 노란색 경고(Warning) 제거
        let axValue = unwrappedBounds as! AXValue
        guard AXValueGetValue(axValue, .cgRect, &bounds) else { return nil }
        
        // 텍스트 커서(캐럿)는 선 형태라 너비(width)가 0인 경우가 많습니다.
        // 높이(height)가 0 이하이거나, 블록 지정을 너무 크게(width > 100) 한 경우만 실패로 간주합니다.
        if bounds.height <= 0 || bounds.width > 100 { return nil }
        
        return bounds
    }

    // MARK: - 🌟 미니 플래그 렌더링 엔진
    private func showCursorMiniHUD(text: String, at rect: CGRect) {
        // 🌟 [수정된 부분] 시스템 키보드 이름을 직관적인 아이콘 글자로 매핑 (하드코딩 변환)
        var shortText = ""
        let lowerText = text.lowercased()
                
        if lowerText.contains("u.s.") || lowerText.contains("abc") || lowerText.contains("english") {
            shortText = "A"
        } else if lowerText.contains("두벌식") || lowerText.contains("세벌식") || lowerText.contains("korean") || lowerText.contains("한글") {
            shortText = "한" // 취향에 따라 "가" 로 변경하셔도 좋습니다!
        } else {
            // 일본어(Hiragana) 등 기타 언어는 기존처럼 첫 글자를 대문자로 사용
            shortText = String(text.prefix(1)).uppercased()
        }

        if self.cursorHUDWindow == nil {
            let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .floating // 화면 최상단
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            self.cursorHUDWindow = window
        }

        // SwiftUI로 디자인한 미니 플래그 뷰 주입
        let miniView = NSHostingView(rootView: CursorHUDView(text: shortText))
        self.cursorHUDWindow?.contentView = miniView

        // 🌟 좌표계 변환: CoreGraphics(Top-Left) 좌표를 AppKit(Bottom-Left) 좌표로 뒤집기
        let screenHeight = CGDisplayBounds(CGMainDisplayID()).height
        let viewSize = CGSize(width: 28, height: 28)
        let paddingX: CGFloat = 6  // 커서에서 우측으로 얼마나 띄울지
        let paddingY: CGFloat = 4  // 커서에서 아래쪽으로 얼마나 띄울지
        
        let windowX = rect.maxX + paddingX
        let windowY = screenHeight - rect.maxY - paddingY
        
        self.cursorHUDWindow?.setFrame(NSRect(x: windowX, y: windowY, width: viewSize.width, height: viewSize.height), display: true)
        
        // 애니메이션: 나타나기
        self.cursorHUDWindow?.alphaValue = 0
        self.cursorHUDWindow?.makeKeyAndOrderFront(nil)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1 // 빠르게 나타남 (시선이 뺏기지 않게)
            self.cursorHUDWindow?.animator().alphaValue = 1.0
        }
        
        // 애니메이션: 1초 후 사라지기 (중앙 HUD보다 짧게 유지)
        self.cursorHideTimer?.invalidate()
        self.cursorHideTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { _ in
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.3
                self.cursorHUDWindow?.animator().alphaValue = 0.0
            }, completionHandler: {
                self.cursorHUDWindow?.orderOut(nil)
            })
        }
    }
}

// MARK: - SwiftUI Views

// 기존의 중앙 HUD 디자인 (유지)
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

// 🌟 새로 추가된 미니 플래그 디자인
struct CursorHUDView: View {
    var text: String
    
    var body: some View {
        Text(text)
            .font(.system(size: 15, weight: .bold))
            .foregroundColor(.white)
            .frame(width: 28, height: 28)
            .background(Color.black.opacity(0.75))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            // 작은 그림자를 주어 흰색 배경에서도 잘 보이게 함
            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
    }
}

// 기존 VisualEffectView (유지)
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
