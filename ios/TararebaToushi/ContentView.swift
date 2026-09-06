import SwiftUI

struct ContentView: View {
    @State private var repository = FundRepository.makeDefault()
    @State private var model = ComparisonModel()
    @State private var showsInformation = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicType
    @FocusState private var amountFocused: Bool

    private var automaticallyRefreshes: Bool {
        #if DEBUG
            !ProcessInfo.processInfo.arguments.contains("--offline-sample")
                && ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
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
                    if let error = model.inputError {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.callout)
                            .foregroundStyle(.orange)
                            .accessibilityIdentifier("input-error")
                    }
                    if let result = model.result {
                        results(result)
                    } else if repository.isLoading {
                        ProgressView("サンプルを読み込んでいます").frame(maxWidth: .infinity)
                    } else if repository.dataset == nil {
                        ContentUnavailableView(
                            "データを読み込めませんでした", systemImage: "chart.xyaxis.line",
                            description: Text("下の「データを更新」から再試行できます。"))
                    }
                    dataFooter
                }
                .padding(20)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .scrollDismissesKeyboard(.interactively)
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
            .sheet(isPresented: $showsInformation) { DataInformationView(repository: repository, result: model.result) }
            .task {
                await repository.start(refresh: automaticallyRefreshes)
                model.recalculate(dataset: repository.dataset)
            }
            .onChange(of: repository.dataset?.snapshot.manifest.datasetVersion) { _, _ in
                model.recalculate(dataset: repository.dataset)
            }
            .onChange(of: model.amountText) { _, _ in model.recalculate(dataset: repository.dataset) }
            .onChange(of: model.selectedDate) { _, _ in model.recalculate(dataset: repository.dataset) }
            .onChange(of: amountFocused) { _, focused in if !focused { model.finishAmountEditing() } }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, automaticallyRefreshes { Task { await repository.refresh() } }
            }
            .refreshable { await repository.refresh(force: true) }
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
            Text("同じ金額、同じ期間。ふたつの選択を比べよう。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            SampleNoticeView()
        }
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("もしも、この金額を", systemImage: "yensign.circle")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                TextField("1,000,000", text: $model.amountText)
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .keyboardType(.numberPad)
                    .focused($amountFocused)
                    .accessibilityLabel("投資金額")
                    .accessibilityIdentifier("investment-amount")
                Text("円").font(.title3).foregroundStyle(.secondary)
            }
            Divider()
            DatePicker("投資した日", selection: $model.selectedDate, displayedComponents: .date)
                .font(.subheadline.weight(.medium))
                .accessibilityIdentifier("investment-date")
            HStack(spacing: 10) {
                ForEach([1, 3, 5], id: \.self) { years in
                    Button {
                        amountFocused = false
                        if let day = model.preset(years: years, dataset: repository.dataset) {
                            model.selectedDate = day.date
                        }
                    } label: {
                        Text("\(years)年前").font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppPalette.teal)
                    .background(AppPalette.teal.opacity(0.09), in: Capsule())
                    .disabled(model.preset(years: years, dataset: repository.dataset) == nil)
                    .accessibilityIdentifier("preset-\(years)")
                }
            }
            if let dataset = repository.dataset {
                Text("「N年前」はデータ基準日（\(dataset.endDate.label)）からの期間です。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .cardSurface()
    }

    private func results(_ result: SimulationResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("ふたつの、たられば").font(.title3.bold()).accessibilityAddTraits(.isHeader)
                Text("\(result.startDate.label) → \(result.endDate.label)")
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                if result.startDate != result.requestedDate {
                    Text("指定日 \(result.requestedDate.label) 以降で、両方のデータが揃う最初の日から計算しています。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            let layout =
                dynamicType >= .xxxLarge
                ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
            layout {
                ForEach(Array(result.funds.enumerated()), id: \.element.id) { index, fund in
                    FundResultCardView(result: fund, index: index)
                }
            }
            DifferenceCardView(result: result)
            ValuationChartView(result: result)
                .id(
                    "\(result.input.amount)-\(result.startDate.rawValue)-\(result.endDate.rawValue)-\(repository.dataset?.snapshot.manifest.datasetVersion ?? "")"
                )
            Text("サンプルデータによる概算です。実際の運用実績ではありません。税金・購入手数料等は含みません。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var dataFooter: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(repository.statusLabel, systemImage: repository.origin == .bundled ? "iphone" : "checkmark.icloud")
                .font(.subheadline.weight(.medium))
            if let message = repository.message {
                Text(message).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("update-message")
            } else if repository.isStale {
                Text("更新確認が必要です。表示中のデータで比較できます。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button {
                amountFocused = false
                Task { await repository.refresh(force: true) }
            } label: {
                HStack {
                    if repository.isRefreshing { ProgressView() }
                    Label(repository.isRefreshing ? "更新を確認中…" : "データを更新", systemImage: "arrow.clockwise")
                }
                .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .disabled(repository.isRefreshing || repository.isLoading)
            .accessibilityIdentifier("refresh-data")
            Button("データと計算について") { showsInformation = true }
                .font(.footnote).frame(maxWidth: .infinity)
        }
        .padding(.bottom, 20)
    }
}

#Preview {
    ContentView()
}
