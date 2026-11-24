import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary

// 漢直 + 交ぜ書き変換の実用性検証
//
// 使い方:
//   swift run -c release mazegaki-test [オプション] [入力...]
//
//   --zenzai            Zenzai を有効化（モデルは models/zenz-v3.1-small-Q5_K_M.gguf）
//   --model PATH        gguf モデルのパスを指定（--zenzai を含意）
//   --limit N           Zenzai の inferenceLimit（既定 1）
//   --expand            「漢字を開く」方式で変換する（既定は入力そのまま＝漢字を素通し）
//   --cap N             --expand 時に試す読み組合せの上限（既定 32）
//   --all-keystrokes    1 文字ずつ入力する方式で、最後の 1 打鍵ではなく、すべての打鍵のうち最大の時間を記録する
//   --prediction M      日本語の予測変換の設定（autoMix〔既定〕/ manualMix / disabled）。分析用
//   --mazegaki          エンジン組み込み版（ConvertRequestOptions.mazegakiMode）で変換する。入力の仕方は素通しと同じ
//                       （1 文字ずつ入力して最後の 1 打鍵の時間を計る）。読み表は --reading-table、上限は --max-readings
//   --reading-table P   読み表のパス（既定 data/kanji_readings.tsv）
//   --readings R        --expand 時の読みの派生規則。legacy（既定。Step 0 と同じ: 語幹・促音化・連濁、上限なし）
//                       または library（ライブラリと同じ: 上限つきの語幹・促音化・連濁・連用形・連用形の連濁）
//   --max-readings N    --readings library のときの、1 字あたりの表の読みの上限（既定 8）
//   --dump-readings P   --readings library の派生結果を P に書き出して終了する（ライブラリとの突き合わせ用）
//   --quiet             候補一覧を出さず結果行だけ表示
//   --table PATH        入力をキー列とみなし、カスタム入力テーブル(TSV)経由で変換（漢直テーブルの動作確認用）
//   --cases PATH        テストケースを TSV から読む（カテゴリ<TAB>入力<TAB>正解1,正解2,…[<TAB>任意]、# 行は無視）。
//                       正解が複数あるときは、いちばん上位のものの順位を採る
//   --out PATH          ケースごとの結果を TSV に書く（ステップ間の差分を取るため）
//   入力                 指定がなければ組み込みケースを実行
//
// - debug ビルドではライブラリの debug ログが大量に出るので release 推奨
// - 素通し方式: 1 文字ずつ ComposingText に挿入して毎回 requestCandidates（ライブ変換と同じ呼び方）
// - 展開方式:   入力中の漢字を読みに開いた全かな文字列を作り、読み組合せごとに requestCandidates して、
//               「入力した漢字が、その読みの位置にそのまま現れる」候補だけを残してマージする

// MARK: - テストケース

struct TestCase {
    var category: String
    var input: String
    var expected: String?
    /// expected 以外の正解（1 つのキーに正解が複数ある評価セット用）
    var alternatives: [String] = []
    var answers: [String] { (expected.map { [$0] } ?? []) + alternatives }
}

func loadCases(_ path: String) -> [TestCase] {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
        print("テストケースを読めません: \(path)")
        exit(1)
    }
    return text.split(separator: "\n").compactMap { line -> TestCase? in
        if line.hasPrefix("#") { return nil }
        let cols = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard cols.count >= 3 else { return nil }
        let answers = cols[2].split(separator: ",").map(String.init)
        return TestCase(category: cols[0], input: cols[1], expected: answers.first, alternatives: Array(answers.dropFirst()))
    }
}

let builtinCases: [TestCase] = [
    // 1. 常用外・難字だけかなにした単語（漢直で最も典型的なケース）
    .init(category: "難字かな", input: "憂うつ", expected: "憂鬱"),
    .init(category: "難字かな", input: "語い", expected: "語彙"),
    .init(category: "難字かな", input: "破たん", expected: "破綻"),
    .init(category: "難字かな", input: "改ざん", expected: "改竄"),
    .init(category: "難字かな", input: "隠ぺい", expected: "隠蔽"),
    .init(category: "難字かな", input: "けん引", expected: "牽引"),
    .init(category: "難字かな", input: "ら致", expected: "拉致"),
    .init(category: "難字かな", input: "き損", expected: "毀損"),
    .init(category: "難字かな", input: "ねつ造", expected: "捏造"),
    .init(category: "難字かな", input: "だ捕", expected: "拿捕"),
    .init(category: "難字かな", input: "危ぐ", expected: "危惧"),
    .init(category: "難字かな", input: "えん罪", expected: "冤罪"),
    .init(category: "難字かな", input: "しっ責", expected: "叱責"),
    .init(category: "難字かな", input: "折しょう", expected: "折衝"),
    .init(category: "難字かな", input: "ぼう大", expected: "膨大"),

    // 2. 3字以上の語・四字熟語で、かなの位置が先頭/中間/末尾
    .init(category: "位置", input: "せん風機", expected: "扇風機"),
    .init(category: "位置", input: "自ぎゃく的", expected: "自虐的"),
    .init(category: "位置", input: "一朝一せき", expected: "一朝一夕"),
    .init(category: "位置", input: "四面そ歌", expected: "四面楚歌"),
    .init(category: "位置", input: "ぼう若無人", expected: "傍若無人"),
    .init(category: "位置", input: "あい昧", expected: "曖昧"),

    // 3. 同音異義語を漢字 1 字で絞り込む
    .init(category: "同音絞込", input: "き社", expected: "貴社"),
    .init(category: "同音絞込", input: "記しゃ", expected: "記者"),
    .init(category: "同音絞込", input: "汽しゃ", expected: "汽車"),
    .init(category: "同音絞込", input: "こう正", expected: "校正"),
    .init(category: "同音絞込", input: "こう生", expected: "厚生"),
    .init(category: "同音絞込", input: "保しょう", expected: "保証"),
    .init(category: "同音絞込", input: "保しょう人", expected: "保証人"),

    // 4. 送り仮名・活用語尾つき
    .init(category: "活用", input: "し烈な", expected: "熾烈な"),
    .init(category: "活用", input: "あざ笑う", expected: "嘲笑う"),
    .init(category: "活用", input: "ののしった", expected: "罵った"),
    .init(category: "活用", input: "こう着した", expected: "膠着した"),

    // 5. 文単位（漢直で書ける字は漢字のまま、書けない字だけかな）
    .init(category: "文", input: "会議で議論がふん糾した", expected: "会議で議論が紛糾した"),
    .init(category: "文", input: "彼の判断はし意的だ", expected: "彼の判断は恣意的だ"),
    .init(category: "文", input: "個人情報のろう洩を防ぐ", expected: "個人情報の漏洩を防ぐ"),
    .init(category: "文", input: "計画が破たんしかけている", expected: "計画が破綻しかけている"),
    .init(category: "文", input: "その件はき損にあたる", expected: "その件は毀損にあたる"),
    .init(category: "文", input: "データをかい竄した疑い", expected: "データを改竄した疑い"),

    // 6. 入力した漢字が「制約」として効くか（開いたことで別の語に化けないか）
    .init(category: "制約", input: "機のう", expected: "機能"),
    .init(category: "制約", input: "帰のう", expected: "帰納"),
    .init(category: "制約", input: "昨のう", expected: "昨日"),
    .init(category: "制約", input: "き能", expected: "機能"),
    .init(category: "制約", input: "こう成", expected: "構成"),
    .init(category: "制約", input: "公せい", expected: "公正"),
    .init(category: "制約", input: "学こう", expected: "学校"),      // 学 ガク→ガッ（促音化）が必要
    .init(category: "制約", input: "日記ちょう", expected: "日記帳"),
    .init(category: "制約", input: "株式会しゃ", expected: "株式会社"),
    .init(category: "制約", input: "本棚", expected: "本棚"),          // 全部漢字（開いても化けないこと）
    .init(category: "制約", input: "ほん棚", expected: "本棚"),        // 棚 タナ→ダナ（連濁）が必要

    // 7. 対照: すべてかな（通常のかな漢字変換）
    .init(category: "対照かな", input: "ゆううつ", expected: "憂鬱"),
    .init(category: "対照かな", input: "はたん", expected: "破綻"),
    .init(category: "対照かな", input: "かいぎでぎろんがふんきゅうした", expected: "会議で議論が紛糾した"),
]

// MARK: - コマンドライン引数

var useZenzai = false
var modelPath = "models/zenz-v3.1-small-Q5_K_M.gguf"
var inferenceLimit = 1
var expandMode = false
var mazegakiMode = false
var predictionMode = ConvertRequestOptions.PredictionMode.autoMix
var allKeystrokes = false
var comboCap = 32
enum ReadingRules: String { case legacy, library }
var readingRules = ReadingRules.legacy
var maxReadingsPerKanji = 8
var readingTablePath = "data/kanji_readings.tsv"
var quiet = false
var tablePath: String? = nil   // 指定時: 入力をキー列とみなし、カスタム入力テーブル(TSV)経由で ComposingText を作る
var casesPath: String? = nil
var outPath: String? = nil
var inputArgs: [String] = []
do {
    var it = CommandLine.arguments.dropFirst().makeIterator()
    while let a = it.next() {
        switch a {
        case "--zenzai": useZenzai = true
        case "--model": modelPath = it.next() ?? modelPath; useZenzai = true
        case "--limit": inferenceLimit = Int(it.next() ?? "") ?? inferenceLimit
        case "--expand": expandMode = true
        case "--mazegaki": mazegakiMode = true
        case "--all-keystrokes": allKeystrokes = true
        case "--prediction":
            switch it.next() {
            case "autoMix": predictionMode = .autoMix
            case "manualMix": predictionMode = .manualMix
            case "disabled": predictionMode = .disabled
            default: print("--prediction は autoMix / manualMix / disabled"); exit(1)
            }
        case "--cap": comboCap = Int(it.next() ?? "") ?? comboCap
        case "--readings":
            guard let r = it.next().flatMap(ReadingRules.init(rawValue:)) else { print("--readings は legacy か library"); exit(1) }
            readingRules = r
        case "--reading-table": readingTablePath = it.next() ?? readingTablePath
        case "--max-readings": maxReadingsPerKanji = Int(it.next() ?? "") ?? maxReadingsPerKanji
        case "--quiet": quiet = true
        case "--table": tablePath = it.next()
        case "--cases": casesPath = it.next()
        case "--out": outPath = it.next()
        case "--dump-readings": _ = it.next()
        default: inputArgs.append(a)
        }
    }
}

// MARK: - コンバータの準備

let zenzaiMode: ConvertRequestOptions.ZenzaiMode
if useZenzai {
    let url = URL(fileURLWithPath: modelPath)
    guard FileManager.default.fileExists(atPath: url.path) else {
        print("モデルが見つかりません: \(url.path)")
        exit(1)
    }
    zenzaiMode = .on(weight: url, inferenceLimit: inferenceLimit, personalizationMode: nil,
                     versionDependentMode: .v3(.init()))
} else {
    zenzaiMode = .off
}
print("Zenzai: \(useZenzai ? "ON (inferenceLimit=\(inferenceLimit))" : "OFF")  方式: \(mazegakiMode ? "エンジン組み込み (max=\(maxReadingsPerKanji), table=\(readingTablePath))" : expandMode ? "漢字を開く (cap=\(comboCap), readings=\(readingRules.rawValue)\(readingRules == .library ? " max=\(maxReadingsPerKanji)" : ""), table=\(readingTablePath))" : "素通し")")

let converter = KanaKanjiConverter.withDefaultDictionary()

let dataDir = FileManager.default.temporaryDirectory
    .appendingPathComponent("mazegaki-test", isDirectory: true)
try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)

let options = ConvertRequestOptions(
    requireJapanesePrediction: predictionMode,   // 0.11.x では Bool（true）。fddde10 以降は PredictionMode
    requireEnglishPrediction: .disabled,
    keyboardLanguage: .ja_JP,
    learningType: .nothing,
    memoryDirectoryURL: dataDir,
    sharedContainerURL: dataDir,
    textReplacer: .withDefaultEmojiDictionary(),
    specialCandidateProviders: KanaKanjiConverter.defaultSpecialCandidateProviders,
    zenzaiMode: zenzaiMode,
    mazegakiMode: mazegakiMode
        ? .on(readingTableURL: URL(fileURLWithPath: readingTablePath), maxReadingsPerKanji: maxReadingsPerKanji)
        : .off,
    metadata: .init(versionString: "mazegaki-test")
)
if mazegakiMode, !FileManager.default.fileExists(atPath: readingTablePath) {
    print("\(readingTablePath) が読めません")
    exit(1)
}

// MARK: - 文字種ヘルパ

func isKanji(_ c: Character) -> Bool {
    c.unicodeScalars.allSatisfy { s in
        (0x4E00...0x9FFF).contains(s.value) || (0x3400...0x4DBF).contains(s.value)
            || (0x20000...0x2FFFF).contains(s.value) || (0xF900...0xFAFF).contains(s.value)
    }
}

func isKana(_ c: Character) -> Bool {
    c.unicodeScalars.allSatisfy { (0x3041...0x3096).contains($0.value) || (0x30A1...0x30FA).contains($0.value) || $0.value == 0x30FC }
}

func toKatakana(_ s: String) -> String {
    String(String.UnicodeScalarView(s.unicodeScalars.map { (0x3041...0x3096).contains($0.value) ? Unicode.Scalar($0.value + 0x60)! : $0 }))
}

func toHiragana(_ s: String) -> String {
    String(String.UnicodeScalarView(s.unicodeScalars.map { (0x30A1...0x30F6).contains($0.value) ? Unicode.Scalar($0.value - 0x60)! : $0 }))
}

/// 入力中の漢字が、候補中に同じ順序で残っているか
func preservesKanji(input: String, candidate: String) -> Bool {
    var it = candidate.makeIterator()
    outer: for k in input where isKanji(k) {
        while let c = it.next() {
            if c == k { continue outer }
        }
        return false
    }
    return true
}

func coversWholeInput(_ c: Candidate, _ text: ComposingText) -> Bool {
    c.composingCount == .inputCount(text.input.count)
        || c.composingCount == .surfaceCount(text.convertTarget.count)
}

/// 候補が覆う入力の先頭部分（ベンチの入力は .direct で 1 文字 = 1 入力要素なので、入力数と表層の文字数は等しい）
func coveredPrefix(_ c: Candidate, _ input: String) -> String {
    func count(_ cc: ComposingCount) -> Int {
        switch cc {
        case .inputCount(let n), .surfaceCount(let n): n
        case .composite(let l, let r): count(l) + count(r)
        }
    }
    return String(input.prefix(count(c.composingCount)))
}

func ms(_ d: Duration) -> Double {
    Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
}

func pad(_ s: String, _ width: Int) -> String {
    let w = s.reduce(0) { $0 + ($1.isASCII ? 1 : 2) }
    return s + String(repeating: " ", count: max(0, width - w))
}

// MARK: - 漢字読み表（KANJIDIC2 由来: data/kanji_readings.tsv）

let kanjiReadings: [Character: [String]] = {
    guard let text = try? String(contentsOfFile: readingTablePath, encoding: .utf8) else {
        if expandMode {
            print("\(readingTablePath) が読めません")
            exit(1)
        }
        return [:]
    }
    var dict: [Character: [String]] = [:]
    for line in text.split(separator: "\n") where !line.hasPrefix("#") {
        let cols = line.split(separator: "\t")
        guard cols.count == 2, let k = cols[0].first else { continue }
        // 表は送り仮名を `.` の後ろに持つ（Docs/converter_api.md の形式）。そのまま保持し、派生の段階で解釈する。
        // CJK 互換漢字は Character としては統合漢字と等しいので、同じキーの行が複数現れる。
        // legacy は Step 0 と同じく後の行で上書きし、library はライブラリと同じく読みを連結する
        let rs = cols[1].split(separator: ",").map(String.init)
        switch readingRules {
        case .legacy: dict[k] = rs
        case .library: dict[k, default: []].append(contentsOf: rs)
        }
    }
    return dict
}()

let dakuten: [Character: [Character]] = [
    "カ": ["ガ"], "キ": ["ギ"], "ク": ["グ"], "ケ": ["ゲ"], "コ": ["ゴ"],
    "サ": ["ザ"], "シ": ["ジ"], "ス": ["ズ"], "セ": ["ゼ"], "ソ": ["ゾ"],
    "タ": ["ダ"], "チ": ["ヂ", "ジ"], "ツ": ["ヅ", "ズ"], "テ": ["デ"], "ト": ["ド"],
    "ハ": ["バ", "パ"], "ヒ": ["ビ", "ピ"], "フ": ["ブ", "プ"], "ヘ": ["ベ", "ペ"], "ホ": ["ボ", "ポ"],
]

/// 漢字 1 字の読み候補（優先順）
@MainActor func readingVariants(of k: Character) -> [String] {
    guard let notations = kanjiReadings[k] else { return [] }
    switch readingRules {
    case .legacy: return legacyReadingVariants(notations)
    case .library: return libraryReadingVariants(notations, limit: maxReadingsPerKanji)
    }
}

/// Step 0 の規則: 表の読みの語幹（上限なし） → 促音化 → 連濁
func legacyReadingVariants(_ notations: [String]) -> [String] {
    var base: [String] = []
    for n in notations {
        let stem = String(n.split(separator: ".", omittingEmptySubsequences: false)[0])
        if !stem.isEmpty, !base.contains(stem) { base.append(stem) }
    }
    var result = base
    func add(_ s: String) { if !result.contains(s) { result.append(s) } }
    for r in base {
        guard r.count >= 2, let last = r.last, "キクチツ".contains(last) else { continue }
        add(String(r.dropLast()) + "ッ")
    }
    for r in base {
        guard let first = r.first, let vs = dakuten[first] else { continue }
        for v in vs { add(String(v) + r.dropFirst()) }
    }
    return result
}

/// ライブラリ（MazegakiReadingTable.derive）と同じ規則。ライブラリの型は package アクセスでベンチから使えないので写している。
/// ライブラリ側の規則を変えたら、ここも合わせること。PR2 の `--mazegaki` ではエンジンが直接使うので、この写しは不要になる。
/// 語幹（上限 limit） → 促音化 → 連濁 → 連用形 → 連用形の連濁
func libraryReadingVariants(_ notations: [String], limit: Int) -> [String] {
    func isKatakana(_ c: Character) -> Bool {
        guard c.unicodeScalars.count == 1, let v = c.unicodeScalars.first?.value else { return false }
        return (0x30A1...0x30FA).contains(v) || v == 0x30FC
    }
    var seen: Set<String> = []
    var bases: [(stem: String, okurigana: String)] = []
    for n in notations {
        guard bases.count < limit else { break }
        let normalized = String(n.filter { $0 != "-" && !$0.isWhitespace })
        let parts = normalized.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let stem = String(parts[0]), oku = parts.count == 2 ? String(parts[1]) : ""
        guard !stem.isEmpty, stem.allSatisfy(isKatakana), oku.allSatisfy(isKatakana),
              seen.insert(stem + "." + oku).inserted else { continue }
        bases.append((stem, oku))
    }
    func sokuon(_ r: String) -> String? {
        guard r.count >= 2, let last = r.last, "キクチツ".contains(last) else { return nil }
        return r.dropLast() + "ッ"
    }
    func rendaku(_ r: String) -> [String] {
        guard let first = r.first, let vs = dakuten[first] else { return [] }
        return vs.map { String($0) + r.dropFirst() }
    }
    let godan: [Character: Character] = ["ウ": "イ", "ク": "キ", "グ": "ギ", "ス": "シ", "ツ": "チ", "ヌ": "ニ", "ブ": "ビ", "ム": "ミ", "ル": "リ"]
    let ie = Set("イキギシジチヂニヒビピミリ" + "エケゲセゼテデネヘベペメレ")
    func conjunctive(_ stem: String, _ oku: String) -> String? {
        guard let last = oku.last else { return nil }
        let body = oku.dropLast()
        if last == "ル", let prev = body.last, ie.contains(prev) { return stem + body }
        guard let i = godan[last] else { return nil }
        return stem + body + String(i)
    }
    var result: [String] = []
    func add(_ r: String) { if !result.contains(r) { result.append(r) } }
    // ペナルティ: 語幹 0 < 促音化 1 = 連濁 1 < 連用形 2 < 連用形の連濁 3（同じペナルティは由来の順）
    for b in bases { add(b.stem) }
    for b in bases { if let x = sokuon(b.stem) { add(x) } }
    for b in bases { rendaku(b.stem).forEach(add) }
    let conj = bases.compactMap { conjunctive($0.stem, $0.okurigana) }
    conj.forEach(add)
    for c in conj { rendaku(c).forEach(add) }
    return result
}

if let i = CommandLine.arguments.firstIndex(of: "--dump-readings"), i + 1 < CommandLine.arguments.count {
    // 読みの派生結果を書き出して終了する（ライブラリの規則と突き合わせるため）
    var out = ""
    for k in kanjiReadings.keys.sorted() {
        out += "\(k)\t\(libraryReadingVariants(kanjiReadings[k]!, limit: maxReadingsPerKanji).joined(separator: ","))\n"
    }
    try out.write(toFile: CommandLine.arguments[i + 1], atomically: true, encoding: .utf8)
    exit(0)
}

// MARK: - 展開方式の本体

/// 入力 1 文字ぶんの単位
struct Unit {
    var char: Character
    var readings: [String]   // 空なら展開しない（かな・記号・表にない漢字）
}

/// 読み組合せを「表の順位の合計」が小さい順に列挙（上限 cap 件）
@MainActor func enumerateCombos(_ sizes: [Int], cap: Int) -> [[Int]] {
    var result: [[Int]] = []
    let maxCost = sizes.reduce(0) { $0 + max(0, $1 - 1) }
    func rec(_ i: Int, _ remaining: Int, _ cur: inout [Int]) {
        if result.count >= cap { return }
        if i == sizes.count {
            if remaining == 0 { result.append(cur) }
            return
        }
        let limit = min(remaining, sizes[i] - 1)
        if limit < 0 { return }
        for v in 0...limit {
            cur.append(v)
            rec(i + 1, remaining - v, &cur)
            cur.removeLast()
            if result.count >= cap { return }
        }
    }
    var cost = 0
    while cost <= maxCost && result.count < cap {
        var cur: [Int] = []
        rec(0, cost, &cur)
        cost += 1
    }
    return result
}

/// 制約: 展開後のカタカナ列 [start, end) に、入力した漢字 k がそのまま現れること
struct Constraint {
    var kanji: Character
    var start: Int
    var end: Int
}

/// 1 語（表記 word / 読み ruby）の中で、制約を満たす文字対応が取れるか
/// - かなは読みと 1:1 一致、制約の位置ではその漢字が制約範囲ちょうどに対応、
///   その他の漢字等は 1〜4 モーラのワイルドカード（制約の開始位置をまたげない）
func alignWord(_ word: [Character], _ ruby: [Character], _ cons: [Int: (Character, Int)]) -> Bool {
    var memo: [Int: Bool] = [:]
    func rec(_ i: Int, _ p: Int) -> Bool {
        let key = i * 1000 + p
        if let m = memo[key] { return m }
        var ok = false
        defer { memo[key] = ok }
        if i == word.count { ok = (p == ruby.count); return ok }
        if p >= ruby.count { return false }
        let c = word[i]
        if let (k, end) = cons[p] {
            ok = (c == k) && rec(i + 1, end)
            return ok
        }
        if isKana(c) {
            ok = Character(toKatakana(String(c))) == ruby[p] && rec(i + 1, p + 1)
            return ok
        }
        for len in 1...min(4, ruby.count - p) {
            if len >= 2, ((p + 1)..<(p + len)).contains(where: { cons[$0] != nil }) { break }
            if rec(i + 1, p + len) { ok = true; return ok }
        }
        return ok
    }
    return rec(0, 0)
}

/// 候補全体が、展開後の読み列 expanded を過不足なく覆い、すべての制約を満たすか
func satisfies(_ c: Candidate, expanded: [Character], constraints: [Constraint]) -> Bool {
    var offset = 0
    var remaining = constraints[...]
    for e in c.data {
        let ruby = Array(e.ruby)
        let end = offset + ruby.count
        guard end <= expanded.count, Array(expanded[offset..<end]) == ruby else { return false }
        var local: [Int: (Character, Int)] = [:]
        while let first = remaining.first, first.start < end {
            guard first.start >= offset, first.end <= end else { return false }   // 語境界をまたぐ
            local[first.start - offset] = (first.kanji, first.end - offset)
            remaining = remaining.dropFirst()
        }
        if !local.isEmpty, !alignWord(Array(e.word), ruby, local) { return false }
        offset = end
    }
    return offset == expanded.count && remaining.isEmpty
}

struct ExpandResult {
    var candidates: [Candidate]
    var combosTried: Int
    var combosWithHit: Int
    var hitComboOfExpected: Int?   // 期待値を最初に出した組合せの番号（1 始まり）
    var readingOfExpected: String?
    var fellBack: Bool
}

@MainActor func convertExpanded(_ input: String, expected: String?) -> ExpandResult {
    let units = input.map { ch in Unit(char: ch, readings: isKanji(ch) ? readingVariants(of: ch) : []) }
    let expandIdx = units.indices.filter { !units[$0].readings.isEmpty }
    let combos = enumerateCombos(expandIdx.map { units[$0].readings.count }, cap: comboCap)

    // text -> (rank within request, -value, combo index)
    var best: [String: (rank: Int, value: Float, combo: Int, cand: Candidate)] = [:]
    var combosWithHit = 0
    var hitCombo: Int?
    var hitReading: String?

    for (ci, combo) in combos.enumerated() {
        var expandedHira = ""
        var expandedKata: [Character] = []
        var constraints: [Constraint] = []
        var choice = 0
        for (i, u) in units.enumerated() {
            if expandIdx.contains(i) {
                let r = u.readings[combo[choice]]; choice += 1
                constraints.append(.init(kanji: u.char, start: expandedKata.count, end: expandedKata.count + r.count))
                expandedKata += Array(r)
                expandedHira += toHiragana(r)
            } else {
                expandedKata += Array(toKatakana(String(u.char)))
                expandedHira.append(u.char)
            }
        }
        var text = ComposingText()
        text.insertAtCursorPosition(expandedHira, inputStyle: .direct)
        let result = converter.requestCandidates(text, options: options)
        converter.stopComposition()

        let passed = result.mainResults.filter { satisfies($0, expanded: expandedKata, constraints: constraints) }
        if !passed.isEmpty { combosWithHit += 1 }
        for (rank, c) in passed.enumerated() {
            let v = Float(c.value)
            if let cur = best[c.text], (cur.rank, -cur.value) <= (rank, -v) { continue }
            best[c.text] = (rank, v, ci, c)
            if c.text == expected, hitCombo == nil {
                hitCombo = ci + 1
                hitReading = expandedHira
            }
        }
    }

    if best.isEmpty {
        // フォールバック: 素通しで変換
        var text = ComposingText()
        text.insertAtCursorPosition(input, inputStyle: .direct)
        let result = converter.requestCandidates(text, options: options)
        converter.stopComposition()
        return .init(candidates: result.mainResults.filter { coversWholeInput($0, text) },
                     combosTried: combos.count, combosWithHit: 0, hitComboOfExpected: nil, readingOfExpected: nil, fellBack: true)
    }
    // 各リクエスト内の順位（Zenzai の判断を尊重）→ 評価値 の順
    // 入力と同一の候補（例: 改ざん→改ざん）は交ぜ書き変換としては無意味なので末尾へ
    let merged = best.values.sorted {
        ($0.cand.text == input ? 1 : 0, $0.rank, -$0.value, $0.combo) < ($1.cand.text == input ? 1 : 0, $1.rank, -$1.value, $1.combo)
    }.map(\.cand)
    return .init(candidates: merged, combosTried: combos.count, combosWithHit: combosWithHit,
                 hitComboOfExpected: hitCombo, readingOfExpected: hitReading, fellBack: false)
}

// MARK: - 実行

struct Outcome {
    var testCase: TestCase
    var rank: Int?
    var latency: Double
    var combos: Int
    var kanjiLost: Bool      // 上位 showCount 件に、入力漢字が消えた候補がある
    var top1: String
}

let showCount = 8
let clock = ContinuousClock()

let cases = if let casesPath {
    loadCases(casesPath)
} else if inputArgs.isEmpty {
    builtinCases
} else {
    inputArgs.map { TestCase(category: "任意", input: $0, expected: nil) }
}

// カスタム入力テーブル（漢直テーブル想定）の動作確認モード
if let tablePath {
    // fddde10 以降は InputTableID.custom が無いので、名前を付けて登録する
    guard let table = try? InputStyleManager.loadTable(from: URL(fileURLWithPath: tablePath)) else {
        print("入力テーブルを読めません: \(tablePath)")
        exit(1)
    }
    InputStyleManager.registerInputStyle(table: table, for: "mazegaki-bench")
    let style = InputStyle.mapped(id: .tableName("mazegaki-bench"))
    for keys in inputArgs {
        var text = ComposingText()
        for k in keys {
            text.insertAtCursorPosition(String(k), inputStyle: style)
        }
        let result = converter.requestCandidates(text, options: options)
        converter.stopComposition()
        print("keys=\(keys)  convertTarget=\(text.convertTarget)  input=\(text.input.count)要素")
        print("    " + result.mainResults.prefix(5).enumerated().map { "\($0 + 1).\($1.text)" }.joined(separator: "  "))
    }
    exit(0)
}

// ウォームアップ（辞書・モデルの初回ロード時間を計測から除く）
do {
    var t = ComposingText()
    t.insertAtCursorPosition("あ", inputStyle: .direct)
    _ = converter.requestCandidates(t, options: options)
    converter.stopComposition()
}

var outcomes: [Outcome] = []
var currentCategory = ""

for tc in cases {
    if tc.category != currentCategory {
        currentCategory = tc.category
        print("\n━━ \(tc.category) ━━")
    }

    var candidates: [Candidate] = []
    var latency = 0.0
    var note = ""
    var combos = 1
    var literalText = ComposingText()

    if expandMode {
        var r: ExpandResult!
        let elapsed = clock.measure { r = convertExpanded(tc.input, expected: tc.expected) }
        latency = ms(elapsed)
        candidates = r.candidates
        combos = r.combosTried
        note = r.fellBack ? "  [該当なし→素通し]" : "  組合せ\(r.combosTried)中\(r.combosWithHit)件ヒット"
        if let h = r.hitComboOfExpected, let reading = r.readingOfExpected {
            note += " 正解は#\(h)(\(reading))"
        }
    } else {
        // 1 文字ずつ入力（漢直 IM で打鍵ごとに変換を回す想定）。最終打鍵の時間を記録
        var result: ConversionResult!
        for ch in tc.input {
            literalText.insertAtCursorPosition(String(ch), inputStyle: .direct)
            let elapsed = clock.measure { result = converter.requestCandidates(literalText, options: options) }
            latency = allKeystrokes ? max(latency, ms(elapsed)) : ms(elapsed)
        }
        converter.stopComposition()
        candidates = result.mainResults
    }

    let rank = tc.answers.compactMap { e in candidates.firstIndex { $0.text == e }.map { $0 + 1 } }.min()
    let mark: String
    switch rank {
    case .some(1): mark = "◎ 1位"
    case .some(let r) where r <= 5: mark = "○ \(r)位"
    case .some(let r): mark = "△ \(r)位"
    case .none: mark = tc.expected == nil ? "" : "× 圏外(\(candidates.count)件中)"
    }

    var header = pad(tc.input, 26)
    if tc.expected != nil { header += "→ \(pad(tc.answers.joined(separator: ","), 22)) \(pad(mark, 16))" }
    header += String(format: " %6.1fms", latency) + note
    print(header)

    if !quiet {
        let listed = candidates.prefix(showCount).enumerated().map { i, c -> String in
            var s = "\(i + 1).\(c.text)"
            if !expandMode, !coversWholeInput(c, literalText) { s += "[部分]" }
            if !preservesKanji(input: coveredPrefix(c, tc.input), candidate: c.text) { s += "[漢字消失]" }
            if tc.answers.contains(c.text) { s = "【\(s)】" }
            return s
        }
        print("    " + listed.joined(separator: "  "))
    }

    // 部分候補（入力の先頭だけを変換した候補）は、その候補が覆う範囲の漢字だけを見る
    let kanjiLost = candidates.prefix(showCount).contains { !preservesKanji(input: coveredPrefix($0, tc.input), candidate: $0.text) }
    outcomes.append(.init(testCase: tc, rank: rank, latency: latency, combos: combos,
                          kanjiLost: kanjiLost, top1: candidates.first?.text ?? ""))
}

// MARK: - 集計

let scored = outcomes.filter { $0.testCase.expected != nil }
if !scored.isEmpty {
    print("\n━━ 集計 ━━")
    var categories: [String] = []
    for o in scored where !categories.contains(o.testCase.category) {
        categories.append(o.testCase.category)
    }
    print("\(pad("カテゴリ", 12)) 件数  1位  5位内  圏内  圏外   平均ms   最大ms")
    for cat in categories + ["全体"] {
        let os = cat == "全体" ? scored : scored.filter { $0.testCase.category == cat }
        let top1 = os.filter { $0.rank == 1 }.count
        let top5 = os.filter { ($0.rank ?? .max) <= 5 }.count
        let found = os.filter { $0.rank != nil }.count
        let avg = os.map(\.latency).reduce(0, +) / Double(os.count)
        let worst = os.map(\.latency).max() ?? 0
        print("\(pad(cat, 12)) \(String(format: "%4d %4d %6d %5d %5d %8.1f %8.1f", os.count, top1, top5, found, os.count - found, avg, worst))")
    }
    let lost = scored.filter(\.kanjiLost)
    print("\n入力漢字の消失（上位\(showCount)件に含むケース）: \(lost.count)件"
          + (lost.isEmpty ? "" : "  例: " + lost.prefix(20).map(\.testCase.input).joined(separator: ", ")))
    let misses = scored.filter { $0.rank == nil }
    if !misses.isEmpty {
        let shown = misses.prefix(60).map { "\($0.testCase.input)→\($0.testCase.expected!)" }.joined(separator: ", ")
        print("\n圏外: " + shown + (misses.count > 60 ? " ほか\(misses.count - 60)件" : ""))
    }
}

if let outPath {
    var lines = ["# カテゴリ\t入力\t正解\t順位\t1位\tms\t漢字消失"]
    for o in outcomes {
        lines.append([o.testCase.category, o.testCase.input, o.testCase.answers.joined(separator: ","),
                      o.rank.map(String.init) ?? "-", o.top1, String(format: "%.2f", o.latency),
                      o.kanjiLost ? "1" : "0"].joined(separator: "\t"))
    }
    try lines.joined(separator: "\n").appending("\n").write(toFile: outPath, atomically: true, encoding: .utf8)
    print("結果を書き出しました: \(outPath)")
}
