# 実装・検証メモ

確認日：2026-09-06。最新の画面は、投資信託を選び、開始日・金額を入力してから1商品の結果へ進む構成です。

## 投資信託の選択

入力画面の先頭にオルカン／S&P500の2択ボタンを追加しました。初期選択はオルカンで、選択中のボタンにはチェックを表示します。結果画面は選んだ商品の増減額と投資後の金額だけを表示します。条件を変更して戻ったときも商品・開始日・金額を保持します。

シミュレーションに成功したときに選択を入力条件と一緒に保存します。旧バージョンの保存データに商品が含まれない場合は、開始日・金額を引き継いでオルカンを選択します。計算には従来と同じ2商品の共通観測日を使います。

Xcode 26.6でビルドとSwift Testingの37テストが成功しました。iPhone 17 Pro / iOS 26.5では9件、iPad mini (A17 Pro) / iOS 26.5 / ダークでは3件のUIテストが成功しています。両商品の結果の選び分け、戻って選択を変えて再計算、無効金額の修正、オフライン再起動での選択復元、以前の保存データの読み込みを確認しました。

文字を最大まで拡大すると2択ボタンを縦に並べ、金額欄は表示幅に合わせて文字サイズを調整します。金額が省略されないことを目視で確認し、調整後のiPhoneの2件・iPadの1件の画面テストも成功しました。

以下の画面記録はUIテストの架空の固定値を使用し、S&P500を選択した例です。

- [iPhone：投資信託の選択](screenshots/iphone-fund-selection-input.png)
- [iPhone：選んだ商品の結果](screenshots/iphone-fund-selection-results.png)
- [iPad：投資信託の選択・ダーク](screenshots/ipad-fund-selection-input.png)
- [iPad：選んだ商品の結果・ダーク](screenshots/ipad-fund-selection-results.png)

検証結果は `/tmp/TararebaFundSelection-iPhone.xcresult` と `/tmp/TararebaFundSelection-iPad.xcresult`、表示調整後の結果は `/tmp/TararebaFundSelection-Layout-iPhone.xcresult` と `/tmp/TararebaFundSelection-Layout-iPad.xcresult` に保存しています。一時ファイルのため恒久保存ではありません。

以下は投資信託の選択を追加する前の検証記録です。

## 入力と結果画面の分離

初期画面を開始日・投資金額・「シミュレート」に絞りました。ボタンを押したときだけ入力を検証して計算し、別画面に各商品の増減額と投資後の金額を表示します。入力に戻ると条件が保持され、変更後は再度ボタンを押して計算します。期間プリセット、損益率、差額カード、グラフは表示しません。出典や計算の説明、手動更新は右上の情報ボタンから確認できます。

データ取得や更新だけでは結果を表示しません。初回の通信失敗時はシミュレーションを無効にし、入力画面に再試行を表示します。取得済みであればオフラインでもボタンから計算できます。

| 対象 | 環境・結果 |
|---|---|
| Debugビルド | Xcode 26.6 / 汎用iOS Simulatorで成功 |
| Swift Testing | 既存の35テスト、4スイート成功 |
| iPhone UI | iPhone 17 Pro / iOS 26.5、8テスト成功 |
| iPad UI | iPad mini (A17 Pro) / iOS 26.5 / ダーク、3テスト成功 |

入力だけの初期表示、ボタンでの画面遷移、入力値を保持した条件変更、無効金額・期間のエラー、利益・損失・増減ゼロ、初回通信失敗と再試行、オフライン再起動、更新失敗時の結果保持を確認しました。iPhoneではアクセシビリティの最大文字サイズでスクロールして両商品の結果と戻るボタンを操作できることも確認しています。

以下の画面記録はUIテストの架空の固定値を使用しています。実際の運用実績を示すものではありません。

- [iPhone：入力画面](screenshots/iphone-simple-input.png)
- [iPhone：結果画面](screenshots/iphone-simple-results.png)
- [iPad：入力画面・ダーク](screenshots/ipad-simple-input.png)
- [iPad：結果画面・ダーク](screenshots/ipad-simple-results.png)

ダーク表示の「シミュレート」の文字色を背景に合わせて調整し、両端末の入力・結果画面テストを再実行して成功しました。上の画面記録はこの調整後のものです。

検証結果は `/tmp/TararebaSimpleFlow-iPhone.xcresult`、`/tmp/TararebaSimpleFlow-iPad.xcresult`、`/tmp/TararebaSimpleFlow-VisualCheck.xcresult`、ビルドログは `/tmp/tarareba-simple-flow-build.log` に保存しています。一時ファイルのため恒久保存ではありません。

以下は画面分離前の実装・配信検証の記録です。プリセットやグラフを含む旧画面の記述は現在の画面構成とは異なります。

## 実装した範囲

2商品の一括投資比較、金額・開始日とプリセット、評価額・損益・差額、共通観測日のグラフと日付選択、説明画面を実装しました。初回ダウンロード、取得後のオフライン利用、入力の保存、6時間ごとの更新確認、手動更新、データ検証と正常キャッシュの保持に対応しています。

公式CSVの取得・API照合・検証と手動デプロイ手順を用意しました。生成先は配信用フォルダのみで、実データ・サンプルともにアプリへ同梱しません。通常起動は実データを取得し、テスト用サンプルはモード・ID・キャッシュを分離しています。日次更新のワークフローも用意し、GitHubへの反映とAPIトークン登録を待っています。

## 自動検証

| 対象 | 環境・結果 |
|---|---|
| Debugビルド | Xcode 26.6 / iOS 26.0シミュレーターで成功 |
| Releaseビルド | 汎用iOS Simulator（arm64 / x86_64）で成功 |
| Swift Testing | 35テスト、4スイート成功。引数付きテストは複数ケースを含む |
| iPhone UI | iPhone 17 Pro / iOS 26.0、7テスト成功 |
| iPad UI | iPad mini (A17 Pro) / iOS 26.0 / ダーク、初回失敗と再試行・比較と出典の2テスト成功 |
| Node.js | 公式CSV/API照合・版の保持・公開判定・エラー処理・サンプル生成の20テスト成功 |
| GitHub Actions | actionlint 1.7.12と各シェルステップの構文検証が成功 |
| 日次のGit保存処理 | 一時リポジトリでデータだけのコミット、旧版の保持、変更なしの省略、別ファイルのステージ検出、競合push時の停止を確認 |
| デプロイ設定 | Wrangler 4.129.0の `deploy --dry-run` が成功。公開は行っていない |
| 配信データ検証 | スキーマ・値・日付・パス・共通日を確認 |
| データ非同梱 | `npm run validate` でアプリのソース、`npm run verify:app` でReleaseの `.app` にJSON・JSONC・CSVがないことを確認 |
| 公開URLとの通信 | iPadシミュレーターの空の保存先から実際のCloudflare配信データを取得・保存・表示し、配信用JSONとの一致を確認 |
| Git差分 | `git diff --check` 成功 |

Swiftの検証は、+20%/+40%/-20%、元本変更、丸めと表示同額、上限、無効入力、休日補正、最新日の単純な最小値ではない共通終了日、うるう年、東京時間での年月日、範囲外・空・重複・不正系列を含みます。

通信・保存では404/500/HTML/タイムアウト/応答サイズ/リダイレクト拒否、同一版での履歴取得省略、新版の一括切り替え、片方の取得失敗・不正JSON・版/モード不一致・保存失敗時の旧版保持、破損キャッシュ、配信元別の保存、再試行、更新の重複防止を検証しました。

UIテストはテストランナー側で用意した架空の応答をDebugアプリへ渡します。価格データはアプリ本体のソースやリソースに置きません。初回オフラインでは結果を表示しないこと、日本語の通信エラー案内、再試行後の比較、取得後のオフライン再起動を確認しました。サンプル表示、説明画面、無効金額の結果非表示と復帰、5年前への変更、文字の最大拡大、損失表示、前後の観測日選択、1点のグラフ、更新先404も含みます。

実データ対応では、初回にmanifestと2履歴を取得してから保存・表示すること、片方の失敗時に不完全なキャッシュを残さないこと、以前の同梱データ由来のキャッシュを無視して再取得することを検証しました。404後の取得済みデータ保持と新版への切り替え、サンプル混入の拒否、モード別キャッシュ、HTTPS出典URLも確認しています。

Node.jsでは税引前分配金がある架空フィクスチャを用い、通常基準価額と再投資系列を取り違えず、分配金を二重加算しないことを確認しました。CSVの列変更・日付不正・履歴欠落・APIとの不一致・HTTPエラー・大きすぎる応答を拒否し、同じ内容の版と日時、新旧履歴の保持、公式データの生成処理がiOS側にファイルを書かないことを検証しています。サンプル生成を実行してもiOS側にデータが作られないことを確認しました。

XcodeのAppIntentsメタデータ抽出スキップ警告は、AppIntentsを使用していないため出力されます。Swiftのコンパイルエラーはありません。

## 日次更新の検証

毎朝7:17（日本時間）のGitHub Actionsワークフローを追加しました。取得は最大3回、公開後の照合は最大5回試します。検証済みのデータを先にGitへ保存してから、公開版と異なる場合だけデプロイします。

Node.jsの追加8テストでは、同じ公開版の省略、Gitに新版が保存済みでも公開が旧版なら再公開が必要と判定すること、公開manifestの404、HTTP・通信・HTML・JSONの異常、片方の履歴欠落、不正パスのリクエスト前拒否、同じ版の改変拒否、古いデータへの巻き戻し拒否、公開中の旧版ファイル保持を確認しました。

`publish:status` と `publish:verify` を実際の公開URLに対して実行し、版 `mufg-20260904-6c4cf880560d` のmanifest・2履歴がローカルと一致することを確認しました。公開判定・照合コマンドはデプロイを行いません。

GitHubのリポジトリは公開、デフォルトブランチは `main`、直接pushを禁止する保護はありません。`CLOUDFLARE_ACCOUNT_ID` の登録を確認しました。`CLOUDFLARE_API_TOKEN` は未登録で、ワークフロー自体もローカルにのみ存在するため、GitHub上での実行や新しい版の自動公開は未確認です。有効化と通知設定は [日次更新の手順](data-updates.md) を参照してください。

## 目視確認

iPhoneのライト表示とiPadのダーク表示で初回取得失敗の案内を確認しました。iPadでは初回の通信失敗時に価格データが保存されないことも確認し、同じ空の保存先で通常のHTTP通信に戻して、公開データを取得・表示しました。100万円、指定日2025-01-01（計算開始2025-01-06）、終了2026-09-04の例では、評価額はオルカン1,381,174円、S&P500 1,308,418円、差額72,756円です。

- [iPhone：初回取得失敗時は価格・比較結果なし](screenshots/iphone-first-download.png)
- [iPad：Cloudflareから取得した実データの表示](screenshots/ipad-downloaded-data.png)

以下の3枚は同梱方式を使っていた旧開発版の画面記録です。現在の取得方法の検証には使用しません。

- [実データ：iPhone 入力・商品名](screenshots/iphone-live-comparison.png)
- [実データ：iPhone 評価額・差額](screenshots/iphone-live-results.png)
- [実データ：iPad ダークモード](screenshots/ipad-live-dark.png)

初回のサンプル実装では大きな文字の縦並びカード、損失の符号、1点グラフも確認しました。以下はサンプル版の記録です。

- [iPhone 比較画面](screenshots/iphone-comparison.png)
- [iPhone グラフ](screenshots/iphone-chart.png)
- [iPad ダークモード](screenshots/ipad-dark.png)

テストの詳細はXcodeのReport Navigatorから確認できます。同梱廃止後のログは `/tmp/tarareba-remote-only-tests.log`、`/tmp/tarareba-remote-only-ipad.log`、`/tmp/tarareba-remote-only-release.log` に保存しています。DerivedDataは `/tmp/TararebaRemoteOnlyDerivedData` を新規に作成し、旧ビルドの同梱リソースを引き継いでいません。一時ディレクトリのログは恒久保存ではありません。

## 配信状況

2026-09-06の公開前は、既存公開先に `test.json` のみがあり、`sample/manifest.json` と `live/manifest.json` は404でした。同日、利用者の依頼により `npm run deploy` で既存Worker `tarareba-data` に公開しました。

- `https://tarareba-data.hibiki-apps.workers.dev/test.json`：200、指定どおりの疎通JSON。
- `https://tarareba-data.hibiki-apps.workers.dev/live/manifest.json`：200、実データの一覧。
- `https://tarareba-data.hibiki-apps.workers.dev/sample/manifest.json`：200、開発用サンプルの一覧。

公式CSV2件と最新情報API2件から生成した2026-09-04までの実データを公開しています。オルカンは1,913観測、S&P500は1,995観測で、最新の通常基準価額は37,945円 / 44,392円。CSVとAPIが一致しました。版は `mufg-20260904-6c4cf880560d` です。

公開前にJSON検証とNode.jsの12テストが成功しました。公開後に実データ・サンプルそれぞれのmanifestと2つの履歴、計7つのJSONを取得し、HTTP 200・ローカルファイルとのバイト単位の一致を確認しました。両データセットは取得したJSONで再検証しています。

manifestと履歴の `Content-Type` は `application/json`。manifestの `Cache-Control` は `public, max-age=0, must-revalidate`、版付き履歴は `public, max-age=31536000, immutable` を確認しました。Cloudflareのデプロイ版IDは `5e9721c4-af0c-4a78-a566-a6b1e58471b8` です。

公開後に、アプリの実際のHTTP通信でも初回取得を確認しました。既存データから隔離した空の保存先を使い、オフライン起動では保存ファイルなし、オンライン起動後は `origin: remote` と取得日時のある単一スナップショットが保存されました。manifestと2履歴が公開したJSONと一致し、オルカン1,913観測・S&P500 1,995観測を確認しました。取得済みで同じ版のmanifestなら、履歴の再取得を省略します。

## 残る手動確認

- 実機iPhoneでの操作、VoiceOverの連続読み上げ、全画面・全入力に対するアクセシビリティ監査。
- 長時間のバックグラウンド復帰、実回線の低速通信中の進捗表示、通信中のプロセス強制終了。自動テストでは関連する時計・エラー・保存境界を検証済みです。
- iPad横向きなど全サイズでの確認。今回のiPad UIテストは縦向きです。
- 実機アプリから公開版への更新確認。次のデータ更新時には、Cloudflare上での新版への切り替えと旧版履歴の保持も確認します。
- 日次更新のAPIトークン登録、GitHubへのコード反映、初回実行と失敗通知の受信確認。スケジュール自体の停止を検知する独立した外部監視は未導入です。

アプリを試すための次の操作は、`ios/TararebaToushi.xcodeproj` をXcodeで開き、`TararebaToushi` スキームをCmd+Rで実行することです。
