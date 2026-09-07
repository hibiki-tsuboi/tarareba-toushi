import SwiftUI

struct DataInformationView: View {
    let repository: FundRepository
    let result: SimulationResult?
    @Environment(\.dismiss) private var dismiss
    private var isSample: Bool { repository.configuration.mode == .sample }

    var body: some View {
        NavigationStack {
            List {
                Section("データの更新") {
                    Text(repository.statusLabel)
                        .fontWeight(.medium)
                    if let message = repository.message {
                        Text(message)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("update-message")
                    } else if repository.dataset != nil, repository.isStale {
                        Text("更新確認が必要です。取得済みのデータでシミュレーションできます。")
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        Task { await repository.refresh(force: true) }
                    } label: {
                        HStack {
                            if repository.isRefreshing { ProgressView() }
                            Label(repository.isRefreshing ? "更新を確認中…" : "データを更新", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(repository.isRefreshing || repository.isLoading)
                    .accessibilityIdentifier("refresh-data")
                }
                Section {
                    DataNoticeView(mode: repository.configuration.mode)
                    Text(isSample
                        ? "比較する2商品はシミュレーションを試すための架空データです。実在する投資信託の基準価額や成績を再現していません。"
                        : "eMAXIS Slim 全世界株式（オール・カントリー）と、eMAXIS Slim 米国株式（S&P500）を同じ条件で比較します。運用会社の公開データを本アプリ用に加工しています。株価指数そのものの値ではありません。")
                }
                if !isSample {
                    Section("公表値とシミュレーション結果") {
                        row("算出主体", "たられば投資")
                        Text("使用する基準価額は三菱UFJアセットマネジメントの公表値です。評価額・損益・損益率は、公表データをもとに本アプリが独自に算出した値であり、同社の公表値ではありません。")
                        Text("三菱UFJアセットマネジメントが本アプリや算出内容を推奨・保証・公認するものではありません。")
                    }
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
                                Text("出所：\(fund.series.source.name)")
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
                    Text("起動・復帰時に、前回の確認成功から6時間以上経過していれば更新を確認します。旧形式の価格データを保存している場合は6時間を待たずに確認します。手動更新もできます。通信に失敗した場合は正常な保存データを保持します。")
                    Text("データ基準日は、2商品の観測値が揃う最後の日です。今日のリアルタイム価格やファイルの公開日時ではありません。")
                }
                Section("計算のしかた") {
                    Text(isSample
                        ? "評価額 ＝ 元本 × 終了日の系列値 ÷ 開始日の系列値\n損益 ＝ 評価額 − 元本\n損益率 ＝（終了値 ÷ 開始値 − 1）× 100"
                        : "評価額 ＝ 元本 × 終了日の基準価額 ÷ 開始日の基準価額\n損益 ＝ 評価額 − 元本\n損益率 ＝（終了日の基準価額 ÷ 開始日の基準価額 − 1）× 100")
                    Text("入力金額をそれぞれの商品に全額投資した場合を比較します。2商品への分割投資ではありません。指定日以降で両方のデータが揃う最初の日から、最後の共通日までで計算します。履歴開始前の期間は計算できません。")
                    if let result {
                        row("比較する投資信託", result.funds.map(\.descriptor.displayName).joined(separator: "\n"))
                        row("それぞれの投資金額", MoneyFormat.yen(Decimal(result.input.amount)))
                        row("指定した日", result.requestedDate.label)
                        row("算出基準日", result.endDate.label)
                        row("計算に使用した日", "\(result.startDate.label)〜\(result.endDate.label)")
                    }
                    Text(isSample
                        ? "今回は分配金再投資を表す架空の指数を使っています。分配金を別に加算していません。"
                        : "通常の基準価額（1万口あたり）を使います。分配金の受取額・再投資は計算に含めません。分配金が支払われた場合、表示する増減額にはその受取分が含まれないため、投資全体の損益とは異なります。")
                    Text("内部では10進数で計算し、表示時に円単位で四捨五入します。表示損益は表示評価額から元本を引き、差額は2つの表示評価額から求めます。損益率は小数1桁表示です。")
                }
                Section("比較の前提") {
                    Text("売却時の税金、購入・換金時の手数料等は計算していません。注文・約定日・端数処理を完全に再現するものではありません。")
                    if !isSample {
                        Text("使用する基準価額は運用管理費用（信託報酬）控除後です。信託報酬をもう一度差し引くことはしません。")
                        Text("「オルカン」は三菱UFJアセットマネジメントの登録商標です。")
                    }
                    Text("過去の比較結果は将来の成果を保証しません。特定の商品の購入・売却を推奨するものではありません。")
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
