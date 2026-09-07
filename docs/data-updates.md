# 配信データの日次更新

GitHub Actionsの [Update fund data](../.github/workflows/update-fund-data.yml) が、毎日 **7:17（日本時間、UTC 22:17）** に実行する設定です。手動の **Run workflow** にも対応しています。

2026-09-06時点ではローカル実装・テストまで完了しています。`CLOUDFLARE_ACCOUNT_ID` は対象リポジトリに登録済みです。GitHubへのコード反映と `CLOUDFLARE_API_TOKEN` の登録が完了するまでは自動公開は稼働しません。

## 更新の流れ

1. デフォルトブランチの最新コードと過去の配信JSONを取得し、Node.js 24で `npm ci`、`npm test` を実行します。
2. `npm run fetch:mufg` で2商品の最新値APIを確認し、保存済み最終日の翌日から不足する日付をAPIで順に取得します。CSVは使用せず、既存の過去日は再取得しません。失敗した場合は60秒間隔で最大3回試し、正常なデータを `npm run validate` で検証します。
3. `npm run publish:status` で公開中のmanifest・2履歴と比較します。同じ版なら内容まで一致することを確認し、公開を省略します。
4. 更新した `public/live/` をGitにコミット・pushしてから、必要な場合だけ `npm run deploy` を実行します。
5. `npm run publish:verify` で公開されたmanifest・2履歴の内容とJSONの形式を確認します。反映待ちを考慮し、15秒間隔で最大5回確認します。

休日も実行しますが、元データに変化がなければ新しい版や作成日時を作りません。アプリは引き続き同じ `live/manifest.json` を参照します。

## 初回の設定

対象リポジトリは `hibiki-tsuboi/tarareba-toushi` です。現在のデフォルトブランチは `main` です。

1. Cloudflareで **Edit Cloudflare Workers** テンプレートからAPIトークンを作成し、配信に使うアカウントへ範囲を限定します。ローカルの `wrangler login` で得た認証はGitHub Actionsには引き継がれません。
2. [リポジトリのActions secrets](https://github.com/hibiki-tsuboi/tarareba-toushi/settings/secrets/actions) に次の2つを登録します。トークンの値はソースコードやチャットに貼り付けないでください。

| 名前 | 値 |
|---|---|
| `CLOUDFLARE_ACCOUNT_ID` | 配信WorkerがあるCloudflareアカウントのID |
| `CLOUDFLARE_API_TOKEN` | 作成したデプロイ用APIトークン |

3. ワークフローと現在のアプリ・配信スクリプトをデフォルトブランチに反映します。ワークフローだけを古いコードへ追加しないでください。
4. [Actions](https://github.com/hibiki-tsuboi/tarareba-toushi/actions) → **Update fund data** → **Run workflow** を実行し、成功と実行サマリーの版・基準日を確認します。
5. [GitHubの通知設定](https://github.com/settings/notifications) でActionsの失敗通知を有効にし、以後の更新結果を確認します。

ワークフロー内で `contents: write` を指定し、生成データをGitHubの標準 `GITHUB_TOKEN` で保存します。ブランチ保護で直接pushが禁止されている場合は、自動保存に適したブランチ運用を別途決めてください。保護設定の迂回やforce pushは行いません。

[Cloudflare公式のGitHub Actions設定](https://developers.cloudflare.com/workers/ci-cd/external-cicd/github-actions/)に認証の詳細があります。

## 失敗と再試行

- 取得・検証・Gitへのpushに失敗した場合は、公開処理へ進みません。同時に複数の更新ジョブを実行せず、実行中のジョブを次の実行でキャンセルしない設定です。
- Gitへの保存後に公開が失敗しても、次回は実際の公開JSONと比較するため、Git差分がなくても再度公開します。
- 同じ版で内容が異なる、履歴が短くなる、公開中の旧版JSONがチェックアウト内にない場合は停止します。旧版のURLを維持するため、`public/live/funds/` の過去版もGitに保存してください。
- 再試行は **Re-run all jobs** または **Run workflow** で行います。取得済みのアプリは正常な端末保存データを引き続き利用できます。
- GitHubへの自動コミットでリモートが進むため、ローカルで次の作業を始める際は最新のブランチを取り込んでください。

手動でデータを更新・公開する場合も、検証済みJSONを先にGitへ保存・pushし、日次ジョブと同時実行しないでください。

## スケジュールの確認

GitHubの定期実行は正確な時刻の実行を保証せず、高負荷時には遅延・実行の欠落が起こり得ます。また、公開リポジトリで60日間活動がない場合は無効化されます。[GitHubのschedule仕様](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule)

Actionsの最終実行日時とサマリーのデータ基準日を確認してください。ワークフロー自体が起動しなかった場合はジョブの失敗通知も発生しません。外部サービスからの独立した監視は、この実装には含めていません。
