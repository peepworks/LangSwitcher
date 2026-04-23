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
    
    // 🌟 [리뷰 반영] lazy var의 스레드 불안정성을 피하기 위해 상수(let)로 변경하여 완벽한 스레드 안전성 보장
    private let eventSource: CGEventSource? = CGEventSource(stateID: .combinedSessionState)
    
    func executeCorrection() {
        // [Swift 6 대응] Non-Sendable인 NSPasteboard 객체를 통째로 캡처하지 않고,
        // Sendable 타입으로 안전한 Int와 String? 값만 미리 추출해 둡니다.
        let initialCount = NSPasteboard.general.changeCount
        let oldString = NSPasteboard.general.string(forType: .string)

        // 1. 설정에 따라 블록 지정 시뮬레이션
        if SettingsManager.shared.isSentenceMode {
            simulateKey(keyCode: 123, modifiers: [.maskCommand, .maskShift]) // Cmd + Shift + Left
        } else {
            simulateKey(keyCode: 123, modifiers: [.maskAlternate, .maskShift]) // Opt + Shift + Left
        }

        // 2. 블록 지정이 완료될 시간을 위해 아주 짧게 대기 후 복사 실행
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.simulateKey(keyCode: 8, modifiers: [.maskCommand]) // Cmd + C

            // 3. 클립보드 변화 감지 (최대 0.5초 대기)
            var attempts = 0
                
            Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
                attempts += 1
                
                // [Swift 6 대응] 블록 내부에서 NSPasteboard.general을 직접 호출하여 캡처를 방지합니다.
                let localPB = NSPasteboard.general

                // 10번 시도(0.5초) 후 포기 또는 클립보드가 변경되었을 때
                if localPB.changeCount != initialCount || attempts > 10 {
                    timer.invalidate()

                    // 🌟 헬퍼 함수: 클립보드를 원래 상태로 복구
                    func restoreClipboard() {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            let restorePB = NSPasteboard.general
                            if let old = oldString {
                                restorePB.clearContents()
                                restorePB.setString(old, forType: .string)
                            } else {
                                restorePB.clearContents()
                            }
                        }
                    }

                    // 4. 복사된 텍스트 확인 (실패 시 복구하고 종료)
                    guard let selectedText = localPB.string(forType: .string), !selectedText.isEmpty else {
                        restoreClipboard()
                        return
                    }

                    // 5. 한/영 판단 및 변환 실행
                    let isEnglish = selectedText.contains { $0.isASCII && $0.isLetter }
                    let convertedText = isEnglish ? self.convertToKo(selectedText) : self.convertToEn(selectedText)

                    // 6. 변환할 내용이 동일하면 무시 (동일할 경우에도 복구하고 종료)
                    if selectedText == convertedText {
                        restoreClipboard()
                        return
                    }

                    // 7. 변환된 텍스트 붙여넣기
                    localPB.clearContents()
                    localPB.setString(convertedText, forType: .string)
                    self.simulateKey(keyCode: 9, modifiers: [.maskCommand]) // Cmd + V
                    
                    // 명시적으로 붙여넣기 명령을 시스템에 하달한 "직후"에 복구 타이머를 시작합니다.
                    restoreClipboard()
                }
            }
        }
    }

    // 영어를 두벌식 한글 조합으로 변환 (오토마타)
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

    private func simulateKey(keyCode: CGKeyCode, modifiers: CGEventFlags) {
        guard let src = eventSource else { return }
        
        let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
        down?.flags = modifiers
        down?.post(tap: .cghidEventTap)
        
        let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
        up?.post(tap: .cghidEventTap)
    }
}
