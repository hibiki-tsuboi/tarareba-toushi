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

struct SampleNoticeView: View {
    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text("サンプルデータ").fontWeight(.semibold)
                Text("実際の運用実績ではありません")
            }
        } icon: {
            Image(systemName: "sparkles.rectangle.stack")
        }
        .font(.caption)
        .foregroundStyle(Color.primary.opacity(0.8))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

struct FundResultCardView: View {
    let result: FundResult
    let index: Int
    @ScaledMetric(relativeTo: .title3) private var badgeSize: CGFloat = 38

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: index == 0 ? "globe.asia.australia.fill" : "chart.line.uptrend.xyaxis")
                .font(.title3).foregroundStyle(AppPalette.series(index))
                .frame(width: badgeSize, height: badgeSize)
                .background(AppPalette.series(index).opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            Text(result.descriptor.displayName)
                .font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 4) {
                Text("評価額").font(.caption).foregroundStyle(.secondary)
                Text(MoneyFormat.yen(result.displayedValuation))
                    .font(.system(.title2, design: .rounded, weight: .bold)).monospacedDigit()
                    .minimumScaleFactor(0.65).lineLimit(1)
                    .accessibilityIdentifier("valuation-\(result.id)")
            }
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text("損益").font(.caption).foregroundStyle(.secondary)
                Text(MoneyFormat.signed(result.displayedProfit) + "円")
                    .font(.subheadline.bold()).monospacedDigit().minimumScaleFactor(0.7).lineLimit(1)
                Text(MoneyFormat.signed(result.returnPercent, digits: 1) + "%")
                    .font(.caption.weight(.semibold)).monospacedDigit()
            }
            .foregroundStyle(result.displayedProfit < 0 ? Color.primary : AppPalette.series(index))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
        .accessibilityElement(children: .contain)
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
            Text("架空のサンプルによる比較です").font(.caption).opacity(0.85)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(Color(red: 0.08, green: 0.28, blue: 0.3), in: RoundedRectangle(cornerRadius: 24))
    }
}
