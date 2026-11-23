package import Foundation
import SwiftUtils

/// 交ぜ書き変換で、入力漢字 1 字を展開する読み
package struct MazegakiReading: Sendable, Equatable, Hashable {
    /// 読みの由来
    package enum Kind: Int, Sendable, Equatable, Hashable, Comparable {
        /// 読み表の読み（送り仮名を除いた語幹）。例: 通（トオ.ル）→ トオ
        case stem
        /// 促音化。例: 学（ガク）→ ガッ
        case sokuon
        /// 連濁。例: 社（シャ）→ ジャ
        case rendaku
        /// 送り仮名を吸収した連用形。例: 通（トオ.ル）→ トオリ
        case conjunctive
        /// 連用形の連濁。例: 通（トオ.ル）→ ドオリ
        case conjunctiveRendaku

        package static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        /// 読みに付けるペナルティ（値が大きいほど不利）。調整は辞書引きへの組み込みの際に行う。
        package var penalty: PValue {
            switch self {
            case .stem: 0
            case .sokuon: 1
            case .rendaku: 1
            case .conjunctive: 2
            case .conjunctiveRendaku: 3
            }
        }
    }

    /// カタカナの読み
    package var ruby: String
    package var kind: Kind

    package var penalty: PValue {
        self.kind.penalty
    }
}

/// 交ぜ書き変換に使う漢字の読み表
///
/// 形式（UTF-8 のテキスト。1 行 1 字）:
/// ```
/// # 行頭が # の行と空行は無視する
/// 漢字<TAB>読み1,読み2,…
/// ```
/// - 読みはカタカナで、優先度の高い順に並べる。ひらがなはカタカナとして扱う。
/// - `.` より後ろは送り仮名（例: `トオ.ル`）。語幹（`トオ`）に加えて、連用形（`トオリ`）を派生させる。
/// - `-`（接頭・接尾の印）は無視する。
/// - カタカナ以外の文字を含む読み、1 字でない見出しの行は無視する。同じ字の行が複数あれば、読みを順に連結する。
package struct MazegakiReadingTable: Sendable {
    /// 読み表のテキストを解析する
    /// - Parameters:
    ///   - text: 読み表のテキスト
    ///   - maxReadingsPerKanji: 読み表から使う読みの数の上限（1 字あたり）。派生させた読みはこの数に含めない。
    package init(parsing text: String, maxReadingsPerKanji: Int) {
        var raw: [Character: [String]] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("#") {
                continue
            }
            let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard columns.count == 2, columns[0].count == 1, let kanji = columns[0].first else {
                continue
            }
            raw[kanji, default: []].append(contentsOf: columns[1].split(separator: ",").map(String.init))
        }
        self.init(entries: raw, maxReadingsPerKanji: maxReadingsPerKanji)
    }

    /// 漢字ごとの読みの一覧から作る。読みの書式は読み表と同じ（`トオ.ル`など）。
    package init(entries: [Character: [String]], maxReadingsPerKanji: Int) {
        let limit = max(0, maxReadingsPerKanji)
        var table: [Character: [MazegakiReading]] = [:]
        table.reserveCapacity(entries.count)
        for (kanji, notations) in entries {
            let readings = Self.derive(from: notations, limit: limit)
            if !readings.isEmpty {
                table[kanji] = readings
            }
        }
        self.table = table
    }

    /// 読み表のファイルを読み込む
    package init(contentsOf url: URL, maxReadingsPerKanji: Int) throws {
        let text = try String(contentsOf: url, encoding: .utf8)
        self.init(parsing: text, maxReadingsPerKanji: maxReadingsPerKanji)
    }

    private var table: [Character: [MazegakiReading]]

    /// 読み表にある字の数
    package var count: Int {
        self.table.count
    }

    /// 漢字 1 字の読みを、ペナルティの小さい順に返す。読み表にない字では空配列を返す（展開しない）。
    package func readings(of kanji: Character) -> [MazegakiReading] {
        self.table[kanji] ?? []
    }

    // MARK: - 読みの派生

    /// 読み表の書式の読み（`トオ.ル`など）を、語幹と送り仮名に分ける。カタカナ以外を含むものは`nil`。
    static func parseNotation(_ notation: String) -> (stem: String, okurigana: String)? {
        let normalized = String(notation.filter { $0 != "-" && !$0.isWhitespace }.map { $0.toKatakana() })
        let parts = normalized.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let stem = String(parts[0])
        let okurigana = parts.count == 2 ? String(parts[1]) : ""
        guard !stem.isEmpty, stem.allSatisfy(isKatakana), okurigana.allSatisfy(isKatakana) else {
            return nil
        }
        return (stem, okurigana)
    }

    /// 読みの一覧から、語幹・促音化・連濁・連用形の読みを作る。
    /// 並びはペナルティの小さい順で、同じペナルティの中では由来の順、その中では表の順。重複する読みは先に出たものだけを残す。
    static func derive(from notations: [String], limit: Int) -> [MazegakiReading] {
        var seenNotations: Set<String> = []
        var bases: [(stem: String, okurigana: String)] = []
        for notation in notations {
            guard bases.count < limit else {
                break
            }
            guard let parsed = parseNotation(notation), seenNotations.insert(parsed.stem + "." + parsed.okurigana).inserted else {
                continue
            }
            bases.append(parsed)
        }

        var candidates: [MazegakiReading] = []
        for base in bases {
            candidates.append(.init(ruby: base.stem, kind: .stem))
        }
        for base in bases {
            if let sokuon = sokuon(of: base.stem) {
                candidates.append(.init(ruby: sokuon, kind: .sokuon))
            }
        }
        for base in bases {
            for rendaku in rendaku(of: base.stem) {
                candidates.append(.init(ruby: rendaku, kind: .rendaku))
            }
        }
        let conjunctives = bases.compactMap { conjunctive(stem: $0.stem, okurigana: $0.okurigana) }
        for conjunctive in conjunctives {
            candidates.append(.init(ruby: conjunctive, kind: .conjunctive))
        }
        for conjunctive in conjunctives {
            for rendaku in rendaku(of: conjunctive) {
                candidates.append(.init(ruby: rendaku, kind: .conjunctiveRendaku))
            }
        }

        // 安定ソートで、ペナルティ → 由来 → 表の順に並べる
        let sorted = candidates.enumerated().sorted { lhs, rhs in
            if lhs.element.penalty != rhs.element.penalty {
                return lhs.element.penalty < rhs.element.penalty
            }
            if lhs.element.kind != rhs.element.kind {
                return lhs.element.kind < rhs.element.kind
            }
            return lhs.offset < rhs.offset
        }.map(\.element)

        var seenRubies: Set<String> = []
        return sorted.filter { seenRubies.insert($0.ruby).inserted }
    }

    /// 促音化: 2 字以上で末尾がキ・ク・チ・ツの読みの末尾をッにする（学 ガク → ガッ）
    static func sokuon(of reading: String) -> String? {
        guard reading.count >= 2, let last = reading.last, "キクチツ".contains(last) else {
            return nil
        }
        return reading.dropLast() + "ッ"
    }

    /// 連濁: 先頭の清音を濁音・半濁音にする（社 シャ → ジャ、発 ハツ → バツ・パツ）
    static func rendaku(of reading: String) -> [String] {
        guard let first = reading.first, let voiced = rendakuTable[first] else {
            return []
        }
        return voiced.map { String($0) + reading.dropFirst() }
    }

    /// 送り仮名を吸収した連用形
    /// - 送り仮名が「イ段・エ段 + ル」で終わる（2 字以上）: 一段活用とみなし、ルを落とす（落 オ.チル → オチ）
    /// - 送り仮名がウ段で終わる: 五段活用とみなし、末尾をイ段にする（通 トオ.ル → トオリ、引 ヒ.ク → ヒキ）
    ///   送り仮名がルだけの場合は一段活用（着 キ.ル → キ）の可能性もあるが、その形は語幹と同じなので語幹の読みで取れる
    /// - それ以外（形容詞など）: 作らない
    static func conjunctive(stem: String, okurigana: String) -> String? {
        guard let last = okurigana.last else {
            return nil
        }
        let body = okurigana.dropLast()
        if last == "ル", let previous = body.last, iRowOrERow.contains(previous) {
            return stem + body
        }
        guard let iRow = godanConjunctiveTable[last] else {
            return nil
        }
        return stem + body + String(iRow)
    }

    private static func isKatakana(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else {
            return false
        }
        // ァ (U+30A1) 〜 ヺ (U+30FA)、ー (U+30FC)
        return (0x30A1...0x30FA).contains(scalar.value) || scalar.value == 0x30FC
    }

    private static let rendakuTable: [Character: [Character]] = [
        "カ": ["ガ"], "キ": ["ギ"], "ク": ["グ"], "ケ": ["ゲ"], "コ": ["ゴ"],
        "サ": ["ザ"], "シ": ["ジ"], "ス": ["ズ"], "セ": ["ゼ"], "ソ": ["ゾ"],
        "タ": ["ダ"], "チ": ["ヂ", "ジ"], "ツ": ["ヅ", "ズ"], "テ": ["デ"], "ト": ["ド"],
        "ハ": ["バ", "パ"], "ヒ": ["ビ", "ピ"], "フ": ["ブ", "プ"], "ヘ": ["ベ", "ペ"], "ホ": ["ボ", "ポ"],
    ]

    private static let godanConjunctiveTable: [Character: Character] = [
        "ウ": "イ", "ク": "キ", "グ": "ギ", "ス": "シ", "ツ": "チ",
        "ヌ": "ニ", "ブ": "ビ", "ム": "ミ", "ル": "リ",
    ]

    private static let iRowOrERow: Set<Character> = Set(
        "イキギシジチヂニヒビピミリ" + "エケゲセゼテデネヘベペメレ"
    )
}
