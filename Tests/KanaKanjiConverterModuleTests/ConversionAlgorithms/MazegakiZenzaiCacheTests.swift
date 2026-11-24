@testable import KanaKanjiConverterModule
import XCTest

/// E9: Zenzai の制約の計算で、交ぜ書きの候補（ruby が入力の読み）を入力の位置に対応づける
final class MazegakiZenzaiCacheTests: XCTestCase {
    private let table = MazegakiReadingTable(parsing: "破\tハ,ヤブ.ル\n取\tシュ,ト.ル\n引\tイン,ヒ.ク\n", maxReadingsPerKanji: 8)

    private func composingText(_ s: String) -> ComposingText {
        var t = ComposingText()
        t.insertAtCursorPosition(s, inputStyle: .direct)
        return t
    }

    private func candidate(_ items: [(String, String)]) -> Candidate {
        Candidate(
            text: items.map(\.0).joined(),
            value: -10,
            composingCount: .surfaceCount(items.map(\.1.count).reduce(0, +)),
            lastMid: MIDData.一般.mid,
            data: items.map { DicdataElement(word: $0.0, ruby: $0.1, cid: CIDData.一般名詞.cid, mid: MIDData.一般.mid, value: -10) }
        )
    }

    func testReplaceableConstraintFollowsMazegakiCandidate() {
        // 「破たん」を「破綻」(ハタン) と変換した後に「し」を足した
        let cache = Kana2Kanji.ZenzaiCache(
            self.composingText("破たん"),
            constraint: .init([]),
            satisfyingCandidate: self.candidate([("破綻", "ハタン")])
        )
        let constraint = cache.getNewConstraint(for: self.composingText("破たんし"), mazegakiTable: self.table)
        XCTAssertEqual(constraint.constraint, Array("破綻".utf8))
    }

    func testReplaceableConstraintWithSeveralWords() {
        // 取ひき + を → 取引(トリヒキ) を(ヲ)。取 = トリ、引 = ヒ
        let cache = Kana2Kanji.ZenzaiCache(
            self.composingText("取ひきを"),
            constraint: .init([]),
            satisfyingCandidate: self.candidate([("取引", "トリヒキ"), ("を", "ヲ")])
        )
        let constraint = cache.getNewConstraint(for: self.composingText("取ひきをし"), mazegakiTable: self.table)
        XCTAssertEqual(constraint.constraint, Array("取引を".utf8))
    }

    func testPrefixCandidateRemainsForMazegakiInput() {
        let prefix = self.candidate([("破綻", "ハタン")])
        let cache = Kana2Kanji.ZenzaiCache(
            self.composingText("破たん"),
            constraint: .init([]),
            satisfyingCandidate: prefix,
            prefixCandidate: prefix
        )
        let newInput = self.composingText("破たんし")
        XCTAssertNotNil(cache.prefixCandidate(remainingIn: newInput, mazegakiTable: self.table))
        let constraint = cache.getNewConstraint(for: newInput, mazegakiTable: self.table)
        // 固定部分の長さは、入力の先頭のうち、その表記が覆う文字数（破たん = 3）
        XCTAssertEqual(constraint.fixedPrefix, .init(byteCount: Array("破綻".utf8).count, rubyCount: 3))
    }

    func testWithoutMazegakiTableBehavesAsBefore() {
        // かなの入力では従来どおり ruby の一致で対応づける
        let cache = Kana2Kanji.ZenzaiCache(
            self.composingText("はたん"),
            constraint: .init([]),
            satisfyingCandidate: self.candidate([("破綻", "ハタン")])
        )
        XCTAssertEqual(cache.getNewConstraint(for: self.composingText("はたんし")).constraint, Array("破綻".utf8))
        // 読み表がなければ、入力漢字を読みとして扱わない
        let mazegakiCache = Kana2Kanji.ZenzaiCache(
            self.composingText("破たん"),
            constraint: .init([]),
            satisfyingCandidate: self.candidate([("破綻", "ハタン")])
        )
        XCTAssertEqual(mazegakiCache.getNewConstraint(for: self.composingText("破たんし")).constraint, [])
    }

    func testCarriedConstraintIsDroppedWhenInputKanjiChange() {
        // 「ひ」を「日」と変換した後に入力漢字「告」を足した。かなに対して認めた「日」を引き継ぐと「日告」に縛られる
        let table = MazegakiReadingTable(parsing: "告\tコク\n", maxReadingsPerKanji: 8)
        let cache = Kana2Kanji.ZenzaiCache(
            self.composingText("ひ"),
            constraint: .init(Array("日".utf8)),
            satisfyingCandidate: self.candidate([("日", "ヒ")])
        )
        XCTAssertEqual(cache.getNewConstraint(for: self.composingText("ひ告"), mazegakiTable: table).constraint, [])
        // 入力漢字を消した場合も引き継がない
        let kanjiCache = Kana2Kanji.ZenzaiCache(
            self.composingText("取破"),
            constraint: .init(Array("取破".utf8)),
            satisfyingCandidate: self.candidate([("取", "ト"), ("破", "ハ")])
        )
        XCTAssertEqual(kanjiCache.getNewConstraint(for: self.composingText("取"), mazegakiTable: self.table).constraint, [])
    }

    func testFallbackConstraintKeepsOnlyFixedPrefix() {
        // 引き継いだ制約は外し、利用者が確定した固定部分だけを残す
        XCTAssertEqual(Kana2Kanji.mazegakiFallbackConstraint(from: .init(Array("半".utf8))), .init([]))
        let fixed = Array("破綻".utf8)
        let fixedPrefix = Kana2Kanji.PrefixConstraint.FixedPrefix(byteCount: fixed.count, rubyCount: 3)
        let constraint = Kana2Kanji.PrefixConstraint(Array("破綻を".utf8), fixedPrefix: fixedPrefix)
        XCTAssertEqual(Kana2Kanji.mazegakiFallbackConstraint(from: constraint), .init(fixed, fixedPrefix: fixedPrefix))
    }

    // MARK: - 案B: モデルに渡す入力

    func testEvaluationInputIsCandidateRubyForMazegakiInput() {
        let result = Kana2Kanji.zenzaiEvaluationInput(
            candidate: self.candidate([("破綻", "ハタン")]),
            inputData: self.composingText("破たん"),
            cursorPosition: nil,
            constraint: .init([]),
            mazegakiTable: self.table
        )
        XCTAssertEqual(result.input, "ハタン")
    }

    func testEvaluationInputConvertsFixedPrefixToRubyCount() {
        // 取ひき（表層 3 文字）= 取引（ruby 4 文字）
        let fixed = Array("取引".utf8)
        let constraint = Kana2Kanji.PrefixConstraint(fixed, fixedPrefix: .init(byteCount: fixed.count, rubyCount: 3))
        let result = Kana2Kanji.zenzaiEvaluationInput(
            candidate: self.candidate([("取引", "トリヒキ"), ("を", "ヲ")]),
            inputData: self.composingText("取ひきを"),
            cursorPosition: nil,
            constraint: constraint,
            mazegakiTable: self.table
        )
        XCTAssertEqual(result.input, "トリヒキヲ")
        XCTAssertEqual(result.constraint.fixedPrefix, .init(byteCount: fixed.count, rubyCount: 4))
        XCTAssertEqual(result.constraint.constraint, fixed)
    }

    func testEvaluationInputIsUnchangedWithoutMazegaki() {
        let constraint = Kana2Kanji.PrefixConstraint([])
        for (input, table) in [("はたん", self.table), ("破たん", nil)] as [(String, MazegakiReadingTable?)] {
            let result = Kana2Kanji.zenzaiEvaluationInput(
                candidate: self.candidate([("破綻", "ハタン")]),
                inputData: self.composingText(input),
                cursorPosition: nil,
                constraint: constraint,
                mazegakiTable: table
            )
            XCTAssertEqual(result.input, input)
        }
        // カーソルが途中にある場合も従来どおり
        let result = Kana2Kanji.zenzaiEvaluationInput(
            candidate: self.candidate([("破綻", "ハタン")]),
            inputData: self.composingText("破たん"),
            cursorPosition: 1,
            constraint: constraint,
            mazegakiTable: self.table
        )
        XCTAssertEqual(result.input, "破たん")
    }
}
