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

@MainActor // 🌟 Swift 6 완벽 격리 선언
class TypoConverter {
    static let shared = TypoConverter()

    private let eventSource: CGEventSource? = CGEventSource(stateID: .combinedSessionState)
    
    private var isConvertingInProgress = false
    private var savedClipboardString: String?
    private var watchdogTask: Task<Void, Never>?

    private init() {}

    // MARK: - 스마트 자동 오타 감지용 엔진 (EventMonitor 전용 훅)
    func detectAndConvert(englishInput: String) -> String? {
        guard englishInput.count >= 2 else { return nil }

        let converted = convertToKo(englishInput)
        var hasSyllable = false
        var hasIncomplete = false

        for char in converted {
            guard let scalar = char.unicodeScalars.first else { continue }
            if scalar.value >= 0xAC00 && scalar.value <= 0xD7A3 {
                hasSyllable = true
            } else if (scalar.value >= 0x3130 && scalar.value <= 0x318F) || (char.isASCII && char.isLetter) {
                hasIncomplete = true
            }
        }

        if hasSyllable {
            if !hasIncomplete {
                return converted
            } else {
                let containsEnglish = englishInput.contains { $0.isASCII && $0.isLetter }
                let containsKoreanSyllable = englishInput.unicodeScalars.contains { $0.value >= 0xAC00 && $0.value <= 0xD7A3 }

                if containsEnglish && containsKoreanSyllable {
                    let cleaned = String(converted.filter { char in
                        guard let val = char.unicodeScalars.first?.value else { return true }
                        let isIncompleteJamo = (val >= 0x3130 && val <= 0x318F)
                        let isStrayEnglish = char.isASCII && char.isLetter
                        return !isIncompleteJamo && !isStrayEnglish
                    })

                    if !cleaned.isEmpty { return cleaned }
                }
            }
        }
        return nil
    }

    // MARK: - 수동 단축키 오타 교정 (Watchdog 레이어 장착)
    func executeCorrection() {
        guard !isConvertingInProgress else { return }
        isConvertingInProgress = true

        // 2초 뒤 강제 잠금 해제 세이프티 가드 발동
        watchdogTask?.cancel()
        watchdogTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            dprint("🚨 [TypoConverter] 비동기 오토메이션 체인 유실 감지! 강제 셀프 힐링을 집행합니다.")
            self.safeRestoreAndUnlock()
        }

        self.backupClipboard()

        // 커서 앞 한 단어 자동 지정 블록 선택 (Option + Shift + Left Arrow)
        self.postKeyEvent(keyCode: 123, modifiers: [.maskAlternate, .maskShift])

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let localPB = NSPasteboard.general
            let initialCount = localPB.changeCount

            // 복사 명령 하드웨어 시뮬레이션 (Cmd+C)
            self.postKeyEvent(keyCode: 8, modifiers: .maskCommand)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                if localPB.changeCount != initialCount,
                   let selectedText = localPB.string(forType: .string), !selectedText.isEmpty {

                    let convertedText = self.convertString(selectedText)
                    localPB.clearContents()
                    localPB.setString(convertedText, forType: .string)

                    // 붙여넣기 시뮬레이션 (Cmd+V)
                    self.postKeyEvent(keyCode: 9, modifiers: .maskCommand)

                    let activeAppID = AppMonitor.shared.activeAppBundleID
                    let delay = self.getClipboardRestoreDelay(for: activeAppID)

                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        self.safeRestoreAndUnlock()
                    }
                } else {
                    self.postKeyEvent(keyCode: 124, modifiers: []) // 블록 해제 예외 처리
                    self.safeRestoreAndUnlock()
                }
            }
        }
    }

    private func safeRestoreAndUnlock() {
        watchdogTask?.cancel()
        watchdogTask = nil
        restoreClipboard()
        isConvertingInProgress = false
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
        up?.flags = modifiers
        up?.post(tap: .cghidEventTap)
    }

    private func convertString(_ text: String) -> String {
        let containsEnglish = text.contains { $0.isASCII && $0.isLetter }
        let containsKoreanSyllable = text.unicodeScalars.contains { $0.value >= 0xAC00 && $0.value <= 0xD7A3 }

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

    // MARK: - 두벌식 오토마타 엔진 코어 복원
    func convertToKo(_ englishText: String) -> String {
        let chos = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ")
        let jungs = Array("ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ")
        let jongs = Array(" ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ")
        let doubleJongs: [String: String] = ["ㄱㅅ":"ㄳ", "ㄴㅈ":"ㄵ", "ㄴㅎ":"ㄶ", "ㄹㄱ":"ㄺ", "ㄹㅁ":"ㄻ", "ㄹㅂ":"ㄼ", "ㄹㅅ":"ㄽ", "ㄹㅌ":"ㄾ", "ㄹㅍ":"ㄿ", "ㄹㅎ":"ㅀ", "ㅂㅅ":"ㅄ"]
        let doubleJungs: [String: String] = ["ㅗㅏ":"ㅘ", "ㅗㅐ":"ㅙ", "ㅗㅣ":"ㅚ", "ㅜㅓ":"ㅝ", "ㅜㅔ":"ㅞ", "ㅜㅣ":"ㅟ", "ㅡㅣ":"ㅢ"]
        let engToKor: [Character: Character] = ["q":"ㅂ","w":"ㅈ","e":"ㄷ","r":"ㄱ","t":"ㅅ","y":"ㅛ","u":"ㅕ","i":"ㅑ","o":"ㅐ","p":"ㅔ","a":"ㅁ","s":"ㄴ","d":"ㅇ","f":"ㄹ","g":"ㅎ","h":"ㅗ","j":"ㅓ","k":"ㅏ","l":"ㅣ","z":"ㅋ","x":"ㅌ","c":"ㅊ","v":"ㅍ","b":"ㅠ","n":"ㅜ","m":"ㅡ","Q":"ㅃ","W":"ㅉ","E":"ㄸ","R":"ㄲ","T":"ㅆ","O":"ㅒ","P":"ㅖ"]

        var result = ""
        var cho = ""
        var jung = ""
        var jong = ""

        func commit(c: String, ju: String, jo: String) {
            if !c.isEmpty && !ju.isEmpty {
                let cIdx = chos.firstIndex(of: Character(c)) ?? 0
                let juIdx = jungs.firstIndex(of: Character(ju)) ?? 0
                let joIdx = jo.isEmpty ? 0 : (jongs.firstIndex(of: Character(jo)) ?? 0)
                let uni = ((cIdx * 21) + juIdx) * 28 + joIdx + 0xAC00
                if let scalar = UnicodeScalar(uni) { result.append(Character(scalar)) }
            } else {
                result += c + ju + jo
            }
        }

        let chars = Array(englishText)
        var i = 0

        while i < chars.count {
            let c = chars[i]
            guard let korChar = engToKor[c] else {
                commit(c: cho, ju: jung, jo: jong)
                cho = ""; jung = ""; jong = ""
                result.append(c)
                i += 1
                continue
            }

            let kor = String(korChar)
            let isVowel = jungs.contains(korChar)

            if !isVowel {
                if cho.isEmpty { cho = kor }
                else if jung.isEmpty {
                    commit(c: cho, ju: jung, jo: jong)
                    cho = kor; jung = ""; jong = ""
                } else {
                    var nextIsVowel = false
                    if i + 1 < chars.count, let n = engToKor[chars[i+1]], jungs.contains(n) { nextIsVowel = true }

                    if nextIsVowel {
                        commit(c: cho, ju: jung, jo: jong)
                        cho = kor; jung = ""; jong = ""
                    } else {
                        if jong.isEmpty { jong = kor }
                        else if let combined = doubleJongs[jong + kor] { jong = combined }
                        else {
                            commit(c: cho, ju: jung, jo: jong)
                            cho = kor; jung = ""; jong = ""
                        }
                    }
                }
            } else {
                if cho.isEmpty || jong.isEmpty {
                    if jung.isEmpty { jung = kor }
                    else if let combined = doubleJungs[jung + kor] { jung = combined }
                    else {
                        commit(c: cho, ju: jung, jo: jong)
                        cho = ""; jung = kor; jong = ""
                    }
                } else {
                    let splitJongs: [String: (String, String)] = ["ㄳ":("ㄱ","ㅅ"), "ㄴㅈ":("ㄴ","ㅈ"), "ㄶ":("ㄴ","ㅎ"), "ㄺ":("ㄹ","ㄱ"), "ㄻ":("ㄹ","ㅁ"), "ㄼ":("ㄹ","ㅂ"), "ㄽ":("ㄹ","ㅅ"), "ㄾ":("ㄹ","ㅌ"), "ㄿ":("ㄹ","ㅍ"), "ㅀ":("ㄹ","ㅎ"), "ㅄ":("ㅂ","ㅅ")]

                    if let split = splitJongs[jong] {
                        commit(c: cho, ju: jung, jo: split.0)
                        cho = split.1; jung = kor; jong = ""
                    } else {
                        commit(c: cho, ju: jung, jo: "")
                        cho = jong; jung = kor; jong = ""
                    }
                }
            }
            i += 1
        }
        commit(c: cho, ju: jung, jo: jong)
        return result
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

    private func getClipboardRestoreDelay(for bundleID: String?) -> TimeInterval {
        guard let bundleID = bundleID else { return 0.15 }
        let snapshot = SettingsManager.shared.snapshot
        if let customApp = snapshot.appDelays.first(where: { $0.bundleIdentifier == bundleID }) {
            return customApp.delay
        }
        return 0.15
    }
}
