//
//  ImportantObjectsBoard.swift
//  test
//
//  Created by Samy 📍 on 20/06/2025.
//  Leaderboard des objets les plus importants
//

import SwiftUI
import UIKit

struct ImportantObjectsBoard: View {
    let importantObjects: [(object: TrackedObject, score: Float)]
    @Binding var isVisible: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header du leaderboard
            headerView
            
            // Liste des objets importants
            if importantObjects.isEmpty {
                emptyStateView
            } else {
                objectsListView
            }
        }
        .background(Color.black.opacity(0.85))
        .cornerRadius(16)
        .padding()
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }
    
    // MARK: - Header
    @ViewBuilder
    private var headerView: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "trophy.fill")
                    .font(.title2)
                    .foregroundColor(.yellow)
                
                Text("Objets Importants")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
            
            Spacer()
            
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isVisible = false
                }
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.2))
    }
    
    // MARK: - Empty State
    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(.gray)
            
            Text("Aucun objet détecté")
                .font(.body)
                .foregroundColor(.gray)
            
            Text("Les objets les plus importants apparaîtront ici")
                .font(.caption)
                .foregroundColor(.gray.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(30)
    }
    
    // MARK: - Objects List
    @ViewBuilder
    private var objectsListView: some View {
        VStack(spacing: 8) {
            ForEach(Array(importantObjects.enumerated()), id: \.offset) { index, item in
                ImportantObjectRow(
                    rank: index + 1,
                    object: item.object,
                    score: item.score
                )
            }
        }
        .padding(.horizontal)
        .padding(.bottom)
    }
}

// MARK: - Important Object Row
struct ImportantObjectRow: View {
    let rank: Int
    let object: TrackedObject
    let score: Float
    
    private var rankColor: Color {
        switch rank {
        case 1: return .yellow
        case 2: return .gray
        case 3: return .orange
        default: return .blue
        }
    }
    
    private var rankIcon: String {
        switch rank {
        case 1: return "crown.fill"
        case 2: return "medal.fill"
        case 3: return "medal"
        default: return "\(rank).circle.fill"
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Rang avec icône
            HStack(spacing: 4) {
                Image(systemName: rankIcon)
                    .font(.headline)
                    .foregroundColor(rankColor)
                
                if rank > 3 {
                    Text("\(rank)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(rankColor)
                }
            }
            .frame(width: 30)
            
            // Informations de l'objet
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    // ID avec couleur de tracking
                    Text("#\(object.trackingNumber)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(object.color))
                        .cornerRadius(4)
                    
                    // Nom de l'objet
                    Text(object.label.capitalized)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    // Score numérique
                    Text(String(format: "%.2f", score))
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(scoreColor.opacity(0.8))
                        .cornerRadius(4)
                }
                
                // Détails supplémentaires
                HStack(spacing: 12) {
                    // Durée de vie
                    Label("\(String(format: "%.1f", object.lifetime))s", systemImage: "clock")
                        .font(.caption2)
                        .foregroundColor(.gray)
                    
                    // Confiance
                    Label("\(String(format: "%.0f", object.confidence * 100))%", systemImage: "checkmark.seal")
                        .font(.caption2)
                        .foregroundColor(.gray)
                    
                    // Distance si disponible
                    if let distance = object.distance {
                        Label(formatDistance(distance), systemImage: "location")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                    
                    Spacer()
                }
            }
            
            // Jauge de score
            ScoreGauge(score: score)
                .frame(width: 60, height: 20)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.05))
        .cornerRadius(10)
    }
    
    private var scoreColor: Color {
        if score >= 0.8 {
            return .green
        } else if score >= 0.6 {
            return .yellow
        } else if score >= 0.4 {
            return .orange
        } else {
            return .red
        }
    }
    
    private func formatDistance(_ distance: Float) -> String {
        if distance < 1.0 {
            return "\(Int(distance * 100))cm"
        } else if distance < 10.0 {
            return "\(String(format: "%.1f", distance))m"
        } else {
            return "\(Int(distance))m"
        }
    }
}

// MARK: - Score Gauge
struct ScoreGauge: View {
    let score: Float
    
    private var gaugeColor: Color {
        // Gradient du rouge au vert selon le score
        if score >= 0.8 {
            return .green
        } else if score >= 0.6 {
            return Color(red: 0.8, green: 0.8, blue: 0.2) // Jaune-vert
        } else if score >= 0.4 {
            return .yellow
        } else if score >= 0.2 {
            return .orange
        } else {
            return .red
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Arrière-plan de la jauge
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .cornerRadius(10)
                
                // Remplissage de la jauge
                Rectangle()
                    .fill(gaugeColor)
                    .frame(width: geometry.size.width * CGFloat(score))
                    .cornerRadius(10)
                    .animation(.easeInOut(duration: 0.5), value: score)
                
                // Animation de brillance
                if score > 0.1 {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    gaugeColor.opacity(0.3),
                                    gaugeColor.opacity(0.8),
                                    gaugeColor.opacity(0.3)
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * CGFloat(score))
                        .cornerRadius(10)
                }
            }
        }
    }
}

// MARK: - Bouton d'affichage du leaderboard
struct ImportantObjectsButton: View {
    @Binding var isVisible: Bool
    let objectCount: Int
    
    var body: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.3)) {
                isVisible.toggle()
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: "trophy.fill")
                    .font(.title2)
                    .foregroundColor(.yellow)
                
                Text("Top")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                if objectCount > 0 {
                    Text("\(objectCount)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.yellow)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.yellow.opacity(0.2))
                        .cornerRadius(3)
                }
            }
            .padding(10)
            .background(Color.black.opacity(0.6))
            .cornerRadius(12)
        }
    }
}

