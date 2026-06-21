import CodexBarCore
import SwiftUI

struct CodexResetCreditsPresentation: Equatable {
    let text: String
    let detailText: String?
    let helpText: String?
    let creditToConsume: CodexRateLimitResetCredit?
}

struct CodexResetCreditsContent: View {
    let model: CodexResetCreditsPresentation

    @State private var showsDetails = false

    @Environment(\.menuItemHighlighted) private var isHighlighted
    @Environment(\.codexResetCreditConsumer) private var consumeCredit

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                self.showsDetails.toggle()
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    Text(self.model.text)
                        .font(.body)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: self.showsDetails ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                }
            }
            .buttonStyle(.plain)
            .help(self.model.helpText ?? self.model.text)

            if self.showsDetails {
                ForEach(self.detailLines, id: \.self) { line in
                    Text(line)
                        .font(.footnote)
                        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                        .lineLimit(2)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let detailText = self.model.detailText, !detailText.isEmpty {
                    Text(detailText)
                        .font(.footnote)
                        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                        .lineLimit(1)
                }
                Spacer()
                if let creditToConsume = self.model.creditToConsume, let consumeCredit {
                    Button(L("Use Reset")) {
                        consumeCredit(creditToConsume)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help(L("Use the next expiring Codex reset credit"))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(self.model.helpText ?? self.model.text)
        .accessibilityElement(children: .combine)
        .accessibilityLabel([
            self.model.text,
            self.model.detailText,
        ].compactMap(\.self).joined(separator: ", "))
    }

    private var detailLines: [String] {
        self.model.helpText?.components(separatedBy: "\n").filter { !$0.isEmpty } ?? []
    }
}

extension UsageMenuCardView.Model {
    static func codexResetCredits(input: Input) -> CodexResetCreditsPresentation? {
        guard let text = codexResetCreditsText(input: input) else { return nil }
        return CodexResetCreditsPresentation(
            text: text,
            detailText: Self.codexResetCreditsDetailText(input: input),
            helpText: Self.codexResetCreditsHelpText(input: input),
            creditToConsume: Self.codexResetCreditToConsume(input: input))
    }

    static func codexResetCreditsText(input: Input) -> String? {
        guard input.provider == .codex,
              let resetCredits = input.snapshot?.codexResetCredits,
              resetCredits.availableCount > 0
        else {
            return nil
        }
        if resetCredits.availableCount == 1 {
            return L("1 manual reset available")
        }
        return String(format: L("%d manual resets available"), resetCredits.availableCount)
    }

    static func codexResetCreditToConsume(input: Input) -> CodexRateLimitResetCredit? {
        guard input.provider == .codex
        else {
            return nil
        }
        return input.snapshot?.codexResetCredits?.nextExpiringAvailableCredit
    }

    static func codexResetCreditsDetailText(input: Input) -> String? {
        guard input.provider == .codex,
              let resetCredits = input.snapshot?.codexResetCredits,
              let expiresAt = resetCredits.nextExpiringAvailableCredit?.expiresAt
        else {
            return nil
        }
        let timeText: String
        switch input.resetTimeDisplayStyle {
        case .absolute:
            timeText = UsageFormatter.resetDescription(from: expiresAt, now: input.now)
        case .countdown:
            let countdown = UsageFormatter.resetCountdownDescription(from: expiresAt, now: input.now)
            timeText = countdown == "now" ? L("now") : countdown
        }
        return String(format: L("Next expires %@"), timeText)
    }

    static func codexResetCreditsHelpText(input: Input) -> String? {
        guard input.provider == .codex,
              let resetCredits = input.snapshot?.codexResetCredits
        else {
            return nil
        }
        let lines = resetCredits.credits.map { credit in
            let expires = Self.codexResetCreditExpiryText(credit, now: input.now)
            return "\(credit.status.rawValue), \(expires)"
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private static func codexResetCreditExpiryText(
        _ credit: CodexRateLimitResetCredit,
        now: Date)
        -> String
    {
        guard let expiresAt = credit.expiresAt else { return L("No expiry") }
        let absolute = UsageFormatter.resetDescription(from: expiresAt, now: now)
        guard credit.status == .available, expiresAt > now else { return absolute }
        let countdown = UsageFormatter.resetCountdownDescription(from: expiresAt, now: now)
        return "\(countdown) (\(absolute))"
    }
}
