# たられば投資

過去の一括投資を、同じ元本・同じ期間で比較するSwiftUIアプリです。現在は**架空のサンプルデータのみ**を使用します。広告・課金・ログインはありません。

## 起動

Xcode 26.6 / Swift 6.3.3で開発。Swift 5言語モード、最低対応iOS 26.0。外部Swiftパッケージは不要です。

```sh
open ios/TararebaToushi.xcodeproj
```

`TararebaToushi` スキームでiPhoneシミュレーターを選び、Cmd+R。初回オフラインやサンプル未デプロイでも同梱データで操作できます。既存のBundle Identifier・Development Teamを維持しています。

## 構成

```text
ios/TararebaToushi/
  App/                 配信URL・モード・更新間隔・金額上限
  Models/              JSONの型
  Domain/              厳格な日付・共通日解決・Decimalによる計算
  Data/                HTTP取得・検証・同梱データ・キャッシュ・更新
  Features/            比較カード・グラフ・説明画面
  Resources/           自動生成した同梱サンプル
ios/TararebaToushiTests/    計算・データ・通信・保存の自動テスト
ios/TararebaToushiUITests/  オフライン起動・入力・期間・説明画面
tarareba-data/             生成・検証スクリプトと配信用JSON
docs/data-format.md        JSONの契約と計算ルール
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

Swift Testingで固定フィクスチャ、URLProtocolでHTTP応答、差し替え可能な保存先・時計・通信で更新を検証します。UIテストはDebugの起動引数 `--offline-sample` を使用します。Xcodeの共有スキームに両テストターゲットを登録済みです。

## 操作と採用した判断

- 金額は1円〜10億円、初期値100万円。全角数字・カンマを受け付け、編集中は強制整形しません。無効入力では古い結果を消します。
- 初期開始日は2025年1月1日。履歴範囲外の指定日は自動変更せず、利用可能な範囲を案内します。
- 「1・3・5年前」は端末の今日ではなく、データの共通終了日から計算します。
- 日付はグレゴリオ暦・東京時間で固定。存在する共通日だけを使い、休日や欠測値を補間しません。
- 金額はDecimal、表示時に四捨五入。損益・差額は丸めた評価額から求めます。グラフ描画時のみDoubleへ変換します。
- 画面上部、商品名、差額、説明画面でサンプルであることを明示します。出典は「開発用に生成した架空の比較データ」です。

## データ更新

`App/AppConfiguration.swift` に配信元と `sample/manifest.json` を集約しています。起動・復帰時、前回の確認成功から6時間以上経過していれば確認し、手動更新は間隔を無視します。同じ版では履歴を再取得しません。

2商品すべてを検証し、Application Supportの単一スナップショットをatomic書き込みしてから画面を切り替えます。ファイル名は配信URL・モード・スキーマのハッシュ、内部には版を含みます。別の配信元や実データモードのキャッシュは混在しません。取得日時と更新確認成功日時を別に保持し、同梱版とリモートmanifestが一致しただけの場合は「取得済み」と偽りません。

実データモードは将来用の境界のみです。実データの取得・正規化・分配金処理・配信は未実装で、サンプルへ黙って切り替えません。実データ提供元への問い合わせ回答を確認した後で対応します。

## 公開と残る確認

今回のサンプルのCloudflareへのデプロイ、実データの取得、実機確認は別工程です。配信準備と公開後の確認は [配信用README](tarareba-data/README.md) を参照してください。公開前でもCmd+Rでアプリを試せます。

検証結果と手動確認項目は [検証メモ](docs/validation.md) に記録します。
