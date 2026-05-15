import SwiftUI

struct WorkbenchLibraryView: View {
    @ObservedObject var viewModel: WorkbenchViewModel
    @State private var showClearConfirm = false
    
    var body: some View {
        ZStack {
            if viewModel.savedResults.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "tray.full")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No stored data for this tool yet.")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
            } else {
                List {
                    Section {
                        ForEach(viewModel.savedResults.sorted(by: { $0.timestamp > $1.timestamp })) { result in
                            resultRow(result)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        viewModel.deleteResult(result)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    } header: {
                        HStack {
                            Text("\(viewModel.savedResults.count) Items")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                            Spacer()
                            Button(role: .destructive) {
                                showClearConfirm = true
                            } label: {
                                Text("Clear All")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
                .listStyle(InsetGroupedListStyle())
            }
        }
        .alert("Clear History", isPresented: $showClearConfirm) {
            Button("Clear All", role: .destructive) {
                viewModel.clearHistory()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete all history for \(viewModel.tool.displayName)? This cannot be undone.")
        }
    }
    
    private func resultRow(_ result: ScanResult) -> some View {
        Button {
            viewModel.editingResult = result
            viewModel.showEditSheet = true
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(result.timestamp, style: .date)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(viewModel.toolColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(viewModel.toolColor.opacity(0.1))
                        .cornerRadius(4)
                    
                    Spacer()
                    
                    Text(result.timestamp, style: .time)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                
                let summary = Array(result.fields.prefix(3))
                if !summary.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(summary, id: \.key) { key, value in
                            HStack(alignment: .top, spacing: 4) {
                                Text(key.capitalized + ":")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundColor(.secondary)
                                    .frame(width: 70, alignment: .leading)
                                Text(value)
                                    .font(.system(size: 11, design: .rounded))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                            }
                        }
                    }
                } else {
                    Text("Stored result with \(result.fields.count) fields")
                        .font(.system(size: 11, design: .rounded).italic())
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }
}
