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
    
    var onMicTap: () -> Void
    var onCameraTap: () -> Void
    var onSend: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var animateGradient = false
    
    var body: some View {
        VStack(spacing: 0) {
            inputModeSelector
            
            HStack(spacing: 12) {
                // Text input field
                HStack {
                    TextField(inputMode.placeholder, text: $textInput)
                        .font(.system(size: 16, design: .rounded))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .disabled(!isModelLoaded)
                    
                    if !textInput.isEmpty {
                        Button(action: onSend) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(colorScheme == .dark ? .black : .white)
                                .frame(width: 32, height: 32)
                                .background(Color.primary)
                                .clipShape(Circle())
                        }
                        .padding(.trailing, 6)
                        .disabled(isGenerating)
                    }
                }
                .background(Color.primary.opacity(0.05))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 1))
                
                // Camera button
                Button(action: onCameraTap) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [.indigo.opacity(0.8), .blue.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 48, height: 48)
                            .shadow(color: Color.indigo.opacity(0.3), radius: 8, x: 0, y: 0)
                        
                        Image(systemName: "camera.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .disabled(isLoadingModels || isGenerating)
                .opacity(isLoadingModels ? 0.4 : 1.0)
                
                // Mic button
                Button(action: onMicTap) {
                    ZStack {
                        Circle()
                            .fill(
                                isRecording
                                ? LinearGradient(colors: [.red, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [.cyan.opacity(0.8), .purple.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .frame(width: 48, height: 48)
                            .shadow(
                                color: (isRecording ? Color.red : Color.cyan).opacity(isRecording ? 0.6 : 0.3),
                                radius: isRecording ? 15 : 8, x: 0, y: 0
                            )
                        
                        if isRecording {
                            Circle()
                                .stroke(Color.primary.opacity(0.5), lineWidth: 2)
                                .frame(width: 56, height: 56)
                                .scaleEffect(animateGradient ? 1.2 : 1.0)
                                .opacity(animateGradient ? 0 : 1)
                                .animation(.easeOut(duration: 1.0).repeatForever(autoreverses: false), value: animateGradient)
                        }
                        
                        Image(systemName: isRecording ? "waveform" : "mic.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .disabled(isLoadingModels || isGenerating)
                .opacity(isLoadingModels ? 0.4 : 1.0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .shadow(color: Color.primary.opacity(0.15), radius: 10, y: 5)
                    .overlay(Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
            )
            .padding(.horizontal)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                animateGradient.toggle()
            }
        }
    }
    
    private var inputModeSelector: some View {
        HStack(spacing: 8) {
            ForEach(ChatInputMode.allCases) { mode in
                Button {
                    inputMode = mode
                } label: {
                    Label(mode.rawValue, systemImage: mode.icon)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(inputMode == mode ? .white : .primary.opacity(0.65))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(inputMode == mode ? Color.primary : Color.primary.opacity(0.07))
                        )
                }
                .disabled(isGenerating || isLoadingModels)
            }
            
            Spacer()
            
            if inputMode == .tool {
                Text("\(userDefinitionsCount) custom")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }
}
