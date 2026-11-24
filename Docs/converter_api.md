#  KanaKanjiConverter API

KanaKanjiConverterの主要APIを示します。以下の例ではデフォルト辞書版を利用しています。

```swift
import KanaKanjiConverterModuleWithDefaultDictionary
let converter = KanaKanjiConverter.withDefaultDictionary()
```
なお、`KanaKanjiConverter.withDefaultDictionary(preloadDictionary: true)`とすることでメモリを大きく消費する代わりに辞書データをすべて読み込んだ状態になります。
## `setKeyboardLanguage(_:)`

これから入力しようとしている言語を設定します。このAPIは日本語/英語をサポートするアプリケーションでは必須です。
なお、AzooKeyKanaKanjiConverterは通常デフォルトで日本語の設定となっています。英語入力への切り替えの際、ユーザの入力より先にこの関数を呼び出すことでデータがプリロードされ、応答性が向上する可能性があります。

## 辞書・学習関連のAPI

### `importDynamicUserDictionary(_:shortcuts:)`
動的ユーザ辞書と動的ショートカットを登録します。`DicdataElement` の配列を直接渡します。

```swift
converter.importDynamicUserDictionary(
    [
        DicdataElement(word: "anco", ruby: "アンコ", cid: 1288, mid: 501, value: -5),
    ],
    shortcuts: [
        DicdataElement(word: "ありがとうございます", ruby: "アザス", cid: 1288, mid: 501, value: -5),
    ]
)
```
`ruby` はカタカナで指定してください。`value` は `-5`〜`-10` 程度が目安です。`shortcuts` は全文一致ショートカット用の語彙を登録します（省略可能）。

### `updateUserDictionaryURL(_:)`
ユーザ辞書（`user.louds*` 等）が置かれているディレクトリURLを更新します。

```swift
converter.updateUserDictionaryURL(documents)
```

### `updateLearningConfig(_:)`
学習設定を更新します。

```swift
converter.updateLearningConfig(
    LearningConfig(learningType: .inputAndOutput, maxMemoryCount: 65536, memoryURL: documents)
)
```

### `updateLearningData(_:)`, `commitUpdateLearningData()`, `resetMemory()`
確定候補に基づく学習データを反映・保存・リセットします。

```swift
converter.updateLearningData(candidate)
converter.commitUpdateLearningData()   // 永続化
// 全学習のリセット
converter.resetMemory()
```

### `stopComposition()`
内部状態のキャッシュをリセットします。入力の区切りで呼ぶと安定します。

## 変換オプション

### `mazegakiMode`（交ぜ書き変換）

`ConvertRequestOptions` の `mazegakiMode` で、交ぜ書き変換（`convertTarget` に漢字とかなが混在した入力の変換）を設定します。既定値は `.off` です。

```swift
let options = ConvertRequestOptions(
    // ...
    mazegakiMode: .on(readingTableURL: readingTableURL, maxReadingsPerKanji: 8),
    metadata: .init(versionString: "Your App Version X")
)
```

* `readingTableURL` には漢字の読み表のファイルを指定します。読み表はライブラリに同梱されていないので、利用する側で用意してください。読み込めない場合は `.off` と同じに動作します。
* `maxReadingsPerKanji` は、読み表から使う読みの数の上限（1 字あたり、表の先頭から数えます）です。ライブラリが派生させる読み（下記）はこの数に含めません。
* 読み表は設定ごとに 1 回だけ読み込まれます。ファイルを更新した場合は、URL を変えるなどして設定を変更してください。
* 有効にすると、入力に含まれる漢字を読みに展開して辞書を引き、入力した漢字がその読みの位置に現れる語だけを候補にします（例: 「破たん」→「破綻」、「機のう」→「機能」。「帰納」「昨日」は出しません）。仕組みは[conversion_algorithms.md](./conversion_algorithms.md)の「交ぜ書き変換」を参照してください。
* 入力した漢字が消える候補や、別の字に置き換わる候補は出しません。「同じ字」は Unicode の正準等価で判定します。例えば`神`（U+795E）と CJK 互換漢字の`神`（U+FA19）は同じ字とみなし、`桜`と`櫻`のような正準等価でない異体字は別の字として扱います。異体字セレクタ付きの字は、セレクタなしの字とは別の字として扱い、読みに展開しません。
* 予測変換を候補に混ぜる設定（`requireJapanesePrediction: .autoMix`）でも、入力に漢字を含む場合は、入力全体を変換した最良の候補を先頭に置き、予測変換の候補はその後に並べます（「けん引」の先頭は「牽引」で、「牽引車」はその後）。
* 入力に漢字を含まない場合、変換結果は`.off`と同じです。

#### 読み表の形式

UTF-8 のテキストで、1 行に 1 字を書きます。

```
# 行頭が # の行と空行は無視します
漢字<TAB>読み1,読み2,…
```

```
学	ガク,マナ.ブ
通	ツウ,ツ,トオ.ル,カヨ.ウ
落	ラク,オ.チル,オ.トス
```

* 読みはカタカナで、優先度の高い順に並べます。ひらがなはカタカナとして扱います。
* `.` より後ろは送り仮名です。`-`（接頭・接尾の印）は無視します。
* カタカナ以外の文字を含む読みと、見出しが 1 字でない行は無視します。同じ字の行が複数ある場合は、読みを順に連結します。
* 表にない字は読みに展開せず、従来どおりそのまま扱います。

#### ライブラリが派生させる読み

読み表の各読みから、次の読みを派生させます。派生させた読みには、語幹の読みより大きいペナルティを付けます。

| 由来 | 規則 | 例 |
|---|---|---|
| 語幹 | 送り仮名を除いた読み | 通（トオ.ル）→ トオ |
| 促音化 | 2 字以上で末尾がキ・ク・チ・ツの読みの末尾をッにする | 学（ガク）→ ガッ |
| 連濁 | 先頭の清音を濁音・半濁音にする | 社（シャ）→ ジャ、発（ハツ）→ バツ・パツ |
| 連用形 | 送り仮名が「イ段・エ段＋ル」（2 字以上）で終わるものはルを落とす。ウ段で終わるものは末尾をイ段にする。それ以外（形容詞など）は作らない | 落（オ.チル）→ オチ、通（トオ.ル）→ トオリ |
| 連用形の連濁 | 連用形の先頭の清音を濁音・半濁音にする | 通（トオ.ル）→ ドオリ |
