# たられば投資

過去の一括投資を、同じ元本・同じ期間で比較するSwiftUIアプリです。**eMAXIS Slim 全世界株式（オール・カントリー）と米国株式（S&P500）の公式データ**を使用します。広告・課金・ログインはありません。

## 起動

Xcode 26.6 / Swift 6.3.3で開発。Swift 5言語モード、最低対応iOS 26.0。外部Swiftパッケージは不要です。

```sh
open ios/TararebaToushi.xcodeproj
```

`TararebaToushi` スキームでiPhoneシミュレーターを選び、Cmd+R。取得済みの実データを同梱しているため、初回オフラインや配信先未配置でも比較できます。共通の比較開始日は2018-10-31以降です。

## 構成

```text
ios/TararebaToushi/
  App/                 配信URL・モード・更新間隔・金額上限
  Models/              JSONの型
  Domain/              厳格な日付・共通日解決・Decimalによる計算
  Data/                HTTP取得・検証・同梱データ・キャッシュ・更新
  Features/            比較カード・グラフ・説明画面
  Resources/           取得済み実データと開発用サンプル
ios/TararebaToushiTests/    計算・データ・通信・保存の自動テスト
ios/TararebaToushiUITests/  オフライン起動・入力・期間・説明画面
tarareba-data/             公式CSV・API取得、生成・検証スクリプトと配信用JSON
docs/data-format.md        JSONの契約と計算ルール
docs/mufg-data.md          取得元・商品の識別・系列の意味
```

ルートの既存 `AGENTS.md` は変更していません。その中のXcodeコマンドは `ios/` を作業ディレクトリにすると使用できます。

## ビルドとテスト

```sh
xcodebuild -project ios/TararebaToushi.xcodeproj \
  -scheme TararebaToushi -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/TararebaToushiDerivedData build

xcrun simctl list devices available
# 上で確認したiOS 26.0以上のSimulator UUIDを使用
xcodebuild -project ios/TararebaToushi.xcodeproj \
  -scheme TararebaToushi -destination 'platform=iOS Simulator,id=<UUID>' \
  -derivedDataPath /tmp/TararebaToushiDerivedData \
  -parallel-testing-enabled NO test

cd tarareba-data
npm run validate
npm test
```

Swift Testingで固定フィクスチャ、URLProtocolでHTTP応答、差し替え可能な保存先・時計・通信で更新を検証します。Debugの `--offline-sample` はサンプルを、`--offline-live` は同梱実データを使い、自動通信を止めます。UIテストは `--ui-testing` で通信とキャッシュを隔離します。Xcodeの共有スキームに両テストターゲットを登録済みです。

## 操作と採用した判断

- 金額は1円〜10億円、初期値100万円。全角数字・カンマを受け付け、編集中は強制整形しません。無効入力では古い結果を消します。
- 初期開始日は2025年1月1日。履歴範囲外の指定日は自動変更せず、利用可能な範囲を案内します。
- 「1・3・5年前」は端末の今日ではなく、データの共通終了日から計算します。
- 日付はグレゴリオ暦・東京時間で固定。存在する共通日だけを使い、休日や欠測値を補間しません。
- 金額はDecimal、表示時に四捨五入。損益・差額は丸めた評価額から求めます。グラフ描画時のみDoubleへ変換します。
- 通常起動では実データと出典を表示します。説明画面に正式商品名、公式商品ページへのリンク、基準日、計算の前提を記載しています。開発用サンプルを選んだ場合は各所にサンプルと表示します。

## データ更新

`App/AppConfiguration.swift` に配信元とモードを集約しています。通常は `live/manifest.json`、開発用サンプルは `sample/manifest.json` です。起動・復帰時、前回の確認成功から6時間以上経過していれば確認し、手動更新は間隔を無視します。同じ版では履歴を再取得しません。

2商品すべてを検証し、Application Supportの単一スナップショットをatomic書き込みしてから画面を切り替えます。ファイル名は配信URL・モード・スキーマのハッシュ、内部には版を含みます。別の配信元や実データモードのキャッシュは混在しません。取得日時と更新確認成功日時を別に保持し、同梱版とリモートmanifestが一致しただけの場合は「取得済み」と偽りません。

配信側の更新は `tarareba-data/` で `npm run fetch:mufg`。公式CSVの分配金再投資系列を採用し、最新日と基準価額を公式APIと照合して、配信用JSONと同梱実データを一緒に生成します。取得・形式・照合のエラーでは既存データを保持します。定期収集は設定していないため、アプリの更新ボタンだけでは配信元の履歴は新しくなりません。

## 公開と残る確認

実データを取得してローカルで利用できる状態です。Cloudflareへの公開と実機確認は別工程です。更新・公開手順は [配信用README](tarareba-data/README.md)、取得元と系列の説明は [公式データの取り込み](docs/mufg-data.md) を参照してください。

検証結果と手動確認項目は [検証メモ](docs/validation.md) に記録します。
