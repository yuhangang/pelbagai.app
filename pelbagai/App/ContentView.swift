//
//  ContentView.swift
//  Pelbagai
//
//  Created by Ang Yu Hang on 07/05/2026.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject private var manager = WhisperManager.shared
    
    var body: some View {
        VStack(spacing: 30) {
            // Header
            VStack(spacing: 8) {
                Text("WhisperKit Demo")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                
                Text("On-Device Speech to Text")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 40)
            
            // Transcription Display Area
            ScrollView {
                Text(manager.transcript.isEmpty ? "Tap the microphone and start speaking..." : manager.transcript)
                    .font(.system(size: 20, weight: .regular, design: .default))
                    .foregroundColor(manager.transcript.isEmpty ? .gray : .primary)
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.secondary.opacity(0.15))
            )
            .padding(.horizontal)
            
            // Controls
            VStack(spacing: 20) {
                if !manager.isModelLoaded {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Loading Core ML Model...")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                }
                
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        manager.toggleRecording()
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(manager.isRecording ? Color.red : Color.blue)
                            .frame(width: 80, height: 80)
                            .shadow(color: (manager.isRecording ? Color.red : Color.blue).opacity(0.4), radius: 10, x: 0, y: 5)
                        
                        Image(systemName: manager.isRecording ? "square.fill" : "mic.fill")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .disabled(!manager.isModelLoaded)
                .opacity(manager.isModelLoaded ? 1.0 : 0.5)
                .padding(.bottom, 40)
            }
        }
        .background(Color.clear)
        // Load the model when the view appears
        .task {
            await manager.loadModel()
        }
    }
}

#Preview {
    ContentView()
}
