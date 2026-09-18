import SwiftUI

enum AppPalette {
    static let teal = Color("InvestmentTeal")
    static let blue = Color("InvestmentBlue")
    // Hues stay far apart so up to eight lines and figures remain tellable apart:
    // 35° 81° 127° 178° 222° 269° 303° 335°, never closer than 32°. Eight is the
    // practical limit for telling the lines apart; a ninth needs another cue than hue.
    // Appended, never reordered: the index decides a fund's colour.
    static let seriesColors = [
        teal, blue, Color("InvestmentViolet"), Color("InvestmentAmber"), Color("InvestmentRose"),
        Color("InvestmentGreen"), Color("InvestmentLime"), Color("InvestmentMagenta"),
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
                Text(MoneyFormat.signed(result.returnPercent, digits: 1) + "%")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("return-\(result.id)")
            }
            VStack(alignment: .leading, spacing: 6) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) { valuation }
                    VStack(alignment: .leading, spacing: 4) { valuation }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) { deepestLoss }
                    VStack(alignment: .leading, spacing: 4) { deepestLoss }
                }
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

    @ViewBuilder private var deepestLoss: some View {
        Text("いちばん沈んだとき")
            .font(.caption)
            .foregroundStyle(.secondary)
        Text(result.deepestLoss?.label ?? "元本割れなし")
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .accessibilityIdentifier("deepest-loss-\(result.id)")
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

// A monthly plan set against the same principal paid in at once on its start day.
struct LumpSumComparisonCardView: View {
    let result: SimulationResult

    // Each row already answers for its own fund, so one fund needs no summary.
    private var summary: String? {
        guard result.funds.count > 1 else { return nil }
        let advantages = result.funds.map(\.displayedLumpSumAdvantage)
        let lumpSum = advantages.filter { $0 > 0 }.count
        let monthly = advantages.filter { $0 < 0 }.count
        let tied = advantages.count - lumpSum - monthly
        let everyFund = advantages.count == 2 ? "2商品とも" : "すべての商品で"
        if lumpSum == advantages.count { return "この期間は、\(everyFund)一括のほうが多い結果でした。" }
        if monthly == advantages.count { return "この期間は、\(everyFund)積立のほうが多い結果でした。" }
        if tied == advantages.count { return "この期間は、表示上すべて同じ金額でした。" }
        let parts = [
            lumpSum > 0 ? "一括のほうが多かったのは\(lumpSum)商品" : nil,
            monthly > 0 ? "積立のほうが多かったのは\(monthly)商品" : nil,
            tied > 0 ? "同じ金額だったのは\(tied)商品" : nil,
        ]
        return "この期間、" + parts.compactMap { $0 }.joined(separator: "、") + "でした。"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("一括で投資していたら")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text("同じ元本\(MoneyFormat.yen(result.principal))を、\(result.startDate.label)にまとめて投資した場合です。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(result.funds) { fund in
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            name(fund)
                            Spacer(minLength: 8)
                            figures(fund, alignment: .trailing)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            name(fund)
                            figures(fund, alignment: .leading)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("lump-sum-\(fund.id)")
                }
            }
            if let summary {
                Text(summary)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("lump-sum-summary")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func name(_ fund: FundResult) -> some View {
        Text(fund.shortName)
            .font(.subheadline)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func figures(_ fund: FundResult, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(MoneyFormat.yen(fund.displayedLumpSumValuation))
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
            Text(verdict(fund))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            // Beside the fund card's own figure, what paying everything in first had to sit through.
            Text("いちばん沈んだとき：\(fund.lumpSumDeepestLoss?.label ?? "元本割れなし")")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func verdict(_ fund: FundResult) -> String {
        let advantage = fund.displayedLumpSumAdvantage
        if advantage > 0 { return "一括のほうが\(MoneyFormat.yen(advantage))多い" }
        if advantage < 0 { return "積立のほうが\(MoneyFormat.yen(-advantage))多い" }
        return "同じ金額"
    }
}
