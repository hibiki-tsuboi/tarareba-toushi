import SwiftUI

// Chosen from a sheet so the input screen can show every setting at once, with room
// here to say what each fund holds.
struct FundPickerView: View {
    let funds: [FundDescriptor]
    let selection: [String]
    let message: String?
    let onToggle: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("\(selection.count)商品を選択中（\(AppConfiguration.maximumComparisonFunds)商品まで選べます）")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("fund-selection-count")
                    if let message {
                        Label(message, systemImage: "exclamationmark.circle")
                            .font(.callout)
                            .foregroundStyle(.orange)
                            .accessibilityIdentifier("fund-selection-error")
                    }
                    VStack(spacing: 8) {
                        ForEach(funds) { fund in
                            choice(fund)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("比べる投資信託")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                        .accessibilityIdentifier("fund-picker-done")
                }
            }
        }
    }

    private func choice(_ fund: FundDescriptor) -> some View {
        let isSelected = selection.contains(fund.id)
        let index = selection.firstIndex(of: fund.id) ?? 0
        return Button {
            onToggle(fund.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(isSelected ? AppPalette.series(index) : Color.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(fund.shortName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.primary)
                    Text(fund.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(isSelected ? AppPalette.series(index).opacity(0.1) : Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(isSelected ? AppPalette.series(index) : Color.secondary.opacity(0.3),
                        lineWidth: 1.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(fund.shortName)、\(fund.summary)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("fund-\(fund.id)")
    }
}
