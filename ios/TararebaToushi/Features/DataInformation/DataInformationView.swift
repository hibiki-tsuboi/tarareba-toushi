import SwiftUI

struct DataInformationView: View {
    let repository: FundRepository
    let result: SimulationResult?
    @Environment(\.dismiss) private var dismiss
    private var isSample: Bool { repository.configuration.mode == .sample }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DataNoticeView(mode: repository.configuration.mode)
                    Text(isSample
                        ? "画面の2商品は比較体験を試すための架空データです。実在する投資信託の基準価額や成績を再現していません。"
                        : "eMAXIS Slim 全世界株式（オール・カントリー）と、eMAXIS Slim 米国株式（S&P500）を比較します。運用会社の公開データを本アプリ用に加工しています。株価指数そのものの値ではありません。")
                }
                Section("表示中のデータ") {
                    row("データモード", repository.configuration.mode.label)
                    row("読み込み元", repository.statusLabel)
                    row("版", repository.dataset?.snapshot.manifest.datasetVersion ?? "—")
                    row("共通のデータ基準日", repository.dataset?.endDate.label ?? "—")
                    row("端末での最終取得日時", timestamp(repository.fetchedAt, empty: "未取得"))
                    row("更新確認成功日時", timestamp(repository.checkedAt, empty: "未確認"))
                    if let dataset = repository.dataset {
                        row("配信データの作成日時", dataset.snapshot.manifest.publishedAt)
                        ForEach(dataset.funds, id: \.descriptor.id) { fund in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(fund.descriptor.displayName).fontWeight(.medium)
                                Text(fund.series.source.name)
                                Text(fund.series.source.note).foregroundStyle(.secondary)
                                if let text = fund.series.source.url, let url = URL(string: text) {
                                    Link("出典の商品ページ", destination: url)
                                }
                            }
                            .font(.footnote)
                        }
                    }
                }
                Section("配信と更新") {
                    Text(repository.configuration.dataBaseURL).font(.footnote).textSelection(.enabled)
                    Text("初回起動時に比較データを取得します。初回はインターネット接続が必要です。取得後は端末に保存し、オフラインでも前回のデータで比較できます。")
                    Text("起動・復帰時に、前回の確認成功から6時間以上経過していれば更新を確認します。手動更新もできます。通信に失敗した場合は正常な保存データを保持します。")
                    Text("データ基準日は、2商品の観測値が揃う最後の日です。今日のリアルタイム価格やファイルの公開日時ではありません。")
                }
                Section("計算のしかた") {
                    Text("評価額 ＝ 元本 × 終了日の系列値 ÷ 開始日の系列値\n損益 ＝ 評価額 − 元本\n損益率 ＝（終了値 ÷ 開始値 − 1）× 100")
                    Text("指定日以降で両方のデータが揃う最初の日から、最後の共通日までを比較します。履歴開始前の期間は計算できません。")
                    if let result {
                        row("指定した日", result.requestedDate.label)
                        row("計算に使用した日", "\(result.startDate.label)〜\(result.endDate.label)")
                    }
                    Text(isSample
                        ? "今回は分配金再投資を表す架空の指数を使っています。分配金を別に加算していません。"
                        : "公式の「基準価額（分配金再投資）」を使います。税引前の分配金を再投資したと仮定する系列です。分配実績がない場合は基準価額と同じ値になります。分配金を別に足していません。")
                    Text("内部では10進数で計算し、表示時に円単位で四捨五入します。表示損益は表示評価額から元本を引き、差額は2つの表示評価額から求めます。損益率は小数1桁表示です。")
                }
                Section("比較の前提") {
                    Text("売却時の税金、購入・換金時の手数料等は計算していません。注文・約定日・端数処理・再投資日を完全に再現するものではありません。")
                    if !isSample {
                        Text("使用する基準価額は運用管理費用（信託報酬）控除後です。信託報酬をもう一度差し引くことはしません。")
                        Text("「オルカン」は三菱UFJアセットマネジメントの登録商標です。")
                    }
                    Text("過去の比較結果は将来の成果を保証しません。特定の商品の購入を推奨するものではありません。")
                }
            }
            .font(.subheadline)
            .navigationTitle("データと計算について")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } } }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }

    private func timestamp(_ date: Date?, empty: String) -> String {
        guard let date else { return empty }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.calendar = TradingDay.calendar
        formatter.timeZone = TradingDay.calendar.timeZone
        formatter.dateFormat = "yyyy/MM/dd HH:mm（日本時間）"
        return formatter.string(from: date)
    }
}
