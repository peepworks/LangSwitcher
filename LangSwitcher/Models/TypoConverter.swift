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

import AppKit

class TypoConverter {
    static let shared = TypoConverter()
    
    // lazy var의 스레드 불안정성을 피하기 위해 상수(let)로 변경하여 완벽한 스레드 안전성 보장
    private let eventSource: CGEventSource? = CGEventSource(stateID: .combinedSessionState)
    
    // 타이밍 충돌을 막아줄 튼튼한 자물쇠 (진행 상태 플래그)
    private var isConvertingInProgress = false
    
    // 클립보드 원본 백업용 변수
    private var savedClipboardString: String?
    
    // MARK: - 스마트 자동 오타 감지용 엔진
    func detectAndConvert(englishInput: String) -> String? {
        guard englishInput.count >= 2 else { return nil }
        
        let converted = convertToKo(englishInput)
        
        var hasSyllable = false
        var hasIncomplete = false
        
        for char in converted {
            guard let scalar = char.unicodeScalars.first else { continue }
            
            if scalar.value >= 0xAC00 && scalar.value <= 0xD7A3 {
                hasSyllable = true
            }
            else if (scalar.value >= 0x3130 && scalar.value <= 0x318F) || (char.isASCII && char.isLetter) {
                hasIncomplete = true
                break
            }
        }
        
        if hasSyllable && !hasIncomplete {
            return converted
        }
        
        return nil
    }

    // MARK: - 수동 단축키 오타 교정 (VSCode 방어 및 데드락 완벽 해결)
    func executeCorrection() {
        guard !isConvertingInProgress else { return }
        isConvertingInProgress = true
            
        DispatchQueue.main.async {
            self.backupClipboard()
            
            // 커서 앞 한 단어 자동 지정 (Option + Shift + Left Arrow)
            self.postKeyEvent(keyCode: 123, modifiers: [.maskAlternate, .maskShift])
            
            // 블록이 잡힐 시간 대기
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                let localPB = NSPasteboard.general
                let initialCount = localPB.changeCount
                
                // 복사 (Cmd+C) 시도
                self.postKeyEvent(keyCode: 8, modifiers: .maskCommand)
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    // 1. 복사가 정상적으로 완료되었을 때 (성공 경로)
                    if localPB.changeCount != initialCount,
                       let selectedText = localPB.string(forType: .string), !selectedText.isEmpty {
                        
                        let convertedText = self.convertString(selectedText)
                        localPB.clearContents()
                        localPB.setString(convertedText, forType: .string)
                        
                        // 붙여넣기 (Cmd+V)
                        self.postKeyEvent(keyCode: 9, modifiers: .maskCommand)
                        
                        // 🌟 [수정됨] 현재 활성화된 앱을 확인하고 동적 딜레이를 적용합니다.
                        let activeAppID = AppMonitor.shared.activeAppBundleID
                        let delay = self.getClipboardRestoreDelay(for: activeAppID)
                        
                        // 계산된 delay만큼 대기 후 자물쇠 해제
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            self.safeRestoreAndUnlock()
                        }
                        
                    } else {
                        // 2. 복사 실패 시 (예외 경로: 빈 줄 등)
                        // 잘못 잡힌 블록을 풀고 🌟즉시 자물쇠를 해제합니다!
                        self.postKeyEvent(keyCode: 124, modifiers: [])
                        self.safeRestoreAndUnlock() // ✅ 완벽한 데드락 방지
                    }
                }
            }
        }
    }

    // 🌟 코드 가독성을 위해 변환 및 붙여넣기 로직을 별도 함수로 분리했습니다.
    private func performConversionAndPaste(text: String, pb: NSPasteboard) {
        let convertedText = self.convertString(text)
        
        pb.clearContents()
        pb.setString(convertedText, forType: .string)
        
        // Cmd+V 붙여넣기
        self.postKeyEvent(keyCode: 9, modifiers: .maskCommand)
        
        // 🌟 [수정됨] 여기에도 동일하게 동적 딜레이를 적용합니다.
        let activeAppID = AppMonitor.shared.activeAppBundleID
        let delay = self.getClipboardRestoreDelay(for: activeAppID)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.safeRestoreAndUnlock()
        }
    }

    // MARK: - 클립보드 및 키보드 헬퍼 함수
    
    private func safeRestoreAndUnlock() {
        restoreClipboard()
        self.isConvertingInProgress = false
    }

    private func backupClipboard() {
        self.savedClipboardString = NSPasteboard.general.string(forType: .string)
    }
    
    private func restoreClipboard() {
        if let saved = savedClipboardString {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(saved, forType: .string)
        }
    }
    
    private func postKeyEvent(keyCode: CGKeyCode, modifiers: CGEventFlags) {
        simulateKey(keyCode: keyCode, modifiers: modifiers)
    }
    
    private func simulateKey(keyCode: CGKeyCode, modifiers: CGEventFlags) {
        guard let src = eventSource else { return }
        
        let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
        down?.flags = modifiers
        down?.post(tap: .cghidEventTap)
        
        let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
        up?.flags = modifiers // 🌟 [버그 수정] 키를 뗄 때도 수식키(Modifiers) 상태를 유지해 줘야 꼬이지 않습니다.
        up?.post(tap: .cghidEventTap)
    }
    
    private func convertString(_ text: String) -> String {
        let hasKorean = text.unicodeScalars.contains {
            ($0.value >= 0xAC00 && $0.value <= 0xD7A3) || ($0.value >= 0x3130 && $0.value <= 0x318F)
        }
        return hasKorean ? convertToEn(text) : convertToKo(text)
    }

    // MARK: - 한/영 변환 오토마타 로직
    private func convertToKo(_ englishText: String) -> String {
        let chos = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ")
        let jungs = Array("ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ")
        let jongs = Array(" ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ")
        let doubleJongs: [String: String] = ["ㄱㅅ":"ㄳ", "ㄴㅈ":"ㄵ", "ㄴㅎ":"ㄶ", "ㄹㄱ":"ㄺ", "ㄹㅁ":"ㄻ", "ㄹㅂ":"ㄼ", "ㄹㅅ":"ㄽ", "ㄹㅌ":"ㄾ", "ㄹㅍ":"ㄿ", "ㄹㅎ":"ㅀ", "ㅂㅅ":"ㅄ"]
        let doubleJungs: [String: String] = ["ㅗㅏ":"ㅘ", "ㅗㅐ":"ㅙ", "ㅗㅣ":"ㅚ", "ㅜㅓ":"ㅝ", "ㅜㅔ":"ㅞ", "ㅜㅣ":"ㅟ", "ㅡㅣ":"ㅢ"]
        let engToKor: [Character: Character] = ["q":"ㅂ","w":"ㅈ","e":"ㄷ","r":"ㄱ","t":"ㅅ","y":"ㅛ","u":"ㅕ","i":"ㅑ","o":"ㅐ","p":"ㅔ","a":"ㅁ","s":"ㄴ","d":"ㅇ","f":"ㄹ","g":"ㅎ","h":"ㅗ","j":"ㅓ","k":"ㅏ","l":"ㅣ","z":"ㅋ","x":"ㅌ","c":"ㅊ","v":"ㅍ","b":"ㅠ","n":"ㅜ","m":"ㅡ","Q":"ㅃ","W":"ㅉ","E":"ㄸ","R":"ㄲ","T":"ㅆ","O":"ㅒ","P":"ㅖ"]

        var result = ""; var cho = ""; var jung = ""; var jong = ""
        func commit() {
            if !cho.isEmpty && !jung.isEmpty {
                let cIdx = chos.firstIndex(of: Character(cho)) ?? 0; let juIdx = jungs.firstIndex(of: Character(jung)) ?? 0; let joIdx = jong.isEmpty ? 0 : (jongs.firstIndex(of: Character(jong)) ?? 0)
                let uni = ((cIdx * 21) + juIdx) * 28 + joIdx + 0xAC00
                if let scalar = UnicodeScalar(uni) { result.append(Character(scalar)) }
            } else { result += cho + jung + jong }
            cho = ""; jung = ""; jong = ""
        }

        let chars = Array(englishText); var i = 0
        while i < chars.count {
            let c = chars[i]; guard let korChar = engToKor[c] else { commit(); result.append(c); i += 1; continue }
            let kor = String(korChar); let isVowel = jungs.contains(korChar)
            if !isVowel {
                if cho.isEmpty { cho = kor }
                else if jung.isEmpty { commit(); cho = kor }
                else {
                    var nextIsVowel = false
                    if i + 1 < chars.count, let n = engToKor[chars[i+1]], jungs.contains(n) { nextIsVowel = true }
                    if nextIsVowel { commit(); cho = kor }
                    else {
                        if jong.isEmpty { jong = kor }
                        else if let combined = doubleJongs[jong + kor] { jong = combined }
                        else { commit(); cho = kor }
                    }
                }
            } else {
                if cho.isEmpty || jong.isEmpty {
                    if jung.isEmpty { jung = kor }
                    else if let combined = doubleJungs[jung + kor] { jung = combined }
                    else { commit(); jung = kor }
                } else {
                    let splitJongs: [String: (String, String)] = ["ㄳ":("ㄱ","ㅅ"), "ㄵ":("ㄴ","ㅈ"), "ㄶ":("ㄴ","ㅎ"), "ㄺ":("ㄹ","ㄱ"), "ㄻ":("ㄹ","ㅁ"), "ㄼ":("ㄹ","ㅂ"), "ㄽ":("ㄹ","ㅅ"), "ㄾ":("ㄹ","ㅌ"), "ㄿ":("ㄹ","ㅍ"), "ㅀ":("ㄹ","ㅎ"), "ㅄ":("ㅂ","ㅅ")]
                    if let split = splitJongs[jong] { jong = split.0; commit(); cho = split.1; jung = kor }
                    else { let nCho = jong; jong = ""; commit(); cho = nCho; jung = kor }
                }
            }
            i += 1
        }
        commit(); return result
    }

    private func convertToEn(_ koreanText: String) -> String {
        let engMap: [Character: String] = ["ㅂ":"q", "ㅈ":"w", "ㄷ":"e", "ㄱ":"r", "ㅅ":"t", "ㅛ":"y", "ㅕ":"u", "ㅑ":"i", "ㅐ":"o", "ㅔ":"p", "ㅁ":"a", "ㄴ":"s", "ㅇ":"d", "ㄹ":"f", "ㅎ":"g", "ㅗ":"h", "ㅓ":"j", "ㅏ":"k", "ㅣ":"l", "ㅋ":"z", "ㅌ":"x", "ㅊ":"c", "ㅍ":"v", "ㅠ":"b", "ㅜ":"n", "ㅡ":"m", "ㅃ":"Q", "ㅉ":"W", "ㄸ":"E", "ㄲ":"R", "ㅆ":"T", "ㅒ":"O", "ㅖ":"P"]
        let doubleJongsMap: [Character: String] = ["ㄳ":"rt", "ㄵ":"sw", "ㄶ":"sg", "ㄺ":"fr", "ㄻ":"fa", "ㄼ":"fq", "ㄽ":"ft", "ㄾ":"fx", "ㄿ":"fv", "ㅀ":"fg", "ㅄ":"qt"]
        let doubleJungsMap: [Character: String] = ["ㅘ":"hk", "ㅙ":"ho", "ㅚ":"hl", "ㅝ":"nj", "ㅞ":"np", "ㅟ":"nl", "ㅢ":"ml"]

        var result = ""
        for char in koreanText {
            let scalar = char.unicodeScalars.first?.value ?? 0
            if scalar >= 0xAC00 && scalar <= 0xD7A3 {
                let index = Int(scalar) - 0xAC00
                let choIdx = index / (21 * 28); let jungIdx = (index % (21 * 28)) / 28; let jongIdx = index % 28
                let chos = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ"); let jungs = Array("ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ"); let jongs = Array(" ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ")
                
                result += engMap[chos[choIdx]] ?? ""
                result += doubleJungsMap[jungs[jungIdx]] ?? (engMap[jungs[jungIdx]] ?? "")
                if jongIdx > 0 { result += doubleJongsMap[jongs[jongIdx]] ?? (engMap[jongs[jongIdx]] ?? "") }
            } else {
                if let doubleJung = doubleJungsMap[char] { result += doubleJung }
                else if let doubleJong = doubleJongsMap[char] { result += doubleJong }
                else if let single = engMap[char] { result += single }
                else { result += String(char) }
            }
        }
        return result
    }
    
    // 🌟 [수정됨] 앱별로 가장 최적화된 복구 딜레이를 개별적으로 관리하는 사전(Dictionary) 추가
    // 이 사전을 함수 바깥(클래스 내부 변수)으로 빼서 관리가 쉽도록 만듭니다.
    private let clipboardDelayMap: [String: TimeInterval] = [
        "com.microsoft.VSCode": 0.7,
        "com.tinyspeck.slackmacgap": 0.6,
        "com.hnc.Discord": 0.6,
        "notion.id": 0.6,
        "md.obsidian": 0.5,
        "com.google.Chrome": 0.4 // 브라우저는 에디터보다는 조금 더 빠르므로 0.4초
    ]

    // 🌟 [수정됨] Set 방식 대신 Dictionary를 조회하도록 함수 변경
    private func getClipboardRestoreDelay(for bundleID: String?) -> TimeInterval {
        guard let bundleID = bundleID else { return 0.15 } // 번들 ID가 없으면 기본값 반환
        
        // 🌟 사전에 번들 ID가 존재하면 그 맞춤형 시간을 반환하고,
        // 사전에 없는 일반 네이티브 앱이라면 기본값인 0.15초를 반환합니다.
        return clipboardDelayMap[bundleID] ?? 0.15
    }
}
