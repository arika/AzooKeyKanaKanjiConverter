/// 交ぜ書き変換の制約: 辞書語の ruby の`rubyRange`の範囲に、入力した漢字`kanji`がそのまま現れること
package struct MazegakiConstraint: Sendable, Equatable, Hashable {
    package init(kanji: Character, rubyRange: Range<Int>) {
        self.kanji = kanji
        self.rubyRange = rubyRange
    }

    package var kanji: Character
    package var rubyRange: Range<Int>
}

/// 交ぜ書き変換の整合判定
///
/// 辞書語の word の各文字を ruby の部分列に対応づけ、制約を満たせるかを判定する。
/// 1. かなは ruby と 1 文字ずつ一致すること（ひらがなはカタカナとして比べる）。
/// 2. 制約の開始位置では、word の文字が入力した漢字と一致し、ruby のちょうどその範囲に対応すること。
/// 3. その他の文字（漢字など）は ruby の 1〜4 文字に対応してよい。ただし、制約の開始位置をまたいではならない。
///
/// 「一致」は`Character`の`==`（Unicode の正準等価）で判定する。CJK 互換漢字（U+FA19 神）と対応する統合漢字（U+795E 神）は同じ字とみなす。
package enum MazegakiAlignment {
    /// ruby の文字以外の 1 文字が対応できる ruby の長さの上限
    static let maxRubyLengthPerCharacter = 4

    /// - Parameters:
    ///   - word: 辞書語の表記
    ///   - ruby: 辞書語の読み（カタカナ）
    ///   - constraints: ruby の中での制約。範囲は互いに重ならないこと。
    package static func matches(word: String, ruby: [Character], constraints: [MazegakiConstraint]) -> Bool {
        let word = Array(word)
        // ruby の位置 → その位置から始まる制約
        var constraintAt: [MazegakiConstraint?] = Array(repeating: nil, count: ruby.count)
        for constraint in constraints {
            guard constraint.rubyRange.lowerBound >= 0,
                  constraint.rubyRange.upperBound <= ruby.count,
                  !constraint.rubyRange.isEmpty else {
                // 語の範囲をまたぐ制約は不適合
                return false
            }
            constraintAt[constraint.rubyRange.lowerBound] = constraint
        }
        // memo[i * (ruby.count + 1) + p]: word[i...] と ruby[p...] を対応づけられるか
        var memo: [Bool?] = Array(repeating: nil, count: (word.count + 1) * (ruby.count + 1))

        func rec(_ i: Int, _ p: Int) -> Bool {
            let key = i * (ruby.count + 1) + p
            if let memoized = memo[key] {
                return memoized
            }
            let result: Bool
            if i == word.count {
                result = p == ruby.count
            } else if p >= ruby.count {
                result = false
            } else if let constraint = constraintAt[p] {
                result = word[i] == constraint.kanji && rec(i + 1, constraint.rubyRange.upperBound)
            } else if let kana = katakana(of: word[i]) {
                result = kana == ruby[p] && rec(i + 1, p + 1)
            } else {
                var found = false
                for length in 1 ... min(maxRubyLengthPerCharacter, ruby.count - p) {
                    // 制約の開始位置をまたがない
                    if length >= 2, constraintAt[p + length - 1] != nil {
                        break
                    }
                    if rec(i + 1, p + length) {
                        found = true
                        break
                    }
                }
                result = found
            }
            memo[key] = result
            return result
        }
        return rec(0, 0)
    }

    /// かなならカタカナにして返す。かなでなければ`nil`
    private static func katakana(of character: Character) -> Character? {
        guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first else {
            return nil
        }
        switch scalar.value {
        case 0x3041 ... 0x3096:
            return Unicode.Scalar(scalar.value + 0x60).map(Character.init)
        case 0x30A1 ... 0x30FA, 0x30FC:
            return character
        default:
            return nil
        }
    }
}
