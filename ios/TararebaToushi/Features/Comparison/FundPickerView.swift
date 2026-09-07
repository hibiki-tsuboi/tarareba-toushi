import SwiftUI

struct FundPickerView: View {
    let funds: [FundDescriptor]
    let selection: [String]
    let onToggle: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("比較する投資信託")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text("\(selection.count) / \(AppConfiguration.maximumComparisonFunds)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(AppConfiguration.maximumComparisonFunds)商品中\(selection.count)商品を選択中")
                    .accessibilityIdentifier("fund-selection-count")
            }
            VStack(spacing: 8) {
                ForEach(funds) { fund in
                    choice(fund)
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
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(isSelected ? AppPalette.series(index) : Color.secondary)
                    .accessibilityHidden(true)
                Text(fund.shortName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .background(isSelected ? AppPalette.series(index).opacity(0.1) : Color.clear,
                in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(isSelected ? AppPalette.series(index) : Color.secondary.opacity(0.3),
                        lineWidth: 1.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(fund.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("fund-\(fund.id)")
    }
}
