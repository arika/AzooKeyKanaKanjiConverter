import Foundation
@testable import KanaKanjiConverterModuleWithDefaultDictionary
import XCTest

/// Step 3: 交ぜ書きの候補では ruby と convertTarget が一致しない。その前提に依存していた処理のテスト
final class MazegakiRubyTests: XCTestCase {
    private static let readingTable = """
    破\tハ
    損\tソン,ソコ.ナウ
    毀\tキ,コワ.ス
    取\tシュ,ト.ル
    引\tイン,ヒ.ク
    牽\tケン,ヒ.ク
    改\tカイ,アラタ.メル
    竄\tザン,ソン
    """

    private var tableURL: URL!

    override func setUpWithError() throws {
        self.tableURL = FileManager.default.temporaryDirectory.appendingPathComponent("mazegaki-ruby-test-\(UUID().uuidString).tsv")
        try Self.readingTable.write(to: self.tableURL, atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: self.tableURL)
    }

    private func options(
        mazegaki: Bool = true,
        prediction: ConvertRequestOptions.PredictionMode = .disabled,
        typoCorrection: ConvertRequestOptions.TypoCorrectionMode = .disabled
    ) -> ConvertRequestOptions {
        ConvertRequestOptions(
            N_best: 10,
            requireJapanesePrediction: prediction,
            requireEnglishPrediction: .disabled,
            keyboardLanguage: .ja_JP,
            learningType: .nothing,
            memoryDirectoryURL: URL(fileURLWithPath: ""),
            sharedContainerURL: URL(fileURLWithPath: ""),
            textReplacer: .empty,
            specialCandidateProviders: [],
            typoCorrectionMode: typoCorrection,
            mazegakiMode: mazegaki ? .on(readingTableURL: self.tableURL) : .off,
            metadata: nil
        )
    }

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
            lastMid: 0,
            data: items.map { DicdataElement(word: $0.0, ruby: $0.1, cid: 0, mid: 0, value: -10) }
        )
    }

    // MARK: - E7: 完全一致の判定

    func testExactMatchAcceptsMazegakiReading() {
        let converter = KanaKanjiConverter.withDefaultDictionary()
        _ = converter.requestCandidates(self.composingText("破たん"), options: self.options())
        // 破 = ハ と読めば「破たん」に完全一致する
        XCTAssertTrue(converter.isExactMatchCandidate(self.candidate([("破綻", "ハタン")]), convertTarget: "破たん"))
        XCTAssertTrue(converter.isExactMatchCandidate(self.candidate([("取引", "トリヒキ")]), convertTarget: "取ひき"))
        // 素通しの候補も完全一致
        XCTAssertTrue(converter.isExactMatchCandidate(self.candidate([("破", "破"), ("単", "タン")]), convertTarget: "破たん"))
        // かなの部分が違う（誤り訂正の結果など）なら完全一致ではない
        XCTAssertFalse(converter.isExactMatchCandidate(self.candidate([("破談", "ハダン")]), convertTarget: "破たん"))
        // 読み表にない読みなら完全一致ではない
        XCTAssertFalse(converter.isExactMatchCandidate(self.candidate([("刃綻", "ジンタン")]), convertTarget: "破たん"))
    }

    func testExactMatchWithoutMazegakiIsUnchanged() {
        let converter = KanaKanjiConverter.withDefaultDictionary()
        _ = converter.requestCandidates(self.composingText("破たん"), options: self.options(mazegaki: false))
        XCTAssertFalse(converter.isExactMatchCandidate(self.candidate([("破綻", "ハタン")]), convertTarget: "破たん"))
        XCTAssertTrue(converter.isExactMatchCandidate(self.candidate([("破綻", "ハタン")]), convertTarget: "はたん"))
    }

    func testExactMatchCandidateIsNotForcedIntoTopThree() {
        // 交ぜ書きの候補が完全一致と判定されないと、上位 3 件に完全一致の候補がないとみなされ、
        // 値の低い素通しの候補（県引 = ケン + 引、改Theン）が 3 番目に割り込む
        for (input, passThrough) in [("けん引", "県引"), ("改ざん", "改Theン")] {
            let result = KanaKanjiConverter.withDefaultDictionary()
                .requestCandidates(self.composingText(input), options: self.options())
            let top3 = Array(result.mainResults.prefix(3))
            XCTAssertFalse(top3.contains { $0.text == passThrough }, "\(input): \(top3.map(\.text))")
            // 上位 3 件は値の順に並ぶ（割り込みがない）
            XCTAssertEqual(top3.map(\.value), top3.map(\.value).sorted(by: >), "\(input): \(top3.map(\.text))")
        }
    }

    // MARK: - E8: 予測変換

    func testPredictionUsesCandidateRuby() {
        // 「破た」から、候補の ruby ハタ で予測して「破綻」を出す（テスト用の表では 破 の読みはハだけ）
        let converter = KanaKanjiConverter.withDefaultDictionary()
        let result = converter.requestCandidates(self.composingText("破た"), options: self.options(prediction: .manualMix))
        XCTAssertTrue(result.predictionResults.contains { $0.text == "破綻" }, result.predictionResults.map(\.text).description)
    }

    func testPredictionKeepsInputKanji() {
        let converter = KanaKanjiConverter.withDefaultDictionary()
        for input in ["破た", "毀そ", "取ひ", "き損"] {
            let result = converter.requestCandidates(self.composingText(input), options: self.options(prediction: .manualMix))
            let kanji = input.filter { $0.unicodeScalars.first!.properties.isIdeographic }
            for candidate in result.predictionResults {
                var rest = candidate.text[...]
                for k in kanji {
                    guard let index = rest.firstIndex(of: k) else {
                        XCTFail("\(input): \(candidate.text)")
                        break
                    }
                    rest = rest[rest.index(after: index)...]
                }
            }
            converter.stopComposition()
        }
    }
}
