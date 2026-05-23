import SwiftUI
import UniformTypeIdentifiers

struct SkillsBrowserSheet: View {
    @EnvironmentObject var skills: SkillRegistry
    @Binding var showSkillImporter: Bool
    let onSkillSelected: (Skill) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var expandedSkillName: String? = nil
    @State private var searchText = ""
    
    var filteredSkills: [Skill] {
        if searchText.isEmpty {
            return skills.allSkills
        } else {
            return skills.allSkills.filter { skill in
                skill.displayName.localizedCaseInsensitiveContains(searchText) ||
                skill.description.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()
                
                Circle()
                    .fill(Color.purple.opacity(0.12))
                    .frame(width: 250, height: 250)
                    .blur(radius: 50)
                    .offset(x: -120, y: -150)
                
                Circle()
                    .fill(Color.cyan.opacity(0.12))
                    .frame(width: 250, height: 250)
                    .blur(radius: 50)
                    .offset(x: 120, y: 150)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Agent Skills")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                            Text("Augment the chatbot with on-device specialized personas and targeted instruction sets.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                        .padding(.top, 10)
                        
                        Button {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                showSkillImporter = true
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "square.and.arrow.down.fill")
                                    .font(.title2)
                                    .foregroundColor(.purple)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Import Custom Skill")
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Text("Load a .md file matching the SKILL.md schema.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color(.secondarySystemBackground))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(LinearGradient(colors: [.purple, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                                    )
                            )
                        }
                        .padding(.horizontal)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Available Skills")
                                    .font(.headline)
                                Spacer()
                            }
                            .padding(.horizontal)
                            
                            // Custom Premium Glassmorphic Search Bar
                            HStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(.secondary)
                                
                                TextField("Search skills by name or description...", text: $searchText)
                                    .textFieldStyle(PlainTextFieldStyle())
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                                
                                if !searchText.isEmpty {
                                    Button(action: {
                                        searchText = ""
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.secondarySystemBackground).opacity(0.6))
                                    .background(.ultraThinMaterial)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(LinearGradient(colors: [.white.opacity(0.15), .clear], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                            )
                            .padding(.horizontal)
                            
                            if skills.allSkills.isEmpty {
                                Text("No skills available.")
                                    .foregroundColor(.secondary)
                                    .padding()
                            } else if filteredSkills.isEmpty {
                                VStack(spacing: 16) {
                                    Image(systemName: "magnifyingglass.circle.fill")
                                        .font(.system(size: 48))
                                        .foregroundStyle(
                                            LinearGradient(
                                                colors: [.purple.opacity(0.8), .cyan.opacity(0.8)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                    
                                    VStack(spacing: 6) {
                                        Text("No Skills Found")
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        
                                        Text("No skills matched \"\(searchText)\". Try adjusting your search query or importing a custom skill.")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                            .multilineTextAlignment(.center)
                                            .padding(.horizontal, 24)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 32)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color(.secondarySystemBackground).opacity(0.4))
                                        .background(.ultraThinMaterial)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(LinearGradient(colors: [.purple.opacity(0.2), .cyan.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                                )
                                .padding(.horizontal)
                            } else {
                                ForEach(filteredSkills) { skill in
                                    SkillRowCard(
                                        skill: skill,
                                        isActive: false, // You might pass activeSkill explicitly if you want to highlight it
                                        isExpanded: expandedSkillName == skill.name,
                                        onActivate: {
                                            onSkillSelected(skill)
                                            dismiss()
                                        },
                                        onDeactivate: {
                                            
                                        },
                                        onToggleExpand: {
                                            if expandedSkillName == skill.name {
                                                expandedSkillName = nil
                                            } else {
                                                expandedSkillName = skill.name
                                            }
                                        },
                                        onDelete: {
                                            skills.removeUserSkill(named: skill.name)
                                        }
                                    )
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                    .font(.headline)
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

struct SkillRowCard: View {
    let skill: Skill
    let isActive: Bool
    let isExpanded: Bool
    let onActivate: () -> Void
    let onDeactivate: () -> Void
    let onToggleExpand: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(color(for: skill.color).opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: skill.icon)
                        .foregroundColor(color(for: skill.color))
                        .font(.system(size: 20, weight: .semibold))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(skill.displayName)
                            .font(.headline)
                        
                        Text(skill.isBuiltIn ? "Built-in" : "Custom")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(skill.isBuiltIn ? Color.cyan.opacity(0.15) : Color.purple.opacity(0.15))
                            )
                            .foregroundColor(skill.isBuiltIn ? .cyan : .purple)
                    }
                    
                    Text(skill.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                Button {
                    if isActive {
                        onDeactivate()
                    } else {
                        onActivate()
                    }
                } label: {
                    Text(isActive ? "Deactivate" : "Activate")
                        .font(.system(size: 13, weight: .bold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(isActive ? Color.red.opacity(0.1) : Color.primary.opacity(0.08))
                        )
                        .foregroundColor(isActive ? .red : .primary)
                }
            }
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    Divider()
                    Text("Prompt Instructions:")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                    
                    ScrollView {
                        Text(skill.resolvedInstructions)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(8)
                    }
                    .frame(maxHeight: 120)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            HStack {
                Button {
                    withAnimation(.spring()) {
                        onToggleExpand()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        Text(isExpanded ? "Hide Instructions" : "View Instructions")
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if !skill.isBuiltIn {
                    Button(role: .destructive) {
                        withAnimation {
                            onDelete()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                            Text("Delete")
                        }
                        .font(.caption2)
                        .foregroundColor(.red.opacity(0.8))
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isActive ? color(for: skill.color).opacity(0.06) : Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isActive ? color(for: skill.color).opacity(0.3) : Color.clear, lineWidth: 1.5)
        )
    }
    
    private func color(for name: String) -> Color {
        switch name.lowercased() {
        case "cyan": return .cyan
        case "green": return .green
        case "orange": return .orange
        case "purple": return .purple
        case "pink": return .pink
        default: return .blue
        }
    }
}
