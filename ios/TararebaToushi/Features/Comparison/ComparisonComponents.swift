import SwiftUI

enum AppPalette {
    static let teal = Color("InvestmentTeal")
    static let blue = Color("InvestmentBlue")
    static func series(_ index: Int) -> Color { index == 0 ? teal : blue }
}

extension View {
    func cardSurface() -> some View {
        self
            .padding(20)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
    }
}

struct DataNoticeView: View {
    let mode: DatasetMode

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(mode == .sample ? "サンプルデータ" : "投資信託の実データ").fontWeight(.semibold)
                Text(mode == .sample ? "実際の運用実績ではありません" : "出典：三菱UFJアセットマネジメント")
            }
        } icon: {
            Image(systemName: mode == .sample ? "sparkles.rectangle.stack" : "chart.xyaxis.line")
        }
        .font(.caption)
        .foregroundStyle(Color.primary.opacity(0.8))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((mode == .sample ? Color.orange : AppPalette.teal).opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

struct FundResultCardView: View {
    let result: FundResult
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(result.descriptor.displayName)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                Text("増減額")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(MoneyFormat.signed(result.displayedProfit) + "円")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(result.displayedProfit <= 0 ? Color.primary : AppPalette.series(index))
                    .accessibilityIdentifier("profit-\(result.id)")
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) { valuation }
                VStack(alignment: .leading, spacing: 4) { valuation }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var valuation: some View {
        Text("投資後の金額")
            .font(.caption)
            .foregroundStyle(.secondary)
        Text(MoneyFormat.yen(result.displayedValuation))
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .accessibilityIdentifier("valuation-\(result.id)")
    }
}

struct DifferenceCardView: View {
    let result: SimulationResult
    private var winner: String? {
        guard result.displayedDifference != 0 else { return nil }
        return result.funds[result.displayedDifference > 0 ? 1 : 0].descriptor.displayName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("この条件での差額", systemImage: "arrow.left.arrow.right").font(.subheadline.weight(.medium))
            Text(MoneyFormat.yen(abs(result.displayedDifference)))
                .font(.system(.largeTitle, design: .rounded, weight: .bold)).monospacedDigit()
                .minimumScaleFactor(0.65).lineLimit(1).accessibilityIdentifier("comparison-difference")
            Text(winner.map { "この期間では、\($0)のほうが多い結果でした。" } ?? "表示上の差額は0円。同じ結果でした。")
                .font(.subheadline).fixedSize(horizontal: false, vertical: true)
            Text(result.isSample ? "架空のサンプルによる比較です" : "過去のデータによる比較です。将来の成果を保証しません。")
                .font(.caption).opacity(0.85)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(Color(red: 0.08, green: 0.28, blue: 0.3), in: RoundedRectangle(cornerRadius: 24))
    }
}
