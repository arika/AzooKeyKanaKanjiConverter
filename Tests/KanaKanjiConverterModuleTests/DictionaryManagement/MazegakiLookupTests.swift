@testable import KanaKanjiConverterModule
import SwiftUtils
import XCTest

final class MazegakiAlignmentTests: XCTestCase {
    private func matches(_ word: String, _ ruby: String, _ constraints: [(Character, Range<Int>)]) -> Bool {
        MazegakiAlignment.matches(
            word: word,
            ruby: Array(ruby),
            constraints: constraints.map { MazegakiConstraint(kanji: $0.0, rubyRange: $0.1) }
        )
    }

    func testKanjiAtConstraintPosition() {
        // 破たん → ハタン（破 = [0, 1)）
        XCTAssertTrue(matches("破綻", "ハタン", [("破", 0 ..< 1)]))
        // 破が無い
        XCTAssertFalse(matches("は単", "ハタン", [("破", 0 ..< 1)]))
        XCTAssertFalse(matches("波端", "ハタン", [("破", 0 ..< 1)]))
    }

    func testConstraintRangeMustMatchExactly() {
        // 機のう → キノウ（機 = [0, 1)）: 機能 ✓、帰納 ✗、昨日 ✗
        XCTAssertTrue(matches("機能", "キノウ", [("機", 0 ..< 1)]))
        XCTAssertFalse(matches("帰納", "キノウ", [("機", 0 ..< 1)]))
        XCTAssertFalse(matches("昨日", "キノウ", [("機", 0 ..< 1)]))
        // 機 が [0, 2) に対応する語は、[0, 1) の制約を満たさない
        XCTAssertFalse(matches("機ウ", "キノウ", [("機", 0 ..< 1)]))
    }

    func testKanaMustMatchRuby() {
        // 取 = トリ なら、送り仮名「り」が ruby の「ヒ」と一致しないので不適合
        XCTAssertFalse(matches("取り引き", "トリヒキ", [("取", 0 ..< 2)]))
        XCTAssertTrue(matches("取引", "トリヒキ", [("取", 0 ..< 2)]))
        // 取 = ト なら、送り仮名「り」が ruby の「リ」に対応する
        XCTAssertTrue(matches("取り引き", "トリヒキ", [("取", 0 ..< 1)]))
        XCTAssertFalse(matches("取る", "トリ", [("取", 0 ..< 1)]))
        // ひらがなはカタカナとして比べる
        XCTAssertTrue(matches("ひき取る", "ヒキトル", [("取", 2 ..< 3)]))
    }

    func testOtherCharacterCannotStraddleConstraintStart() {
        // 四面そ歌 → シメンソカ（四 = [0,1)、面 = [1,3)、歌 = [4,5)）
        XCTAssertTrue(matches("四面楚歌", "シメンソカ", [("四", 0 ..< 1), ("面", 1 ..< 3), ("歌", 4 ..< 5)]))
        // 楚 が「ソカ」に対応すると、歌 の制約の開始位置をまたぐ
        XCTAssertFalse(matches("四面楚", "シメンソカ", [("四", 0 ..< 1), ("面", 1 ..< 3), ("歌", 4 ..< 5)]))
    }

    func testConstraintOutsideRubyIsRejected() {
        XCTAssertFalse(matches("破", "ハ", [("破", 0 ..< 2)]))
    }

    func testCanonicalEquivalence() {
        // CJK 互換漢字 U+FA19 と統合漢字 U+795E は正準等価なので同じ字とみなす
        let compat = Character("\u{FA19}")
        let unified = Character("\u{795E}")
        XCTAssertTrue(matches("\u{FA19}社", "ジンジャ", [(unified, 0 ..< 2)]))
        XCTAssertTrue(matches("\u{795E}社", "ジンジャ", [(compat, 0 ..< 2)]))
        // 正準等価でない異体字は別の字
        XCTAssertFalse(matches("櫻", "サクラ", [("桜", 0 ..< 3)]))
    }

    func testSurfaceConstraintRemovesVariantCharacters() {
        let table = MazegakiReadingTable(parsing: "桜\tオウ,サクラ\n", maxReadingsPerKanji: 8)
        XCTAssertTrue(DicdataStore.satisfiesMazegakiConstraintsOnSurface(DicdataElement(word: "桜", ruby: "桜", cid: 0, mid: 0, value: -10), table: table))
        XCTAssertFalse(DicdataStore.satisfiesMazegakiConstraintsOnSurface(DicdataElement(word: "櫻", ruby: "桜", cid: 0, mid: 0, value: -10), table: table))
        // 読み表にない漢字も表意文字なので制約の対象
        XCTAssertFalse(DicdataStore.satisfiesMazegakiConstraintsOnSurface(DicdataElement(word: "髙", ruby: "高", cid: 0, mid: 0, value: -10), table: table))
        // ruby に漢字が無ければ常に通す
        XCTAssertTrue(DicdataStore.satisfiesMazegakiConstraintsOnSurface(DicdataElement(word: "櫻", ruby: "サクラ", cid: 0, mid: 0, value: -10), table: table))
    }
}

final class MazegakiGeneratorTests: XCTestCase {
    private func table(_ text: String) -> MazegakiReadingTable {
        MazegakiReadingTable(parsing: text, maxReadingsPerKanji: 8)
    }

    private func outputs(_ input: String, _ table: MazegakiReadingTable, left: Int = 0, right: Range<Int>? = nil) -> [MazegakiGenerator.Output] {
        let surface = Array(input.toKatakana())
        var generator = MazegakiGenerator(
            surface: surface,
            range: .init(leftIndex: left, rightIndexRange: right ?? left ..< surface.count),
            table: table
        )
        var result: [MazegakiGenerator.Output] = []
        while let output = generator.next() {
            result.append(output)
        }
        return result
    }

    func testExpandsKanjiAndKeepsKana() {
        let t = table("破\tハ,ヤブ.ル\n")
        let result = outputs("破たん", t)
        // 読みの順: ハ、ヤブ（語幹）→ バ、パ（連濁）→ ヤブリ（連用形）。それぞれに タ、タン を続ける
        XCTAssertEqual(result.map { String($0.characters) }, [
            "ハ", "ハタ", "ハタン", "ヤブ", "ヤブタ", "ヤブタン", "バ", "バタ", "バタン",
            "パ", "パタ", "パタン", "ヤブリ", "ヤブリタ", "ヤブリタン",
        ])
        XCTAssertEqual(result.map(\.endIndex), Array(repeating: [0, 1, 2], count: 5).flatMap { $0 })
        XCTAssertEqual(result[2].constraints, [MazegakiConstraint(kanji: "破", rubyRange: 0 ..< 1)])
        XCTAssertEqual(result[5].constraints, [MazegakiConstraint(kanji: "破", rubyRange: 0 ..< 2)])
        // 語幹は 0、連濁と連用形はそれより大きい
        XCTAssertEqual(result[2].penalty, 0)
        XCTAssertGreaterThan(result[8].penalty, result[5].penalty)
        XCTAssertGreaterThan(result[14].penalty, result[8].penalty)
    }

    func testNoOutputBeforeFirstKanji() {
        let t = table("損\tソン\n")
        let result = outputs("き損", t)
        // 「キ」だけ（漢字を含まない範囲）は返さない
        XCTAssertEqual(result.map { String($0.characters) }, ["キソン", "キゾン"])
        XCTAssertEqual(result[0].constraints, [MazegakiConstraint(kanji: "損", rubyRange: 1 ..< 3)])
    }

    func testNoOutputWithoutKanji() {
        let t = table("破\tハ\n")
        var generator = MazegakiGenerator(surface: Array("ハタン"), range: .init(leftIndex: 0, rightIndexRange: 0 ..< 3), table: t)
        XCTAssertFalse(generator.hasExpandableKanji)
        XCTAssertNil(generator.next())
    }

    func testStopsAtKanjiNotInTable() {
        let t = table("破\tハ\n")
        // 綻 は読み表にないので、その先は作らない
        XCTAssertEqual(outputs("破綻す", t).map { String($0.characters) }, ["ハ", "バ", "パ"])
    }

    func testRightIndexRangeLimitsOutputsButNotTraversal() {
        let t = table("破\tハ,ヤブ\n")
        // 差分更新: 終わりの位置が 2 のものだけを返す
        let result = outputs("破たん", t, right: 2 ..< 3)
        XCTAssertEqual(result.map { String($0.characters) }, ["ハタン", "ヤブタン", "バタン", "パタン"])
    }

    func testLeftIndex() {
        let t = table("損\tソン\n")
        XCTAssertEqual(outputs("毀き損", t, left: 1).map { String($0.characters) }, ["キソン", "キゾン"])
    }

    func testCollidingStringsKeepSeparateConstraints() {
        // 日（ニチ、終わり 0）と 日ち（ニ + チ、終わり 1）がどちらも「ニチ」になる
        let t = table("日\tニチ,ニ\n")
        let result = outputs("日ち", t).filter { String($0.characters) == "ニチ" }
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(Set(result.map(\.endIndex)), [0, 1])
        // 読みの切り方が違うもの: ア + カサ と アカ + サ
        let t2 = table("亜\tア,アカ\n傘\tカサ,サ\n")
        let result2 = outputs("亜傘", t2).filter { String($0.characters) == "アカサ" }
        XCTAssertEqual(result2.count, 2)
        XCTAssertEqual(Set(result2.map { $0.constraints.map(\.rubyRange) }), [[0 ..< 1, 1 ..< 3], [0 ..< 2, 2 ..< 3]])
    }

    func testUnreachablePathPrunesSubtree() {
        let t = table("破\tハ,ヤブ\n")
        let surface = Array("破たんする".toKatakana())
        var generator = MazegakiGenerator(surface: surface, range: .init(leftIndex: 0, rightIndexRange: 0 ..< surface.count), table: t)
        var emitted: [String] = []
        while let output = generator.next() {
            let s = String(output.characters)
            emitted.append(s)
            // 「ヤブ」で始まる語は辞書にないことにする（長さ 2 の接頭辞がたどれない）
            if s.hasPrefix("ヤブ") {
                generator.setUnreachablePath(prefixLength: 2)
            }
        }
        XCTAssertEqual(Array(emitted.prefix(7)), ["ハ", "ハタ", "ハタン", "ハタンス", "ハタンスル", "ヤブ", "バ"])
        XCTAssertEqual(emitted.filter { $0.hasPrefix("ヤブ") }, ["ヤブ"])
        XCTAssertTrue(emitted.contains("パタンスル"))
    }

    func testUnreachablePathPrunesSiblingsSharingPrefix() {
        // 2 字目の読みの選び方によらず「ハタ」で始まる文字列は、まとめて刈る
        let t = table("破\tハ\n多\tタ,タン\n")
        let surface = Array("破多い".toKatakana())
        var generator = MazegakiGenerator(surface: surface, range: .init(leftIndex: 0, rightIndexRange: 0 ..< surface.count), table: t)
        var emitted: [String] = []
        while let output = generator.next() {
            let s = String(output.characters)
            emitted.append(s)
            if s == "ハタ" {
                generator.setUnreachablePath(prefixLength: 2)
            }
        }
        // 「ハタ」の後、同じ段の兄弟「タン」（ハタン…）も飛ばし、連濁の「ダ」へ進む
        XCTAssertEqual(Array(emitted.prefix(3)), ["ハ", "ハタ", "ハダ"])
        XCTAssertEqual(emitted.filter { $0.hasPrefix("ハタ") }, ["ハタ"])
    }
}
