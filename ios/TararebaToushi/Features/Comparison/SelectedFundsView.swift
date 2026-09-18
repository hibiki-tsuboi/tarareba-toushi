import SwiftUI

// The chosen funds on the input screen, in the colours their results will use. The whole
// block opens the picker, so there is no small target to find.
struct SelectedFundsView: View {
    let funds: [FundDescriptor]
    let onChange: () -> Void

    var body: some View {
        Button(action: onChange) {
            VStack(alignment: .leading, spacing: 10) {
                // At the largest text sizes the title would otherwise break mid-word.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        title
                        Spacer(minLength: 8)
                        change
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        title
                        change
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(funds.enumerated()), id: \.element.id) { index, fund in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            // Sized with the text, so it stays beside the name at every text size.
                            Image(systemName: "circle.fill")
                                .font(.caption2)
                                .foregroundStyle(AppPalette.series(index))
                            ViewThatFits(in: .horizontal) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) { describe(fund) }
                                VStack(alignment: .leading, spacing: 2) { describe(fund) }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("比べる投資信託：\(funds.map(\.shortName).joined(separator: "、"))")
        .accessibilityHint("商品を選び直せます")
        .accessibilityIdentifier("fund-selection")
    }

    private var title: some View {
        Text("比べる投資信託")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
    }

    private var change: some View {
        HStack(spacing: 2) {
            Text("変更")
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
        }
        .font(.subheadline)
        .foregroundStyle(.tint)
        .fixedSize()
    }

    @ViewBuilder private func describe(_ fund: FundDescriptor) -> some View {
        Text(fund.shortName)
            .font(.subheadline.weight(.semibold))
        Text(fund.summary)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
