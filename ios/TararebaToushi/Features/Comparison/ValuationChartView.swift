import Charts
import SwiftUI

struct ValuationChartView: View {
    let result: SimulationResult
    @State private var selectedDate: Date?

    private var selectedIndex: Int {
        guard let points = result.funds.first?.points else { return 0 }
        guard let selectedDate else { return max(0, points.count - 1) }
        return points.indices.min(by: {
            abs(points[$0].day.date.timeIntervalSince(selectedDate))
                < abs(points[$1].day.date.timeIntervalSince(selectedDate))
        }) ?? 0
    }

    private var upperBound: Double {
        let maximum =
            result.funds.flatMap(\.points).map { NSDecimalNumber(decimal: $0.amount).doubleValue }.max()
            ?? Double(result.input.amount)
        return max(1, maximum * 1.12)
    }

    private var dateDomain: ClosedRange<Date> {
        if result.startDate == result.endDate {
            return result.startDate.date.addingTimeInterval(-43_200)...result.endDate.date.addingTimeInterval(43_200)
        }
        return result.startDate.date...result.endDate.date
    }

    private var axisDates: [Date] {
        guard let points = result.funds.first?.points, !points.isEmpty else { return [] }
        return Array(Set([points[0].day.date, points[points.count / 2].day.date, points[points.count - 1].day.date])).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("評価額の歩み").font(.headline).accessibilityAddTraits(.isHeader)
                Spacer()
                Text("円").font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(result.funds.enumerated()), id: \.element.id) { i, fund in
                    Label(fund.descriptor.displayName, systemImage: i == 0 ? "circle.fill" : "diamond.fill")
                        .font(.caption)
                        .foregroundStyle(AppPalette.series(i))
                }
                Label("元本 \(MoneyFormat.yen(Decimal(result.input.amount)))", systemImage: "minus")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            chart
            if let first = result.funds.first, first.points.indices.contains(selectedIndex) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(first.points[selectedIndex].day.label).font(.subheadline.monospacedDigit().bold())
                        Spacer()
                        Button("前の観測日", systemImage: "chevron.left") { select(index: selectedIndex - 1) }
                            .labelStyle(.iconOnly)
                            .frame(minWidth: 44, minHeight: 44)
                            .disabled(selectedIndex == 0)
                        Button("次の観測日", systemImage: "chevron.right") { select(index: selectedIndex + 1) }
                            .labelStyle(.iconOnly)
                            .frame(minWidth: 44, minHeight: 44)
                            .disabled(selectedIndex == first.points.count - 1)
                    }
                    ForEach(Array(result.funds.enumerated()), id: \.element.id) { i, fund in
                        ViewThatFits(in: .horizontal) {
                            HStack {
                                Text(fund.descriptor.displayName)
                                Spacer()
                                Text(MoneyFormat.yen(fund.points[selectedIndex].amount)).fontWeight(.semibold)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(fund.descriptor.displayName)
                                Text(MoneyFormat.yen(fund.points[selectedIndex].amount)).fontWeight(.semibold)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(AppPalette.series(i))
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(12)
                .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            }
            Text("グラフをなぞると、その日の評価額を確認できます。共通の観測日のみを結んでいます。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cardSurface()
    }

    private var chart: some View {
        Chart {
            RuleMark(y: .value("元本", result.input.amount))
                .foregroundStyle(Color.secondary.opacity(0.65))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            ForEach(Array(result.funds.enumerated()), id: \.element.id) { i, fund in
                ForEach(fund.points) { point in
                    LineMark(
                        x: .value("日付", point.day.date),
                        y: .value("評価額", NSDecimalNumber(decimal: point.amount).doubleValue),
                        series: .value("商品", fund.id)
                    )
                    .foregroundStyle(AppPalette.series(i))
                    .lineStyle(StrokeStyle(lineWidth: 2.5, dash: i == 0 ? [] : [6, 3]))
                    if fund.points.count == 1 {
                        PointMark(
                            x: .value("日付", point.day.date),
                            y: .value("評価額", NSDecimalNumber(decimal: point.amount).doubleValue)
                        )
                        .foregroundStyle(AppPalette.series(i))
                        .symbol(i == 0 ? .circle : .diamond)
                    }
                }
            }
            if let first = result.funds.first, first.points.indices.contains(selectedIndex), selectedDate != nil {
                RuleMark(x: .value("選択日", first.points[selectedIndex].day.date))
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
                }
            }
        }
        .frame(height: 230)
        .accessibilityLabel(result.isSample
            ? "2商品の評価額推移。実際の運用実績ではありません。下の前後ボタンでも観測日を選択できます。"
            : "過去の基準価額から計算した2商品の評価額推移。下の前後ボタンでも観測日を選択できます。")
    }

    private func select(index: Int) {
        guard let points = result.funds.first?.points, points.indices.contains(index) else { return }
        selectedDate = points[index].day.date
    }
}
