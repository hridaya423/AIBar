import CodexBarCore
import SwiftUI

struct SubscriptionValueSummaryView: View {
    let estimate: SubscriptionValueEstimate
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("Subscription value this month"))
                    .font(.subheadline.weight(.medium))
                Spacer(minLength: 8)
                Text("\(Int((self.estimate.utilization * 100).rounded()))%")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    .monospacedDigit()
            }
            ProgressView(value: min(1, self.estimate.utilization))
                .progressViewStyle(.linear)
            Text(verbatim: "\(UsageFormatter.currencyString(self.estimate.usedUSD, currencyCode: "USD")) / ~"
                + UsageFormatter.currencyString(self.estimate.monthlyMaxUSD, currencyCode: "USD"))
                .font(.caption)
                .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
