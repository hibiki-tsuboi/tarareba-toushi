# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

「たられば投資」＝複数の投資信託に同額を一括投資していた場合を比較するiOSアプリと、その価格データを配信するCloudflare Workersの2つで構成されたリポジトリです。現在の配信商品はオルカン・S&P500・TOPIX・NASDAQ100・日経平均・純金・新興国株・ナノテク・遺伝子工学・先進国債券の10本で、同時比較は8商品まで・既定は先頭2商品です。ドキュメント・コミットメッセージ・UI文言・エラーメッセージはすべて日本語で書きます。

## 構成

| ディレクトリ | 中身 |
|---|---|
| `ios/` | SwiftUIアプリ（Xcode 26.6 / Swift 5言語モード / iOS 26.0+ / 外部パッケージなし） |
| `tarareba-data/` | 公式API取得・JSON検証・サンプル生成・Cloudflare配信（Node.js 22+、依存はwranglerのみ） |
| `docs/` | データ契約・取得元・日次更新・検証メモ |
| `.github/workflows/update-fund-data.yml` | 毎朝7:17 JSTの取得〜公開ジョブ |

ルートの `AGENTS.md` はXcode移動前に書かれたもので、その中のパスは `ios/` を作業ディレクトリにした場合のものとして読みます。

## コマンド

### iOSアプリ（リポジトリルートで実行）

```sh
xcodebuild -project ios/TararebaToushi.xcodeproj \
  -scheme TararebaToushi -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/TararebaToushiDerivedData build

xcrun simctl list devices available   # iOS 26.0以上のUUIDを確認
xcodebuild -project ios/TararebaToushi.xcodeproj \
  -scheme TararebaToushi -destination 'platform=iOS Simulator,id=<UUID>' \
  -derivedDataPath /tmp/TararebaToushiDerivedData \
  -parallel-testing-enabled NO test
```

テストは `generic/platform=iOS Simulator` では実行できず、具体的なSimulator UUIDが必要です。単体で走らせる場合は `-only-testing` を追加します。

```sh
-only-testing:TararebaToushiTests                                    # ターゲット全体
-only-testing:TararebaToushiTests/SimulationTests                    # スイート
-only-testing:TararebaToushiTests/SimulationTests/expectedReturnsAndDifference
```

スキームには単体テストとUIテストの両方が登録されているので、`-only-testing` を付けない `test` はUIテストまで走ります。`PublishedDataUITests` は実際にCloudflareへ通信する任意の確認で、期待する版・条件・評価額を `TEST_RUNNER_TARAREBA_PUBLISHED_EXPECTATION`（`TEST_RUNNER_` 接頭辞がないとテストランナーへ渡りません）で指定したときだけ実行され、通常はスキップされます。実例は `docs/validation.md` にあります。

Release確認は必ず**新しいDerivedData**を指定し、続けて同梱物を検査します（過去ビルドの残留リソース混入を防ぐため）。

```sh
xcodebuild -project ios/TararebaToushi.xcodeproj -scheme TararebaToushi \
  -configuration Release -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/TararebaReleaseVerification build
npm --prefix tarareba-data run verify:app -- \
  /tmp/TararebaReleaseVerification/Build/Products/Release-iphonesimulator/TararebaToushi.app
```

### 配信データ（`tarareba-data/` で実行）

```sh
npm ci
npm test                    # node --test tests/*.test.mjs
node --test tests/mufg.test.mjs                          # ファイル単位
node --test --test-name-pattern 'corrected latest NAV'   # テスト名で絞る
npm run validate            # public/{live,sample} の契約検証 + iOSソースの同梱物チェック
npm run generate            # 架空サンプル生成（通信なし・実データ不変）
npm run fetch:mufg          # 公式APIから差分取得して public/live/ を上書き
npm run publish:status      # 公開中のJSONと比較（読み取りのみ、needs_deployを出力）
npm run deploy              # validate → wrangler deploy
npm run publish:verify      # 公開結果とローカルの完全一致を確認（読み取りのみ）
npm run dev                 # wrangler dev（public/ をローカル配信して確認）
```

手動公開の順序は `validate` → `test` → `publish:status` → **検証済みJSONをGitへコミット・push** → `deploy` → `publish:verify`。日次ジョブと同時に実行しないでください。

## アーキテクチャ

### データの流れ

```
三菱UFJ 投信情報API（日次） / 設定来CSV（新商品の初回のみ）
  └ scripts/fetch-mufg.mjs      日付+通常基準価額(nav)だけを抽出・照合
      └ public/live/manifest.json + public/live/funds/<id>.json   （固定URL・上書き）
          └ Cloudflare Workers Static Assets (wrangler.jsonc → ./public)
              └ ios Data/RemoteDataSource → DatasetValidator → LocalSnapshotStore
                  └ Domain/SimulationCalculator → Features/Comparison
```

### 契約は2言語に二重実装されている

`tarareba-data/scripts/contract.mjs` と `ios/TararebaToushi/Data/DatasetValidator.swift` は**同じ不変条件**（スキーマ版、ID・パス・版の正規表現、通貨、`valueBasis`、観測日の昇順・重複なし、値の10進数書式、上限30,000観測 / 2MiB、共通日の存在）を別々に実装しています。片方を変更したら必ずもう片方と `docs/data-format.md` も更新し、両方のテストを走らせます。

### 配信形式1と2

- **形式2（現行の実データ）**: `funds/<id>.json` の固定URLを上書き。商品ごとの `contentVersion` は系列JSONのSHA-256（`fund-<64hex>`）で、対応する履歴の `datasetVersion` と一致します。一覧全体の `datasetVersion` は変更検知用でURLには入りません。内容が変わらなければ版も `publishedAt` も保持します。
- **形式1（サンプルのみ）**: `funds/<id>.<datasetVersion>.json`。実データの版付きファイルと `public/test.json` は2026-09-07に削除しました（アプリ未公開のため後方互換は不要）。再現性のためサンプルは形式1のまま維持し、同名・異内容の上書きを拒否します。
- アプリは両形式を読めますが、旧アプリは形式2を読めません。**アプリの更新を先に反映してから配信を切り替えます。**
- `public/_headers`: 一覧と `live/funds/*` は `max-age=0, must-revalidate`、`sample/funds/*` のみ `immutable`。

### 取得ロジック（`scripts/fetch-mufg.mjs`）

- 保存済み履歴のない商品があれば、その商品IDを挙げて**通信前に停止**します。設定来の取り込みだけ `npm run fetch:mufg -- --backfill` を明示。取り込みは**CSV 1リクエスト**で、日付指定APIを設定来ぶん叩くことはありません。`funds` に商品を足したときも同じ経路で、**保存済みの商品は取り直しません**。
- 通常は2商品の最新値APIを確認し、保存済み最終日の翌日から不足日だけ日付指定APIで取得。既存の過去日は再取得しません。最新日が同じなら値の訂正だけ末尾へ反映します。
- 「その日の観測なし」と扱えるのは日付指定の要求で、**該当なし応答**（HTTP 200・`result.status===404`・`errcd==='BIZ00018'`・`retcount===0`・`datasets===null`・`errors.count===1`・`error_list`が`E00026`1件。休場日に実際に返るのはこれ）か、**空応答**（HTTP 200・`result.status===200`・`errcd`なし・`errors.count===0`・`retcount===0`・空配列）に完全一致した場合のみ。APIはエラーでもHTTPを200に保ち、種別は本文の`result.status`に載ります。他のHTTPエラー・エラーコードを休日扱いにしてはいけません。補間もしません。
- 通信はHTTPS・リダイレクト拒否・20秒・2MiB上限・直列（2回目以降は1秒待機）。
- `writeSnapshot` は履歴を先に、`manifest.json` を最後に書き、途中失敗時は完了済みの書き込みをロールバックします。**既存の観測日が欠ける／履歴が短くなる更新は拒否**します。
- 書き込み先は `public/live/` のみ。iOS側へデータファイルを生成することはありません。

### iOSの層

- `App/AppConfiguration.swift` — 配信URL・`DatasetMode`（`live` / `sample`）・6時間の更新間隔・金額上限などの設定の集約点。`cacheIdentity`（URL＋モード＋保存形式）が保存ファイル名のハッシュになり、配信元やモードの異なるキャッシュが混ざりません。
- `Data/FundRepository.swift` — `@MainActor @Observable`。起動時に保存データを読み、6時間経過していれば更新。`transport` / `store` / `now` を注入してテストします。取得失敗時は保存済みスナップショットを保持し、結果画面へは進めません。旧形式（`valueBasis != "nav"`）が残っている場合だけ6時間を待たずに更新します。
- `Data/RemoteDataSource.swift` — 一覧を取得し、`contentVersion` が変わった商品の履歴だけダウンロード。一覧と履歴が食い違えば一覧から**1回だけ**再取得し、揃わなければ既存を保持します。
- `Data/LocalSnapshotStore.swift` — Application Support配下に検証済みの単一スナップショットをatomic書き込み。バックアップ対象から除外。`origin == .bundled` の旧開発版キャッシュは採用しません。
- `Domain/TradingDay.swift` — グレゴリオ暦・Asia/Tokyo固定の暦日。端末のカレンダー・タイムゾーンに依存しません。
- `Domain/SimulationCalculator.swift` — 内部はすべて`Decimal`。評価額を1円へ四捨五入してから表示損益・差額を求めます（丸め後の値どうしで計算）。`Double`はグラフ描画時のみ。計算対象は `SimulationInput.fundIDs` の選択商品だけで、結果は配信順（オルカン→S&P500）に並べます。
- `Models/Dataset.swift` — `ValidatedDataset.window(for:)` が**選択商品だけの共通観測日**を返します。全商品の積集合は取りません（履歴の短い商品を1つ足しただけで、無関係な商品の比較期間まで縮むため）。同時比較は `AppConfiguration.maximumComparisonFunds`（8商品）まで、既定は先頭2商品。**配信商品数と同時比較の上限は別**で、10本を配信して同時比較は8本までにしています。系列色は選択順の添字で引くので、必要な色数は商品数ではなく上限と同じ8色です。上限を上げるときだけ `AppPalette.seriesColors` を足します。

### iOSのコードの前提

- ビルド設定は `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` ＋ `SWIFT_APPROACHABLE_CONCURRENCY = YES`（Swift 5言語モード）。**既定でMainActor隔離**なので、`DatasetMode` / `AppConfiguration` / `FixtureURLProtocol` のようにアクターを跨ぐ型にだけ明示的に `nonisolated` を付けます。
- 単体テストはSwift Testing（`@Test` / `#expect`）、UIテストはXCTest。フィクスチャは各テストターゲットの `TestFixtures.swift` / `UITestFixtures.swift` に集約します。
- テスト用の分岐（`--ui-testing` と `TARAREBA_TEST_*`）はすべて `#if DEBUG` の中にあり、Releaseビルドには入りません。UIテストは `TARAREBA_TEST_SESSION` ごとに `UserDefaults(suiteName:)` と保存先を分けるので、テスト間で入力値やキャッシュが混ざりません。
- `accessibilityIdentifier` はUIテストとの契約です（`simulate` / `refresh-data` / `data-info` / `edit-input` / `input-error` / `comparison-difference` など）。評価額と損益、グラフの読み取り行は `valuation-<商品ID>` / `profit-<商品ID>` / `chart-value-<商品ID>` と商品IDから組み立てるため、商品IDを変えるとUIテストの参照先も変わります。
- コーディングスタイル（4スペース、型名とファイル名の一致、View型の `View` 接尾辞、MainActor前提）は `AGENTS.md` の該当節が現行の指針です。SwiftLint / SwiftFormatの設定はありません。

## 変更時に守ること

- **アプリに価格データを同梱しない。** `ios/TararebaToushi/` 配下（`.xcassets` を除く）に `.json` / `.jsonc` / `.csv` があると `npm run validate` と `verify:app` が失敗します。テスト用フィクスチャはテストターゲット内、UIテストの応答はランナーの環境変数（`--ui-testing` + `TARAREBA_TEST_*`）で渡します。
- **日々の更新はAPIのみ。** CSVを使うのは、保存済み履歴のない商品を設定来CSV（`fund_file/setteirai/<コード>.csv`・Shift_JIS）から1回だけ取り込むときに限ります。取り込み後は最終日と、等間隔に選んだ最大20日を日付指定APIと照合し、1件でも食い違えば書き込みません。既存商品の履歴をCSVで上書きする経路はありません。**再投資基準価額・税引前分配金は書式を検証するだけで保存しません。** 信託報酬の再控除もしません。
- **既存の日付と値は書き換えない。** 補間・丸め直し・株価指数の接ぎ足しをせず、選択商品の共通観測日だけで計算します。
- `DatasetValidator.supportsValueBasis` の `reinvestedIndex` 許可は、2026-09-07に通常基準価額と同値だと監査した版（`mufg-20260904-6c4cf880560d`）の**商品別ハッシュ一致時のみ**です。未確認の再投資系列を通常基準価額として扱ってはいけません。
- 認証情報（`CLOUDFLARE_API_TOKEN` など）をiOSアプリ・`public/`・ソース・チャットに入れないこと。`.dev.vars*` / `.env*` はgitignore済み。
- コミットメッセージは絵文字＋日本語の要約（例: `✨ オルカンとS&P500の同時比較に対応`、`♻️ …`、`🐛 …`、`🔧 …`）。

## 参照

- `docs/data-format.md` — JSONの契約、日付・値の規則、計算式と丸め順序
- `docs/mufg-data.md` — 取得元・商品コード・API仕様・系列の意味・出典表示の前提
- `docs/data-updates.md` — 日次ジョブの流れ、Actions secrets、失敗時の再試行
- `docs/validation.md` — 実施済みの検証結果と手動確認項目
- `tarareba-data/README.md` — 配信・移行コマンドの詳細
