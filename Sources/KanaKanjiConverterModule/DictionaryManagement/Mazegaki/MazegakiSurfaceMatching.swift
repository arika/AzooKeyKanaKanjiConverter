/// 交ぜ書き変換で、入力（`convertTarget`）の表層と、候補の ruby との対応を求める
///
/// 交ぜ書きの候補では、ruby が入力漢字の読みになるので、「ruby の連結が`convertTarget.toKatakana()`と一致する」という前提が成り立たない。
/// その前提で位置を対応づけていた処理（完全一致の判定、予測変換、Zenzai の制約）のために、表層と ruby を突き合わせる。
package enum MazegakiSurfaceMatching {
    package struct Match: Sendable, Equatable {
        /// 対応づけた表層の長さ（先頭から）
        package var surfaceCount: Int
        /// ruby の中での、入力漢字の制約
        package var constraints: [MazegakiConstraint]
    }

    /// 表層の先頭と ruby 全体を対応づける方法をすべて返す。
    ///
    /// - かな・記号などは、ruby の文字と 1 文字ずつ一致すること（表層はカタカナにしてから渡す）。
    /// - 読み表にある字は、その字の読み（派生させたものを含む）のどれかに対応するか、ruby にその字自身が残っていること（素通し）。
    /// - 読み表にない漢字は、ruby にその字自身が残っていること。
    /// - Parameters:
    ///   - surface: `convertTarget`をカタカナにしたものの、対応づけを始める位置以降
    ///   - ruby: 候補の ruby
    package static func matches(surface: ArraySlice<Character>, ruby: [Character], table: MazegakiReadingTable) -> [Match] {
        var results: [Match] = []
        var constraints: [MazegakiConstraint] = []
        func rec(_ i: Int, _ p: Int) {
            if p == ruby.count {
                results.append(Match(surfaceCount: i - surface.startIndex, constraints: constraints))
                return
            }
            guard i < surface.endIndex else {
                return
            }
            let character = surface[i]
            let readings = table.readings(of: character)
            if !readings.isEmpty || MazegakiGenerator.isIdeographic(character) {
                for reading in readings {
                    let r = Array(reading.ruby)
                    if p + r.count <= ruby.count, ruby[p ..< p + r.count].elementsEqual(r) {
                        constraints.append(MazegakiConstraint(kanji: character, rubyRange: p ..< p + r.count))
                        rec(i + 1, p + r.count)
                        constraints.removeLast()
                    }
                }
                // 素通し: ruby に入力漢字がそのまま残っている
                if ruby[p] == character {
                    constraints.append(MazegakiConstraint(kanji: character, rubyRange: p ..< p + 1))
                    rec(i + 1, p + 1)
                    constraints.removeLast()
                }
            } else if ruby[p] == character {
                rec(i + 1, p + 1)
            }
        }
        rec(surface.startIndex, 0)
        return results
    }

    /// 表層全体と ruby 全体を対応づけられるか
    package static func matchesWhole(surface: [Character], ruby: [Character], table: MazegakiReadingTable) -> Bool {
        Self.matches(surface: surface[...], ruby: ruby, table: table).contains { $0.surfaceCount == surface.count }
    }

    /// 語（word / ruby）が表層の先頭のどれだけを覆うか。語の表記が入力漢字の制約を満たす対応だけを採る。
    /// 対応づけられなければ`nil`
    package static func surfaceCount(of word: String, ruby: String, in surface: ArraySlice<Character>, table: MazegakiReadingTable) -> Int? {
        let ruby = Array(ruby)
        return Self.matches(surface: surface, ruby: ruby, table: table).first {
            MazegakiAlignment.matches(word: word, ruby: ruby, constraints: $0.constraints)
        }?.surfaceCount
    }
}
