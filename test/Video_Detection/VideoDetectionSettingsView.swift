//
//  VideoDetectionSettingsView.swift
//  test
//
//  Created by Samy 📍 on 18/06/2025.
//

import SwiftUI

struct VideoDetectionSettingsView: View {
    @Binding var isPresented: Bool
    @ObservedObject var videoManager: VideoDetectionManager
    
    // Classes spécifiques à votre modèle
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
    @State private var skipFrames: Int = 10  // Plus élevé pour les vidéos
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
                // En-tête spécifique vidéo
                headerView
                
                // Configuration Skip Frames pour vidéo
                skipFramesSection
                
                Divider()
                
                // Recherche
                searchSection
                
                // Liste des classes
                classesListSection
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
    
    // MARK: - Header avec statistiques vidéo
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
                    Text("Mode Vidéo")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Optimisé")
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
                
                Button("Recommandé Vidéo") {
                    resetToVideoDefault()
                }
                .buttonStyle(QuickActionButtonStyle(color: .purple))
            }
        }
        .padding()
        .background(Color(.systemGray6))
    }
    
    // MARK: - Section Skip Frames optimisée pour vidéo
    private var skipFramesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Skip Frames (Vidéo)")
                    .font(.headline)
                
                Spacer()
                
                Text("1 frame sur \(skipFrames + 1)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text("Rapide")
                    .font(.caption)
                
                Slider(value: Binding(
                    get: { Double(skipFrames) },
                    set: { skipFrames = Int($0) }
                ), in: 5...30, step: 1)  // Plus élevé pour les vidéos
                
                Text("Précis")
                    .font(.caption)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Valeur: \(skipFrames)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("⚡ Plus élevé = traitement plus rapide mais moins de détections")
                    .font(.caption2)
                    .foregroundColor(.orange)
                
                Text("🎯 Plus bas = plus de détections mais traitement plus long")
                    .font(.caption2)
                    .foregroundColor(.blue)
            }
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
                Section(header: Text(category).font(.headline)) {
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
    
    private func resetToVideoDefault() {
        // Configuration optimisée pour les vidéos
        selectedClasses = Set([
            // Véhicules prioritaires
            "car", "truck", "bus", "motorcycle", "bicycle",
            // Personnes
            "person", "cyclist", "motorcyclist",
            // Signalisation importante
            "traffic light", "traffic sign", "traffic cone",
            // Véhicules spéciaux
            "vehicle group", "slow vehicle"
        ])
        skipFrames = 10
    }
    
    private func loadCurrentSettings() {
        skipFrames = videoManager.getSkipFrames()
        selectedClasses = Set(videoManager.getActiveClasses())
        
        // Si aucune classe n'est définie, utiliser les valeurs par défaut vidéo
        if selectedClasses.isEmpty {
            resetToVideoDefault()
        }
    }
    
    private func saveSettings() {
        videoManager.setSkipFrames(skipFrames)
        videoManager.setActiveClasses(Array(selectedClasses))
        print("✅ Paramètres vidéo sauvegardés: \(selectedClasses.count) classes, skip: \(skipFrames)")
    }
}
