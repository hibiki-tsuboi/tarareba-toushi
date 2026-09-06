# 比較用JSON配信

Cloudflare Workers Static Assets向けに、たられば投資の実データと開発用サンプルを用意します。Worker名・配信先は既存設定を維持しています。`public/test.json` は従来の疎通確認用です。

## 公式データの取得・更新

Node.js 22以上を使用し、このディレクトリで実行します。

```sh
npm ci
npm run fetch:mufg
npm run validate
npm test
```

`fetch:mufg` は2商品の公式「設定来データ」CSVと最新値APIに、順番に計4回アクセスします。Shift_JISをデコードし、商品・列・日付・正数・設定来の範囲・分配金再投資系列・APIとの最新日/基準価額一致を確認します。取得や照合に失敗した場合は時間をおいて再実行してください。アプリからUFJへの直接通信は行いません。

全体の検証に成功すると `public/live/` の配信用JSONを生成します。iOSアプリにはデータファイルを生成しません。版は `mufg-YYYYMMDD-<内容のハッシュ>`、作成日時はUTC。既存の履歴ファイルは保持し、データが変わらない場合は同じ版・日時になります。新版でも既存の観測日が欠ける履歴は拒否します。

取得処理の詳細は [公式データの取り込み](../docs/mufg-data.md) を参照してください。更新は手動で、定期取得や自動デプロイは設定していません。同時に複数の更新コマンドを実行せず、コマンドの正常終了と検証を確認してから公開します。

## 開発用サンプルの生成

架空サンプルはネットワーク不要で生成します。`generate` は実データを変更しません。

```sh
npm run generate
npm run validate
npm test
```

デフォルトは2020-01-06〜2026-09-04、seed=42、sample-v1。版付き履歴は同名・異内容の上書きを拒否します。変更時は必ず新しい版を使います。

```sh
npm run generate -- --start 2020-01-06 --end 2026-09-04 --seed 43 --version sample-v2
npm run validate
```

生成先は `public/sample/` のみです。旧版の履歴ファイルは削除しません。公開日時は再現性のため指定終了日の00:00 UTCとし、値の観測日・端末の取得日時とは区別します。`npm run validate` は配信JSONを検証し、iOSのソース配下にJSON・JSONC・CSVがあれば失敗します（アセットカタログのメタデータを除く）。ビルド済みアプリも `npm run verify:app -- <TararebaToushi.appの絶対パス>` で確認できます。

## 手動公開

2026-09-06に実データ・サンプルを公開済みです。次回のデータ更新後も、以下の手順で検証・公開します。

```sh
npm run validate
npm test
npm run deploy
```

`deploy` は検証後に `wrangler deploy` を実行します。トークンをiOSアプリや `public/` に入れないでください。公開フォルダにはJSONと `_headers` のみを配置します。

## 公開後の確認

```sh
curl -i https://tarareba-data.hibiki-apps.workers.dev/test.json
curl -i https://tarareba-data.hibiki-apps.workers.dev/live/manifest.json
curl -i https://tarareba-data.hibiki-apps.workers.dev/sample/manifest.json
curl -i https://tarareba-data.hibiki-apps.workers.dev/sample/funds/demo-all-country.sample-v1.json
curl -i https://tarareba-data.hibiki-apps.workers.dev/sample/funds/demo-sp500.sample-v1.json
```

実データの2つの履歴URLは `live/manifest.json` の `funds[].path` を `live/` に連結して確認します。HTTP 200、`Content-Type: application/json`、JSON内の版・商品ID・日付を確認してください。manifestの404はファイル未配置を示す場合があります。アプリの初回取得に失敗すると比較できません。以前に取得を完了していれば、保存済みデータを引き続き表示します。

`_headers` ではmanifestに `max-age=0, must-revalidate`、版付き履歴に `max-age=31536000, immutable` を指定しています。実際のレスポンスで適用を確認してください。これはクライアント向け設定であり、CDN内部のキャッシュTTLを同一に設定したという意味ではありません。[Cloudflare公式ヘッダー仕様](https://developers.cloudflare.com/workers/static-assets/headers/)

既存の版付き履歴は当面すべて保持します。削除が必要になった場合は、古いmanifestの利用期間とアプリの互換性を確認して保持方針を見直します。少なくとも新旧2版を同時に配置します。古いJSONを同名で置換しないでください。

[Workers Static Assets公式手順](https://developers.cloudflare.com/workers/static-assets/get-started/)、[データ形式](../docs/data-format.md)
