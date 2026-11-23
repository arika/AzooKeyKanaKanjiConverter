// swift-tools-version: 6.1
// 交ぜ書き変換のベンチマーク（フォーク専用。upstream への PR には含めない）
//
// 実行（このディレクトリで）:
//   python3 -I scripts/kanjidic2tsv.py <kanjidic2.xml.gz> data/kanji_readings.tsv   # 初回のみ
//   swift run -c release mazegaki-bench                    # 素通し（既存の挙動）
//   swift run -c release mazegaki-bench --expand           # 外付け展開方式（事前検証の方式）
//   swift run -c release mazegaki-bench --zenzai ...       # Zenzai 併用（models/ に gguf を置く）
//
// エンジン組み込み版（--mazegaki）は、plans/mazegaki.md の PR2 で追加する。

import PackageDescription

let package = Package(
    name: "mazegaki-bench",
    platforms: [.macOS(.v13)],
    dependencies: [
        // フォーク本体（2 階層上）を参照する。パッケージ名はディレクトリ名で決まるので、
        // フォークは既定の名前（AzooKeyKanaKanjiConverter）のディレクトリに clone しておくこと。
        // 事前検証では、Zenzai の GPU 版（"Zenzai"）が macOS 27 の Metal で落ちたため、CPU 版にしている
        .package(path: "../..", traits: ["ZenzaiCPU"])
    ],
    targets: [
        .executableTarget(
            name: "mazegaki-bench",
            dependencies: [
                .product(name: "KanaKanjiConverterModuleWithDefaultDictionary", package: "AzooKeyKanaKanjiConverter")
            ],
            swiftSettings: [.interoperabilityMode(.Cxx)]
        )
    ]
)
