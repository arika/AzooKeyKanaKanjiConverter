@testable import KanaKanjiConverterModule
import Foundation
import XCTest

final class MazegakiReadingTableTests: XCTestCase {
    /// テスト用の小さな読み表（自作）
    private static let sampleTable = """
    # テスト用の読み表
    学\tガク,マナ.ブ
    社\tシャ,ヤシロ
    通\tツウ,ツ,トオ.ル,カヨ.ウ
    切\tセツ,サイ,キ.ル,キ.レル
    落\tラク,オ.チル,オ.トス
    取\tシュ,ト.ル
    発\tハツ,ホツ
    高\tコウ,タカ.イ
    損\tソン,そこ.なう
    上\tジョウ,-あ.げる,ウエ

    # 不正な行は無視する
    破損\tハソン
    綻
    毀\tキ,abc,コワ.ス
    """

    private func makeTable(maxReadingsPerKanji: Int = 8) -> MazegakiReadingTable {
        MazegakiReadingTable(parsing: Self.sampleTable, maxReadingsPerKanji: maxReadingsPerKanji)
    }

    private func rubies(_ kanji: Character, in table: MazegakiReadingTable) -> [String] {
        table.readings(of: kanji).map(\.ruby)
    }

    private func kind(_ ruby: String, of kanji: Character, in table: MazegakiReadingTable) -> MazegakiReading.Kind? {
        table.readings(of: kanji).first { $0.ruby == ruby }?.kind
    }

    // MARK: - 読み込み

    func testParseSkipsCommentsAndInvalidLines() {
        let table = makeTable()
        // 学 社 通 切 落 取 発 高 損 上 毀 の 11 字。「破損」（2 字の見出し）と「綻」（読みの列がない）は無視する
        XCTAssertEqual(table.count, 11)
        XCTAssertTrue(table.readings(of: "破").isEmpty)
        XCTAssertTrue(table.readings(of: "綻").isEmpty)
    }

    func testKanjiNotInTableIsNotExpanded() {
        let table = makeTable()
        XCTAssertEqual(table.readings(of: "綻"), [])
        XCTAssertEqual(table.readings(of: "あ"), [])
        XCTAssertEqual(table.readings(of: "A"), [])
    }

    func testInvalidReadingIsSkipped() {
        let table = makeTable()
        XCTAssertEqual(rubies("毀", in: table).filter { $0.contains("a") }, [])
        XCTAssertTrue(rubies("毀", in: table).contains("キ"))
        XCTAssertTrue(rubies("毀", in: table).contains("コワ"))
    }

    func testHiraganaAndHyphenAreNormalized() {
        let table = makeTable()
        // そこ.なう → ソコ（語幹）、ソコナイ（連用形）
        XCTAssertEqual(kind("ソコ", of: "損", in: table), .stem)
        XCTAssertEqual(kind("ソコナイ", of: "損", in: table), .conjunctive)
        // -あ.げる → ア（語幹）、アゲ（一段の連用形）
        XCTAssertEqual(kind("ア", of: "上", in: table), .stem)
        XCTAssertEqual(kind("アゲ", of: "上", in: table), .conjunctive)
    }

    func testDuplicateLinesAreMerged() {
        let table = MazegakiReadingTable(parsing: "学\tガク\n学\tマナ.ブ,ガク\n", maxReadingsPerKanji: 8)
        XCTAssertEqual(table.readings(of: "学").filter { $0.kind == .stem }.map(\.ruby), ["ガク", "マナ"])
    }

    func testLoadFromURL() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mazegaki-\(UUID().uuidString).tsv")
        try Self.sampleTable.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let table = try MazegakiReadingTable(contentsOf: url, maxReadingsPerKanji: 8)
        XCTAssertEqual(table.count, 11)
        XCTAssertEqual(rubies("社", in: table).first, "シャ")
    }

    func testLoadFromMissingURLThrows() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mazegaki-missing-\(UUID().uuidString).tsv")
        XCTAssertThrowsError(try MazegakiReadingTable(contentsOf: url, maxReadingsPerKanji: 8))
    }

    // MARK: - 派生

    func testStemsKeepTableOrder() {
        let table = makeTable()
        XCTAssertEqual(table.readings(of: "通").filter { $0.kind == .stem }.map(\.ruby), ["ツウ", "ツ", "トオ", "カヨ"])
        XCTAssertEqual(Array(rubies("通", in: table).prefix(4)), ["ツウ", "ツ", "トオ", "カヨ"])
    }

    func testSokuon() {
        let table = makeTable()
        XCTAssertEqual(kind("ガッ", of: "学", in: table), .sokuon)
        XCTAssertEqual(kind("ハッ", of: "発", in: table), .sokuon)
        XCTAssertEqual(kind("ラッ", of: "落", in: table), .sokuon)
        // 1 字の読み（ツ）は促音化しない
        XCTAssertNil(kind("ッ", of: "通", in: table))
        // 末尾がキクチツ以外は促音化しない
        XCTAssertNil(kind("シッ", of: "社", in: table))
    }

    func testRendaku() {
        let table = makeTable()
        XCTAssertEqual(kind("ジャ", of: "社", in: table), .rendaku)
        XCTAssertEqual(kind("バツ", of: "発", in: table), .rendaku)
        XCTAssertEqual(kind("パツ", of: "発", in: table), .rendaku)
        XCTAssertEqual(kind("ダカ", of: "高", in: table), .rendaku)
        // 清音で始まらない読み（ガク、マナ）は連濁しない
        XCTAssertEqual(table.readings(of: "学").filter { $0.kind == .rendaku }, [])
    }

    func testConjunctiveGodan() {
        let table = makeTable()
        XCTAssertEqual(kind("トオリ", of: "通", in: table), .conjunctive)
        XCTAssertEqual(kind("カヨイ", of: "通", in: table), .conjunctive)
        XCTAssertEqual(kind("キリ", of: "切", in: table), .conjunctive)
        XCTAssertEqual(kind("トリ", of: "取", in: table), .conjunctive)
        XCTAssertEqual(kind("マナビ", of: "学", in: table), .conjunctive)
        XCTAssertEqual(kind("オトシ", of: "落", in: table), .conjunctive)
    }

    func testConjunctiveIchidan() {
        let table = makeTable()
        XCTAssertEqual(kind("オチ", of: "落", in: table), .conjunctive)
        XCTAssertEqual(kind("キレ", of: "切", in: table), .conjunctive)
        // 一段の可能性がある「キ.ル」の連用形「キ」は語幹と同じなので、語幹として残る
        XCTAssertEqual(kind("キ", of: "切", in: table), .stem)
        // 一段の連用形にリを付けた形は作らない
        XCTAssertNil(kind("オチリ", of: "落", in: table))
    }

    func testNoConjunctiveForAdjectiveOrNoOkurigana() {
        let table = makeTable()
        // 形容詞（タカ.イ）は連用形を作らない
        XCTAssertEqual(table.readings(of: "高").filter { $0.kind == .conjunctive }, [])
        // 送り仮名のない読みからは作らない
        XCTAssertEqual(table.readings(of: "発").filter { $0.kind == .conjunctive || $0.kind == .conjunctiveRendaku }, [])
    }

    func testConjunctiveRendaku() {
        let table = makeTable()
        XCTAssertEqual(kind("ドオリ", of: "通", in: table), .conjunctiveRendaku)
        XCTAssertEqual(kind("ギリ", of: "切", in: table), .conjunctiveRendaku)
        XCTAssertEqual(kind("ドリ", of: "取", in: table), .conjunctiveRendaku)
    }

    func testOrderAndPenalty() {
        let table = makeTable()
        let readings = table.readings(of: "通")
        // ペナルティの小さい順
        XCTAssertEqual(readings.map(\.penalty), readings.map(\.penalty).sorted())
        // 由来ごとのペナルティ: 語幹 < 促音化・連濁 < 連用形 < 連用形の連濁
        XCTAssertLessThan(MazegakiReading.Kind.stem.penalty, MazegakiReading.Kind.sokuon.penalty)
        XCTAssertLessThan(MazegakiReading.Kind.stem.penalty, MazegakiReading.Kind.rendaku.penalty)
        XCTAssertLessThan(MazegakiReading.Kind.rendaku.penalty, MazegakiReading.Kind.conjunctive.penalty)
        XCTAssertLessThan(MazegakiReading.Kind.conjunctive.penalty, MazegakiReading.Kind.conjunctiveRendaku.penalty)
        // 同じペナルティでは促音化が連濁より先。その中では表の順
        XCTAssertEqual(rubies("発", in: table), ["ハツ", "ホツ", "ハッ", "ホッ", "バツ", "パツ", "ボツ", "ポツ"])
    }

    func testNoDuplicateRubies() {
        let table = makeTable()
        for kanji in "学社通切落取発高損上毀" {
            let rubies = rubies(kanji, in: table)
            XCTAssertEqual(rubies.count, Set(rubies).count, "\(kanji): \(rubies)")
        }
    }

    // MARK: - 上限

    func testMaxReadingsPerKanjiLimitsTableReadings() {
        let table = makeTable(maxReadingsPerKanji: 2)
        let readings = table.readings(of: "通")
        // 表の先頭 2 つ（ツウ、ツ）だけを使い、そこから派生させる
        XCTAssertEqual(readings.filter { $0.kind == .stem }.map(\.ruby), ["ツウ", "ツ"])
        XCTAssertFalse(readings.contains { $0.ruby.hasPrefix("トオ") || $0.ruby.hasPrefix("ドオ") })
        // 派生形は上限に含めない
        XCTAssertTrue(readings.contains { $0.ruby == "ヅウ" && $0.kind == .rendaku })
    }

    func testMaxReadingsPerKanjiCountsDistinctReadings() {
        // 重複と不正な読みは上限に数えない
        let table = MazegakiReadingTable(parsing: "学\tガク,ガク,abc,マナ.ブ\n", maxReadingsPerKanji: 2)
        XCTAssertEqual(table.readings(of: "学").filter { $0.kind == .stem }.map(\.ruby), ["ガク", "マナ"])
    }

    func testZeroMaxReadingsDisablesExpansion() {
        let table = makeTable(maxReadingsPerKanji: 0)
        XCTAssertEqual(table.count, 0)
        XCTAssertEqual(table.readings(of: "学"), [])
        XCTAssertEqual(MazegakiReadingTable(parsing: Self.sampleTable, maxReadingsPerKanji: -1).count, 0)
    }

    // MARK: - MazegakiMode とキャッシュ

    func testMazegakiModeDefaultIsOff() {
        let options = ConvertRequestOptions(
            requireJapanesePrediction: .autoMix,
            requireEnglishPrediction: .disabled,
            keyboardLanguage: .ja_JP,
            learningType: .nothing,
            memoryDirectoryURL: URL(fileURLWithPath: ""),
            sharedContainerURL: URL(fileURLWithPath: ""),
            textReplacer: .empty,
            specialCandidateProviders: nil,
            metadata: nil
        )
        XCTAssertEqual(options.mazegakiMode, .off)
        XCTAssertFalse(options.mazegakiMode.enabled)
        XCTAssertFalse(ConvertRequestOptions.default.mazegakiMode.enabled)
    }

    func testMazegakiModeOn() {
        let url = URL(fileURLWithPath: "/tmp/readings.tsv")
        let mode = ConvertRequestOptions.MazegakiMode.on(readingTableURL: url)
        XCTAssertTrue(mode.enabled)
        XCTAssertEqual(mode.readingTableURL, url)
        XCTAssertEqual(mode.maxReadingsPerKanji, 8)
        XCTAssertEqual(ConvertRequestOptions.MazegakiMode.on(readingTableURL: url, maxReadingsPerKanji: -3).maxReadingsPerKanji, 0)
        XCTAssertNotEqual(mode, .off)
        XCTAssertNotEqual(mode, .on(readingTableURL: url, maxReadingsPerKanji: 4))
    }

    func testCacheReturnsNilWhenOff() {
        let cache = MazegakiReadingTableCache()
        XCTAssertNil(cache.table(for: .off))
    }

    func testCacheLoadsOnceAndReloadsWhenModeChanges() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mazegaki-\(UUID().uuidString).tsv")
        try Self.sampleTable.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let cache = MazegakiReadingTableCache()
        let mode = ConvertRequestOptions.MazegakiMode.on(readingTableURL: url)
        XCTAssertEqual(cache.table(for: mode)?.count, 11)

        // 同じ設定では読み込み直さない（ファイルを書き換えても結果は変わらない）
        try "学\tガク\n".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(cache.table(for: mode)?.count, 11)

        // 設定が変わったら読み込み直す
        XCTAssertEqual(cache.table(for: .on(readingTableURL: url, maxReadingsPerKanji: 4))?.count, 1)
        // 無効にしたら nil
        XCTAssertNil(cache.table(for: .off))
    }

    func testCacheReturnsNilForMissingFile() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mazegaki-missing-\(UUID().uuidString).tsv")
        let cache = MazegakiReadingTableCache()
        XCTAssertNil(cache.table(for: .on(readingTableURL: url)))
        XCTAssertNil(cache.table(for: .on(readingTableURL: url)))
    }
}
