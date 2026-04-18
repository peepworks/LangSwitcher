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
    
    func executeCorrection() {
        let pasteboard = NSPasteboard.general
        let oldString = pasteboard.string(forType: .string)
            
        // 1. 설정에 따라 블록 지정
        if SettingsManager.shared.isSentenceMode {
            simulateKey(keyCode: 123, modifiers: [.maskCommand, .maskShift]) // Cmd+Shift+Left
        } else {
            simulateKey(keyCode: 123, modifiers: [.maskAlternate, .maskShift]) // Opt+Shift+Left
        }
            
        // 🌟 수정: 블록 지정이 완료될 때까지 0.1초(안전빵) 대기
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                
            self.simulateKey(keyCode: 8, modifiers: [.maskCommand]) // Cmd + C
                
            // 🌟 수정: 시스템이 텍스트를 클립보드에 완벽히 복사할 때까지 0.1초 대기
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    
                guard let selectedText = pasteboard.string(forType: .string), !selectedText.isEmpty else { return }
                    
                let isEnglish = selectedText.contains { $0.isASCII && $0.isLetter }
                let convertedText = isEnglish ? self.convertToKo(selectedText) : self.convertToEn(selectedText)
                    
                if selectedText == convertedText { return }
                    
                pasteboard.clearContents()
                pasteboard.setString(convertedText, forType: .string)
                self.simulateKey(keyCode: 9, modifiers: [.maskCommand]) // Cmd + V
                    
                // 원래 클립보드 복구 (붙여넣기가 끝날 때까지 0.15초 넉넉히 대기)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    if let old = oldString {
                        pasteboard.clearContents()
                        pasteboard.setString(old, forType: .string)
                    } else {
                        pasteboard.clearContents()
                    }
                }
            }
        }
    }

    // 영어를 두벌식 한글 조합으로 완벽하게 변환 (오토마타)
    private func convertToKo(_ englishText: String) -> String {
        let chos = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ")
        let jungs = Array("ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ")
        let jongs = Array(" ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ")

        let doubleJongs: [String: String] = ["ㄱㅅ":"ㄳ", "ㄴㅈ":"ㄵ", "ㄴㅎ":"ㄶ", "ㄹㄱ":"ㄺ", "ㄹㅁ":"ㄻ", "ㄹㅂ":"ㄼ", "ㄹㅅ":"ㄽ", "ㄹㅌ":"ㄾ", "ㄹㅍ":"ㄿ", "ㄹㅎ":"ㅀ", "ㅂㅅ":"ㅄ"]
        let doubleJungs: [String: String] = ["ㅗㅏ":"ㅘ", "ㅗㅐ":"ㅙ", "ㅗㅣ":"ㅚ", "ㅜㅓ":"ㅝ", "ㅜㅔ":"ㅞ", "ㅜㅣ":"ㅟ", "ㅡㅣ":"ㅢ"]

        let engToKor: [Character: Character] = [
            "q":"ㅂ","w":"ㅈ","e":"ㄷ","r":"ㄱ","t":"ㅅ","y":"ㅛ","u":"ㅕ","i":"ㅑ","o":"ㅐ","p":"ㅔ",
            "a":"ㅁ","s":"ㄴ","d":"ㅇ","f":"ㄹ","g":"ㅎ","h":"ㅗ","j":"ㅓ","k":"ㅏ","l":"ㅣ",
            "z":"ㅋ","x":"ㅌ","c":"ㅊ","v":"ㅍ","b":"ㅠ","n":"ㅜ","m":"ㅡ",
            "Q":"ㅃ","W":"ㅉ","E":"ㄸ","R":"ㄲ","T":"ㅆ","O":"ㅒ","P":"ㅖ"
        ]

        var result = ""
        var cho = "", jung = "", jong = ""

        func commit() {
            if !cho.isEmpty && !jung.isEmpty {
                let choIdx = chos.firstIndex(of: Character(cho)) ?? 0
                let jungIdx = jungs.firstIndex(of: Character(jung)) ?? 0
                let jongIdx = jong.isEmpty ? 0 : (jongs.firstIndex(of: Character(jong)) ?? 0)

                let uni = ((choIdx * 21) + jungIdx) * 28 + jongIdx + 0xAC00
                if let scalar = UnicodeScalar(uni) { result.append(Character(scalar)) }
            } else {
                result += cho + jung + jong
            }
            cho = ""; jung = ""; jong = ""
        }

        let chars = Array(englishText)
        var i = 0

        while i < chars.count {
            let c = chars[i]
            guard let korChar = engToKor[c] else {
                commit()
                result.append(c)
                i += 1
                continue
            }
            let kor = String(korChar)

            let isVowel = jungs.contains(korChar)
            let isConsonant = chos.contains(korChar) || jongs.contains(korChar)

            if isConsonant {
                if cho.isEmpty {
                    cho = kor
                } else if jung.isEmpty {
                    commit()
                    cho = kor
                } else {
                    var nextIsVowel = false
                    if i + 1 < chars.count, let nextKor = engToKor[chars[i+1]], jungs.contains(nextKor) {
                        nextIsVowel = true
                    }

                    if nextIsVowel {
                        commit()
                        cho = kor
                    } else {
                        if jong.isEmpty {
                            jong = kor
                        } else {
                            if let combined = doubleJongs[jong + kor] {
                                jong = combined
                            } else {
                                commit()
                                cho = kor
                            }
                        }
                    }
                }
            } else if isVowel {
                if cho.isEmpty {
                    if jung.isEmpty { jung = kor }
                    else if let combined = doubleJungs[jung + kor] { jung = combined }
                    else { commit(); jung = kor }
                } else if jong.isEmpty {
                    if jung.isEmpty { jung = kor }
                    else if let combined = doubleJungs[jung + kor] { jung = combined }
                    else { commit(); jung = kor }
                } else {
                    let splitJongs: [String: (String, String)] = ["ㄳ":("ㄱ","ㅅ"), "ㄵ":("ㄴ","ㅈ"), "ㄶ":("ㄴ","ㅎ"), "ㄺ":("ㄹ","ㄱ"), "ㄻ":("ㄹ","ㅁ"), "ㄼ":("ㄹ","ㅂ"), "ㄽ":("ㄹ","ㅅ"), "ㄾ":("ㄹ","ㅌ"), "ㄿ":("ㄹ","ㅍ"), "ㅀ":("ㄹ","ㅎ"), "ㅄ":("ㅂ","ㅅ")]
                    if let split = splitJongs[jong] {
                        jong = split.0
                        let nextCho = split.1
                        commit()
                        cho = nextCho
                        jung = kor
                    } else {
                        let nextCho = jong
                        jong = ""
                        commit()
                        cho = nextCho
                        jung = kor
                    }
                }
            }
            i += 1
        }
        commit()
        return result
    }

    // 역변환 로직: 한글을 다시 영문 키보드 배열로 분해
    private func convertToEn(_ koreanText: String) -> String {
        let engMap: [Character: String] = [
            "ㅂ":"q", "ㅈ":"w", "ㄷ":"e", "ㄱ":"r", "ㅅ":"t", "ㅛ":"y", "ㅕ":"u", "ㅑ":"i", "ㅐ":"o", "ㅔ":"p",
            "ㅁ":"a", "ㄴ":"s", "ㅇ":"d", "ㄹ":"f", "ㅎ":"g", "ㅗ":"h", "ㅓ":"j", "ㅏ":"k", "ㅣ":"l",
            "ㅋ":"z", "ㅌ":"x", "ㅊ":"c", "ㅍ":"v", "ㅠ":"b", "ㅜ":"n", "ㅡ":"m",
            "ㅃ":"Q", "ㅉ":"W", "ㄸ":"E", "ㄲ":"R", "ㅆ":"T", "ㅒ":"O", "ㅖ":"P"
        ]

        let doubleJongsMap: [Character: String] = ["ㄳ":"rt", "ㄵ":"sw", "ㄶ":"sg", "ㄺ":"fr", "ㄻ":"fa", "ㄼ":"fq", "ㄽ":"ft", "ㄾ":"fx", "ㄿ":"fv", "ㅀ":"fg", "ㅄ":"qt"]
        let doubleJungsMap: [Character: String] = ["ㅘ":"hk", "ㅙ":"ho", "ㅚ":"hl", "ㅝ":"nj", "ㅞ":"np", "ㅟ":"nl", "ㅢ":"ml"]

        var result = ""
        for char in koreanText {
            if let scalar = char.unicodeScalars.first, scalar.value >= 0xAC00 && scalar.value <= 0xD7A3 {
                let index = Int(scalar.value) - 0xAC00
                let choIdx = index / (21 * 28)
                let jungIdx = (index % (21 * 28)) / 28
                let jongIdx = index % 28

                let chos = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ")
                let jungs = Array("ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ")
                let jongs = Array(" ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ")

                let cho = chos[choIdx]
                let jung = jungs[jungIdx]

                result += engMap[cho] ?? String(cho)
                result += doubleJungsMap[jung] ?? (engMap[jung] ?? String(jung))

                if jongIdx > 0 {
                    let jong = jongs[jongIdx]
                    result += doubleJongsMap[jong] ?? (engMap[jong] ?? String(jong))
                }
            } else {
                result += doubleJungsMap[char] ?? (doubleJongsMap[char] ?? (engMap[char] ?? String(char)))
            }
        }
        return result
    }

    // 시스템 키보드 이벤트 시뮬레이터
    private func simulateKey(keyCode: CGKeyCode, modifiers: CGEventFlags) {
        guard let src = CGEventSource(stateID: .combinedSessionState) else { return }
        let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
        down?.flags = modifiers
        down?.post(tap: .cghidEventTap)
        let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
        up?.flags = modifiers
        up?.post(tap: .cghidEventTap)
    }
}
