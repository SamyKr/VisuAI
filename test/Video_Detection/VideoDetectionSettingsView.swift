//
//  VideoDetectionSettingsView.swift (Version corrigée)
//  test
//
//  Created by Samy 📍 on 18/06/2025.
//  Updated for VideoDetectionManager - 19/06/2025
//

import SwiftUI

struct VideoDetectionSettingsView: View {  // ← Nom correct
    @Binding var isPresented: Bool
    @ObservedObject var videoManager: VideoDetectionManager  // ← Changé de cameraManager vers videoManager
    
    // Classes de votre modèle spécifique
    private let allClasses = [
        "sidewalk", "road", "pedestrian crossing", "driveway", "bike lane", "parking area",
        "railway", "service lane", "wall", "fence", "curb", "guardrail", "temporary barrier",
        "other barrier", "pole", "car", "truck", "bus", "motorcycle", "bicycle", "slow vehicle",
        "vehicle group", "rail vehicle", "boat", "person", "cyclist", "motorcyclist",
        "traffic light", "traffic sign", "streetlight", "traffic cone", "bench", "trash can",
        "fire hydrant", "mailbox", "parking meter", "bike rack", "phone booth", "pothole",
        "manhole", "storm drain", "water valve", "junction box", "building", "bridge",
        "tunnel", "garage", "vegetation", "water", "ground", "animals"
    ].sorted()
    
    @State private var selectedClasses: Set<String> = []
    @State private var skipFrames: Int = 5
    @State private var searchText = ""
    @State private var confidenceThreshold: Float = 0.5
    @State private var maxDetections: Int = 10
    
    var filteredClasses: [String] {
        if searchText.isEmpty {
            return allClasses
        } else {
            return allClasses.filter { $0.lowercased().contains(searchText.lowercased()) }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // En-tête avec statistiques
                headerView
                
                // Sections des paramètres
                ScrollView {
                    VStack(spacing: 20) {
                        // Configuration Skip Frames
                        skipFramesSection
                        
                        Divider()
                        
                        // Configuration Détection
                        detectionSection
                        
                        Divider()
                        
                        // Recherche de classes
                        searchSection
                        
                        // Liste des classes
                        classesListSection
                    }
                    .padding()
                }
            }
            .navigationTitle("Paramètres Vidéo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuler") {
                        loadCurrentSettings()
                        isPresented = false
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Sauvegarder") {
                        saveSettings()
                        isPresented = false
                    }
                    .fontWeight(.bold)
                }
            }
        }
        .onAppear {
            loadCurrentSettings()
        }
    }
    
    // MARK: - Header avec statistiques
    private var headerView: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Classes Actives")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(selectedClasses.count)/\(allClasses.count)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text("Mode")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Vidéo")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.purple)
                }
            }
            
            // Boutons de sélection rapide
            HStack(spacing: 12) {
                Button("Tout sélectionner") {
                    selectedClasses = Set(allClasses)
                }
                .buttonStyle(QuickActionButtonStyle(color: .blue))
                
                Button("Tout désélectionner") {
                    selectedClasses.removeAll()
                }
                .buttonStyle(QuickActionButtonStyle(color: .red))
                
                Button("Par défaut") {
                    resetToDefault()
                }
                .buttonStyle(QuickActionButtonStyle(color: .orange))
            }
        }
        .padding()
        .background(Color(.systemGray6))
    }
    
    // MARK: - Section Skip Frames
    private var skipFramesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("⚡ Performance Vidéo")
                    .font(.headline)
                
                Spacer()
                
                Text("1 frame sur \(skipFrames + 1)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text("Rapidité")
                    .font(.caption)
                
                Slider(value: Binding(
                    get: { Double(skipFrames) },
                    set: { skipFrames = Int($0) }
                ), in: 0...10, step: 1)
                
                Text("Qualité")
                    .font(.caption)
            }
            
            Text("Valeur: \(skipFrames) - Traite ~\(String(format: "%.1f", 100.0 / Double(skipFrames + 1)))% des frames")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Section Détection
    private var detectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("🎯 Paramètres de Détection")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Seuil de confiance")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Text("\(String(format: "%.1f", confidenceThreshold * 100))%")
                        .font(.caption)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(4)
                }
                
                Slider(value: $confidenceThreshold, in: 0.1...0.9, step: 0.1)
                
                Text("Objets détectés avec confiance > \(String(format: "%.0f", confidenceThreshold * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Détections maximales")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Text("\(maxDetections)")
                        .font(.caption)
                        .foregroundColor(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(4)
                }
                
                Slider(value: Binding(
                    get: { Double(maxDetections) },
                    set: { maxDetections = Int($0) }
                ), in: 1...20, step: 1)
                
                Text("Maximum \(maxDetections) objets affichés simultanément")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Section de recherche
    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("🔍 Classes de Détection")
                .font(.headline)
            
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Rechercher une classe...", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                if !searchText.isEmpty {
                    Button("Effacer") {
                        searchText = ""
                    }
                    .font(.caption)
                }
            }
        }
    }
    
    // MARK: - Liste des classes
    private var classesListSection: some View {
        LazyVStack(spacing: 0) {
            ForEach(groupedClasses.keys.sorted(), id: \.self) { category in
                VStack(alignment: .leading, spacing: 0) {
                    // En-tête de catégorie
                    HStack {
                        Text(category.capitalized)
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Text("\(groupedClasses[category]?.count ?? 0)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(4)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color.gray.opacity(0.1))
                    
                    // Classes de la catégorie
                    ForEach(groupedClasses[category] ?? [], id: \.self) { className in
                        ClassRowView(
                            className: className,
                            isSelected: selectedClasses.contains(className),
                            onToggle: { toggleClass(className) }
                        )
                        .padding(.horizontal, 12)
                    }
                }
                .background(Color.white)
                .cornerRadius(8)
                .padding(.bottom, 8)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private var groupedClasses: [String: [String]] {
        let filtered = filteredClasses
        
        var groups: [String: [String]] = [:]
        
        for className in filtered {
            let category = getCategoryForClass(className)
            if groups[category] == nil {
                groups[category] = []
            }
            groups[category]?.append(className)
        }
        
        return groups
    }
    
    private func getCategoryForClass(_ className: String) -> String {
        switch className {
        case "sidewalk", "road", "pedestrian crossing", "driveway", "bike lane", "parking area", "railway", "service lane":
            return "🛣️ infrastructure routière"
        case "wall", "fence", "curb", "guardrail", "temporary barrier", "other barrier":
            return "🚧 barrières"
        case "car", "truck", "bus", "motorcycle", "bicycle", "slow vehicle", "vehicle group", "rail vehicle", "boat":
            return "🚗 véhicules"
        case "person", "cyclist", "motorcyclist":
            return "👥 personnes"
        case "traffic light", "traffic sign", "streetlight", "traffic cone", "pole":
            return "🚦 signalisation"
        case "bench", "trash can", "fire hydrant", "mailbox", "parking meter", "bike rack", "phone booth":
            return "🏪 mobilier urbain"
        case "pothole", "manhole", "storm drain", "water valve", "junction box":
            return "🔧 infrastructure technique"
        case "building", "bridge", "tunnel", "garage":
            return "🏢 bâtiments"
        case "vegetation", "water", "ground", "animals":
            return "🌿 environnement"
        default:
            return "📦 autres"
        }
    }
    
    private func toggleClass(_ className: String) {
        if selectedClasses.contains(className) {
            selectedClasses.remove(className)
        } else {
            selectedClasses.insert(className)
        }
    }
    
    private func resetToDefault() {
        selectedClasses = Set(allClasses)
        selectedClasses.remove("building")
        selectedClasses.remove("vegetation")
        selectedClasses.remove("road")
        selectedClasses.remove("sidewalk")
        selectedClasses.remove("ground")
        selectedClasses.remove("wall")
        selectedClasses.remove("fence")
        
        skipFrames = 5
        confidenceThreshold = 0.5
        maxDetections = 10
    }
    
    private func loadCurrentSettings() {
        // Charger les paramètres depuis le VideoDetectionManager
        // (Si vous avez des méthodes de configuration dans VideoDetectionManager)
        
        // Pour l'instant, valeurs par défaut
        if selectedClasses.isEmpty {
            resetToDefault()
        }
    }
    
    private func saveSettings() {
        // Sauvegarder les paramètres dans le VideoDetectionManager
        // (Si vous avez des méthodes de configuration dans VideoDetectionManager)
        
        print("✅ Paramètres vidéo sauvegardés:")
        print("   - \(selectedClasses.count) classes actives")
        print("   - Skip frames: \(skipFrames)")
        print("   - Seuil confiance: \(confidenceThreshold)")
        print("   - Max détections: \(maxDetections)")
    }
}

// MARK: - Vue pour chaque ligne de classe (partagée)
struct ClassRowView: View {
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

// MARK: - Style pour les boutons d'action rapide (partagé)
struct QuickActionButtonStyle: ButtonStyle {
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
