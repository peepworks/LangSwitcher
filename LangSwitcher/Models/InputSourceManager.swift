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

import Foundation
import Carbon

// ✅ 지원하는 모든 언어와 시스템 언어 코드를 매핑합니다.
enum SupportedLanguage: String, CaseIterable, Identifiable {
    case english = "영어 (en)"
    case korean = "한국어 (ko)"
    case japanese = "일본어 (ja)"
    case chineseSimp = "중국어 간체 (zh-Hans)"
    case chineseTrad = "중국어 번체 (zh-Hant)"
    case german = "독일어 (de)"
    case french = "프랑스어 (fr)"
    case spanish = "스페인어 (es)"
    case italian = "이탈리아어 (it)"
    case dutch = "네덜란드어 (nl)"
    case russian = "러시아어 (ru)"
    
    var id: String { self.rawValue }
    
    // macOS 시스템이 키보드를 인식할 때 사용하는 접두사 코드
    var tisLanguageCode: String {
        switch self {
        case .english: return "en"          // en_US, en_GB, en_AU 등 모두 포함
        case .korean: return "ko"           // ko_KR
        case .japanese: return "ja"         // ja_JP
        case .chineseSimp: return "zh-Hans" // zh_CN (간체)
        case .chineseTrad: return "zh-Hant" // zh_TW, zh_HK (번체)
        case .german: return "de"           // de_DE
        case .french: return "fr"           // fr_FR
        case .spanish: return "es"          // es_ES
        case .italian: return "it"          // it_IT
        case .dutch: return "nl"            // nl_NL
        case .russian: return "ru"          // ru_RU
        }
    }
}

class InputSourceManager {
    static let shared = InputSourceManager()

    func switchLanguage(to langName: String) {
        // UI에서 전달받은 텍스트를 Enum으로 변환 (기본값: 영어)
        let targetLang = SupportedLanguage(rawValue: langName) ?? .english
        
        // 1. 영어와 한국어는 가장 많이 쓰이므로, 명확한 ID로 먼저 1차 시도 (가장 빠르고 정확한 Fallback)
        if targetLang == .english {
            if selectSource(byID: "com.apple.keylayout.ABC") || selectSource(byID: "com.apple.keylayout.US") { return }
        } else if targetLang == .korean {
            if selectSource(byID: "com.apple.inputmethod.Korean.2SetKorean") { return }
        }

        // 2. 그 외 다국어 및 ID가 다른 키보드들은 시스템 언어 코드로 2차 정밀 검색
        if selectSource(byLanguage: targetLang.tisLanguageCode) {
            print("✅ 언어 전환 성공: \(langName)")
        } else {
            print("❌ 언어 전환 실패: \(langName) 키보드를 찾을 수 없습니다.")
        }
    }

    // ID로 직접 전환 (가장 빠름)
    private func selectSource(byID id: String) -> Bool {
        let filter = [kTISPropertyInputSourceID: id] as CFDictionary
        if let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource],
           let target = list.first {
            TISSelectInputSource(target)
            return true
        }
        return false
    }

    // 언어 코드로 전환 (hasPrefix를 사용하여 지역 코드까지 완벽 커버)
    private func selectSource(byLanguage langCode: String) -> Bool {
        guard let sourceList = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else { return false }
        
        for source in sourceList {
            let isSelectablePtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable)
            let isSelectable = isSelectablePtr != nil ? Unmanaged<NSNumber>.fromOpaque(isSelectablePtr!).takeUnretainedValue().boolValue : false
            
            if isSelectable,
               let langPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages),
               let langs = Unmanaged<AnyObject>.fromOpaque(langPtr).takeUnretainedValue() as? [String] {
                
                // 예: "en-US" 문자열이 "en"으로 시작하는지 확인 (국가 상관없이 언어만 맞으면 전환)
                if langs.contains(where: { $0.hasPrefix(langCode) }) {
                    TISSelectInputSource(source)
                    return true
                }
            }
        }
        return false
    }
}
