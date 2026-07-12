//
//  TypoExceptionManager.swift
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

import Foundation
import Combine
import SwiftUI

class TypoExceptionManager: ObservableObject {
    static let shared = TypoExceptionManager()
    
    private let storageKey = "typoExcludedWords"
    
    // 🌟 터미널 명령어 및 개발 환경 필수 예외 명령어 기본 세팅
    private let defaultCommands = [
        "sudo", "vi", "vim", "cd", "ls", "rm", "mv", "cp",
        "mkdir", "cat", "grep", "pwd", "mysql", "git",
        "ssh", "npm", "yarn", "docker", "brew", "apt", "tar",
        "node", "python", "pip", "kill", "ps", "top",
        "clear", "history", "ping", "curl", "wget", "chmod", "chown"
    ]
    
    @Published var excludedWords: [String] {
        didSet {
            UserDefaults.standard.set(excludedWords, forKey: storageKey)
        }
    }
    
    init() {
        if let saved = UserDefaults.standard.array(forKey: storageKey) as? [String] {
            self.excludedWords = saved
        } else {
            self.excludedWords = defaultCommands.sorted()
            UserDefaults.standard.set(self.excludedWords, forKey: storageKey)
        }
    }
    
    func addWord(_ word: String) {
        let cleanWord = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanWord.isEmpty, !excludedWords.contains(cleanWord) else { return }
        excludedWords.append(cleanWord)
        excludedWords.sort()
    }
    
    func removeWord(at offsets: IndexSet) {
        excludedWords.remove(atOffsets: offsets)
    }
    
    func removeWord(_ word: String) {
        excludedWords.removeAll { $0 == word }
    }
    
    // 🌟 엔진에서 이 단어가 예외 항목인지 검증할 때 호출
    func isExcluded(_ word: String) -> Bool {
        return excludedWords.contains(word.lowercased())
    }
    
    // 기본값 초기화 기능
    func resetToDefaults() {
        self.excludedWords = defaultCommands.sorted()
    }
}
