import SwiftUI

struct ToolConfirmationBlock: View {
    let pending: PendingToolCall
    var onConfirm: ([String: String]) -> Void
    var onCancel: () -> Void

    @State private var arguments: [String: String]

    init(
        pending: PendingToolCall,
        onConfirm: @escaping ([String: String]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.pending = pending
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _arguments = State(initialValue: pending.arguments)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.cyan)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Confirm Tool Action")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text(pending.displayName)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }

            if pending.schema.isEmpty {
                Text("This action does not require extra details.")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(pending.schema.keys.sorted(), id: \.self) { key in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(key)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(.secondary)
                            TextField(pending.schema[key] ?? key, text: binding(for: key))
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                Button(role: .cancel, action: onCancel) {
                    Text("Cancel")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    onConfirm(arguments)
                } label: {
                    Text("Confirm")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.2), radius: 30, x: 0, y: 16)
        )
        .padding(.horizontal, 32)
    }

    private func binding(for key: String) -> Binding<String> {
        Binding(
            get: { arguments[key] ?? "" },
            set: { arguments[key] = $0 }
        )
    }
}
