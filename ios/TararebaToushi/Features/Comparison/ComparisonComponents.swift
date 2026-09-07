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
                Text(mode == .sample ? "実際の運用実績ではありません" : "出所：三菱UFJアセットマネジメント")
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
            Text(result.shortName)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(result.descriptor.displayName)
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
    private var higherFund: String? {
        guard result.displayedDifference != 0 else { return nil }
        return result.funds[result.displayedDifference > 0 ? 1 : 0].shortName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) { difference }
                VStack(alignment: .leading, spacing: 8) { difference }
            }
            Text(higherFund.map { "この期間では、\($0)のほうが多い結果でした。" }
                ?? "表示上の差額は0円。同じ結果でした。")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("comparison-summary")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    @ViewBuilder private var difference: some View {
        Text("この期間の差額")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        Text(MoneyFormat.yen(abs(result.displayedDifference)))
            .font(.system(.title3, design: .rounded, weight: .bold))
            .monospacedDigit()
            .accessibilityIdentifier("comparison-difference")
    }
}
