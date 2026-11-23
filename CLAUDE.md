# CLAUDE.md — AzooKeyKanaKanjiConverter 交ぜ書きフォーク

このリポジトリは [AzooKeyKanaKanjiConverter](https://github.com/azooKey/AzooKeyKanaKanjiConverter) のフォークである。
**交ぜ書き変換**（`convertTarget` に漢字とかなが混在した入力の変換）を実装し、最終的に upstream へ提案することを目指す。

- 提案文書（upstream 向け）: `Docs/Visions/mazegaki.md`
- 作業計画（フォーク内部用）: `plans/mazegaki.md`

作業を始める前に、両方を読むこと。

## 最重要の原則

1. **クライアントに依存しない。** この機能は azooKey on macOS 専用ではない。
   iOS 版 azooKey、fcitx5-hazkey、azooKey-Windows、azoo-key-skkserv などの他のクライアントからも使える API にする。
   - API・コメント・テスト・ドキュメントに、特定クライアントの UI や設定を持ち込まない。
   - 「漢直」は動機の一例として書くのはよいが、API 名は `Mazegaki…` のような一般的な名前にする。
2. **既定では無効にする（`.off`）。** 無効のときは、変換結果も性能も upstream と同一でなければならない。
3. **データを同梱しない。** 漢字の読み表は API 経由で受け取る（URL またはプロトコル）。
   KANJIDIC2（CC BY-SA 4.0）由来のデータを、ライブラリ本体（`Sources/`）に入れない。
   テスト用の数十字程度の自作の小さな表は可。
   mazegaki-dic（ipadic 由来）は手元での分析・評価専用。その中身や、そこから抜き出したデータ（読みの組、評価セット）は、
   どのブランチにもコミットしない。コミットしてよいのは、分析をもとに書いた規則のコードとテストだけ。
4. **不変条件:** 交ぜ書きモードでは、入力した漢字が消える候補も、別の字に置き換わる候補も出さない。精度より優先する。
5. **変更してよい範囲は `plans/mazegaki.md` に書いた範囲に限る。**
   次のものに手を入れる必要が出たら、作業を止めて相談すること。
   - ラティスの最短経路探索
   - 辞書形式（LOUDS / loudstxt3）と辞書データ（サブモジュール）
   - 学習データの形式

## ブランチと PR

- `main`: upstream の main を追従するだけ。ここに直接コミットしない。
- `mazegaki`: 公開用の統合ブランチ。Desktop のフォークはこのブランチの commit を参照する。
- `pr/N-…`: upstream に出す PR の単位のブランチ。後の PR は前の PR に依存するので、積み重ねて切る。

  | ブランチ | 分岐元 | 内容 |
  |---|---|---|
  | `pr/1-mazegaki-api` | upstream の main（`plans/mazegaki.md` の「前提」の revision） | API と読み表 |
  | `pr/2-mazegaki-lookup` | `pr/1-mazegaki-api` | 辞書引きへの組み込み |
  | `pr/3-mazegaki-ruby` | `pr/2-mazegaki-lookup` | ruby の前提の解消 |
  | `pr/4-mazegaki-zenzai` | `pr/3-mazegaki-ruby` | Zenzai |

  - 前の PR ブランチを修正したら、後のブランチを rebase する。
  - 次のフォーク専用ファイルは含めない: `CLAUDE.md`、`plans/`、`Tools/mazegaki-bench/`。
  - `Docs/Visions/mazegaki.md` は、PR に含めるか、Issue に貼るかを利用者が判断する。
- フォーク専用ファイルの変更（ベンチの機能追加、計画の更新）は、`mazegaki` に直接コミットする。
- **ベンチは `mazegaki` 上で実行する。** PR ブランチにはベンチが無いので、計測するときは次のようにする。
  1. PR ブランチを `mazegaki` に merge する。
  2. `mazegaki` 上でベンチを実行する。
  3. 直す必要があれば PR ブランチで直し、もう一度 merge する。
- コミットは 1 つの論点ごとに分ける。フォーク専用ファイルの変更と、ライブラリの変更を同じコミットに混ぜない
  （cherry-pick で PR ブランチに移せるようにするため）。
- upstream に PR を作る・Issue を立てる・コメントする操作は、**必ず利用者の指示を待つ**。勝手に行わない。

## ビルド・テスト

```bash
swift build
swift test                                  # 既存テストが全部通ること
swift build -c release

# 交ぜ書きベンチマーク（フォーク専用。Tools/mazegaki-bench で実行）
cd Tools/mazegaki-bench
swift run -c release mazegaki-bench                     # 素通し（既存の挙動）
swift run -c release mazegaki-bench --expand            # 外付け展開方式（比較基準）
swift run -c release mazegaki-bench --mazegaki          # エンジン組み込み版（PR2 で追加）
```

- debug ビルドでは `debug()` のログが大量に出るので、計測は必ず release で行う。
- 性能を比べるときは、同じマシン・同じビルド設定で、変更前と変更後を連続して計測する。

## コーディング

- 既存のスタイルに合わせる（`Sendable`、`package` アクセスレベル、`debug()` によるログなど）。
- 公開 API を追加したら `Docs/converter_api.md` に追記する。
  アルゴリズムを追加したら `Docs/conversion_algorithms.md` に追記する。
- 行番号は信用しない。関数名・型名で検索して、現在の場所を確かめること。

## 報告の形式

作業の区切りごとに、次の内容をまとめて報告する。

- 変更したファイルと、その要約。どの PR ブランチに入る予定の変更か。
- `swift test` の結果
- ベンチマークの結果（1 位 / 5 位以内 / 圏外 / 平均時間・最大時間）。直前の結果との差分も示す。
- 不変条件「入力した漢字の消失 0 件」の確認結果
- `.off` のときに upstream と差がないことの確認結果
- 未確認の事項、判断を保留した事項
