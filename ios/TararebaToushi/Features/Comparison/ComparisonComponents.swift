import SwiftUI

enum AppPalette {
    static let teal = Color("InvestmentTeal")
    static let blue = Color("InvestmentBlue")
    // Hues stay far apart so up to five lines and figures remain tellable apart.
    static let seriesColors = [
        teal, blue, Color("InvestmentViolet"), Color("InvestmentAmber"), Color("InvestmentRose"),
    ]
    static func series(_ index: Int) -> Color {
        seriesColors[min(max(index, 0), seriesColors.count - 1)]
    }
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

struct ComparisonSummaryCardView: View {
    let result: SimulationResult
    private var leader: FundResult? { result.ranking.first }
    private var isTied: Bool { result.displayedSpread == 0 }

    private var summary: String {
        guard let leader, !isTied else {
            return result.funds.count == 2
                ? "表示上の差額は0円。同じ結果でした。" : "表示上の金額はすべて同じ結果でした。"
        }
        return result.funds.count == 2
            ? "この期間では、\(leader.shortName)のほうが多い結果でした。"
            : "この期間で最も多かったのは\(leader.shortName)でした。"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) { difference }
                VStack(alignment: .leading, spacing: 8) { difference }
            }
            Text(summary)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("comparison-summary")
            if result.funds.count > 2 {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(result.ranking.enumerated()), id: \.element.id) { rank, fund in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(rank + 1).")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Text(fund.shortName)
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            Text(MoneyFormat.yen(fund.displayedValuation))
                                .font(.subheadline.weight(.medium))
                                .monospacedDigit()
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("rank-\(fund.id)")
                    }
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    @ViewBuilder private var difference: some View {
        Text(result.funds.count == 2 ? "この期間の差額" : "この期間の最大差")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        Text(MoneyFormat.yen(result.displayedSpread))
            .font(.system(.title3, design: .rounded, weight: .bold))
            .monospacedDigit()
            .accessibilityIdentifier("comparison-difference")
    }
}
