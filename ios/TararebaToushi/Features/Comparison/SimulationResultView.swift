import SwiftUI

struct SimulationResultView: View {
    let result: SimulationResult
    let repository: FundRepository
    @State private var showsInformation = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var resultsLayout: AnyLayout {
        horizontalSizeClass == .regular && !dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 16))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("それぞれに\(MoneyFormat.yen(Decimal(result.input.amount)))を投資していたら")
                        .font(.title3.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text("\(result.startDate.label) 〜 \(result.endDate.label)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                resultsLayout {
                    ForEach(Array(result.funds.enumerated()), id: \.element.id) { index, fund in
                        FundResultCardView(result: fund, index: index)
                    }
                }
                DifferenceCardView(result: result)
                VStack(alignment: .leading, spacing: 6) {
                    if !result.isSample {
                        Text("三菱UFJアセットマネジメント公表データをもとに、たられば投資が独自に算出しています。")
                        Text("算出基準日：\(result.endDate.label)")
                    }
                    Text(result.isSample
                        ? "サンプルデータによる概算です。実際の運用実績ではありません。"
                        : "通常の基準価額による概算です。分配金の受取額・再投資、税金・購入手数料等は含みません。")
                    if !result.isSample {
                        Text("過去の比較結果は将来の成果を保証しません。")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                Button {
                    dismiss()
                } label: {
                    Text("条件を変更する")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: 18))
                .controlSize(.large)
                .accessibilityIdentifier("edit-input")
            }
            .padding(20)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("シミュレーション結果")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("データと計算について", systemImage: "info.circle") { showsInformation = true }
                    .accessibilityIdentifier("data-info")
            }
        }
        .sheet(isPresented: $showsInformation) {
            DataInformationView(repository: repository, result: result)
        }
    }
}
