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

    private var isConvertingInProgress = false
    private let conversionLock = NSLock()
    
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
            }
        }
        
        if hasSyllable {
            if !hasIncomplete {
                return converted
            } else {
                // 🌟 [핵심 해결책] macOS 한영 전환 딜레이 버그 패턴 감지 ("q완벽하게", "d일어나고")
                let containsEnglish = englishInput.contains { $0.isASCII && $0.isLetter }
                let containsKoreanSyllable = englishInput.unicodeScalars.contains { $0.value >= 0xAC00 && $0.value <= 0xD7A3 }
                
                // 영어와 한글이 섞여 있다면 딜레이로 인한 오타가 확실하므로 찌꺼기를 필터링합니다.
                if containsEnglish && containsKoreanSyllable {
                    let cleaned = String(converted.filter { char in
                        guard let val = char.unicodeScalars.first?.value else { return true }
                        let isIncompleteJamo = (val >= 0x3130 && val <= 0x318F) // 찌꺼기 자음/모음 (예: ㄷ)
                        let isStrayEnglish = char.isASCII && char.isLetter     // 찌꺼기 알파벳 (예: e)
                        
                        // 찌꺼기가 아닌 완벽한 글자나 기호, 띄어쓰기만 남깁니다.
                        return !isIncompleteJamo && !isStrayEnglish
                    })
                    
                    if !cleaned.isEmpty {
                        return cleaned
                    }
                }
            }
        }
        
        return nil
    }

    // MARK: - 수동 단축키 오타 교정 (VSCode 방어 및 데드락 완벽 해결)
    func executeCorrection() {
        conversionLock.lock()
        // 함수 블록이 끝날 때 무조건 자물쇠를 풀도록 예약합니다.
        defer { conversionLock.unlock() }

        // 이미 작업 중이면 그냥 종료 (defer가 알아서 unlock 해줌)
        guard !isConvertingInProgress else { return }

        // 작업 시작 표시
        isConvertingInProgress = true
        
        // 4. 안전하게 팻말을 바꿨으니 자물쇠를 풉니다.
        conversionLock.unlock()
            
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
        // 상태를 false로 되돌릴 때도 자물쇠를 채웁니다.
        conversionLock.lock()
        isConvertingInProgress = false
        conversionLock.unlock()
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
    
    // MARK: - 수동 단축키 교정 시에도 찌꺼기 제거 적용
    private func convertString(_ text: String) -> String {
        let containsEnglish = text.contains { $0.isASCII && $0.isLetter }
        let containsKoreanSyllable = text.unicodeScalars.contains { $0.value >= 0xAC00 && $0.value <= 0xD7A3 }
        
        // 🌟 수동 교정(단축키)으로 블록을 잡고 실행했을 때도 "d일어나고" -> "일어나고"로 완벽하게 정제합니다.
        if containsEnglish && containsKoreanSyllable {
            let converted = convertToKo(text)
            let cleaned = String(converted.filter { char in
                guard let val = char.unicodeScalars.first?.value else { return true }
                let isIncompleteJamo = (val >= 0x3130 && val <= 0x318F)
                let isStrayEnglish = char.isASCII && char.isLetter
                return !isIncompleteJamo && !isStrayEnglish
            })
            if !cleaned.isEmpty { return cleaned }
        }
        
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

    // 🌟 [수정됨] SettingsManager의 스냅샷에서 사용자가 설정한 값을 읽어옵니다.
    private func getClipboardRestoreDelay(for bundleID: String?) -> TimeInterval {
        guard let bundleID = bundleID else { return 0.15 } // 번들 ID가 없으면 기본값 반환

        // 🌟 스냅샷을 확인하여 사용자가 설정한 앱 목록에 있으면 그 딜레이를 반환
        let snapshot = SettingsManager.shared.snapshot
        if let customApp = snapshot.appDelays.first(where: { $0.bundleIdentifier == bundleID }) {
            return customApp.delay
        }

        // 등록되지 않은 일반 앱은 가장 빠른 네이티브 딜레이(0.15초) 적용
        return 0.15
    }
}
