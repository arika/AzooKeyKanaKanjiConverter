//
//  ConvertRequestOptions.swift
//  Keyboard
//
//  Created by ensan on 2022/12/20.
//  Copyright © 2022 ensan. All rights reserved.
//

public import Foundation

public struct ConvertRequestOptions: Sendable {
    public enum PredictionMode: Sendable, Equatable {
        case autoMix
        case manualMix
        case disabled

        var isEnabled: Bool {
            self != .disabled
        }

        var shouldMix: Bool {
            self == .autoMix
        }
    }

    /// 通常の変換リクエストで classic typo correction をどう扱うかの設定。
    public enum TypoCorrectionMode: Sendable, Equatable, Hashable {
        /// プラットフォーム既定に従います。
        case automatic
        /// classic typo correction を常に有効にします。
        case enabled
        /// typo correction を無効にします。
        case disabled
    }
    /// 変換リクエストに必要な設定データ
    ///
    /// - parameters:
    ///   - N_best: 変換候補の数。上位`N`件までの言語モデル上の妥当性を保証します。大きくすると計算量が増加します。
    ///   - requireJapanesePrediction: 日本語の予測変換候補の扱い。`.autoMix`は候補に混ぜ、`.manualMix`は`ConversionResult`に分離、`.disabled`は生成しません。
    ///   - requireEnglishPrediction: 英語の予測変換候補の扱い。`.autoMix`は候補に混ぜ、`.manualMix`は`ConversionResult`に分離、`.disabled`は生成しません。ローマ字入力を用いた日本語入力では`.disabled`にした方が良いでしょう。
    ///   - keyboardLanguage: キーボードの言語を指定します。
    ///   - englishCandidateInRoman2KanaInput: `true`の場合、日本語ローマ字入力時に英語変換候補を出力します。`false`の場合、ローマ字入力時に英語変換候補を出力しません。
    ///   - fullWidthRomanCandidate: `true`の場合、全角英数字の変換候補が出力に含まれるようになります。
    ///   - halfWidthKanaCandidate: `true`の場合、半角カナの変換候補が出力に含まれるようになります。
    ///   - learningType: 学習モードを指定します。詳しくは`LearningType`を参照してください。
    ///   - maxMemoryCount: 学習が有効な場合に保持するデータの最大数を指定します。`0`の場合`learningType`を`nothing`に指定する方が適切です。
    ///   - shouldResetMemory: `true`の場合、変換を開始する前に学習データをリセットします。
    ///   - dictionaryResourceURL: 内蔵辞書データの読み出し先を指定します。
    ///   - memoryDirectoryURL: 学習データの保存先を指定します。書き込み可能なディレクトリを指定してください。
    ///   - sharedContainerURL: ユーザ辞書など、キーボード外で書き込んだ設定データの保存されているディレクトリを指定します。
    ///   - textReplacer: 予測変換のための置換機を指定します。
    ///   - specialCandidateProviders: 特殊変換を実施する変換関数を挿入します
    ///   - experimentalZenzaiPredictiveInput: Zenzai の予測入力フォールバックを有効にします（experimental）。
    ///   - typoCorrectionMode: 通常の変換リクエストで classic typo correction をどう扱うかを指定します。
    ///   - mazegakiMode: 交ぜ書き変換（漢字とかなが混在した入力の変換）の設定です。詳しくは`ConvertRequestOptions.MazegakiMode`を参照してください。
    ///   - metadata: メタデータを指定します。詳しくは`ConvertRequestOptions.Metadata`を参照してください。
    public init(N_best: Int = 10, requireJapanesePrediction: PredictionMode, requireEnglishPrediction: PredictionMode, keyboardLanguage: KeyboardLanguage, englishCandidateInRoman2KanaInput: Bool = false, fullWidthRomanCandidate: Bool = false, halfWidthKanaCandidate: Bool = false, learningType: LearningType, maxMemoryCount: Int = 65536, shouldResetMemory: Bool = false, memoryDirectoryURL: URL, sharedContainerURL: URL, textReplacer: TextReplacer, specialCandidateProviders: [any SpecialCandidateProvider]?, zenzaiMode: ZenzaiMode = .off, preloadDictionary: Bool = false, experimentalZenzaiPredictiveInput: Bool = false, typoCorrectionMode: TypoCorrectionMode = .automatic, mazegakiMode: MazegakiMode = .off, metadata: ConvertRequestOptions.Metadata?) {
        self.N_best = N_best
        self.requireJapanesePrediction = requireJapanesePrediction
        self.requireEnglishPrediction = requireEnglishPrediction
        self.keyboardLanguage = keyboardLanguage
        self.englishCandidateInRoman2KanaInput = englishCandidateInRoman2KanaInput
        self.fullWidthRomanCandidate = fullWidthRomanCandidate
        self.halfWidthKanaCandidate = halfWidthKanaCandidate
        self.learningType = learningType
        self.maxMemoryCount = maxMemoryCount
        self.shouldResetMemory = shouldResetMemory
        self.memoryDirectoryURL = memoryDirectoryURL
        self.sharedContainerURL = sharedContainerURL
        self.metadata = metadata
        self.textReplacer = textReplacer
        self.specialCandidateProviders = specialCandidateProviders ?? KanaKanjiConverter.defaultSpecialCandidateProviders
        self.zenzaiMode = zenzaiMode
        self.preloadDictionary = preloadDictionary
        self.experimentalZenzaiPredictiveInput = experimentalZenzaiPredictiveInput
        self.typoCorrectionMode = typoCorrectionMode
        self.mazegakiMode = mazegakiMode

        if shouldResetMemory {
            print("Warning: Passing `shouldResetMemory: true` in `ConvertRequestOptions` is deprecated. Use `KanaKanjiConverter.resetMemory` instead.")
        }
    }

    public var N_best: Int
    public var requireJapanesePrediction: PredictionMode
    public var requireEnglishPrediction: PredictionMode
    public var keyboardLanguage: KeyboardLanguage
    // KeyboardSettingのinjection用途
    public var englishCandidateInRoman2KanaInput: Bool
    public var fullWidthRomanCandidate: Bool
    public var halfWidthKanaCandidate: Bool
    public var learningType: LearningType
    public var maxMemoryCount: Int
    public var shouldResetMemory: Bool
    /// 変換用
    public var textReplacer: TextReplacer
    // ディレクトリなど
    public var memoryDirectoryURL: URL
    public var sharedContainerURL: URL
    /// providers to generate "special" candidates such as Unicode conversion.
    public var specialCandidateProviders: [any SpecialCandidateProvider]
    public var zenzaiMode: ZenzaiMode
    public var preloadDictionary: Bool
    /// Enable experimental predictive input for Zenzai fallback candidates.
    public var experimentalZenzaiPredictiveInput: Bool
    /// 通常の変換リクエストで classic typo correction をどう扱うかの設定。
    public var typoCorrectionMode: TypoCorrectionMode
    /// 交ぜ書き変換の設定。
    public var mazegakiMode: MazegakiMode
    // メタデータ
    public var metadata: Metadata?

    // MARK: プライベートAPI
    package var requestQuery: RequestQuery = .default

    static var `default`: Self {
        Self(
            N_best: 10,
            requireJapanesePrediction: .autoMix,
            requireEnglishPrediction: .autoMix,
            keyboardLanguage: .ja_JP,
            englishCandidateInRoman2KanaInput: true,
            learningType: .inputAndOutput,
            maxMemoryCount: 65536,
            shouldResetMemory: false,
            // dummy data, won't work
            memoryDirectoryURL: (try? FileManager.default.url(for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: false)) ?? Bundle.main.bundleURL,
            // dummy data, won't work
            sharedContainerURL: Bundle.main.bundleURL,
            textReplacer: .empty,
            specialCandidateProviders: nil,
            preloadDictionary: false,
            metadata: nil
        )
    }

    public struct Metadata: Sendable {
        /// - parameters:
        ///   - appVersionString: アプリのバージョンを指定します。このデータは`KanaKanjiCovnerter.toVersionCandidate(_:)`などで用いられます。
        @available(*, deprecated, renamed: "init(versionString:)", message: "it be removed in AzooKeyKanaKanjiConverter v1.0")
        public init(appVersionString: String) {
            self.versionString = "azooKey Version " + appVersionString
        }

        /// - parameters:
        ///   - versionString: アプリのバージョンを示す文字列全体を`"MyIME Version 0.7.1"`のように指定します。このデータは`KanaKanjiCovnerter.toVersionCandidate(_:)`などで用いられます。
        public init(versionString: String = "Powererd by AzooKeyKanaKanjiConverter") {
            self.versionString = versionString
        }
        var versionString: String
    }

    package enum RequestQuery: Sendable {
        case `default`
        case 完全一致
    }

    public struct ZenzaiV2DependentMode: Sendable, Equatable, Hashable {
        public init(profile: String? = nil, leftSideContext: String? = nil, maxLeftSideContextLength: Int? = nil) {
            self.profile = profile
            self.leftSideContext = leftSideContext
            self.maxLeftSideContextLength = maxLeftSideContextLength
        }

        /// プロフィールコンテクストを設定した場合、プロフィールを反映したプロンプトが自動的に付与されます。プロフィールは10〜20文字程度の長さにとどめることを推奨します。
        public var profile: String?
        /// 左側の文字列を文脈として与えます。
        public var leftSideContext: String?
        /// 文脈の最大長を制約します
        public var maxLeftSideContextLength: Int?
    }

    public struct ZenzaiV3DependentMode: Sendable, Equatable, Hashable {
        public init(
            profile: String? = nil,
            topic: String? = nil,
            style: String? = nil,
            preference: String? = nil,
            leftSideContext: String? = nil,
            rightSideContext: String? = nil,
            maxLeftSideContextLength: Int? = nil,
            maxRightSideContextLength: Int? = nil,
            enableAlignmentSeparator: Bool = false
        ) {
            self.profile = profile
            self.topic = topic
            self.style = style
            self.preference = preference
            self.leftSideContext = leftSideContext
            self.rightSideContext = rightSideContext
            self.maxLeftSideContextLength = maxLeftSideContextLength
            self.maxRightSideContextLength = maxRightSideContextLength
            self.enableAlignmentSeparator = enableAlignmentSeparator
        }

        /// プロフィールコンテクストを設定した場合、プロフィールを反映したプロンプトが自動的に付与されます。プロフィールは10〜20文字程度の長さにとどめることを推奨します。
        public var profile: String?
        /// topicを設定した場合、話題にあった変換が自動的に優先されます。話題は10〜20文字程度の長さにとどめることを推奨します。
        public var topic: String?
        /// styleを設定した場合、文章のスタイルにあった変換が自動的に優先されます。スタイルは10〜20文字程度の長さにとどめることを推奨します。
        public var style: String?
        /// preferenceコンテクストを設定した場合、ユーザの書き方の好みに合わせた変換が自動的に優先されます。preferenceは10〜20文字程度の長さにとどめることを推奨します。
        public var preference: String?
        /// 左側の文字列を文脈として与えます。
        public var leftSideContext: String?
        /// 右側の文字列を文脈として与えます。
        public var rightSideContext: String?
        /// 左文脈の最大長を制約します
        public var maxLeftSideContextLength: Int?
        /// 右文脈の最大長を制約します
        public var maxRightSideContextLength: Int?
        /// カーソル位置に応じたalignment separatorをプロンプトと候補に挿入します。
        public var enableAlignmentSeparator: Bool
    }

    public enum ZenzaiVersionDependentMode: Sendable, Equatable, Hashable {
        case v2(ZenzaiV2DependentMode)
        case v3(ZenzaiV3DependentMode)
    }

    public struct ZenzaiMode: Sendable, Equatable {
        public struct PersonalizationMode: Sendable, Equatable {
            public init(baseNgramLanguageModel: String, personalNgramLanguageModel: String, n: Int = 5, d: Double = 0.75, alpha: Float = 0.5) {
                self.baseNgramLanguageModel = baseNgramLanguageModel
                self.personalNgramLanguageModel = personalNgramLanguageModel
                self.n = n
                self.d = d
                self.alpha = alpha
            }

            var n: Int = 5
            var d: Double = 0.75
            var alpha: Float = 0.5
            var baseNgramLanguageModel: String
            var personalNgramLanguageModel: String
        }
        public static let off = ZenzaiMode(
            enabled: false,
            weightURL: URL(fileURLWithPath: ""),
            inferenceLimit: 10,
            requestRichCandidates: false,
            versionDependentMode: .v3(.init())
        )

        /// activate *Zenzai* - Neural Kana-Kanji Conversiion Engine
        /// - Parameters:
        ///    - weight: path for model weight (gguf)
        ///    - inferenceLimit: applying inference count limitation. Smaller limit makes conversion faster but quality will be worse. (Default: 10)
        ///    - requestRichCandidates: when this flag is true, the converter spends more time but generate richer N-Best candidates for candidate list view. Usually this option is not recommended for live conversion.
        ///    - personalizationMode: values for personalization.
        ///    - versionDependentMode: specify zenz model version and its configuration.
        public static func on(weight: URL, inferenceLimit: Int = 10, requestRichCandidates: Bool = false, personalizationMode: PersonalizationMode?, versionDependentMode: ZenzaiVersionDependentMode = .v3(.init())) -> Self {
            ZenzaiMode(
                enabled: true,
                weightURL: weight,
                inferenceLimit: inferenceLimit,
                requestRichCandidates: requestRichCandidates,
                personalizationMode: personalizationMode,
                versionDependentMode: versionDependentMode
            )
        }
        var enabled: Bool
        var weightURL: URL
        var inferenceLimit: Int
        var requestRichCandidates: Bool
        var personalizationMode: PersonalizationMode?
        var versionDependentMode: ZenzaiVersionDependentMode
    }

    /// 交ぜ書き変換（`convertTarget`に漢字とかなが混在した入力の変換）の設定。
    ///
    /// 有効にすると、入力に含まれる漢字を読み表の読みに展開して辞書を引き、入力した漢字を保ったまま変換します。
    /// 漢字の読み表はライブラリに同梱されないため、利用者が用意したファイルを指定します。形式は`Docs/converter_api.md`を参照してください。
    public struct MazegakiMode: Sendable, Equatable, Hashable {
        /// 交ぜ書き変換を無効にします（既定）。
        public static let off = MazegakiMode(
            enabled: false,
            readingTableURL: URL(fileURLWithPath: ""),
            maxReadingsPerKanji: 0
        )

        /// 交ぜ書き変換を有効にします。
        /// - Parameters:
        ///    - readingTableURL: 漢字の読み表のファイルの URL。読み込めない場合は`.off`と同じに動作します。
        ///    - maxReadingsPerKanji: 読み表から使う読みの数の上限（1 字あたり、表の先頭から数えます）。促音化・連濁などライブラリが派生させる読みはこの数に含めません。負の値は`0`として扱います。(Default: 8)
        public static func on(readingTableURL: URL, maxReadingsPerKanji: Int = 8) -> Self {
            MazegakiMode(
                enabled: true,
                readingTableURL: readingTableURL,
                maxReadingsPerKanji: max(0, maxReadingsPerKanji)
            )
        }

        var enabled: Bool
        var readingTableURL: URL
        var maxReadingsPerKanji: Int
    }
}
