# データ形式と計算

## 配置

`sample/manifest.json` は `schemaVersion: 1`、`datasetVersion`、`isSample: true`、UTCのISO 8601 `publishedAt` と2つの `funds` を持ちます。商品IDは `demo-all-country` / `demo-sp500`。`displayName` に「サンプル」を含め、`currency` はJPY固定です。

`path` はmanifestのあるディレクトリを基準とする `funds/<id>.<datasetVersion>.json` のみ許可します。版は英小文字・数字・ハイフンの1〜64文字、先頭は英小文字または数字。絶対URL、親ディレクトリ、パーセントエンコード、クエリ、別ドメインの指定は許可しません。HTTPリダイレクトはすべて拒否します。

各系列は同じスキーマ・版・モード・商品ID・通貨と、`valueBasis`、`source`、`observations` を持ちます。未知の追加キーは無視できますが、未知のスキーマや系列基準は拒否します。

```json
{
  "schemaVersion": 1,
  "datasetVersion": "sample-v1",
  "isSample": true,
  "fundId": "demo-all-country",
  "currency": "JPY",
  "valueBasis": "reinvestedIndex",
  "source": {
    "kind": "synthetic",
    "name": "開発用に生成した架空の比較データ",
    "url": null,
    "note": "実際の運用実績ではありません"
  },
  "observations": [{"date": "2025-01-06", "value": "10000.000000"}]
}
```

## 日付と値

- 日付は1900〜2200年の実在する `YYYY-MM-DD`。昇順・重複なし。先頭と末尾がmanifestの `firstDate` / `lastDate` と一致する必要があります。
- 観測値は正の10進数文字列。整数部12桁以内、小数部6桁以内。指数表記、NaN、負数、0は禁止です。最大30,000観測/商品、HTTP応答は2MiB/ファイルまでです。
- `reinvestedIndex` は分配金再投資を表す系列。現在は任意の10000を基準とした架空指数であり、実在ファンドの1万口あたりの基準価額ではありません。
- `navWithoutDistributions` は全配信期間について分配金なしと確認した基準価額用です。採用時は提供者が根拠・期間・費用の意味を確認し、出典注記を用意する必要があります。JSON検証だけで金融上の事実や利用許諾を証明するものではありません。

## 共通期間と計算

開始日は指定日以降の最初の共通観測日、終了日は最後の共通観測日です。指定日がどちらかの履歴開始前、または共通終了後なら計算しません。共通日がない場合も拒否します。開始＝終了は元本と同額、損益0です。

```text
評価額(t) = 元本 × 系列値(t) ÷ 系列値(開始日)
損益(t) = 評価額(t) − 元本
損益率(t) = (系列値(t) ÷ 系列値(開始日) − 1) × 100
```

内部はDecimal。表示評価額を1円単位で四捨五入し、表示損益＝表示評価額−元本、表示差額＝Bの表示評価額−Aの表示評価額とします。表示上の同額は勝者なし。率は小数1桁。税金・購入換金手数料は除外し、整数口数への丸めや分配金の二重加算はしません。

## サンプルの再現性

生成はネットワーク不要で、開始・終了・seed・versionが同じなら同一です。平日の架空時系列であり、日本の祝日カレンダーや実績を再現しません。固定の3点フィクスチャはSwiftテストに分離しています。配信JSONと同梱 `BundledSample.json` は共通の生成処理から作り、`npm run validate` で一致を確認します。
