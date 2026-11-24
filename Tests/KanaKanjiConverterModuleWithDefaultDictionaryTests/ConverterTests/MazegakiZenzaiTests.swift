#if Zenzai || ZenzaiCPU
import Foundation
@testable import KanaKanjiConverterModule
@testable import KanaKanjiConverterModuleWithDefaultDictionary
import XCTest

/// 交ぜ書き変換と Zenzai を併用した変換のテスト。モデルが無い環境では飛ばす。
///
/// パッケージの trait `Zenzai`（または`ZenzaiCPU`）を有効にしたときだけ動く（`swift test --traits Zenzai`）。
/// モデルの場所は環境変数`MAZEGAKI_ZENZAI_WEIGHT`で指定する。指定が無ければ`ZenzaiTests`と同じ場所を使う。
final class MazegakiZenzaiTests: XCTestCase {
    /// テスト用の小さな読み表（自作）
    private static let readingTable = """
    座\tザ
    濫\tラン
    告\tコク
    """

    private var tableURL: URL!

    override func setUpWithError() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: Self.weightURL.path), "Zenzai のモデルが無い")
        self.tableURL = FileManager.default.temporaryDirectory.appendingPathComponent("mazegaki-zenzai-test-\(UUID().uuidString).tsv")
        try Self.readingTable.write(to: self.tableURL, atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        if let tableURL {
            try? FileManager.default.removeItem(at: tableURL)
        }
    }

    private static var weightURL: URL {
        if let path = ProcessInfo.processInfo.environment["MAZEGAKI_ZENZAI_WEIGHT"] {
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: "/Library/Input Methods/azooKeyMac.app/Contents/Resources/ggml-model-Q5_K_M.gguf")
    }

    private var options: ConvertRequestOptions {
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
            zenzaiMode: .on(weight: Self.weightURL, inferenceLimit: 5, personalizationMode: .none, versionDependentMode: .v3(.init())),
            typoCorrectionMode: .disabled,
            mazegakiMode: .on(readingTableURL: self.tableURL),
            metadata: nil
        )
    }

    /// 入力全体を一度に入れて変換した 1 位
    private func firstResult(_ input: String) -> String? {
        let converter = KanaKanjiConverter.withDefaultDictionary()
        var composingText = ComposingText()
        composingText.insertAtCursorPosition(input, inputStyle: .direct)
        return converter.requestCandidates(composingText, options: self.options).mainResults.first?.text
    }

    /// 1 文字ずつ入れて、打鍵ごとに変換した最後の 1 位
    private func firstResultTypedGradually(_ input: String) -> String? {
        let converter = KanaKanjiConverter.withDefaultDictionary()
        var composingText = ComposingText()
        var result: ConversionResult?
        for character in input {
            composingText.insertAtCursorPosition(String(character), inputStyle: .direct)
            result = converter.requestCandidates(composingText, options: self.options)
        }
        return result?.mainResults.first?.text
    }

    @MainActor
    func testFailedEvaluationKeepsFirstDraft() {
        // モデルは読み（アンザ）だけを見ると「あんざ」を好み、入力漢字「座」を残す候補では満たせない。
        // そのときに、モデルの訂正に合わせて作った素通しの候補（あん座）を 1 位にしない
        XCTAssertEqual(self.firstResult("あん座"), "安座")
    }

    @MainActor
    func testConstraintBeforeInputKanjiIsNotCarriedOver() {
        // 「はん」「ひ」の時点で認めた表記（半、日）に縛られない
        XCTAssertEqual(self.firstResultTypedGradually("はん濫"), "氾濫")
        XCTAssertEqual(self.firstResultTypedGradually("ひ告"), "被告")
    }
}
#endif
