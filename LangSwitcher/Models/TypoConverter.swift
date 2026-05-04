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
    /// 영문 입력을 분석하여 완벽한 한국어 패턴(자음+모음 조합)이면 변환된 텍스트를 반환, 아니면 nil 반환
    func detectAndConvert(englishInput: String) -> String? {
        // 1. 최소 2글자 이상일 때만 분석
        guard englishInput.count >= 2 else { return nil }
        
        // 2. 일단 한글 오토마타 엔진을 돌려 변환 시도
        let converted = convertToKo(englishInput)
        
        var hasSyllable = false
        var hasIncomplete = false
        
        // 3. 변환된 결과물 검증
        for char in converted {
            guard let scalar = char.unicodeScalars.first else { continue }
            
            // 완성된 한글 음절 (가 ~ 힣 : 0xAC00 ~ 0xD7A3)
            if scalar.value >= 0xAC00 && scalar.value <= 0xD7A3 {
                hasSyllable = true
            }
            // 조합되지 못하고 남은 찌꺼기 자음/모음 (ㄱ~ㅎ, ㅏ~ㅣ : 0x3130 ~ 0x318F)
            // 또는 변환되지 않은 영문 알파벳이 남아있는 경우
            else if (scalar.value >= 0x3130 && scalar.value <= 0x318F) || (char.isASCII && char.isLetter) {
                hasIncomplete = true
                break // 하나라도 불완전한 글자가 있으면 영단어로 간주하고 즉시 탈락
            }
        }
        
        // 4. 완성된 글자가 존재하고, 불완전한 찌꺼기 글자가 '전혀' 없을 때만 완벽한 오타로 간주
        if hasSyllable && !hasIncomplete {
            return converted
        }
        
        return nil
    }

    // MARK: - 기존 수동 단축키 오타 교정
    func executeCorrection() {
        // 1. 이미 작업 중이라면 사용자가 연타해도 무시하고 돌려보냅니다.
        guard !isConvertingInProgress else { return }
        isConvertingInProgress = true
            
        DispatchQueue.main.async {
            // 원본 클립보드 백업
            self.backupClipboard()
                
            let localPB = NSPasteboard.general
            let initialCount = localPB.changeCount
            
            // Cmd+C 이벤트 발생 (8은 'C' 키코드)
            self.postKeyEvent(keyCode: 8, useCommand: true)
                
            // 0.1초 뒤에 클립보드 확인
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                // 2. 복사 실패 시 안전하게 복구하고 자물쇠를 풉니다.
                guard localPB.changeCount != initialCount,
                        let selectedText = localPB.string(forType: .string),
                        !selectedText.isEmpty
                else {
                    self.safeRestoreAndUnlock()
                    return
                }
                    
                // 한영 변환 수행
                let convertedText = self.convertString(selectedText)
                    
                // 변환된 텍스트를 클립보드에 넣고 Cmd+V (9는 'V' 키코드)
                localPB.clearContents()
                localPB.setString(convertedText, forType: .string)
                self.postKeyEvent(keyCode: 9, useCommand: true)
                    
                // 3. 붙여넣기가 완료될 때까지 충분히(0.6초) 기다렸다가 클립보드를 복구하고 자물쇠를 풉니다.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    self.safeRestoreAndUnlock()
                }
            }
        }
    }
        
    // 클립보드 복구와 자물쇠 해제를 동시에 안전하게 처리하는 통합 함수
    private func safeRestoreAndUnlock() {
        restoreClipboard()
        self.isConvertingInProgress = false
    }

    // MARK: - 클립보드 및 키보드 헬퍼 함수
    private func backupClipboard() {
        self.savedClipboardString = NSPasteboard.general.string(forType: .string)
    }
    
    private func restoreClipboard() {
        if let saved = savedClipboardString {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(saved, forType: .string)
        }
    }
    
    private func postKeyEvent(keyCode: CGKeyCode, useCommand: Bool) {
        let flags: CGEventFlags = useCommand ? .maskCommand : []
        simulateKey(keyCode: keyCode, modifiers: flags)
    }
    
    // 텍스트 내 한글 포함 여부에 따라 변환 방향 결정
    private func convertString(_ text: String) -> String {
        let hasKorean = text.unicodeScalars.contains {
            ($0.value >= 0xAC00 && $0.value <= 0xD7A3) || ($0.value >= 0x3130 && $0.value <= 0x318F)
        }
        return hasKorean ? convertToEn(text) : convertToKo(text)
    }

    // MARK: - 한/영 변환 오토마타 로직
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
