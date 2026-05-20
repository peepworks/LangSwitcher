import XCTest
@testable import LangSwitcher

final class TypoConverterTests: XCTestCase {
    
    func testConvertToKo() {
        // 1. 기본 초+중 조합
        XCTAssertEqual(TypoConverter.shared.convertToKo("gks"), "한")
        XCTAssertEqual(TypoConverter.shared.convertToKo("rmf"), "글")
        
        // 2. 겹받침 정상 처리 (밝, 밯)
        XCTAssertEqual(TypoConverter.shared.convertToKo("qkfr"), "밝") // ㅂ ㅏ ㄹ ㄱ
        XCTAssertEqual(TypoConverter.shared.convertToKo("qkg"), "밯") // ㅂ ㅏ ㅎ
        
        // 3. 🌟 겹받침 쪼개기(splitJongs) 케이스 - 명시적 'ㅇ' 유무에 따른 차이 완벽 검증
        // ㄷㅏㄹㄱㅏ (ekfrk) -> 달가
        XCTAssertEqual(TypoConverter.shared.convertToKo("ekfrk"), "달가")
        
        // ㄷㅏㄹㄱㅇㅏ (ekfrdk) -> 닭아
        XCTAssertEqual(TypoConverter.shared.convertToKo("ekfrdk"), "닭아")
        
        // ㄱㅏㅂㅅㅣ (rkqtl) -> 갑시
        XCTAssertEqual(TypoConverter.shared.convertToKo("rkqtl"), "갑시")
        
        // 4. 모음 연속 조합 (이중 모음)
        // ㅗ + ㅏ = ㅘ (h + k)
        XCTAssertEqual(TypoConverter.shared.convertToKo("ghk"), "화")
        
        // 5. 연속된 자음 (커밋이 중간에 잘 일어나는지 확인)
        XCTAssertEqual(TypoConverter.shared.convertToKo("zzzz"), "ㅋㅋㅋㅋ")
    }
}
