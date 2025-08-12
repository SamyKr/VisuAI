//
//  DetectionSettingsView.swift
//  VizAI Vision
//
//  RÔLE DANS L'ARCHITECTURE:
//  Collection de COMPOSANTS UI RÉUTILISABLES pour la configuration des paramètres de détection
//
//  🎛️ COMPOSANTS PERFORMANCE:
//  - PerformanceMode : Enum définissant 3 modes (Éco/Normal/Rapide) avec skip frames
//  - PerformanceModeButton : Interface utilisateur pour sélection mode performance
//  - Logique optimisation batterie vs qualité détection
//
//  📋 COMPOSANTS CLASSES OBJETS:
//  - CameraClassRowView : Ligne interface pour activer/désactiver types d'objets
//  - Toggle visuel avec état sélectionné/ignoré
//  - Interface cohérente pour gestion 49 classes YOLOv11
//
//  🎨 STYLES INTERFACE:
//  - CameraQuickActionButtonStyle : Style boutons actions rapides
//  - Design cohérent avec charte graphique VizAI
//  - Réutilisabilité dans ParametersView et autres vues configuration
//
//  📱 UTILISATION:
//  - Importé et utilisé dans ParametersView pour interface paramètres
//  - Composants modulaires pour flexibilité interface
//  - Séparation responsabilités : logique métier vs présentation
//
//  FLUX D'UTILISATION:
//  ParametersView → DetectionSettingsView (composants) → CameraManager (application config)

import SwiftUI

// MARK: - Modes de Performance Système

/// Énumération des modes de performance pour optimiser batterie vs qualité détection
enum PerformanceMode: String, CaseIterable {
    case eco = "eco"
    case normal = "normal"
    case rapide = "rapide"
    
    /// Nombre de frames à ignorer pour ce mode (optimisation performance)
    /// Plus le nombre est élevé, plus la batterie est économisée mais moins la détection est fluide
    var skipFrames: Int {
        switch self {
        case .eco: return 7      // Skip 7 frames = ~2-3 FPS (très économe)
        case .normal: return 4   // Skip 4 frames = ~6-8 FPS (équilibré)
        case .rapide: return 1   // Skip 1 frame = ~15-20 FPS (performance max)
        }
    }
    
    /// Nom affiché dans l'interface utilisateur
    var displayName: String {
        switch self {
        case .eco: return "Éco"
        case .normal: return "Normal"
        case .rapide: return "Rapide"
        }
    }
    
    /// Icône SF Symbols représentant le mode
    var icon: String {
        switch self {
        case .eco: return "leaf.fill"        // Feuille = écologie
        case .normal: return "speedometer"   // Compteur = équilibre
        case .rapide: return "bolt.fill"     // Éclair = vitesse
        }
    }
    
    /// Couleur associée au mode pour distinction visuelle
    var color: Color {
        switch self {
        case .eco: return .green     // Vert = économie
        case .normal: return .blue   // Bleu = neutre
        case .rapide: return .orange // Orange = performance
        }
    }
    
    /// Description technique détaillée du mode
    var description: String {
        switch self {
        case .eco: return "Économise la batterie • Skip: 7 frames"
        case .normal: return "Équilibre performance/batterie • Skip: 4 frames"
        case .rapide: return "Performance maximale • Skip: 1 frame"
        }
    }
}

// MARK: - Bouton Sélection Mode Performance

struct PerformanceModeButton: View {
    
    // MARK: - Paramètres Composant
    let mode: PerformanceMode // Mode représenté par ce bouton
    let isSelected: Bool // État sélection actuelle
    let onTap: () -> Void // Action lors du tap utilisateur
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                // Icône du mode
                Image(systemName: mode.icon)
                    .font(.title2)
                    .foregroundColor(isSelected ? .white : mode.color)
                
                // Nom du mode
                Text(mode.displayName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(isSelected ? .white : mode.color)
                
                // Information technique (skip frames)
                Text("Skip: \(mode.skipFrames)")
                    .font(.caption2)
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(modeButtonBackground)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Style Bouton Mode
    
    /// Arrière-plan du bouton selon état sélection
    private var modeButtonBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(isSelected ? mode.color : Color.clear) // Fond coloré si sélectionné
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(mode.color, lineWidth: isSelected ? 0 : 2) // Bordure si non sélectionné
            )
    }
}

// MARK: - Ligne Configuration Classe Objet

struct CameraClassRowView: View {
    
    // MARK: - Paramètres Composant
    let className: String // Nom de la classe d'objet (ex: "car", "person")
    let isSelected: Bool // État activation de cette classe
    let onToggle: () -> Void // Action toggle activation/désactivation
    
    var body: some View {
        HStack {
            Button(action: onToggle) {
                HStack {
                    // Icône checkbox avec état visuel
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .foregroundColor(isSelected ? .blue : .gray)
                        .font(.title2)
                    
                    // Nom classe avec formatage (première lettre majuscule)
                    Text(className.capitalized)
                        .font(.body)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    // Badge "Ignoré" si classe désactivée
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
        .contentShape(Rectangle()) // Zone tap étendue à toute la ligne
        .padding(.vertical, 4)
    }
}

// MARK: - Style Boutons Actions Rapides

struct CameraQuickActionButtonStyle: ButtonStyle {
    
    // MARK: - Paramètres Style
    let color: Color // Couleur principale du bouton
    
    /// Applique le style au bouton avec état pressed
    /// - Parameter configuration: Configuration bouton avec contenu et état
    /// - Returns: Vue stylée du bouton
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption)
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(color.opacity(configuration.isPressed ? 0.7 : 1.0)) // Effet pressed
            .cornerRadius(8)
    }
}
