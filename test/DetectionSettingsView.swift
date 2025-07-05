//
//  DetectionSettingsView.swift (Version avec modes de performance)
//  test
//
//  Created by Samy 📍 on 18/06/2025.
//  Updated with vibration controls - 19/06/2025.
//  Updated with performance modes - 21/06/2025
//

import SwiftUI

// Énumération pour les modes de performance
enum PerformanceMode: String, CaseIterable {
    case eco = "eco"
    case normal = "normal"
    case rapide = "rapide"
    
    var skipFrames: Int {
        switch self {
        case .eco: return 7
        case .normal: return 4
        case .rapide: return 1
        }
    }
    
    var displayName: String {
        switch self {
        case .eco: return "Éco"
        case .normal: return "Normal"
        case .rapide: return "Rapide"
        }
    }
    
    var icon: String {
        switch self {
        case .eco: return "leaf.fill"
        case .normal: return "speedometer"
        case .rapide: return "bolt.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .eco: return .green
        case .normal: return .blue
        case .rapide: return .orange
        }
    }
    
    var description: String {
        switch self {
        case .eco: return "Économise la batterie • Skip: 7 frames"
        case .normal: return "Équilibre performance/batterie • Skip: 4 frames"
        case .rapide: return "Performance maximale • Skip: 1 frame"
        }
    }
}



// MARK: - Bouton de Mode de Performance (NOUVEAU)
struct PerformanceModeButton: View {
    let mode: PerformanceMode
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Image(systemName: mode.icon)
                    .font(.title2)
                    .foregroundColor(isSelected ? .white : mode.color)
                
                Text(mode.displayName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(isSelected ? .white : mode.color)
                
                Text("Skip: \(mode.skipFrames)")
                    .font(.caption2)
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? mode.color : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(mode.color, lineWidth: isSelected ? 0 : 2)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Vue pour chaque ligne de classe
struct CameraClassRowView: View {
    let className: String
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        HStack {
            Button(action: onToggle) {
                HStack {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .foregroundColor(isSelected ? .blue : .gray)
                        .font(.title2)
                    
                    Text(className.capitalized)
                        .font(.body)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    if !isSelected {
                        Text("Ignoré")
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(4)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }
}

// MARK: - Style pour les boutons d'action rapide
struct CameraQuickActionButtonStyle: ButtonStyle {
    let color: Color
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption)
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(color.opacity(configuration.isPressed ? 0.7 : 1.0))
            .cornerRadius(8)
    }
}
