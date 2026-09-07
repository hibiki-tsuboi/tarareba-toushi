import SwiftUI

struct FundPickerView: View {
    @Binding var selection: InvestmentFund
    @Environment(\.dynamicTypeSize) private var dynamicType

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("投資信託")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            let layout = dynamicType.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
            layout {
                ForEach(InvestmentFund.allCases) { fund in
                    choice(fund)
                }
            }
        }
    }

    private func choice(_ fund: InvestmentFund) -> some View {
        let isSelected = selection == fund
        return Button {
            selection = fund
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .accessibilityHidden(true)
                Text(fund.displayName)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .foregroundStyle(isSelected ? AppPalette.teal : Color.primary)
            .background(isSelected ? AppPalette.teal.opacity(0.1) : Color.clear,
                in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(isSelected ? AppPalette.teal : Color.secondary.opacity(0.3), lineWidth: 1.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(fund.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("fund-\(fund.id)")
    }
}
