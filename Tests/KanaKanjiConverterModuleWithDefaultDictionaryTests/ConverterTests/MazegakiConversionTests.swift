import Foundation
@testable import KanaKanjiConverterModuleWithDefaultDictionary
import XCTest

/// 交ぜ書き変換（`ConvertRequestOptions.MazegakiMode`）のテスト
final class MazegakiConversionTests: XCTestCase {
    /// テスト用の小さな読み表（自作）。テストに出てくる字だけを入れる
    private static let readingTable = """
    # テスト用の読み表
    破\tハ,ヤブ.ル,ヤブ.レル
    損\tソン,ソコ.ナウ
    機\tキ,ハタ
    帰\tキ,カエ.ル
    四\tシ,ヨ,ヨン,ヨッ.ツ
    面\tメン,ベン,オモ,ツラ
    歌\tカ,ウタ,ウタ.ウ
    取\tシュ,ト.ル
    引\tイン,ヒ.ク
    桜\tオウ,サクラ
    真\tシン,マ,マコト
    高\tコウ,タカ.イ
    彼\tヒ,カレ,カノ
    判\tハン,バン
    断\tダン,タ.ツ,コトワ.ル
    意\tイ
    的\tテキ,マト
    計\tケイ,ハカ.ル
    画\tガ,カク
    社\tシャ,ヤシロ
    本\tホン,モト
    走\tソウ,ハシ.ル
    見\tケン,ミ.ル
    棚\tホウ,タナ
    """

    private var tableURL: URL!

    override func setUpWithError() throws {
        self.tableURL = FileManager.default.temporaryDirectory.appendingPathComponent("mazegaki-test-\(UUID().uuidString).tsv")
        try Self.readingTable.write(to: self.tableURL, atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: self.tableURL)
    }

    private func requestOptions(mazegakiMode: ConvertRequestOptions.MazegakiMode) -> ConvertRequestOptions {
        ConvertRequestOptions(
            N_best: 10,
            requireJapanesePrediction: .disabled,
            requireEnglishPrediction: .disabled,
            keyboardLanguage: .ja_JP,
            learningType: .nothing,
            memoryDirectoryURL: URL(fileURLWithPath: ""),
            sharedContainerURL: URL(fileURLWithPath: ""),
            textReplacer: .empty,
            specialCandidateProviders: [],
            typoCorrectionMode: .disabled,
            mazegakiMode: mazegakiMode,
            metadata: nil
        )
    }

    private var on: ConvertRequestOptions.MazegakiMode {
        .on(readingTableURL: self.tableURL)
    }

    private func convert(_ input: String, mode: ConvertRequestOptions.MazegakiMode, converter: KanaKanjiConverter? = nil) -> (text: ComposingText, result: ConversionResult) {
        let converter = converter ?? KanaKanjiConverter.withDefaultDictionary()
        var composingText = ComposingText()
        composingText.insertAtCursorPosition(input, inputStyle: .direct)
        return (composingText, converter.requestCandidates(composingText, options: self.requestOptions(mazegakiMode: mode)))
    }

    private func texts(_ input: String, mode: ConvertRequestOptions.MazegakiMode) -> [String] {
        self.convert(input, mode: mode).result.mainResults.map(\.text)
    }

    /// 候補が覆う入力の範囲（`.direct`で入れたので、入力の要素数と表層の文字数は等しい）
    private func coveredCount(_ count: ComposingCount) -> Int {
        switch count {
        case .inputCount(let n), .surfaceCount(let n): n
        case .composite(let l, let r): coveredCount(l) + coveredCount(r)
        }
    }

    private func isKanji(_ c: Character) -> Bool {
        c.unicodeScalars.first?.properties.isIdeographic ?? false
    }

    /// 候補の文字列に、覆う範囲の入力漢字が同じ順序で（正準等価な字として）残っているか
    private func keepsInputKanji(_ candidate: Candidate, input: String) -> Bool {
        let kanji = input.prefix(self.coveredCount(candidate.composingCount)).filter(self.isKanji)
        var rest = candidate.text[...]
        for k in kanji {
            guard let index = rest.firstIndex(of: k) else {
                return false
            }
            rest = rest[rest.index(after: index)...]
        }
        return true
    }

    // MARK: - 変換

    func testMazegakiProducesExpectedWords() {
        for (input, expected) in [
            ("破たん", "破綻"),
            ("き損", "毀損"),
            ("四面そ歌", "四面楚歌"),
            ("取ひき", "取引"),
            ("帰のう", "帰納"),
        ] {
            XCTAssertTrue(self.texts(input, mode: self.on).contains(expected), "\(input) → \(expected)")
        }
    }

    func testOffDoesNotExpand() {
        XCTAssertFalse(self.texts("破たん", mode: .off).contains("破綻"))
        XCTAssertFalse(self.texts("き損", mode: .off).contains("毀損"))
    }

    func testInputKanjiConstrainsCandidates() {
        let kinou = self.texts("機のう", mode: self.on)
        XCTAssertTrue(kinou.contains("機能"))
        XCTAssertFalse(kinou.contains("帰納"))
        XCTAssertFalse(kinou.contains("昨日"))
        XCTAssertTrue(self.texts("帰のう", mode: self.on).contains("帰納"))
    }

    // MARK: - 不変条件

    func testInputKanjiIsNeverLost() {
        for input in [
            "破たん", "き損", "四面そ歌", "取ひき", "機のう", "帰のう",
            "桜づけ", "真だ", "高みつ度", "彼の判断はし意的だ", "計画が破たんしかけている",
        ] {
            let (_, result) = self.convert(input, mode: self.on)
            for candidate in result.mainResults + result.firstClauseResults {
                XCTAssertTrue(self.keepsInputKanji(candidate, input: input), "\(input): \(candidate.text)")
            }
        }
    }

    func testVariantCharactersAreNotProduced() {
        // 素通しでは異体字（桜→櫻）の候補が出ることがあるが、交ぜ書きモードでは出さない
        XCTAssertFalse(self.texts("桜づけ", mode: self.on).contains { $0.contains("櫻") })
    }

    func testCorrectlyTypedInputStaysFirst() {
        // 正しく打ち終えた交ぜ書きの文字列は、そのまま 1 位に残る（入力と同じ文字列の候補を下げない）
        for input in ["取り引き", "彼は走った", "見る"] {
            XCTAssertEqual(self.texts(input, mode: self.on).first, input)
        }
    }

    func testAbsorbingWordIsPreferredOverPassThrough() {
        // かなと入力漢字をまとめて読む語が、素通しの組み合わせ（四面 + ソ + 歌 など）より上に来る
        XCTAssertEqual(self.texts("破たん", mode: self.on).first, "破綻")
        XCTAssertEqual(self.texts("四面そ歌", mode: self.on).first, "四面楚歌")
        XCTAssertEqual(self.texts("取ひき", mode: self.on).first, "取引")
    }

    func testDuplicateTextKeepsBetterReading() {
        // 貴社 は 貴社/キシャ と 貴/キ + 社/ヤシロ の 2 つの経路で出る。ruby の長さではなく値で選ぶ
        XCTAssertTrue(self.texts("き社", mode: self.on).prefix(5).contains("貴社"))
    }

    func testKanjiOnlyInputStaysFirst() {
        // 入力が漢字だけで、正解が入力と同じ文字列の場合
        XCTAssertEqual(self.texts("本棚", mode: self.on).first, "本棚")
    }

    // MARK: - 同一性

    func testSameResultsWithoutKanji() {
        for input in ["はたん", "きのう", "かんじ", "きょうはいいてんきですね", "へんかん"] {
            XCTAssertEqual(self.texts(input, mode: self.on), self.texts(input, mode: .off), input)
        }
    }

    func testMissingTableBehavesAsOff() {
        let missing = ConvertRequestOptions.MazegakiMode.on(readingTableURL: self.tableURL.appendingPathExtension("missing"))
        XCTAssertEqual(self.texts("破たん", mode: missing), self.texts("破たん", mode: .off))
    }

    func testModeChangeIsReflected() {
        // 同じコンバータで設定を切り替えても、前の設定のラティスが残らない
        let converter = KanaKanjiConverter.withDefaultDictionary()
        XCTAssertFalse(self.convert("破たん", mode: .off, converter: converter).result.mainResults.contains { $0.text == "破綻" })
        XCTAssertTrue(self.convert("破たん", mode: self.on, converter: converter).result.mainResults.contains { $0.text == "破綻" })
        XCTAssertFalse(self.convert("破たん", mode: .off, converter: converter).result.mainResults.contains { $0.text == "破綻" })
    }
}
