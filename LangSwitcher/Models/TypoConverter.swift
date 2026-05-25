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

@MainActor // 🌟 Swift 6 완벽 격리 가드
class TypoConverter {
    static let shared = TypoConverter()

    private let eventSource: CGEventSource? = CGEventSource(stateID: .combinedSessionState)
    private var isConvertingInProgress = false
    private var savedClipboardString: String?

    // 제어권을 명확하게 쥐고 흔들 두 개의 타이밍 태스크
    private var correctionTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    private init() {}

    // MARK: - 스마트 자동 오타 감지용 엔진 (이전 레이어 동일 유지)
    func detectAndConvert(englishInput: String) -> String? {
        guard englishInput.count >= 2 else { return nil }
        let converted = convertToKo(englishInput)
        var hasSyllable = false
        var hasIncomplete = false

        for char in converted {
            guard let scalar = char.unicodeScalars.first else { continue }
            if scalar.value >= 0xAC00 && scalar.value <= 0xD7A3 { hasSyllable = true }
            else if (scalar.value >= 0x3130 && scalar.value <= 0x318F) || (char.isASCII && char.isLetter) { hasIncomplete = true }
        }

        if hasSyllable {
            if !hasIncomplete { return converted }
            else {
                let containsEnglish = englishInput.contains { $0.isASCII && $0.isLetter }
                let containsKoreanSyllable = englishInput.unicodeScalars.contains { $0.value >= 0xAC00 && $0.value <= 0xD7A3 }

                if containsEnglish && containsKoreanSyllable {
                    let cleaned = String(converted.filter { char in
                        guard let val = char.unicodeScalars.first?.value else { return true }
                        return !(val >= 0x3130 && val <= 0x318F) && !(char.isASCII && char.isLetter)
                    })
                    if !cleaned.isEmpty { return cleaned }
                }
            }
        }
        return nil
    }

    // MARK: - 수동 단축키 오타 교정 (리뷰어 피드백 완벽 수용 버전)
    
    func executeCorrection() {
        // @MainActor 동기 구역이므로 이 두 줄은 완벽하게 원자적(Atomic)으로 묶여 작동합니다.
        guard !isConvertingInProgress else { return }
        isConvertingInProgress = true

        // 🌟 [리뷰 반영] 잔재 태스크가 있다면 등록 전에 가차없이 초기화
        correctionTask?.cancel()
        timeoutTask?.cancel()

        self.backupClipboard()
        let initialCount = NSPasteboard.general.changeCount

        // 텍스트 블록 선택 시뮬레이션 (Option + Shift + Left Arrow)
        self.postKeyEvent(keyCode: 123, modifiers: [.maskAlternate, .maskShift])

        // ── 파이프라인 1: 오타 교정 메인 본대 태스크 ─────────────────────────
        correctionTask = Task { [weak self] in
            guard let self = self else { return }
            
            try? await Task.sleep(nanoseconds: 50_000_000) // 0.05초
            guard !Task.isCancelled else { return }

            // 복사 (Cmd+C)
            self.postKeyEvent(keyCode: 8, modifiers: .maskCommand)

            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled else { return }

            let localPB = NSPasteboard.general
            if localPB.changeCount != initialCount,
               let selectedText = localPB.string(forType: .string), !selectedText.isEmpty {

                let convertedText = self.convertString(selectedText)
                localPB.clearContents()
                localPB.setString(convertedText, forType: .string)

                // 붙여넣기 (Cmd+V)
                self.postKeyEvent(keyCode: 9, modifiers: .maskCommand)

                let activeAppID = AppMonitor.shared.activeAppBundleID
                let delay = self.getClipboardRestoreDelay(for: activeAppID)

                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } else {
                self.postKeyEvent(keyCode: 124, modifiers: []) // 선택 해제 가드
            }

            // 🌟 본대가 완벽하게 완수되었으므로 중앙 집중형 안전 청소 집행!
            self.safeCleanup()
        }

        // ── 파이프라인 2: [리뷰 반영] 3초 타임아웃 감시병 안전망 ────────────────
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3초 데드라인 수면
            guard !Task.isCancelled else { return } // 본대가 3초 안에 끝났다면 여기서 자동 퇴출

            // 3초가 지나도록 본대가 응답이 없는 크리티컬 행(Hang) 상태라면 강제 구출 실행
            guard let self = self else { return }
            dprint("🚨 [TypoConverter] 메인 오토메이션 파이프라인 행(Hang) 감지! 3초 안전망 가드를 발동합니다.")
            
            self.safeCleanup()
        }
    }

    // 🌟 [리뷰 반영 핵심] 모든 작업 완료 및 실패/타임아웃 경로에서 호출할 단일 청소 함수
    private func safeCleanup() {
        // 1. 서로가 서로를 원격 취소하여 유령 태스크 잔재 폭사 방지
        timeoutTask?.cancel()
        correctionTask?.cancel()
        
        // 2. 런타임 제어권 홀더 초기화
        timeoutTask = nil
        correctionTask = nil
        
        // 3. 독점 시스템 자원 원복 및 플래그 해제 (항상 마지막에 해제)
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
            savedClipboardString = nil // 메모리 캡처 자원 해제
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
                return !(val >= 0x3130 && val <= 0x318F) && !(char.isASCII && char.isLetter)
            })
            if !cleaned.isEmpty { return cleaned }
        }

        let hasKorean = text.unicodeScalars.contains {
            ($0.value >= 0xAC00 && $0.value <= 0xD7A3) || ($0.value >= 0x3130 && $0.value <= 0x318F)
        }
        return hasKorean ? convertToEn(text) : convertToKo(text)
    }

    // MARK: - 두벌식 자모 오토마타 변환 코어 엔진 (이하 동일 유지)
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
            } else { result += c + ju + jo }
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
                        commit(c: cho, ju: jung, jo: "")
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
                let chos = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ"); let jungs = Array("ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ"); let jongs = Array(" ㄱㄲㄳㄴㄵㄶㄷㄹㄺ¼ㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ")

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
        if let customApp = snapshot.appDelays.first(where: { $0.bundleIdentifier == bundleID }) { return customApp.delay }
        return 0.15
    }
}
