import SwiftUI

enum ChatInputMode: String, CaseIterable, Identifiable {
    case chat = "Chat"
    case tool = "Tool"
    
    var id: Self { self }
    
    var icon: String {
        switch self {
        case .chat: return "bubble.left.and.bubble.right"
        case .tool: return "wrench.and.screwdriver"
        }
    }
    
    var placeholder: String {
        switch self {
        case .chat:
            return "Message..."
        case .tool:
            return "Describe the local tool you need..."
        }
    }
}

struct ChatInputView: View {
    @Binding var textInput: String
    @Binding var inputMode: ChatInputMode
    var isRecording: Bool
    var isGenerating: Bool
    var isLoadingModels: Bool
    var isModelLoaded: Bool
    var userDefinitionsCount: Int
    var activeSkill: Skill? = nil
    
    @Binding var pendingImage: UIImage?
    
    var onMicTap: () -> Void
    var onCameraTap: () -> Void
    var onFileTap: () -> Void
    var onSend: () -> Void
    var onSkillsTap: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var animateGradient = false
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            actionRow
            
            VStack(spacing: 8) {
                // Pending Image Preview
                if let image = pendingImage {
                    HStack {
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 60, height: 60)
                                .cornerRadius(12)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.1), lineWidth: 1))
                            
                            Button {
                                withAnimation {
                                    pendingImage = nil
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.gray)
                                    .background(Circle().fill(Color.white))
                            }
                            .offset(x: 8, y: -8)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                HStack {
                    TextField(activeSkill != nil ? "Ask \(activeSkill!.displayName)..." : inputMode.placeholder, text: $textInput)
                        .font(.system(size: 16, design: .rounded))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .disabled(!isModelLoaded)
                        .focused($isFocused)
                        .onSubmit {
                            isFocused = false
                            onSend()
                        }
                    
                    if !textInput.isEmpty || pendingImage != nil {
                        Button(action: {
                            isFocused = false
                            onSend()
                        }) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(colorScheme == .dark ? .black : .white)
                                .frame(width: 32, height: 32)
                                .background(Color.primary)
                                .clipShape(Circle())
                        }
                        .padding(.trailing, 8)
                        .disabled(isGenerating)
                    }
                }
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .shadow(color: Color.primary.opacity(0.05), radius: 5, y: 2)
                        .overlay(Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
                )
                .padding(.horizontal)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                animateGradient.toggle()
            }
        }
    }
    
    private var actionRow: some View {
        HStack(spacing: 12) {
            // Add button (dropdown option)
            Menu {
                Picker("Mode", selection: $inputMode) {
                    Label("Chat Mode", systemImage: "bubble.left.and.bubble.right").tag(ChatInputMode.chat)
                    Label("Tool Mode (\(userDefinitionsCount) custom)", systemImage: "wrench.and.screwdriver").tag(ChatInputMode.tool)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                    Text(inputMode == .chat ? "Chat" : "Tool")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }
                .foregroundColor(colorScheme == .dark ? .black : .white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.primary))
            }
            .disabled(isLoadingModels || isGenerating || !isModelLoaded)
            .opacity(isLoadingModels || !isModelLoaded ? 0.4 : 1.0)
            
            // Skills toggle button
            Button(action: {
                isFocused = false
                onSkillsTap()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text(activeSkill?.displayName ?? "Skills")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(activeSkill != nil ? Color.purple : Color.cyan))
            }
            .disabled(isLoadingModels || isGenerating || !isModelLoaded)
            .opacity(isLoadingModels || !isModelLoaded ? 0.4 : 1.0)
            
            Spacer()
            
            // Camera button
            Button(action: {
                isFocused = false
                onCameraTap()
            }) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.primary.opacity(0.75))
            }
            .disabled(isLoadingModels || isGenerating || !isModelLoaded)
            .opacity(isLoadingModels || !isModelLoaded ? 0.4 : 1.0)
            
            // File button
            Button(action: {
                isFocused = false
                onFileTap()
            }) {
                Image(systemName: "paperclip")
                    .font(.system(size: 18))
                    .foregroundColor(.primary.opacity(0.75))
            }
            .disabled(isLoadingModels || isGenerating || !isModelLoaded)
            .opacity(isLoadingModels || !isModelLoaded ? 0.4 : 1.0)
            
            // Mic button
            Button(action: {
                isFocused = false
                onMicTap()
            }) {
                ZStack {
                    if isRecording {
                        Circle()
                            .stroke(Color.red.opacity(0.3), lineWidth: 2)
                            .frame(width: 32, height: 32)
                            .scaleEffect(animateGradient ? 1.2 : 1.0)
                            .opacity(animateGradient ? 0 : 1)
                            .animation(.easeOut(duration: 1.0).repeatForever(autoreverses: false), value: animateGradient)
                    }
                    
                    Image(systemName: isRecording ? "waveform" : "mic.fill")
                        .font(.system(size: 18))
                        .foregroundColor(isRecording ? .red : .primary.opacity(0.75))
                }
            }
            .disabled(isLoadingModels || isGenerating || !isModelLoaded)
            .opacity(isLoadingModels || !isModelLoaded ? 0.4 : 1.0)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }
}
