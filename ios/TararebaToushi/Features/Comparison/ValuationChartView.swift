import Charts
import SwiftUI

/// The lines are drawn from a thinned copy of each series; every amount shown beside the
/// chart is read from the untouched one, so no displayed figure depends on what the
/// thinning left out.
struct ValuationChartView: View {
    let result: SimulationResult
    @State private var selectedDate: Date?
    private let plotted: [[PlotPoint]]
    private let upperBound: Double

    init(result: SimulationResult) {
        self.result = result
        let plotted = result.funds.map { Self.plot($0.points) }
        let highest = plotted.flatMap { $0 }.map(\.value).max() ?? Double(result.input.amount)
        self.plotted = plotted
        // Zero stays on the axis: the distance between the lines is the answer the screen
        // gives, and a cropped baseline would enlarge it.
        self.upperBound = max(1, highest * 1.12)
    }

    private struct PlotPoint: Identifiable {
        let id: String
        let date: Date
        let value: Double
    }

    // Every selected fund is priced on the same common days, so the first one answers for all.
    private var days: [ValuationPoint] { result.funds.first?.points ?? [] }

    private var selectedIndex: Int {
        guard !days.isEmpty else { return 0 }
        guard let selectedDate else { return days.count - 1 }
        return days.indices.min(by: {
            abs(days[$0].day.date.timeIntervalSince(selectedDate))
                < abs(days[$1].day.date.timeIntervalSince(selectedDate))
        }) ?? 0
    }

    private var dateDomain: ClosedRange<Date> {
        if result.startDate == result.endDate {
            return result.startDate.date.addingTimeInterval(-43_200)...result.endDate.date.addingTimeInterval(43_200)
        }
        return result.startDate.date...result.endDate.date
    }

    // The middle date is dropped unless it stands clear of both ends: the last two common
    // days can sit a day apart, and their labels would then print on top of each other.
    private var axisDates: [Date] {
        guard let first = days.first?.day.date, let last = days.last?.day.date, first < last else {
            return days.first.map { [$0.day.date] } ?? []
        }
        let middle = days[days.count / 2].day.date
        let margin = last.timeIntervalSince(first) * 0.15
        guard middle.timeIntervalSince(first) > margin, last.timeIntervalSince(middle) > margin else {
            return [first, last]
        }
        return [first, middle, last]
    }

    private var chartDescription: String {
        let subject = result.funds.count == 1
            ? "\(result.funds[0].shortName)の評価額推移"
            : "\(result.funds.count)商品の評価額推移"
        let origin = result.isSample
            ? "実際の運用実績ではありません。" : "過去の基準価額から計算した値です。"
        return "\(subject)。\(origin)下の前後ボタンで観測日を選ぶと、その日の評価額を確認できます。"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("評価額の歩み").font(.headline).accessibilityAddTraits(.isHeader)
                Spacer()
                Text("円").font(.caption).foregroundStyle(.secondary)
            }
            chart
            readout
            Text("グラフをなぞると、その日の評価額を確認できます。共通の観測日のみを結んでいます。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .cardSurface()
    }

    private var chart: some View {
        Chart {
            RuleMark(y: .value("元本", result.input.amount))
                .foregroundStyle(Color.secondary.opacity(0.65))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            // Colour alone separates the series: eight hues stay tellable apart, eight
            // dash patterns do not.
            ForEach(Array(result.funds.enumerated()), id: \.element.id) { index, fund in
                ForEach(plotted[index]) { point in
                    LineMark(
                        x: .value("日付", point.date),
                        y: .value("評価額", point.value),
                        series: .value("商品", fund.id)
                    )
                    .foregroundStyle(AppPalette.series(index))
                    .lineStyle(StrokeStyle(lineWidth: 2, lineJoin: .round))
                    if plotted[index].count == 1 {
                        PointMark(x: .value("日付", point.date), y: .value("評価額", point.value))
                            .foregroundStyle(AppPalette.series(index))
                    }
                }
            }
            if days.indices.contains(selectedIndex), selectedDate != nil {
                RuleMark(x: .value("選択日", days[selectedIndex].day.date))
                    .foregroundStyle(Color.secondary.opacity(0.4))
            }
        }
        .chartYScale(domain: 0...upperBound)
        .chartXScale(domain: dateDomain)
        .chartXSelection(value: $selectedDate)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(
                            amount >= 10_000
                                ? "\(MoneyFormat.number(Decimal(amount / 10_000)))万"
                                : MoneyFormat.number(Decimal(amount))
                        )
                        .font(.caption2)
                    }
                }
            }
        }
        .chartXAxis {
            if result.startDate == result.endDate {
                AxisMarks(values: [result.startDate.date]) { _ in
                    AxisValueLabel { Text(result.startDate.label).font(.caption2) }
                }
            } else {
                AxisMarks(values: axisDates) { value in
                    AxisGridLine()
                    AxisValueLabel(
                        format: .dateTime.year(.twoDigits).month(.twoDigits).day(.twoDigits),
                        centered: false,
                        anchor: value.index == 0 ? .topLeading : value.index == axisDates.count - 1 ? .topTrailing : .top)
                        .font(.caption2)
                }
            }
        }
        .frame(height: 230)
        // Axis labels stop growing before they crowd out the plot. Nothing is lost by it:
        // the readout below repeats every date and amount at the reader's own text size.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        // One label for the whole plot: stepping through hundreds of marks one at a time
        // is no way to read it, and the rows below say the same thing in words.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(chartDescription)
        .accessibilityIdentifier("valuation-chart")
    }

    // Doubles as the legend, so the colours are never listed twice.
    @ViewBuilder private var readout: some View {
        if days.indices.contains(selectedIndex) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(days[selectedIndex].day.label)
                        .font(.subheadline.monospacedDigit().bold())
                        .accessibilityIdentifier("chart-selected-day")
                    Spacer()
                    Button("前の観測日", systemImage: "chevron.left") { select(index: selectedIndex - 1) }
                        .labelStyle(.iconOnly)
                        .frame(minWidth: 44, minHeight: 44)
                        .disabled(selectedIndex == 0)
                    Button("次の観測日", systemImage: "chevron.right") { select(index: selectedIndex + 1) }
                        .labelStyle(.iconOnly)
                        .frame(minWidth: 44, minHeight: 44)
                        .disabled(selectedIndex == days.count - 1)
                }
                ForEach(Array(result.funds.enumerated()), id: \.element.id) { index, fund in
                    row(
                        color: AppPalette.series(index), name: fund.shortName,
                        amount: fund.points[selectedIndex].amount
                    )
                    .accessibilityIdentifier("chart-value-\(fund.id)")
                }
                row(color: .secondary, dashed: true, name: "元本", amount: Decimal(result.input.amount))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func row(color: Color, dashed: Bool = false, name: String, amount: Decimal) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                SeriesSwatch(color: color, dashed: dashed)
                Text(name)
                Spacer(minLength: 8)
                Text(MoneyFormat.yen(amount)).fontWeight(.semibold).monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    SeriesSwatch(color: color, dashed: dashed)
                    Text(name)
                }
                Text(MoneyFormat.yen(amount)).fontWeight(.semibold).monospacedDigit()
            }
        }
        .font(.caption)
        .accessibilityElement(children: .combine)
    }

    private func select(index: Int) {
        guard days.indices.contains(index) else { return }
        selectedDate = days[index].day.date
    }

    // Drawn with the same stroke as the mark it stands for.
    private struct SeriesSwatch: View {
        let color: Color
        let dashed: Bool
        @ScaledMetric(relativeTo: .caption) private var width: CGFloat = 16

        var body: some View {
            Path {
                $0.move(to: CGPoint(x: 1.5, y: 1.5))
                $0.addLine(to: CGPoint(x: width - 1.5, y: 1.5))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: dashed ? [3, 3] : []))
            .frame(width: width, height: 3)
            .accessibilityHidden(true)
        }
    }

    // Eight full histories run past ten thousand points and Swift Charts turns sluggish
    // long before that. Each bucket keeps its highest and its lowest observation, so every
    // peak and trough survives at its own date; nothing is averaged, moved or invented.
    static let plottedPointLimit = 600

    private static func plot(_ points: [ValuationPoint]) -> [PlotPoint] {
        thinned(points).map {
            PlotPoint(
                id: $0.day.rawValue, date: $0.day.date,
                value: NSDecimalNumber(decimal: $0.amount).doubleValue)
        }
    }

    static func thinned(_ points: [ValuationPoint]) -> [ValuationPoint] {
        guard points.count > plottedPointLimit else { return points }
        let buckets = plottedPointLimit / 2
        var kept = [0]
        for bucket in 0..<buckets {
            let range = (points.count * bucket / buckets)..<(points.count * (bucket + 1) / buckets)
            guard let low = range.min(by: { points[$0].amount < points[$1].amount }),
                let high = range.max(by: { points[$0].amount < points[$1].amount })
            else { continue }
            for index in [min(low, high), max(low, high)] where index != kept[kept.count - 1] {
                kept.append(index)
            }
        }
        if kept[kept.count - 1] != points.count - 1 { kept.append(points.count - 1) }
        return kept.map { points[$0] }
    }
}
