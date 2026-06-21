import AppKit
import CodexBarCore
import SwiftUI

private final class UsageHistoryMenuHostingView<Content: View>: NSHostingView<Content> {
    override var allowsVibrancy: Bool {
        true
    }
}

extension StatusItemController {
    @discardableResult
    func addUsageHistoryMenuItemIfNeeded(to menu: NSMenu, provider: UsageProvider, width: CGFloat) -> Bool {
        guard let submenu = self.makeUsageHistorySubmenu(provider: provider, width: width) else { return false }
        let item = NSMenuItem(title: L("Subscription Utilization"), action: nil, keyEquivalent: "")
        item.isEnabled = true
        item.representedObject = "usageHistorySubmenu"
        item.submenu = submenu
        menu.addItem(item)
        return true
    }

    func makeUsageHistorySubmenu(provider: UsageProvider, width: CGFloat? = nil) -> NSMenu? {
        guard self.store.supportsPlanUtilizationHistory(for: provider) else { return nil }
        guard !self.store.shouldHidePlanUtilizationMenuItem(for: provider) else { return nil }
        // The submenu now shows only the token-priced utilization summary; if there's no estimate
        // yet (insufficient data), there's nothing to display, so hide the row entirely.
        guard self.store.subscriptionUtilizationEstimate(for: provider) != nil else { return nil }
        if let width {
            return self.makeHostedSubviewPlaceholderMenu(
                chartID: Self.usageHistoryChartID,
                provider: provider,
                width: width)
        }
        return self.makeHostedSubviewPlaceholderMenu(chartID: Self.usageHistoryChartID, provider: provider)
    }

    func appendUsageHistoryChartItem(
        to submenu: NSMenu,
        provider: UsageProvider,
        width: CGFloat) -> Bool
    {
        // The old utilization history chart was confusing; the submenu now shows only the
        // token-priced "value used this month" summary card.
        guard self.menuCardRenderingEnabledForController,
              let estimate = self.store.subscriptionUtilizationEstimate(for: provider)
        else {
            return false
        }

        let summaryView = SubscriptionUtilizationSummaryView(estimate: estimate, width: width)
        let summaryHosting = UsageHistoryMenuHostingView(rootView: summaryView)
        summaryHosting.frame = NSRect(
            origin: .zero,
            size: NSSize(width: width, height: self.hostedSubviewFittingHeight(for: summaryHosting, width: width)))
        let summaryItem = NSMenuItem()
        summaryItem.view = summaryHosting
        summaryItem.isEnabled = true
        summaryItem.representedObject = Self.usageHistoryChartID
        summaryItem.toolTip = provider.rawValue
        submenu.addItem(summaryItem)
        return true
    }
}
