import SwiftUI

struct SimulationResultView: View {
    let result: SimulationResult
    let fund: FundResult
    let repository: FundRepository
    @State private var showsInformation = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(MoneyFormat.yen(Decimal(result.input.amount)))を投資していたら")
                        .font(.title3.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text("\(result.startDate.label) 〜 \(result.endDate.label)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                FundResultCardView(result: fund, index: result.input.fund == .sp500 ? 1 : 0)
                Text(result.isSample
                    ? "サンプルデータによる概算です。実際の運用実績ではありません。"
                    : "過去のデータによる概算です。税金・購入手数料等は含みません。")
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
            .frame(maxWidth: 560)
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
