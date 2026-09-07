import SwiftUI

struct ContentView: View {
    @State private var repository = FundRepository.makeDefault()
    @State private var model = ComparisonModel()
    @State private var showsInformation = false
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
                    if let error = model.inputError {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.callout)
                            .foregroundStyle(.orange)
                            .accessibilityIdentifier("input-error")
                    }
                    simulateButton
                    if repository.dataset == nil { initialDataStatus }
                }
                .padding(20)
                .frame(maxWidth: 560)
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
            .sheet(isPresented: $showsInformation) { DataInformationView(repository: repository, result: nil) }
            .navigationDestination(isPresented: $showsResults) {
                if let result = model.result, let fund = result.selectedFund {
                    SimulationResultView(result: result, fund: fund, repository: repository)
                }
            }
            .task { await repository.start(refresh: automaticallyRefreshes) }
            .onChange(of: amountFocused) { _, focused in if !focused { model.finishAmountEditing() } }
            .onChange(of: model.selectedFund) { _, _ in amountFocused = false }
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
            Text("投資信託を選んで、結果を見てみよう。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if repository.configuration.mode == .sample {
                Text("サンプルデータでシミュレーションします")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 12)
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            FundPickerView(selection: $model.selectedFund)
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text("開始日")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                DatePicker("開始日", selection: $model.selectedDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .accessibilityLabel("開始日")
                    .accessibilityIdentifier("investment-date")
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text("投資金額")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    TextField("1,000,000", text: $model.amountText)
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.4)
                        .keyboardType(.numberPad)
                        .focused($amountFocused)
                        .accessibilityLabel("投資金額")
                        .accessibilityIdentifier("investment-amount")
                    Text("円")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .cardSurface()
    }

    private var simulateButton: some View {
        Button {
            amountFocused = false
            model.finishAmountEditing()
            model.recalculate(dataset: repository.dataset)
            if model.result != nil { showsResults = true }
        } label: {
            Text("シミュレート")
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
