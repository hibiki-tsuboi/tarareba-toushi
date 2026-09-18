import SwiftUI

struct ContentView: View {
    @State private var repository = FundRepository.makeDefault()
    @State private var model = ComparisonModel()
    @State private var showsInformation = false
    @State private var showsFundPicker = false
    @State private var showsResults = false
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var amountFocused: Bool

    private var automaticallyRefreshes: Bool {
        #if DEBUG
            ProcessInfo.processInfo.arguments.contains("--ui-testing")
                || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
        #else
            true
        #endif
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    introduction
                    inputCard
                    if repository.dataset == nil { initialDataStatus }
                }
                .padding(20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .scrollDismissesKeyboard(.interactively)
            // Always in reach, whatever part of the form is on screen.
            .safeAreaBar(edge: .bottom) { actionBar }
            .navigationTitle("たられば投資")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("データと計算について", systemImage: "info.circle") { showsInformation = true }
                        .accessibilityIdentifier("data-info")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完了") { amountFocused = false }
                }
            }
            .sheet(isPresented: $showsInformation) { DataInformationView(repository: repository, result: nil) }
            .sheet(isPresented: $showsFundPicker) {
                if let dataset = repository.dataset {
                    FundPickerView(
                        funds: dataset.funds.map(\.descriptor),
                        selection: model.selectedIDs(in: dataset),
                        message: model.selectionMessage,
                        onToggle: { model.toggle($0, in: dataset) })
                }
            }
            .navigationDestination(isPresented: $showsResults) {
                if let result = model.result {
                    SimulationResultView(result: result, repository: repository)
                }
            }
            .task { await repository.start(refresh: automaticallyRefreshes) }
            // A saved or launch date may fall outside what the loaded data can compare.
            .onChange(of: repository.dataset?.snapshot.manifest.datasetVersion, initial: true) {
                if let dataset = repository.dataset { model.fitDate(in: dataset) }
            }
            .onChange(of: amountFocused) { _, focused in if !focused { model.finishAmountEditing() } }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, automaticallyRefreshes { Task { await repository.refresh() } }
            }
        }
        .tint(AppPalette.teal)
        .environment(\.locale, Locale(identifier: "ja_JP"))
        .environment(\.calendar, TradingDay.calendar)
        .environment(\.timeZone, TradingDay.calendar.timeZone)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("あのとき、\n投資していたら。")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .tracking(-0.6)
                .accessibilityAddTraits(.isHeader)
            Text("同じ条件で、選んだ投資信託を比べてみよう。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if repository.configuration.mode == .sample {
                Text("サンプルデータでシミュレーションします")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 12)
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let dataset = repository.dataset {
                SelectedFundsView(
                    funds: selectedFunds(in: dataset),
                    onChange: {
                        amountFocused = false
                        model.clearSelectionMessage()
                        showsFundPicker = true
                    })
                Divider()
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("投資のしかた")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Picker("投資のしかた", selection: planSelection) {
                    ForEach(InvestmentPlan.allCases, id: \.self) { plan in
                        Text(plan.label).tag(plan)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("investment-plan")
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text("開始日")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                DatePicker("開始日", selection: $model.selectedDate, in: dateBounds, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .accessibilityLabel("開始日")
                    .accessibilityIdentifier("investment-date")
                if let range = startRange {
                    Text("選べる期間：\(range.lowerBound.label)〜\(range.upperBound.label)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("date-range")
                }
                if let adjusted = model.adjustedDate, adjusted == model.selectedDate,
                    let day = try? TradingDay(date: adjusted)
                {
                    Label("選んだ商品のデータがそろう期間に合わせて、開始日を\(day.label)にしました。", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.tint)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("date-adjustment")
                }
                if model.plan == .monthly {
                    Text("毎月この日付に購入します。データのない日（休場日など）は、次にデータのある日に購入します。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text(amountTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    TextField(model.plan == .monthly ? "30,000" : "1,000,000", text: $model.amountText)
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.4)
                        .keyboardType(.numberPad)
                        .focused($amountFocused)
                        .accessibilityLabel(amountTitle)
                        .accessibilityIdentifier("investment-amount")
                    Text("円")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                Text(model.plan == .monthly
                    ? "選んだ商品それぞれに、毎月同じ金額を積み立てた場合を比較します。"
                    : "選んだ商品それぞれに、同じ金額を投資した場合を比較します。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .cardSurface()
    }

    private var amountTitle: String { model.plan == .monthly ? "毎月の積立額" : "投資金額" }

    // In delivered order, which is the order and colouring of the results.
    private func selectedFunds(in dataset: ValidatedDataset) -> [FundDescriptor] {
        let ids = Set(model.selectedIDs(in: dataset))
        return dataset.funds.map(\.descriptor).filter { ids.contains($0.id) }
    }

    private var startRange: ClosedRange<TradingDay>? {
        repository.dataset.flatMap { model.startRange(in: $0) }
    }

    // Whole days, so the time of day the picker carries never shuts out the last one.
    private var dateBounds: ClosedRange<Date> {
        guard let range = startRange else { return Date.distantPast...Date.distantFuture }
        let calendar = TradingDay.calendar
        let first = calendar.startOfDay(for: range.lowerBound.date)
        let lastDay = calendar.startOfDay(for: range.upperBound.date)
        let last = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: lastDay) ?? range.upperBound.date
        return first...last
    }

    private var actionBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let error = model.inputError {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("input-error")
            }
            simulateButton
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        // A bar that grew with the largest text sizes would cover most of the form it serves.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var planSelection: Binding<InvestmentPlan> {
        Binding(
            get: { model.plan },
            set: { plan in
                amountFocused = false
                model.select(plan)
            })
    }

    private var simulateTitle: String {
        guard let dataset = repository.dataset else { return "比較する" }
        let count = model.selectedIDs(in: dataset).count
        return count == 1 ? "結果を見る" : "\(count)つを比較する"
    }

    private var simulateButton: some View {
        Button {
            amountFocused = false
            model.finishAmountEditing()
            model.recalculate(dataset: repository.dataset)
            if model.result != nil { showsResults = true }
        } label: {
            Text(simulateTitle)
                .font(.headline)
                .foregroundStyle(Color(uiColor: .systemBackground))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: 18))
        .controlSize(.large)
        .disabled(repository.dataset == nil)
        .accessibilityIdentifier("simulate")
    }

    private var initialDataStatus: some View {
        VStack(alignment: .leading, spacing: 12) {
            if repository.isLoading || repository.isRefreshing {
                ProgressView("データを取得しています")
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("download-progress")
            } else if let message = repository.message {
                Text("データを取得できませんでした")
                    .font(.subheadline.weight(.medium))
                    .accessibilityIdentifier("initial-data-unavailable")
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("update-message")
                Button("再試行") {
                    amountFocused = false
                    Task { await repository.refresh(force: true) }
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("refresh-data")
            }
        }
    }
}

#Preview {
    ContentView()
}
