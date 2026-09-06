# サンプルJSON配信

Cloudflare Workers Static Assetsで、たられば投資の**架空データだけ**を配信します。Worker名・配信先は既存設定を維持しています。`public/test.json` は従来の疎通確認用です。

## ローカルで生成・検証

このディレクトリで実行します。依存のインストール以外、生成・検証にネットワークは不要です。Node.js 22以上を使用してください。

```sh
npm ci
npm run generate
npm run validate
npm test
```

デフォルトは2020-01-06〜2026-09-04、seed=42、sample-v1。版付き履歴は同名・異内容の上書きを拒否します。変更時は必ず新しい版を使います。

```sh
npm run generate -- --start 2020-01-06 --end 2026-09-04 --seed 43 --version sample-v2
npm run validate
```

同じ処理で `public/sample/` と `../ios/TararebaToushi/Resources/BundledSample.json` を更新します。旧版の履歴ファイルは削除しません。公開日時は再現性のため指定終了日の00:00 UTCとし、値の観測日・端末の取得日時とは区別します。

## 手動公開

**以下は公開を選ぶ時に実行する手順です。実装作業ではデプロイしていません。**

```sh
npm run validate
npm test
npm run deploy
```

`deploy` は検証後に `wrangler deploy` を実行します。トークンをiOSアプリや `public/` に入れないでください。公開フォルダにはJSONと `_headers` のみを配置します。

## 公開後の確認

```sh
curl -i https://tarareba-data.hibiki-apps.workers.dev/test.json
curl -i https://tarareba-data.hibiki-apps.workers.dev/sample/manifest.json
curl -i https://tarareba-data.hibiki-apps.workers.dev/sample/funds/demo-all-country.sample-v1.json
curl -i https://tarareba-data.hibiki-apps.workers.dev/sample/funds/demo-sp500.sample-v1.json
```

HTTP 200、`Content-Type: application/json`、JSON内の版・商品ID・日付を確認します。新版ではURL末尾をその版に変更します。manifestの404はサンプル未配置を示す場合があります。アプリはその場合も同梱サンプルで動作します。

`_headers` ではmanifestに `max-age=0, must-revalidate`、版付き履歴に `max-age=31536000, immutable` を指定しています。実際のレスポンスで適用を確認してください。これはクライアント向け設定であり、CDN内部のキャッシュTTLを同一に設定したという意味ではありません。[Cloudflare公式ヘッダー仕様](https://developers.cloudflare.com/workers/static-assets/headers/)

既存の版付き履歴は当面すべて保持します。削除が必要になった場合は、古いmanifestの利用期間とアプリの互換性を確認して保持方針を見直します。少なくとも新旧2版を同時に配置します。古いJSONを同名で置換しないでください。

[Workers Static Assets公式手順](https://developers.cloudflare.com/workers/static-assets/get-started/)、[データ形式](../docs/data-format.md)
