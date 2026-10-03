# たられば投資

選んだ投資信託へそれぞれ同じ金額を一括投資・毎月積立していた場合の結果を比較するSwiftUIアプリです。三菱UFJアセットマネジメントの公式データを使用し、**オルカン・S&P500などの株式9商品、国内・先進国の債券2商品、国内REIT、8資産バランス、純金の計14商品**を収録しています。商品名・取得元は [取得対象一覧](docs/mufg-data.md#取得対象) を参照してください。広告・課金・ログインはありません。

## 起動

Xcode 26.6 / Swift 6.3.3で開発。Swift 5言語モード、最低対応iOS 26.0。外部Swiftパッケージは不要です。

```sh
open ios/TararebaToushi.xcodeproj
```

`TararebaToushi` スキームでiPhoneシミュレーターを選び、Cmd+R。価格データは同梱していないため、初回はインターネット接続が必要です。Cloudflareから取得したデータを端末に保存し、以後はオフラインでも比較できます。比較できる期間は選んだ商品によって決まり、オルカンとS&P500は2018-10-31以降、インド株を含む場合は2024-02-22以降です。商品の追加は配信データを公開するとアプリへ反映されます。

## 構成

```text
ios/TararebaToushi/
  App/                 配信URL・モード・更新間隔・金額上限
  Models/              JSONの型
  Domain/              厳格な日付・共通日解決・Decimalによる計算
  Data/                HTTP取得・検証・キャッシュ・更新
  Features/            シミュレーション結果・説明画面
ios/TararebaToushiTests/    計算・データ・通信・保存の自動テスト
ios/TararebaToushiUITests/  初回取得・再試行・オフライン利用・画面操作
tarareba-data/             公式API取得、生成・検証スクリプトと配信用JSON
.github/workflows/        GitHub Actionsによる日次更新
docs/data-format.md        JSONの契約と計算ルール
docs/mufg-data.md          取得元・商品の識別・系列の意味
docs/data-updates.md       日次更新の有効化と運用手順
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

- 比較する投資信託をチェックし、開始日と投資金額を入力して比較ボタンを押すと結果画面へ進みます。既定は2商品とも選択済みで、同時に比較できるのは8商品まで、最低1商品です。選択は保存し、次回起動時に復元します。1商品だけのときは差額カードを出さず、3商品以上では順位と最大差を表示します。それぞれの商品に入力金額を全額投資した場合の増減額・投資後の金額・商品間の差額を表示します。「条件を変更する」または戻る操作で、入力値を保ったまま入力画面へ戻れます。
- 結果は配信一覧の順です。iPhoneでは縦並び、十分な幅のあるiPadでは横並びにします。アクセシビリティの文字サイズではiPadも縦並びになります。シミュレーションに成功したときに開始日・金額を保存し、再起動後も復元します。以前の商品選択を含む保存データからも開始日・金額を引き継ぎます。
- 金額は1円〜10億円、初期値100万円。全角数字・カンマを受け付け、編集中は強制整形しません。入力チェックと計算はボタンを押したときに行い、無効入力では入力画面にエラーを表示します。
- 初期開始日は2025年1月1日。履歴範囲外の指定日は自動変更せず、利用可能な範囲を案内します。
- 終了日はデータの共通終了日を使用します。差額はこの期間でどちらの評価額が多かったかを説明し、同額の場合はその旨を表示します。期間プリセットと損益率は画面に表示しません。
- 結果の最後に評価額の折れ線グラフを置きます。元本を点線で示し、系列は色だけで見分けます（線種は変えません）。グラフをなぞるか前後ボタンで観測日を選ぶと、その日の評価額を全商品ぶん一覧で表示し、この一覧が凡例を兼ねます。縦軸は0起点で、共通の観測日だけを結びます。描画点は最大600点へ間引きますが、山と谷は各区間の最大・最小として残し、一覧に出す金額は間引く前の系列から読みます。
- 日付はグレゴリオ暦・東京時間で固定。存在する共通日だけを使い、休日や欠測値を補間しません。共通日は**選択した商品だけ**で求めます。履歴の短い商品を選んでいなければ、その商品は比較期間に影響しません。
- 金額はDecimal、表示時に四捨五入。損益・差額は丸めた評価額から求めます。グラフ描画時のみDoubleへ変換します。
- 右上の情報ボタンから、出典、基準日、計算の前提、データ更新を確認できます。通常起動では実データを使用し、開発用サンプルを選んだ場合は入力・結果画面にサンプルと表示します。

## データ更新

`App/AppConfiguration.swift` に配信元とモードを集約しています。通常は `live/manifest.json`、開発用サンプルは `sample/manifest.json` です。起動・復帰時、前回の確認成功から6時間以上経過していれば確認し、手動更新は間隔を無視します。旧形式の実データが端末に残っている場合は6時間を待たずに確認し、通常基準価額の新版へ更新します。実データは商品ごとの固定URL `live/funds/<商品ID>.json` を使い、一覧の `contentVersion` が変わった商品の履歴だけを取得します。一覧全体が同じ場合は履歴を取得しません。配信の切り替え中に一覧と履歴の更新情報が一致しなければ、一覧から1回再確認し、揃わなければ保存データを保持します。

2商品すべてを検証し、Application Supportの単一スナップショットをatomic書き込みしてから、シミュレーションで利用できるようにします。初回取得に失敗した場合は「2つを比較する」を無効にし、入力画面の「再試行」から取得し直せます。データ取得や更新だけでは結果画面へ進みません。取得後の更新失敗では保存済みデータを保持します。保存ファイル名は配信URL・モード・保存形式のハッシュです。配信形式の変更後も旧アプリで取得した正常なキャッシュを読み込めます。配信元やモードの異なるキャッシュは混在しません。取得日時と更新確認成功日時を別に保持します。以前の開発版で同梱データから作ったキャッシュは採用せず、初回と同じようにダウンロードします。

配信側の更新は `tarareba-data/` で `npm run fetch:mufg`。投信情報APIだけから日付・通常の基準価額を取得し、`public/live/` の商品別JSONと一覧を上書きします。実データの履歴ファイル数は更新回数によって増えません。保存済み最終日の翌日から不足分を日付指定APIで順に取得し、既存の過去日は再取得しません。分配金の受取額・再投資は計算に含めません。既存履歴は通常基準価額との一致を確認したうえで、通信せず移行済みです。サンプル生成も含め、iOS側にはデータファイルを書き込みません。取得・形式・照合のエラーでは既存データを保持します。

GitHub Actionsの日次更新を用意しています。毎朝7:17（日本時間）に取得・検証し、公開JSONと違う場合だけCloudflareへ公開します。生成データを先にGitに保存し、公開失敗後も次回に再試行できます。有効化にはワークフローのGitHubへの反映とCloudflare用のActions secrets登録が必要です。手順は [日次更新](docs/data-updates.md) を参照してください。アプリの更新確認は、配信側の取得・公開処理とは別です。

## 公開と残る確認

2026-10-03に14商品をCloudflareへ公開しました。公開版は `mufg-20261002-891f0e81accd`、全商品のデータ最終日は2026-10-02です。`schemaVersion: 2` の商品別固定URLで配信しています。

アプリは一覧から対応する商品を最大20商品まで取得・表示し、現在の配信用データには14商品を収録しています。商品名・説明・分類は配信一覧で管理するため、対応する種類の商品はアプリの更新なしで追加できます。追加時は公式コードの登録、設定来履歴の取り込み・検証と配信データの公開を行います。同時比較は8商品までです。

`npm run publish:verify` で、[実データの一覧](https://tarareba-data.hibiki-apps.workers.dev/live/manifest.json) と全14商品の履歴が検証済みJSONと完全一致することを確認しました。HTTP応答とキャッシュ設定も確認済みです。アプリの「データを更新」で追加4商品を取得できます。日次更新のスケジュールは現在無効で、今回の公開は手動で実施しました。

更新・公開手順は [配信用README](tarareba-data/README.md)、取得元と系列の説明は [公式データの取り込み](docs/mufg-data.md) を参照してください。

検証結果と手動確認項目は [検証メモ](docs/validation.md) に記録します。
