import SwiftUtils

/// 交ぜ書き変換で、入力に含まれる漢字を読みに展開した文字列を列挙する生成器
///
/// `convertTarget`（カタカナにしたもの）の`leftIndex`から右へ 1 文字ずつ、
/// 読み表にある字は読みのどれかを、それ以外の字はその字自身を選んで、深さ優先で文字列を作る。
/// 終わりの位置が`rightIndexRange`に入り、かつ範囲に展開した漢字を 1 字以上含む文字列だけを返す。
/// 読み表にない漢字（表意文字）に達したら、その先へは進まない（その範囲を含む語は辞書にない）。
struct MazegakiGenerator {
    struct Output {
        /// 展開した文字列（カタカナ）
        var characters: [Character]
        /// `convertTarget`での終わりの位置（この位置の文字を含む）
        var endIndex: Int
        /// 選んだ読みのペナルティの合計
        var penalty: PValue
        /// 展開した漢字ごとの制約（`characters`の中での範囲）
        var constraints: [MazegakiConstraint]
    }

    /// 1 回の辞書引きで返す文字列の数の上限
    static let maxOutputCount = 4096

    private struct Option {
        var characters: [Character]
        var penalty: PValue
        /// 読み表で展開した漢字なら、その字
        var kanji: Character?
    }

    private let leftIndex: Int
    private let rightIndexRange: Range<Int>
    /// `leftIndex`からの各位置で選べるもの。空の位置から先へは進まない
    private let options: [[Option]]

    /// 選んでいる option の番号（深さごと）
    private var path: [Int] = []
    /// 深さ d の option を選ぶ前の`characters`の長さ
    private var lengthBefore: [Int] = []
    private var characters: [Character] = []
    private var penalties: [PValue] = []
    private var constraints: [MazegakiConstraint] = []
    private var constraintCountBefore: [Int] = []
    /// 直前に返した文字列について、この長さの接頭辞がどの辞書でもたどれないと分かった
    private var unreachablePrefixLength: Int?
    private var started = false
    private(set) var outputCount = 0

    init(surface: [Character], range: TypoCorrectionGenerator.ProcessRange, table: MazegakiReadingTable) {
        self.leftIndex = range.leftIndex
        self.rightIndexRange = range.rightIndexRange
        let end = min(surface.count, range.rightIndexRange.upperBound)
        var options: [[Option]] = []
        if self.leftIndex < end {
            options.reserveCapacity(end - self.leftIndex)
            for character in surface[self.leftIndex ..< end] {
                let readings = table.readings(of: character)
                if !readings.isEmpty {
                    options.append(readings.map { Option(characters: Array($0.ruby), penalty: $0.penalty, kanji: character) })
                } else if Self.isIdeographic(character) {
                    options.append([])
                } else {
                    options.append([Option(characters: [character], penalty: 0, kanji: nil)])
                }
            }
        }
        self.options = options
    }

    /// 範囲に展開できる漢字が 1 つもなければ`false`（何も生成しない）
    var hasExpandableKanji: Bool {
        self.options.contains { $0.contains { $0.kanji != nil } }
    }

    /// 表意文字（漢字）かどうか
    static func isIdeographic(_ character: Character) -> Bool {
        character.unicodeScalars.first?.properties.isIdeographic ?? false
    }

    /// 直前に返した文字列の接頭辞`target`がどの辞書でもたどれないことを知らせる
    mutating func setUnreachablePath(prefixLength: Int) {
        if let current = self.unreachablePrefixLength {
            self.unreachablePrefixLength = min(current, prefixLength)
        } else {
            self.unreachablePrefixLength = prefixLength
        }
    }

    mutating func next() -> Output? {
        while self.advance() {
            let depth = self.path.count
            let endIndex = self.leftIndex + depth - 1
            guard self.rightIndexRange.contains(endIndex), !self.constraints.isEmpty else {
                continue
            }
            if self.outputCount >= Self.maxOutputCount {
                debug(#function, "MazegakiGenerator reached maxOutputCount", Self.maxOutputCount)
                return nil
            }
            self.outputCount += 1
            return Output(
                characters: self.characters,
                endIndex: endIndex,
                penalty: self.penalties.last ?? 0,
                constraints: self.constraints
            )
        }
        return nil
    }

    /// 深さ優先の次の節点へ進む。なければ`false`
    private mutating func advance() -> Bool {
        if let deadLength = self.unreachablePrefixLength {
            self.unreachablePrefixLength = nil
            let deadPrefix = Array(self.characters.prefix(deadLength))
            // 今の節点より下はすべて、たどれない接頭辞を持つ。
            // 選ぶ前の長さが deadLength 以上の段は、兄弟もその接頭辞を共有するので、まとめて戻る
            while let before = self.lengthBefore.last, before >= deadLength {
                self.pop()
            }
            // 兄弟でも、選んだ読みによっては同じ接頭辞になる（読み タ と タン など）ので、それも飛ばす
            while self.moveToNextSibling() {
                if self.characters.count < deadLength || !self.characters.starts(with: deadPrefix) {
                    return true
                }
            }
            return false
        }
        if !self.started {
            self.started = true
            return self.descend()
        }
        if self.descend() {
            return true
        }
        return self.moveToNextSibling()
    }

    /// 今の節点の最初の子へ進む
    private mutating func descend() -> Bool {
        let depth = self.path.count
        guard depth < self.options.count, !self.options[depth].isEmpty else {
            return false
        }
        self.push(optionIndex: 0)
        return true
    }

    /// 今の節点の次の兄弟へ進む。兄弟がなければ親の兄弟へ
    private mutating func moveToNextSibling() -> Bool {
        while let last = self.path.last {
            let depth = self.path.count - 1
            self.pop()
            if last + 1 < self.options[depth].count {
                self.push(optionIndex: last + 1)
                return true
            }
        }
        return false
    }

    private mutating func push(optionIndex: Int) {
        let depth = self.path.count
        let option = self.options[depth][optionIndex]
        self.path.append(optionIndex)
        self.lengthBefore.append(self.characters.count)
        self.constraintCountBefore.append(self.constraints.count)
        if let kanji = option.kanji {
            self.constraints.append(MazegakiConstraint(kanji: kanji, rubyRange: self.characters.count ..< self.characters.count + option.characters.count))
        }
        self.characters.append(contentsOf: option.characters)
        self.penalties.append((self.penalties.last ?? 0) + option.penalty)
    }

    private mutating func pop() {
        self.path.removeLast()
        self.characters.removeSubrange(self.lengthBefore.removeLast()...)
        self.constraints.removeSubrange(self.constraintCountBefore.removeLast()...)
        self.penalties.removeLast()
    }
}
