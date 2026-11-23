import Foundation
import SwiftUtils

/// 交ぜ書き変換の読み表を、`MazegakiMode`ごとに 1 回だけ読み込んで保持する
///
/// 読み込みに失敗した場合も結果（`nil`）を保持し、同じ設定で再び読み込みを試みない。設定が変わったときだけ読み込み直す。
package final class MazegakiReadingTableCache {
    package init() {}

    private var key: ConvertRequestOptions.MazegakiMode?
    private var table: MazegakiReadingTable?

    /// 設定に対応する読み表を返す。交ぜ書き変換が無効の場合と、読み表を読み込めない場合は`nil`。
    package func table(for mode: ConvertRequestOptions.MazegakiMode) -> MazegakiReadingTable? {
        guard mode.enabled else {
            return nil
        }
        if self.key == mode {
            return self.table
        }
        self.key = mode
        do {
            let table = try MazegakiReadingTable(contentsOf: mode.readingTableURL, maxReadingsPerKanji: mode.maxReadingsPerKanji)
            debug("MazegakiReadingTableCache: loaded \(table.count) kanji from \(mode.readingTableURL.absoluteString)")
            self.table = table
        } catch {
            debug("MazegakiReadingTableCache: failed to load \(mode.readingTableURL.absoluteString): \(error.localizedDescription)")
            self.table = nil
        }
        return self.table
    }
}
