//
//  TypoConverter.swift
//  LangSwitcher
//
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
        // [락 게이트치기] 메인 액터 격리 구역이므로 원자적으로 체크됩니다.
        guard !isConvertingInProgress else { return }
        isConvertingInProgress = true

        // 🌟 [문제 A 완벽 해결: 찰나의 락 유실 원천 차단]
        // 내부에서 isConvertingInProgress = false를 실행하는 forceCancelAndCleanup() 대신
        // 오직 이전 비동기 태스크들의 '취소' 명령만 순수하게 전파합니다.
        // 이로써 락 상태가 상시 true로 완벽히 고정되어, 연타 시 태스크가 중복 생성되는 틈새가 0%로 통제됩니다.
        timeoutTask?.cancel()
        timeoutTask = nil
        correctionTask?.cancel()
        correctionTask = nil

        // 자원 백업 집행
        self.backupClipboard()
        let initialCount = NSPasteboard.general.changeCount

        // 메인 교정 비동기 트랜잭션 가동
        correctionTask = Task { [weak self] in
            guard let self = self else { return }
            
            // 🌟 [문제 B, C 완벽 해결: 단일 통합 defer 구조 수립]
            // 복수 defer 선언을 과감히 철거하여 Swift LIFO 스택 꼬임 현상을 물리적으로 박멸합니다.
            // 본문 하단의 모든 명시적 청소부 호출을 제거하고, 오직 이 단 하나의 defer 상자가 퇴출 분기를 독점합니다.
            defer {
                if Task.isCancelled {
                    // 비상 탈출 경로: 태스크 대기 도중 외부 취소를 맞이했다면 강제 청소 가동
                    self.forceCancelAndCleanup()
                } else {
                    // 정상 마감 경로: 교정이 성공했거나, 텍스트가 없는 예외 상태 분기를 모두 포괄하여 안전 마감
                    self.cleanupAfterSuccess()
                }
            }
            
            // 1. 선제 유예 딜레이
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled else { return }
            self.postKeyEvent(keyCode: 8, modifiers: .maskCommand) // Cmd+C

            // 2. 복사 이벤트 수신 대기 유예
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled else { return }

            let localPB = NSPasteboard.general
            
            // ─── 조건 분기 시작 ───────────────────────────────────
            if localPB.changeCount != initialCount,
               let selectedText = localPB.string(forType: .string), !selectedText.isEmpty {
                
                // ==========================================
                // ✅ [경로 A] 교정 성공 경로
                // ==========================================
                let convertedText = self.convertString(selectedText)
                localPB.clearContents()
                localPB.setString(convertedText, forType: .string)

                self.postKeyEvent(keyCode: 9, modifiers: .maskCommand) // Cmd+V
                
                let delay = self.getClipboardRestoreDelay(for: AppMonitor.shared.activeAppBundleID)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                
                // 🌟 [명시적 호출 제거] 본문 마지막에 cleanupAfterSuccess()를 적지 않고
                // 그냥 블록을 자연 탈출하면 상단 defer의 else 분기가 알아서 완벽하게 장부를 정산합니다.
                
            } else {
                // ==========================================
                // ⚠️ [경로 B] 선택 텍스트 없음 / 무변화 예외 경로
                // ==========================================
                self.postKeyEvent(keyCode: 124, modifiers: [])
                
                // 🌟 [명시적 호출 제거] 그냥 탈출해도 defer의 else 분기가 안전하게 자물쇠를 풀어줍니다.
                #if DEBUG
                dprint("⚡ [TypoConverter] 선택 텍스트가 없어 예외 분기로 안전하게 탈출 마감합니다.")
                #endif
            }
        }

        // 동적 워치독 타임아웃 세팅 (기존 로직 유지)
        let currentAppID = AppMonitor.shared.activeAppBundleID
        let appDelay = self.getClipboardRestoreDelay(for: currentAppID)
        let calculatedTimeout = max(2.0, min(5.0, appDelay * 3.0))
        let timeoutNanoseconds = UInt64(calculatedTimeout * 1_000_000_000)

        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: timeoutNanoseconds)
            guard !Task.isCancelled else { return }

            guard let self = self else { return }
            self.forceCancelAndCleanup()
        }
    }

    // MARK: - 청소부 이원화 아키텍처 수복 구역 (버그 박멸)

    /// 🌟 [추가] 1. 태스크 내부에서 스스로 임무를 완수하고 퇴출할 때 사용하는 안전 청소부 (Self-Cancel 없음)
    private func cleanupAfterSuccess() {
        // 비상용 워치독 타이머만 해제합니다.
        self.timeoutTask?.cancel()
        self.timeoutTask = nil
        
        // 태스크 내부 구역이므로 장부만 비워 컴파일러 오염을 차단합니다.
        self.correctionTask = nil
        
        // 독점 자원 원복 및 락 팻말 철거
        self.restoreClipboard()
        self.isConvertingInProgress = false
    }

    /// 🌟 [추가] 2. 3초 타임아웃이 터졌거나 외부 프로필 체인지 등에서 비상용으로 강제 중단시킬 때 호출하는 청소부
    func forceCancelAndCleanup() {
        // 아직 잠들어있거나 돌고 있을지 모르는 모든 비동기 스레드를 강제로 사살합니다.
        self.timeoutTask?.cancel()
        self.correctionTask?.cancel()
        
        self.timeoutTask = nil
        self.correctionTask = nil
        
        // 지체 없이 자원 완벽 원복 및 플래그 초기화
        self.restoreClipboard()
        self.isConvertingInProgress = false
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
        let chos = Array("ㄱCCcㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ")
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
