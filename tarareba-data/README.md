# 比較用JSON配信

三菱UFJの公式APIから取得した基準価額を、Cloudflare Workers Static Assetsで公開します。アプリから三菱UFJへの直接通信は行いません。

## 商品ごとの固定URL

```text
public/live/manifest.json           商品一覧・各商品の更新情報
public/live/funds/all-country.json  オルカンの全履歴
public/live/funds/sp500.json        S&P500の全履歴
```

実データは `schemaVersion: 2` です。日々の観測値を配列に追加し、同じファイルへ上書きします。最新日の価格訂正にも対応します。更新回数によってファイル数は増えません。

一覧の `funds[].contentVersion` は商品内容から生成した識別子です。各履歴の `datasetVersion` がこれに一致します。一覧の `datasetVersion` は一覧全体の変更確認用であり、URLには入りません。片方の商品だけ変わった場合、もう片方の履歴の内容と識別子は変わりません。変化がなければ一覧の識別子・作成日時も保持します。

一覧と固定URLの履歴は `Cache-Control: public, max-age=0, must-revalidate` です。アプリは一覧を確認し、必要な商品で更新情報が変わったものだけ取得します。配信切り替えの途中で一覧と履歴が食い違えば、一覧から1回再確認し、揃わなければ正常な保存データを使い続けます。

## 取得と検証

Node.js 22以上を使用します。

```sh
npm ci
npm run fetch:mufg
npm run validate
npm test
```

最新値APIを商品ごとに確認し、保存済み最終日の翌日から不足分を日付指定APIで順に補います。既存の過去日は再取得しません。値が変わらなければ現在の2商品で最新値APIの2回だけです。商品識別・日付・正数・APIのエラーを検証し、直列リクエストの間に1秒待ちます。保存するのは日付と通常の基準価額だけで、CSVは使用しません。

全商品の取得・検証後、変更のある履歴を先に、一覧を最後に置き換えます。通常の書き込みエラーでは完了済みの書き込みを戻します。既存観測日が欠ける履歴は拒否します。複数の更新・生成・デプロイを同時に実行せず、コマンドの正常終了と検証を確認してから公開してください。iOS側にはデータファイルを生成しません。

履歴がない場合、通常のコマンドは通信前に停止します。初回の全履歴構築が必要な場合だけ `npm run fetch:mufg -- --backfill` を使います。設定日から1日ずつ問い合わせるため時間がかかります。既存履歴があれば差分取得です。

詳細は [公式データの取り込み](../docs/mufg-data.md) と [データ形式](../docs/data-format.md) を参照してください。

## 固定URLへの移行（完了）

2026-09-07に通常基準価額（`valueBasis: "nav"`）と商品別固定URL（`schemaVersion: 2`）への移行を完了し、移行スクリプト `migrate:nav` / `migrate:fixed` と公開済みの版付き履歴は削除しました。アプリ未公開のため、版付きURLの後方互換は不要です。実データは `live/funds/<商品ID>.json` の2ファイルだけで、更新のたびに版付きファイルが増えることはありません。

## 日次更新と公開

[Update fund data](../.github/workflows/update-fund-data.yml) は毎朝7:17（日本時間）に取得・検証・Git保存・公開・公開後の照合を行います。変更がなければ公開を省略し、公開に失敗した場合はGit差分がなくても次回に再試行します。有効化にはGitHubへの反映とCloudflareのActions secretsが必要です。[日次更新の手順](../docs/data-updates.md)

手動公開は日次ジョブと同時に実行せず、検証したJSONをGitへコミット・pushしてから行います。

```sh
npm run validate
npm test
npm run publish:status
npm run deploy
npm run publish:verify
```

`publish:status` / `publish:verify` は公開された一覧と全商品履歴をローカルと比較する読み取り専用コマンドです。移行後は旧版ファイルの保存を要求せず、固定URLの内容で判定します。公開済みの観測日が欠ける更新は拒否します。認証情報をiOSアプリや `public/` に含めないでください。

公開後は以下のURLでHTTP 200、JSON、キャッシュ設定を確認します。

```sh
curl -i https://tarareba-data.hibiki-apps.workers.dev/live/manifest.json
curl -i https://tarareba-data.hibiki-apps.workers.dev/live/funds/all-country.json
curl -i https://tarareba-data.hibiki-apps.workers.dev/live/funds/sp500.json
```

## 開発用サンプル

```sh
npm run generate
npm run validate
npm test
```

架空サンプルはネットワーク不要で、実データを変更しません。デフォルトは2020-01-06〜2026-09-04、seed=42、sample-v1です。サンプルは再現性を保つため従来の形式1・版付きURLを維持し、同名・異内容の上書きを拒否します。

```sh
npm run generate -- --start 2020-01-06 --end 2026-09-04 --seed 43 --version sample-v2
```

`npm run validate` はiOSのソース配下に価格データファイルがないことも確認します。ビルド済みアプリは `npm run verify:app -- <TararebaToushi.appの絶対パス>` で確認できます。
