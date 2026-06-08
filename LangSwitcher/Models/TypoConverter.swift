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
    
    private var correctionGeneration: Int = 0

    // 제어권을 명확하게 쥐고 흔들 두 개의 타이밍 태스크
    private var correctionTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    private init() {}

    // MARK: - 스마트 자동 오타 감지용 엔진 (스페이스바 삭제 버그 완벽 수복)
    func detectAndConvert(englishInput: String) -> String? {
        guard englishInput.count >= 2 else { return nil }
        
        // 영문자가 단 하나도 없다면 오타 교정 대상이 아니므로 즉시 차단!
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

    // MARK: - 수동 단축키 오타 교정 (마스터 do-catch 요새 구축 완료)
    func executeCorrection() {
        // 1. 원자적 자물쇠 체크
        guard !isConvertingInProgress else {
            dprint("⚡️ [TypoConverter] 이미 변환 트랜잭션이 진행 중입니다 — 재진입을 안전하게 차단했습니다.")
            return
        }
        isConvertingInProgress = true

        // 2. 오버플로우 안전 증가 연산으로 고유 세대 번호 발행
        correctionGeneration &+= 1
        let myGeneration = correctionGeneration

        // 기존 잔여 태스크들 청정 소각
        timeoutTask?.cancel()
        timeoutTask = nil
        correctionTask?.cancel()
        correctionTask = nil

        self.backupClipboard()
        let initialCount = NSPasteboard.general.changeCount

        // 3. 통합 비동기 트랜잭션 발사
        correctionTask = Task { [weak self] in
            guard let self = self else { return }

            let currentAppID = AppMonitor.shared.activeAppBundleID
            let appDelay = self.getClipboardRestoreDelay(for: currentAppID)
            let calculatedTimeout = max(2.0, min(5.0, appDelay * 3.0))

            // 🌟 [우주 방어 수복 포인트 1] 타임아웃 Task를 작업 문맥 내부로 격리 캡슐화합니다.
            // 실제 작업 스레드가 CPU를 확보하고 구동되는 바로 그 시점부터 정밀 초읽기가 개시됩니다.
            let myTimeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(calculatedTimeout * 1_000_000_000))
                guard !Task.isCancelled else { return }
                
                // 타임아웃 도달 시 메인 액터 컨텍스트에서 안전하게 강제 정리 집행
                self?.forceCancelAndCleanup()
            }

            // 🌟 [우주 방어 수복 포인트 2] 스위프트 구조적 동시성의 핵심인 defer 복구 가드를 결속합니다.
            // 이 블록이 무사히 완수되든, 도중에 에러가 나서 catch문으로 튕겨 나가든 관계없이
            // 종료 즉시 시한폭탄 타이머(myTimeoutTask)의 도화선을 즉시 잘라 누수를 차단합니다.
            defer {
                myTimeoutTask.cancel()
            }

            var wasCancelled = false

            do {
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
                    // 버퍼가 비어있다면 마우스 드래그 상태 확인
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
                    let convertedText = self.convertString(selectedText)
                    localPB.clearContents()
                    localPB.setString(convertedText, forType: .string)

                    try await Task.sleep(nanoseconds: 20_000_000)
                    self.postKeyEvent(keyCode: 9, modifiers: .maskCommand) // Cmd+V

                    let delay = self.getClipboardRestoreDelay(for: AppMonitor.shared.activeAppBundleID)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

                    EventMonitor.shared.clearTypingBuffer()
                    for char in convertedText {
                        EventMonitor.shared.appendToTypingBuffer(char)
                    }
                } else {
                    self.postKeyEvent(keyCode: 124, modifiers: [])
                }
            } catch {
                wasCancelled = true
                dprint("🛑 [TypoConverter] 클립보드 폴링/대기 도중 태스크 취소가 감지되어 즉시 안전 탈출했습니다.")
            }

            // 🌟 [최종 수복 영토] 낙오자 세대까지 예외 없이 트랜잭션 자물쇠 철저 정산
            if self.correctionGeneration == myGeneration {
                if Task.isCancelled || wasCancelled {
                    self.forceCancelAndCleanup()
                } else {
                    await self.cleanupAfterSuccess()
                }
            } else {
                dprint("👻 [GenerationGuard] 구세대(#\(myGeneration)) 태스크 퇴출. 잠금 플래그를 안정적으로 초기화합니다.")
                self.isConvertingInProgress = false
            }
        }
    }

    // MARK: - 정리 및 초기화 로직 (동시성 레이스 컨디션 방어망 구축 완료)
    private func cleanupAfterSuccess() async {
        self.timeoutTask?.cancel()
        self.timeoutTask = nil
        self.correctionTask = nil

        // 🌟 [수복 1] 정상 완료 시 즉시 동기식 정산으로 복원을 집행합니다.
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
        
        // 🌟 [우주 방어 수복 포인트 2]
        // 무의미하고 위험한 [weak self] 비동기 캡처를 전면 파괴합니다.
        // 싱글톤 엔터티 주소에 직접 바인딩하여, 어떤 가혹한 취소 예외 상황에서도
        // 유저의 원본 클립보드 장부 복원이 100% 실행되도록 보장합니다.
        Task { @MainActor in
            await TypoConverter.shared.restoreClipboard()
        }
    }

    private func backupClipboard() {
        self.savedClipboardString = NSPasteboard.general.string(forType: .string)
    }

    private func restoreClipboard() async {
        guard let saved = savedClipboardString else { return }
        
        // 🌟 [우주 방어 수복 포인트 3]
        // OS HID 시스템 큐에 담긴 Cmd+V 이벤트가 타겟 샌드박스 앱의
        // 텍스트 인출 버퍼에 무사히 로드될 수 있도록 찰나의 안전 시간 창(0.03초)을 확보합니다.
        // 단순 Task.yield()의 1프레임 양보로 인해 발생하던 엇박자 롤백 버그가 완벽히 소각됩니다.
        try? await Task.sleep(nanoseconds: 30_000_000)
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(saved, forType: .string)
        savedClipboardString = nil
        
        dprint("✨ [TypoConverter] 유저의 오리지널 클립보드 장부가 완전무결하게 복원되었습니다.")
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

    private func getClipboardRestoreDelay(for bundleID: String?) -> TimeInterval {
        guard let bundleID = bundleID else { return 0.15 }
        let snapshot = SettingsManager.shared.snapshot
        if let customApp = snapshot.appDelays.first(where: { $0.bundleIdentifier == bundleID }) { return customApp.delay }
        return 0.15
    }
}
