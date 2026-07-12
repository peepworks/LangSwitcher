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

@MainActor
class TypoConverter {
    static let shared = TypoConverter()

    // 🌟 [클립보드 독점 상수 수립]
    // 더 이상 앱 전환 지연 설정(appDelays)에 종속되지 않고, 시스템 표준 상수 라인을 선언합니다.
    private static let clipboardRestoreDelay: TimeInterval = 0.15
    private static let clipboardTimeout: TimeInterval = 2.0

    private let eventSource: CGEventSource? = CGEventSource(stateID: .combinedSessionState)
    private var isConvertingInProgress = false
    private var savedClipboardString: String?
    
    private var correctionGeneration: Int = 0

    private var correctionTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    private init() {}

    // MARK: - 스마트 자동 오타 감지용 엔진
    func detectAndConvert(englishInput: String) -> String? {
        // 🛡️ [스마트 자동 감지 차단] 실시간 오타 감지 시에도 예외 목록에 포함된 명령어는 원천 무시합니다.
        if TypoExceptionManager.shared.isExcluded(englishInput) {
            return nil
        }
        
        guard englishInput.count >= 2 else { return nil }
        
        let containsEnglish = englishInput.contains { $0.isASCII && $0.isLetter }
        guard containsEnglish else { return nil }
        
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

    // MARK: - 수동 단축키 오타 교정
    func executeCorrection() {
        // 🌟 [수정 수복] EventMonitor에서 실시간 타이핑 버퍼를 안전하게 로컬 상수로 가져와 스코프 문제를 완벽히 소각합니다.
        let targetBuffer = EventMonitor.shared.typingBuffer
        
        // 🌟 [최적화 수복] 백업/복원과 완벽히 연동되는 엔진 스냅샷 해시셋을 통해 O(1) 속도로 필터링
        // if CurrentSnapshot.typoExcludedWordsSet.contains(targetBuffer) {
        if TypoExceptionManager.shared.isExcluded(targetBuffer) {
            dprint("🛡️ [TypoConverter] 예외 단어 안전 자산 감지 -> 교정 취소.")
            return
        }
        
        guard !isConvertingInProgress else { return }
        isConvertingInProgress = true

        correctionGeneration &+= 1
        let myGeneration = correctionGeneration

        timeoutTask?.cancel()
        timeoutTask = nil
        correctionTask?.cancel()
        correctionTask = nil

        self.backupClipboard()
        let initialCount = NSPasteboard.general.changeCount

        correctionTask = Task { [weak self] in
            guard let self = self else { return }

            // 정산된 클래스 상수를 안전하게 바인딩합니다.
            let calculatedTimeout = Self.clipboardTimeout

            let myTimeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(calculatedTimeout * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.forceCancelAndCleanup()
            }

            defer { myTimeoutTask.cancel() }
            var wasCancelled = false

            do {
                // Task 내부에서도 정밀 분석을 위해 로컬 버퍼 상태를 한 번 더 참조합니다.
                let currentBuffer = EventMonitor.shared.typingBuffer
                let localPB = NSPasteboard.general
                var selectedText = ""
                var didFallback = false
                var currentChangeCount = initialCount

                // [전략 1] 정밀 타겟팅 (Shift + Left Arrow 기반 선택)
                if !currentBuffer.isEmpty {
                    let length = currentBuffer.count
                    for _ in 0..<length {
                        self.postKeyEvent(keyCode: 123, modifiers: .maskShift)
                        try await Task.sleep(nanoseconds: 2_000_000)
                    }

                    self.postKeyEvent(keyCode: 8, modifiers: .maskCommand) // Cmd+C

                    for _ in 0..<30 {
                        try await Task.sleep(nanoseconds: 10_000_000)
                        if localPB.changeCount != currentChangeCount { break }
                    }

                    if localPB.changeCount != currentChangeCount, let text = localPB.string(forType: .string), !text.isEmpty {
                        selectedText = text
                        currentChangeCount = localPB.changeCount
                    } else {
                        didFallback = true
                    }
                } else {
                    self.postKeyEvent(keyCode: 8, modifiers: .maskCommand)
                    for _ in 0..<30 {
                        try await Task.sleep(nanoseconds: 10_000_000)
                        if localPB.changeCount != currentChangeCount { break }
                    }

                    if localPB.changeCount != currentChangeCount, let text = localPB.string(forType: .string), !text.isEmpty {
                        if text.hasSuffix("\n") || text.hasSuffix("\r\n") { didFallback = true }
                        else {
                            selectedText = text
                            currentChangeCount = localPB.changeCount
                        }
                    } else { didFallback = true }
                }

                // [전략 2] 정밀 타겟팅 실패 시 네이티브 단어 선택 폴백
                if didFallback && selectedText.isEmpty {
                    self.postKeyEvent(keyCode: 124, modifiers: [])
                    try await Task.sleep(nanoseconds: 10_000_000)

                    self.postKeyEvent(keyCode: 123, modifiers: [.maskAlternate, .maskShift]) // Opt+Shift+Left
                    try await Task.sleep(nanoseconds: 20_000_000)

                    self.postKeyEvent(keyCode: 8, modifiers: .maskCommand) // Cmd+C

                    for _ in 0..<30 {
                        try await Task.sleep(nanoseconds: 10_000_000)
                        if localPB.changeCount != currentChangeCount { break }
                    }

                    if localPB.changeCount != currentChangeCount, let text = localPB.string(forType: .string), !text.isEmpty {
                        selectedText = text
                    }
                }

                // 4. 최종 변환 및 덮어쓰기 집행
                if !selectedText.isEmpty {
                    let convertedText = self.convertString(text: selectedText)
                    localPB.clearContents()
                    localPB.setString(convertedText, forType: .string)

                    try await Task.sleep(nanoseconds: 20_000_000)
                    self.postKeyEvent(keyCode: 9, modifiers: .maskCommand) // Cmd+V

                    // 타겟 일렉트론 앱의 전환 딜레이를 완벽히 소각하고 순정 시스템 속도(150ms)로 직결 정산합니다.
                    try await Task.sleep(nanoseconds: UInt64(Self.clipboardRestoreDelay * 1_000_000_000))

                    EventMonitor.shared.clearTypingBuffer()
                    for char in convertedText { EventMonitor.shared.appendToTypingBuffer(char) }
                } else {
                    self.postKeyEvent(keyCode: 124, modifiers: [])
                }
            } catch {
                wasCancelled = true
            }

            // 장부 정산 구역
            if self.correctionGeneration == myGeneration {
                if Task.isCancelled || wasCancelled { self.forceCancelAndCleanup() }
                else { await self.cleanupAfterSuccess() }
            } else {
                self.isConvertingInProgress = false
            }
        }
    }

    // MARK: - 정리 및 초기화 로직
    private func cleanupAfterSuccess() async {
        self.timeoutTask?.cancel()
        self.timeoutTask = nil
        self.correctionTask = nil

        await self.restoreClipboard()
        self.isConvertingInProgress = false
    }

    func forceCancelAndCleanup() {
        self.timeoutTask?.cancel()
        self.timeoutTask = nil

        self.correctionTask?.cancel()
        self.correctionTask = nil

        self.isInProgressCleanup()
    }

    private func isInProgressCleanup() {
        self.isConvertingInProgress = false
        Task { @MainActor in
            await TypoConverter.shared.restoreClipboard()
        }
    }

    private func backupClipboard() {
        self.savedClipboardString = NSPasteboard.general.string(forType: .string)
    }

    private func restoreClipboard() async {
        guard let saved = savedClipboardString else { return }
        let pb = NSPasteboard.general
        let injectedCount = pb.changeCount
        
        try? await Task.sleep(for: .milliseconds(150))
        
        guard pb.changeCount == injectedCount else {
            dprint("⚠️ [TypoConverter] 붙여넣기 대기 중 클립보드 외부 변조 감지. 유저 데이터를 보호하기 위해 원상 복구를 중단합니다.")
            self.savedClipboardString = nil
            return
        }
        
        pb.clearContents()
        pb.setString(saved, forType: .string)
        self.savedClipboardString = nil
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

    private func convertString(text: String) -> String {
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

    // MARK: - 두벌식 자모 오토마타 변환 코어 엔진
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
                
                let chos = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ")
                let jungs = Array("ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ")
                let jongs = Array(" ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ")

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
}
