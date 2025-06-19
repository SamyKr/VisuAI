//
//  DetectionSettingsView.swift
//  test
//
//  Created by Samy 📍 on 18/06/2025.
//

import SwiftUI

struct DetectionSettingsView: View {
    @Binding var isPresented: Bool
    @ObservedObject var cameraManager: CameraManager
    
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
                
                // Configuration Skip Frames
                skipFramesSection
                
                Divider()
                
                // Configuration LiDAR
                if cameraManager.isLiDARAvailable {
                    lidarSection
                    Divider()
                }
                
                // Recherche
                searchSection
                
                // Liste des classes
                classesListSection
            }
            .navigationTitle("Paramètres de Détection")
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
                    Text("LiDAR")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack {
                        if cameraManager.isLiDARAvailable {
                            Image(systemName: cameraManager.isLiDAREnabled ? "dot.radiowaves.left.and.right" : "dot.radiowaves.left.and.right")
                                .foregroundColor(cameraManager.isLiDAREnabled ? .blue : .gray)
                            Text(cameraManager.isLiDAREnabled ? "ON" : "OFF")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(cameraManager.isLiDAREnabled ? .blue : .gray)
                        } else {
                            Text("N/A")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.gray)
                        }
                    }
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
                Text("Skip Frames")
                    .font(.headline)
                
                Spacer()
                
                Text("1 frame sur \(skipFrames + 1)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text("Performance")
                    .font(.caption)
                
                Slider(value: Binding(
                    get: { Double(skipFrames) },
                    set: { skipFrames = Int($0) }
                ), in: 0...10, step: 1)
                
                Text("Qualité")
                    .font(.caption)
            }
            
            Text("Valeur: \(skipFrames) - FPS estimé: ~\(String(format: "%.1f", 30.0 / Double(skipFrames + 1)))")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
    
    // MARK: - Section LiDAR
    private var lidarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("LiDAR Distance")
                    .font(.headline)
                
                Spacer()
                
                Toggle("", isOn: Binding(
                    get: { cameraManager.isLiDAREnabled },
                    set: { cameraManager.setLiDAREnabled($0) }
                ))
                .labelsHidden()
            }
            
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .foregroundColor(.blue)
                    Text("Mesure de distance en temps réel")
                        .font(.caption)
                }
                
                HStack {
                    Image(systemName: "ruler")
                        .foregroundColor(.blue)
                    Text("Précision jusqu'à 5 mètres")
                        .font(.caption)
                }
                
                HStack {
                    Image(systemName: "battery.25")
                        .foregroundColor(.orange)
                    Text("Consomme plus de batterie")
                        .font(.caption)
                }
            }
            .foregroundColor(.secondary)
        }
        .padding()
    }
    
    // MARK: - Section de recherche
    private var searchSection: some View {
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
        .padding()
    }
    
    // MARK: - Liste des classes
    private var classesListSection: some View {
        List {
            ForEach(groupedClasses.keys.sorted(), id: \.self) { category in
                Section(header: Text(category.capitalized).font(.headline)) {
                    ForEach(groupedClasses[category] ?? [], id: \.self) { className in
                        ClassRowView(
                            className: className,
                            isSelected: selectedClasses.contains(className),
                            onToggle: { toggleClass(className) }
                        )
                    }
                }
            }
        }
        .listStyle(PlainListStyle())
    }
    
    // MARK: - Groupement des classes par catégorie
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
        // Infrastructure routière
        case "sidewalk", "road", "pedestrian crossing", "driveway", "bike lane", "parking area", "railway", "service lane":
            return "🛣️ infrastructure routière"
            
        // Barrières et délimitations
        case "wall", "fence", "curb", "guardrail", "temporary barrier", "other barrier":
            return "🚧 barrières"
            
        // Véhicules
        case "car", "truck", "bus", "motorcycle", "bicycle", "slow vehicle", "vehicle group", "rail vehicle", "boat":
            return "🚗 véhicules"
            
        // Personnes et usagers
        case "person", "cyclist", "motorcyclist":
            return "👥 personnes"
            
        // Signalisation et équipements urbains
        case "traffic light", "traffic sign", "streetlight", "traffic cone", "pole":
            return "🚦 signalisation"
            
        // Mobilier urbain
        case "bench", "trash can", "fire hydrant", "mailbox", "parking meter", "bike rack", "phone booth":
            return "🏪 mobilier urbain"
            
        // Infrastructure technique
        case "pothole", "manhole", "storm drain", "water valve", "junction box":
            return "🔧 infrastructure technique"
            
        // Bâtiments et structures
        case "building", "bridge", "tunnel", "garage":
            return "🏢 bâtiments"
            
        // Environnement naturel
        case "vegetation", "water", "ground", "animals":
            return "🌿 environnement"
            
        default:
            return "📦 autres"
        }
    }
    
    // MARK: - Actions
    private func toggleClass(_ className: String) {
        if selectedClasses.contains(className) {
            selectedClasses.remove(className)
        } else {
            selectedClasses.insert(className)
        }
    }
    
    private func resetToDefault() {
        selectedClasses = Set(allClasses)
        // Retirer les classes par défaut selon vos spécifications
        selectedClasses.remove("building")
        selectedClasses.remove("vegetation")
        selectedClasses.remove("road")
        // Ajout d'autres classes d'infrastructure moins importantes par défaut
        selectedClasses.remove("sidewalk")
        selectedClasses.remove("ground")
        selectedClasses.remove("wall")
        selectedClasses.remove("fence")
        skipFrames = 5
    }
    
    private func loadCurrentSettings() {
        // Charger les paramètres actuels du CameraManager
        skipFrames = cameraManager.getSkipFrames()
        selectedClasses = Set(cameraManager.getActiveClasses())
        
        // Si aucune classe n'est définie, utiliser les valeurs par défaut
        if selectedClasses.isEmpty {
            resetToDefault()
        }
    }
    
    private func saveSettings() {
        cameraManager.setSkipFrames(skipFrames)
        cameraManager.setActiveClasses(Array(selectedClasses))
        print("✅ Paramètres sauvegardés: \(selectedClasses.count) classes, skip: \(skipFrames)")
    }
}

// MARK: - Vue pour chaque ligne de classe
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
    }
}

// MARK: - Style pour les boutons d'action rapide
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
