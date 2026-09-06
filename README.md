# たられば投資

過去の一括投資を、同じ元本・同じ期間で比較するSwiftUIアプリです。**eMAXIS Slim 全世界株式（オール・カントリー）と米国株式（S&P500）の公式データ**を使用します。広告・課金・ログインはありません。

## 起動

Xcode 26.6 / Swift 6.3.3で開発。Swift 5言語モード、最低対応iOS 26.0。外部Swiftパッケージは不要です。

```sh
open ios/TararebaToushi.xcodeproj
```

`TararebaToushi` スキームでiPhoneシミュレーターを選び、Cmd+R。価格データは同梱していないため、初回はインターネット接続が必要です。Cloudflareから取得したデータを端末に保存し、以後はオフラインでも比較できます。共通の比較開始日は2018-10-31以降です。

## 構成

```text
ios/TararebaToushi/
  App/                 配信URL・モード・更新間隔・金額上限
  Models/              JSONの型
  Domain/              厳格な日付・共通日解決・Decimalによる計算
  Data/                HTTP取得・検証・キャッシュ・更新
  Features/            比較カード・グラフ・説明画面
ios/TararebaToushiTests/    計算・データ・通信・保存の自動テスト
ios/TararebaToushiUITests/  初回取得・再試行・オフライン利用・画面操作
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

Swift Testingで固定フィクスチャ、URLProtocolでHTTP応答、差し替え可能な保存先・時計・通信で更新を検証します。UIテストはDebugの `--ui-testing` を使い、テストランナーから架空の応答を渡します。保存先と入力設定はテスト単位で隔離し、テスト用の価格データはアプリ本体に含めません。Xcodeの共有スキームに両テストターゲットを登録済みです。

Releaseの確認には新しいDerivedDataディレクトリを指定し、過去のビルドに残ったリソースの混入を避けます。リポジトリルートで次を実行してください。

```sh
xcodebuild -project ios/TararebaToushi.xcodeproj \
  -scheme TararebaToushi -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/TararebaReleaseVerification build
npm --prefix tarareba-data run verify:app -- \
  /tmp/TararebaReleaseVerification/Build/Products/Release-iphonesimulator/TararebaToushi.app
```

`verify:app` は完成した `.app` 内のJSON・JSONC・CSVを検出すると失敗します。

## 操作と採用した判断

- 金額は1円〜10億円、初期値100万円。全角数字・カンマを受け付け、編集中は強制整形しません。無効入力では古い結果を消します。
- 初期開始日は2025年1月1日。履歴範囲外の指定日は自動変更せず、利用可能な範囲を案内します。
- 「1・3・5年前」は端末の今日ではなく、データの共通終了日から計算します。
- 日付はグレゴリオ暦・東京時間で固定。存在する共通日だけを使い、休日や欠測値を補間しません。
- 金額はDecimal、表示時に四捨五入。損益・差額は丸めた評価額から求めます。グラフ描画時のみDoubleへ変換します。
- 通常起動では実データと出典を表示します。説明画面に正式商品名、公式商品ページへのリンク、基準日、計算の前提を記載しています。開発用サンプルを選んだ場合は各所にサンプルと表示します。

## データ更新

`App/AppConfiguration.swift` に配信元とモードを集約しています。通常は `live/manifest.json`、開発用サンプルは `sample/manifest.json` です。起動・復帰時、前回の確認成功から6時間以上経過していれば確認し、手動更新は間隔を無視します。同じ版では履歴を再取得しません。

2商品すべてを検証し、Application Supportの単一スナップショットをatomic書き込みしてから画面を切り替えます。初回取得に失敗した場合は比較結果を表示せず、「データを更新」で再試行できます。取得後の更新失敗では保存済みデータを保持します。ファイル名は配信URL・モード・スキーマのハッシュ、内部には版を含みます。配信元やモードの異なるキャッシュは混在しません。取得日時と更新確認成功日時を別に保持します。以前の開発版で同梱データから作ったキャッシュは採用せず、初回と同じようにダウンロードします。

配信側の更新は `tarareba-data/` で `npm run fetch:mufg`。公式CSVの分配金再投資系列を採用し、最新日と基準価額を公式APIと照合して、`public/live/` の配信用JSONを生成します。サンプル生成も含め、iOS側にはデータファイルを書き込みません。取得・形式・照合のエラーでは既存データを保持します。定期収集は設定していないため、アプリの更新ボタンだけでは配信元の履歴は新しくなりません。

## 公開と残る確認

2026-09-06にCloudflareへ公開しました。[実データの一覧](https://tarareba-data.hibiki-apps.workers.dev/live/manifest.json) と2商品の履歴がHTTP 200で取得でき、内容とキャッシュ設定も確認済みです。アプリの「データを更新」で公開版を確認できます。実機確認と定期更新の自動化は別工程です。

更新・公開手順は [配信用README](tarareba-data/README.md)、取得元と系列の説明は [公式データの取り込み](docs/mufg-data.md) を参照してください。

検証結果と手動確認項目は [検証メモ](docs/validation.md) に記録します。
