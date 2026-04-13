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

class HUDManager {
    static let shared = HUDManager()
    private var hudWindow: NSPanel?
    private var hideTimer: Timer?

    func showHUD(languageName: String) {
        DispatchQueue.main.async {
            // 패널이 없으면 최초 생성
            if self.hudWindow == nil {
                let panel = NSPanel(
                    contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
                    styleMask: [.borderless, .nonactivatingPanel], // 포커스를 뺏지 않음
                    backing: .buffered,
                    defer: false
                )
                panel.level = .floating // 화면 최상단에 표시
                panel.backgroundColor = .clear
                panel.isOpaque = false
                panel.hasShadow = false
                panel.ignoresMouseEvents = true // 마우스 클릭 무시 (뒤의 앱 클릭 가능)
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary] // 전체화면 앱 위에도 표시
                self.hudWindow = panel
            }

            // HUD UI 교체 및 위치 중앙 정렬
            let hudView = HUDView(languageName: languageName)
            self.hudWindow?.contentView = NSHostingView(rootView: hudView)

            if let screen = NSScreen.main {
                let x = screen.frame.midX - 100
                // 🌟 화면 정중앙 배치 (하단 배치를 원하시면 y를 screen.frame.minY + 140 정도로 수정)
                let y = screen.frame.midY - 100
                self.hudWindow?.setFrameOrigin(NSPoint(x: x, y: y))
            }

            // 부드러운 나타나기 애니메이션
            self.hudWindow?.alphaValue = 0
            self.hudWindow?.makeKeyAndOrderFront(nil)

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                self.hudWindow?.animator().alphaValue = 1.0
            }

            // 1.5초 후 부드럽게 사라지기
            self.hideTimer?.invalidate()
            self.hideTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
                self.hideHUD()
            }
        }
    }

    private func hideHUD() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            self.hudWindow?.animator().alphaValue = 0.0
        }, completionHandler: {
            self.hudWindow?.orderOut(nil)
        })
    }
}

// 🌟 SwiftUI로 그리는 HUD 디자인 (macOS 볼륨 UI 스타일)
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

// 🌟 macOS 네이티브 블러(Blur)를 위한 브릿지
struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow // macOS 기본 HUD 블러 재질
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
