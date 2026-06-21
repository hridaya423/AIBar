import CodexBarCore
import SwiftUI

@MainActor
struct SubscriptionUtilizationSummaryView: View {
    let estimate: SubscriptionUtilizationEstimate
    let width: CGFloat

    private var usedText: String {
        UsageFormatter.currencyString(self.estimate.monthlyUsedUSD, currencyCode: self.estimate.currencyCode)
    }

    private var maxText: String {
        UsageFormatter.currencyString(self.estimate.monthlyMaxUSD, currencyCode: self.estimate.currencyCode)
    }

    private var percentText: String {
        "\(Int(self.estimate.utilizationPercent.rounded()))%"
    }

    private var fillFraction: CGFloat {
        max(0, min(1, CGFloat(self.estimate.utilizationPercent) / 100))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("Subscription value this month"))
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 8)
                Text(self.percentText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.2))
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: self.fillFraction * geo.size.width)
                }
            }
            .frame(height: 6)

            Text(verbatim: "\(self.usedText) / ~\(self.maxText)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            if self.estimate.isProjected {
                Text(L("Estimate sharpens as your weekly limit fills."))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(width: self.width, alignment: .leading)
    }
}
