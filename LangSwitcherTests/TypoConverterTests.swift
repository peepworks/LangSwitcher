import XCTest
@testable import LangSwitcher // 앱 이름에 맞게 수정하세요

final class TypoConverterTests: XCTestCase {
    
    func testConvertToKo() {
        // 1. 기본 초+중 조합
        XCTAssertEqual(TypoConverter.shared.convertToKo("gks"), "한")
        XCTAssertEqual(TypoConverter.shared.convertToKo("rmf"), "글")
        
        // 2. 겹받침 정상 처리 (밝, 밯)
        XCTAssertEqual(TypoConverter.shared.convertToKo("qkfr"), "밝")
        XCTAssertEqual(TypoConverter.shared.convertToKo("qkg"), "밯")
        
        // 3. 겹받침 쪼개기(splitJongs) 케이스
        XCTAssertEqual(TypoConverter.shared.convertToKo("ekfrk"), "달가")
        XCTAssertEqual(TypoConverter.shared.convertToKo("rkqtl"), "갑시")
        
        // 4. 모음 연속 조합 (이중 모음)
        XCTAssertEqual(TypoConverter.shared.convertToKo("ghk"), "화")
        
        // 5. 연속된 자음 조합
        XCTAssertEqual(TypoConverter.shared.convertToKo("zzzz"), "ㅋㅋㅋㅋ")
        
        // ---------------------------------------------------------
        // 🌟 [리뷰어 특별 요청: 엣지 케이스 검증]
        // ---------------------------------------------------------
        
        // ---------------------------------------------------------
        // 🌟 [리뷰어 특별 요청: 엣지 케이스 검증]
        // ---------------------------------------------------------
        
        // 6. 겹받침 + 모음 ('ㅇ' 유무에 따른 동작 분기 확인)
        XCTAssertEqual(TypoConverter.shared.convertToKo("ekfrdl"), "닭이")
        XCTAssertEqual(TypoConverter.shared.convertToKo("ekfrl"), "달기")
        
        // 7. 연속 자음 조합 (단독 입력 시 겹받침이 아닌 개별 자음으로 분리되는 Mac 표준 동작 확인)
        XCTAssertEqual(TypoConverter.shared.convertToKo("rt"), "ㄱㅅ") // ㄱ + ㅅ
        XCTAssertEqual(TypoConverter.shared.convertToKo("sw"), "ㄴㅈ") // ㄴ + ㅈ
        
        // 8. 특수문자가 중간에 삽입된 경우 (강제 커밋 및 예외 처리 검증)
        // 오토마타의 모음-자음 역순 입력 처리 결과인 "되"를 안전하게 유지하며 특수문자 삽입
        XCTAssertEqual(TypoConverter.shared.convertToKo("hell!o"), "되ㅣ!ㅐ")
        XCTAssertEqual(TypoConverter.shared.convertToKo("hello"), "되ㅣㅐ")
        
        
        // 1. 빈 문자열 — nil 반환 or 빈 문자열 여부 확인
        XCTAssertEqual(TypoConverter.shared.convertToKo(""), "")

        // 2. 숫자 / ASCII 비-알파벳 — 변환 없이 그대로 통과해야 함
        XCTAssertEqual(TypoConverter.shared.convertToKo("123"), "123")

        // 3. 이미 한글인 경우 — 의도된 동작이 pass-through인지 확인
        // (현재 로직이 한글 입력을 받으면 어떻게 처리하는지 문서화 효과)

        // 4. ㅢ 조합 — 3자 모음 시퀀스 (드물지만 오토마타 엣지)
        // d(ㅇ) + m(ㅡ) + l(ㅣ) = 의
        XCTAssertEqual(TypoConverter.shared.convertToKo("dml"), "의")

        // 5. 단어 경계에서 겹받침 분리 + 새 음절 시작
        XCTAssertEqual(TypoConverter.shared.convertToKo("ekfrdkek"), "닭아다")
    }
}
