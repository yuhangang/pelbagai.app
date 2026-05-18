import SwiftUI

struct WorkbenchLibraryView: View {
    @ObservedObject var viewModel: WorkbenchViewModel
    @State private var showClearConfirm = false
    @Environment(\.openURL) private var openURL
    
    var body: some View {
        ZStack {
            if viewModel.savedResults.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "tray.full")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text(viewModel.tool.capabilities.contains(.chatbot) ? "No bookmarked articles yet." : "No stored data for this tool yet.")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
            } else {
                if viewModel.tool.capabilities.contains(.chatbot) {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            HStack {
                                Text("\(viewModel.savedResults.count) Bookmarks")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button(role: .destructive) {
                                    showClearConfirm = true
                                } label: {
                                    Text("Clear All")
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 4)
                            
                            ForEach(viewModel.savedResults.sorted(by: { $0.timestamp > $1.timestamp })) { result in
                                chatbotBookmarkCard(result)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
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
    
    @ViewBuilder
    private func chatbotBookmarkCard(_ result: ScanResult) -> some View {
        let topic = result.richFields["topic"]?.flatString ?? result.primaryValue
        let summary = result.richFields["summary"]?.flatString ?? ""
        let imageURL = result.richFields["imageURL"]?.flatString
        let hasUrl = result.richFields["url"]?.flatString != nil || viewModel.tool.urlTemplate != nil
        
        VStack(alignment: .leading, spacing: 0) {
            if let imageURL = imageURL, let url = URL(string: imageURL), !imageURL.isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 120)
                            .clipped()
                    case .failure:
                        EmptyView()
                    case .empty:
                        ProgressView()
                            .frame(height: 120)
                            .frame(maxWidth: .infinity)
                            .background(Color.primary.opacity(0.03))
                    @unknown default:
                        EmptyView()
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(topic)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Spacer()
                    
                    Text(result.timestamp, style: .date)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(.secondary)
                }
                
                if !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                        .lineSpacing(2)
                }
                
                HStack(spacing: 12) {
                    if hasUrl {
                        Button {
                            openArticleLink(for: topic, result: result)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "safari")
                                Text("Open Article")
                            }
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(viewModel.toolColor)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Spacer()
                    
                    Button {
                        viewModel.deleteResult(result)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                            Text("Remove Bookmark")
                        }
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)
            }
            .padding(12)
        }
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }
    
    private func openArticleLink(for topic: String, result: ScanResult) {
        if let savedUrlString = result.richFields["url"]?.flatString, !savedUrlString.isEmpty, let url = URL(string: savedUrlString) {
            openURL(url)
        } else if let template = viewModel.tool.urlTemplate {
            let escaped = topic.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: " ", with: "_")
                .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? topic
            let urlString = template.replacingOccurrences(of: "{topic}", with: escaped)
            if let url = URL(string: urlString) {
                openURL(url)
            }
        }
    }
    
    private func resultRow(_ result: ScanResult) -> some View {
        Button {
            viewModel.editingResult = result
            viewModel.showEditSheet = true
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: result.isValidated ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .foregroundColor(result.isValidated ? .green : .orange)
                        .font(.system(size: 12))
                    
                    Text(result.primaryValue)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Text(result.timestamp, style: .relative)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(.secondary)
                }
                
                let topKeys = result.sortedKeys.prefix(3)
                if !topKeys.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(topKeys), id: \.self) { key in
                            if let fv = result.richFields[key], !fv.isEmpty {
                                if fv.isList {
                                    HStack(alignment: .top, spacing: 4) {
                                        Text(key.capitalized + ":")
                                            .font(.system(size: 11, weight: .bold, design: .rounded))
                                            .foregroundColor(.secondary)
                                            .frame(width: 80, alignment: .leading)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            ForEach(fv.asList.prefix(3), id: \.self) { item in
                                                HStack(spacing: 3) {
                                                    Circle().fill(Color.secondary).frame(width: 3, height: 3)
                                                    Text(item)
                                                        .font(.system(size: 11, design: .rounded))
                                                        .foregroundColor(.primary)
                                                        .lineLimit(1)
                                                }
                                            }
                                            if fv.asList.count > 3 {
                                                Text("+\(fv.asList.count - 3) more")
                                                    .font(.system(size: 10, design: .rounded))
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                    }
                                } else {
                                    HStack(spacing: 4) {
                                        Text(key.capitalized + ":")
                                            .font(.system(size: 11, weight: .bold, design: .rounded))
                                            .foregroundColor(.secondary)
                                            .frame(width: 80, alignment: .leading)
                                        
                                        Text(fv.flatString)
                                            .font(.system(size: 11, design: .rounded))
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    Text("Stored result with \(result.fields.count) fields")
                        .font(.system(size: 11, design: .rounded).italic())
                        .foregroundColor(.secondary)
                }
                
                if result.richFields.count > 3 {
                    Text("+\(result.richFields.count - 3) more fields")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundColor(.secondary)
                }
                
                HStack(spacing: 6) {
                    if result.scriptNotes != nil {
                        Label("Notes", systemImage: "scroll")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.cyan)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.cyan.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    if !result.actions.isEmpty {
                        Label("\(result.actions.count) actions", systemImage: "bolt.badge.checkmark")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.indigo)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.indigo.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    if let state = result.state, !state.isEmpty {
                        Label("\(state.count) state vars", systemImage: "memorychip")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.purple)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
                .padding(.top, 2)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}
