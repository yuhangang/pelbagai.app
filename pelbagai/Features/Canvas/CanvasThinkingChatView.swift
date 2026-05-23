import SwiftUI

struct CanvasThinkingChatView: View {
    @StateObject private var viewModel: CanvasThinkingChatViewModel
    @StateObject private var dummyChatViewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var pulseScale: CGFloat = 1.0
    @State private var rotationDegrees: Double = 0.0
    
    init(sessionId: UUID, initialPrompt: String? = nil, env: AppEnvironment) {
        _viewModel = StateObject(wrappedValue: CanvasThinkingChatViewModel(sessionId: sessionId, initialPrompt: initialPrompt, env: env))
        _dummyChatViewModel = StateObject(wrappedValue: ChatViewModel(sessionId: sessionId, environment: env))
    }
    
    var body: some View {
        ZStack {
            spatialBackground
            
            VStack(spacing: 0) {
                // Navigation Bar
                headerBar
                
                ScrollView {
                    VStack(spacing: 24) {
                        switch viewModel.state {
                        case .welcome:
                            welcomeCard
                        case .gatheringStyle:
                            styleCard
                        case .gatheringFeatures:
                            featuresCard
                        case .thinking:
                            thinkingCard
                        case .generating:
                            generatingCard
                        case .validating:
                            validatingCard
                        case .testing:
                            testingCard
                        case .completed:
                            completedCard
                        }
                    }
                    .padding(.vertical, 24)
                }
            }
        }
        .navigationBarHidden(true)
        .overlay(downloadPromptOverlay)
    }
    
    // MARK: - Subviews
    
    private var spatialBackground: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            
            // Premium ambient lights
            RadialGradient(
                colors: [Color.purple.opacity(0.12), Color.clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 500
            )
            .ignoresSafeArea()
            
            RadialGradient(
                colors: [Color.orange.opacity(0.08), Color.clear],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 600
            )
            .ignoresSafeArea()
        }
    }
    
    private var headerBar: some View {
        HStack {
            Button(action: {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.prepare()
                generator.impactOccurred()
                dismiss()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                    Text("Home")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                }
                .foregroundColor(.purple)
            }
            
            Spacer()
            
            Text("Canvas Builder")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            
            Spacer()
            
            // Top Badge
            Text("AI Labs")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.purple)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.purple.opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(
            VStack {
                Spacer()
                Divider().opacity(0.4)
            }
        )
    }
    
    // MARK: - Creator Steps Panels
    
    private var welcomeCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 32))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.purple, .orange],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Design Your Canvas App")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                
                Text("Describe the utility app, game, or custom calculator you want to create on-device.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            
            TextEditor(text: $viewModel.appDescription)
                .frame(height: 120)
                .padding(10)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.purple.opacity(0.2), lineWidth: 1)
                )
            
            Button(action: {
                viewModel.submitDescription(viewModel.appDescription)
            }) {
                HStack {
                    Spacer()
                    Text("Continue")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [.purple, .orange],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .cornerRadius(16)
                .shadow(color: Color.purple.opacity(0.3), radius: 6, x: 0, y: 3)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.appDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(viewModel.appDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.6 : 1.0)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 24)
    }
    
    private var styleCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Choose Visual Aesthetic")
                .font(.system(size: 22, weight: .bold, design: .rounded))
            
            Text("Select an interface design style sheet for your micro-application.")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            
            let styles = [
                ("Minimal Apple", "Sleek iOS glass sheets and rounded layouts", "ipad.and.iphone"),
                ("Neon Cyber", "Glowing cyberpunk borders with electric accents", "bolt.fill"),
                ("Retro Terminal", "Monochromatic phosphor fonts and simple inputs", "terminal.fill"),
                ("Soft Glass", "Blur backdrop layers and dynamic dynamic shapes", "square.stack.3d.down.right")
            ]
            
            VStack(spacing: 12) {
                ForEach(styles, id: \.0) { style in
                    Button(action: {
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.prepare()
                        generator.impactOccurred()
                        viewModel.selectStyle(style.0)
                    }) {
                        HStack(spacing: 16) {
                            Image(systemName: style.2)
                                .font(.system(size: 20))
                                .foregroundColor(.purple)
                                .frame(width: 40, height: 40)
                                .background(Color.purple.opacity(0.1))
                                .clipShape(Circle())
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(style.0)
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)
                                
                                Text(style.1)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(14)
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 24)
    }
    
    private var featuresCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Device Integration Capabilities")
                .font(.system(size: 22, weight: .bold, design: .rounded))
            
            Text("Select the hardware layers and persistence scopes the AI should hook up.")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            
            let capabilities = [
                ("Local Storage", "Durable per-app sandboxed persistence key/value", "cylinder.split.1x2.fill"),
                ("Camera/Photos", "Access native iOS camera and pick pictures", "camera.fill"),
                ("Haptics/Alerts", "Trigger tactile feedback pulses and native alert dialogs", "bell.badge.fill"),
                ("Share Sheets", "Pass texts or files into system share dialog controllers", "square.and.arrow.up.fill")
            ]
            
            VStack(spacing: 12) {
                ForEach(capabilities, id: \.0) { cap in
                    Button(action: {
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.prepare()
                        generator.impactOccurred()
                        viewModel.toggleCapability(cap.0)
                    }) {
                        let isSelected = viewModel.selectedCapabilities.contains(cap.0)
                        
                        HStack(spacing: 16) {
                            Image(systemName: cap.2)
                                .font(.system(size: 18))
                                .foregroundColor(isSelected ? .white : .purple)
                                .frame(width: 36, height: 36)
                                .background(isSelected ? Color.purple : Color.purple.opacity(0.1))
                                .clipShape(Circle())
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(cap.0)
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)
                                
                                Text(cap.1)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(isSelected ? .purple : .secondary.opacity(0.4))
                        }
                        .padding(14)
                        .background(isSelected ? Color.purple.opacity(0.06) : Color.primary.opacity(0.03))
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(isSelected ? Color.purple.opacity(0.3) : Color.primary.opacity(0.05), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Button(action: {
                viewModel.confirmCapabilities()
            }) {
                HStack {
                    Spacer()
                    Text("Confirm & Launch Builder")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [.purple, .orange],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .cornerRadius(16)
                .shadow(color: Color.purple.opacity(0.3), radius: 6, x: 0, y: 3)
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 24)
    }
    
    private var thinkingCard: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .stroke(
                        LinearGradient(colors: [.purple, .orange], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 3
                    )
                    .frame(width: 80, height: 80)
                    .scaleEffect(pulseScale)
                    .onAppear {
                        withAnimation(Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                            pulseScale = 1.15
                        }
                    }
                
                Image(systemName: "cpu")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.purple)
            }
            
            VStack(spacing: 8) {
                Text("Analyzing Specifications...")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text("Gemma is synthesizing your architecture layout details.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            // Architecture Spec Outline
            ScrollView {
                Text(viewModel.architecturePlan)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 180)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [.purple.opacity(0.2), .orange.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .padding(.horizontal, 24)
    }
    
    private var generatingCard: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.1), lineWidth: 4)
                    .frame(width: 70, height: 70)
                
                Circle()
                    .trim(from: 0, to: 0.6)
                    .stroke(
                        LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 70, height: 70)
                    .rotationEffect(Angle(degrees: rotationDegrees))
                    .onAppear {
                        withAnimation(Animation.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                            rotationDegrees = 360
                        }
                    }
                
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.purple)
            }
            
            VStack(spacing: 8) {
                Text("Generating HTML Layout...")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text(viewModel.statusText)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            // Streaming Token Response Window
            ScrollView {
                Text(viewModel.responseText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 200)
            .background(Color.black.opacity(0.04))
            .cornerRadius(16)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 24)
    }
    
    private var validatingCard: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text("Parsing & Static Analysis...")
                .font(.system(size: 18, weight: .bold, design: .rounded))
            
            Text("Extracting app packages and analyzing CSS parameters.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .padding(.horizontal, 24)
    }
    
    private var testingCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(0.8)
                
                Text("Automated dynamic dynamic assertions verification...")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }
            
            // Checklist of assertions
            VStack(alignment: .leading, spacing: 14) {
                ForEach(0..<viewModel.testAssertions.count, id: \.self) { index in
                    let assertion = viewModel.testAssertions[index]
                    let isCompleted = index < viewModel.currentTestIndex
                    let isPending = index == viewModel.currentTestIndex
                    
                    HStack(alignment: .top, spacing: 12) {
                        if isCompleted {
                            Image(systemName: assertion.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(assertion.passed ? .green : .red)
                        } else if isPending {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 18, height: 18)
                        } else {
                            Image(systemName: "circle")
                                .font(.system(size: 18))
                                .foregroundColor(.secondary.opacity(0.4))
                        }
                        
                        VStack(alignment: .leading, spacing: 3) {
                            Text(assertion.name)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(isCompleted ? .primary : .secondary)
                            
                            Text(isCompleted ? assertion.feedback : assertion.description)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 24)
    }
    
    private var completedCard: some View {
        VStack(alignment: .center, spacing: 20) {
            if let fileURL = viewModel.localFileURL {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(
                        LinearGradient(colors: [.green, .teal], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                
                VStack(spacing: 6) {
                    Text("Verification Passed!")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("100% compliant HTML5 micro-application built successfully.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                // Renders the resulting Canvas App inline!
                CanvasBlockView(localFileURL: fileURL, messageId: viewModel.sessionId, viewModel: dummyChatViewModel)
                    .frame(maxWidth: .infinity)
                
                Button(action: {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.prepare()
                    generator.impactOccurred()
                    dismiss()
                }) {
                    HStack {
                        Spacer()
                        Text("Return to Hub")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding(.vertical, 14)
                    .background(Color.purple)
                    .cornerRadius(16)
                    .shadow(color: Color.purple.opacity(0.2), radius: 6, x: 0, y: 3)
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
                
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.orange)
                
                VStack(spacing: 8) {
                    Text("Layout Verification Failed")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("The model-synthesized layout did not pass core dynamic viewport responsiveness or bridge capabilities checks.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(viewModel.testAssertions.filter { !$0.passed }) { assertion in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                            Text(assertion.feedback)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(14)
                .background(Color.red.opacity(0.05))
                .cornerRadius(12)
                
                Button(action: {
                    dismiss()
                }) {
                    Text("Close Builder")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 16)
    }
    
    // MARK: - Overlays
    
    @ViewBuilder
    private var downloadPromptOverlay: some View {
        if viewModel.showModelDownloadPrompt {
            ZStack {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                
                VStack(spacing: 20) {
                    Image(systemName: "icloud.and.arrow.down.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.purple)
                    
                    VStack(spacing: 8) {
                        Text("Model Required")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                        
                        Text("The Canvas Builder requires downloading the on-device Gemma weights (approx 1.6GB) to run local generation.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    
                    if viewModel.isLoadingModels {
                        VStack(spacing: 8) {
                            ProgressView()
                            Text(viewModel.loadingStatusText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        HStack(spacing: 12) {
                            Button("Cancel") {
                                viewModel.showModelDownloadPrompt = false
                                dismiss()
                            }
                            .buttonStyle(.bordered)
                            
                            Button("Download & Build") {
                                viewModel.retryDownloadAndLoad()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.purple)
                        }
                    }
                }
                .padding(24)
                .frame(width: 300)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color(.systemBackground))
                )
            }
        }
    }
}
