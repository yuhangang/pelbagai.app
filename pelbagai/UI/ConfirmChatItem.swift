import SwiftUI

// MARK: - Confirm Chat Item Data Model

/// A single selectable option within a confirm chat item.
struct ConfirmChatOption: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String?
    let icon: String? // SF Symbol name

    init(title: String, subtitle: String? = nil, icon: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
    }
}

/// Describes a decision point to present inline in a chat timeline.
struct ConfirmChatRequest: Identifiable {
    let id = UUID()
    let headline: String
    let message: String?
    let options: [ConfirmChatOption]
    let accentColor: Color
    let allowsDismiss: Bool

    init(
        headline: String,
        message: String? = nil,
        options: [ConfirmChatOption],
        accentColor: Color = .cyan,
        allowsDismiss: Bool = true
    ) {
        self.headline = headline
        self.message = message
        self.options = options
        self.accentColor = accentColor
        self.allowsDismiss = allowsDismiss
    }
}

// MARK: - Confirm Chat Item View

/// A premium glassmorphic card that presents a decision to the user inline
/// within a chat timeline. Reusable across ChatView and WorkbenchView.
struct ConfirmChatItem: View {
    let request: ConfirmChatRequest
    var onSelect: (ConfirmChatOption) -> Void
    var onDismiss: (() -> Void)?

    @State private var selectedOptionID: UUID?
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Accent gradient bar
            request.accentColor
                .frame(height: 3)
                .frame(maxWidth: .infinity)
                .clipShape(UnevenRoundedRectangle(
                    topLeadingRadius: 24,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 24
                ))

            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(request.accentColor.opacity(0.15))
                            .frame(width: 36, height: 36)
                        Image(systemName: "questionmark.bubble.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(request.accentColor)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(request.headline)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        if let message = request.message, !message.isEmpty {
                            Text(message)
                                .font(.system(size: 13, design: .rounded))
                                .foregroundColor(.secondary)
                                .lineSpacing(2)
                        }
                    }
                }

                // Options
                if !request.options.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(Array(request.options.enumerated()), id: \.element.id) { index, option in
                            ConfirmOptionButton(
                                option: option,
                                accentColor: request.accentColor,
                                isSelected: selectedOptionID == option.id,
                                delay: Double(index) * 0.06
                            ) {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                    selectedOptionID = option.id
                                }
                                // Brief delay so the user sees the selection state
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                    onSelect(option)
                                }
                            }
                        }
                    }
                }

                // Dismiss / Skip button
                if request.allowsDismiss, let onDismiss = onDismiss {
                    Button(action: onDismiss) {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                            Text("Skip")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 14)
        }
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: request.accentColor.opacity(0.08), radius: 16, x: 0, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(request.accentColor.opacity(0.15), lineWidth: 0.5)
        )
        .scaleEffect(appeared ? 1.0 : 0.95)
        .opacity(appeared ? 1.0 : 0.0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                appeared = true
            }
        }
    }
}

// MARK: - Option Button

private struct ConfirmOptionButton: View {
    let option: ConfirmChatOption
    let accentColor: Color
    let isSelected: Bool
    let delay: Double
    let action: () -> Void

    @State private var appeared = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let icon = option.icon {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(accentColor.opacity(isSelected ? 0.2 : 0.08))
                            .frame(width: 34, height: 34)
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(accentColor)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                    if let subtitle = option.subtitle {
                        Text(subtitle)
                            .font(.system(size: 11, design: .rounded))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isSelected ? accentColor : .secondary.opacity(0.5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? accentColor.opacity(0.08) : Color.primary.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(isSelected ? accentColor.opacity(0.3) : Color.primary.opacity(0.06), lineWidth: 0.5)
                    )
            )
            .scaleEffect(isSelected ? 0.98 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isSelected)
        .opacity(appeared ? 1.0 : 0.0)
        .offset(y: appeared ? 0 : 8)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75).delay(delay)) {
                appeared = true
            }
        }
    }
}
