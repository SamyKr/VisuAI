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

struct CameraDetectionSettingsView: View {
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
    @State private var currentPerformanceMode: PerformanceMode = .rapide  // ← NOUVEAU
    @State private var searchText = ""
    
    // États pour les vibrations
    @State private var proximityAlertsEnabled = true
    @State private var graduatedVibrationsEnabled = true
    @State private var graduatedFrequencyEnabled = true
    @State private var dangerDistance: Float = 1.0
    @State private var warningDistance: Float = 2.0
    @State private var minIntensity: Float = 0.3
    @State private var maxIntensity: Float = 1.0
    @State private var minCooldown: Double = 0.1
    @State private var maxCooldown: Double = 0.8
    
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
                        // Configuration Modes de Performance (NOUVEAU)
                        performanceModesSection
                        
                        Divider()
                        
                        // Configuration des vibrations
                        vibrationSettingsSection
                        
                        Divider()
                        
                        // Recherche de classes
                        searchSection
                        
                        // Liste des classes
                        classesListSection
                    }
                    .padding()
                }
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
            print("🔄 Vue paramètres chargée - Mode: \(currentPerformanceMode.displayName)")
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
                    Text("Performance")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(String(format: "%.1f", cameraManager.currentFPS)) FPS")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                }
                
                if cameraManager.lidarAvailable {
                    VStack(alignment: .trailing) {
                        Text("Vibrations")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(proximityAlertsEnabled ? "✅ ON" : "❌ OFF")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(proximityAlertsEnabled ? .orange : .gray)
                    }
                }
            }
            
            // Boutons de sélection rapide
            HStack(spacing: 12) {
                Button("Tout sélectionner") {
                    selectedClasses = Set(allClasses)
                }
                .buttonStyle(CameraQuickActionButtonStyle(color: .blue))
                
                Button("Tout désélectionner") {
                    selectedClasses.removeAll()
                }
                .buttonStyle(CameraQuickActionButtonStyle(color: .red))
                
                Button("Par défaut") {
                    resetToDefault()
                }
                .buttonStyle(CameraQuickActionButtonStyle(color: .orange))
            }
        }
        .padding()
        .background(Color(.systemGray6))
    }
    
    // MARK: - Section Modes de Performance (NOUVEAU - Remplace skipFramesSection)
    private var performanceModesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("⚡ Modes de Performance")
                    .font(.headline)
                
                Spacer()
                
                HStack {
                    Image(systemName: currentPerformanceMode.icon)
                        .foregroundColor(currentPerformanceMode.color)
                    Text(currentPerformanceMode.displayName)
                        .fontWeight(.semibold)
                        .foregroundColor(currentPerformanceMode.color)
                }
            }
            
            // Description du mode actuel
            Text(currentPerformanceMode.description)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
            
            // Boutons de sélection
            HStack(spacing: 12) {
                ForEach(PerformanceMode.allCases, id: \.self) { mode in
                    PerformanceModeButton(
                        mode: mode,
                        isSelected: currentPerformanceMode == mode
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            currentPerformanceMode = mode
                            updatePerformanceMode(mode)
                        }
                    }
                }
            }
            
            // Informations techniques
            VStack(alignment: .leading, spacing: 4) {
                Text("Informations techniques:")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                Text("• Skip: \(currentPerformanceMode.skipFrames) frames (1 sur \(currentPerformanceMode.skipFrames + 1))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Text("• FPS estimé: ~\(String(format: "%.1f", 30.0 / Double(currentPerformanceMode.skipFrames + 1)))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Text("• Valeur moteur: \(cameraManager.getSkipFrames())")
                    .font(.caption2)
                    .foregroundColor(.blue)
                    .fontWeight(.medium)
            }
            .padding(.top, 8)
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .cornerRadius(12)
    }
    
    // MARK: - Section vibrations
    private var vibrationSettingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("📳 Alertes de Proximité")
                    .font(.headline)
                
                Spacer()
                
                if !cameraManager.lidarAvailable {
                    Text("LiDAR requis")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            
            if cameraManager.lidarAvailable {
                VStack(spacing: 16) {
                    // Toggle principal
                    HStack {
                        Text("Activer les alertes")
                            .font(.body)
                        
                        Spacer()
                        
                        Toggle("", isOn: $proximityAlertsEnabled)
                            .labelsHidden()
                    }
                    
                    if proximityAlertsEnabled {
                        // Distance de danger
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("🚨 Distance de danger")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                Spacer()
                                
                                Text("\(String(format: "%.1f", dangerDistance))m")
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.red.opacity(0.1))
                                    .cornerRadius(4)
                            }
                            
                            Slider(value: $dangerDistance, in: 0.2...2.0, step: 0.1)
                            
                            Text("Triple vibration forte si objet < \(String(format: "%.1f", dangerDistance))m")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        // Distance d'avertissement
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("⚠️ Distance d'avertissement")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                Spacer()
                                
                                Text("\(String(format: "%.1f", warningDistance))m")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.1))
                                    .cornerRadius(4)
                            }
                            
                            Slider(value: $warningDistance, in: dangerDistance...5.0, step: 0.1)
                            
                            Text("Double vibration modérée si objet < \(String(format: "%.1f", warningDistance))m")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        // Vibrations graduées (intensité)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("📈 Intensité graduée")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                Spacer()
                                
                                Toggle("", isOn: $graduatedVibrationsEnabled)
                                    .labelsHidden()
                            }
                            
                            if graduatedVibrationsEnabled {
                                VStack(spacing: 8) {
                                    HStack {
                                        Text("Intensité minimale")
                                            .font(.caption)
                                        
                                        Spacer()
                                        
                                        Text("\(String(format: "%.1f", minIntensity))")
                                            .font(.caption)
                                            .fontWeight(.bold)
                                    }
                                    
                                    Slider(value: $minIntensity, in: 0.1...0.9, step: 0.1)
                                    
                                    HStack {
                                        Text("Intensité maximale")
                                            .font(.caption)
                                        
                                        Spacer()
                                        
                                        Text("\(String(format: "%.1f", maxIntensity))")
                                            .font(.caption)
                                            .fontWeight(.bold)
                                    }
                                    
                                    Slider(value: $maxIntensity, in: max(minIntensity, 0.5)...1.0, step: 0.1)
                                }
                                .padding(.leading, 16)
                            }
                            
                            Text(graduatedVibrationsEnabled ?
                                 "Plus l'objet est proche, plus la vibration est forte" :
                                 "Intensité fixe selon le type d'alerte")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        // Fréquence graduée
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("⚡ Fréquence graduée")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                Spacer()
                                
                                Toggle("", isOn: $graduatedFrequencyEnabled)
                                    .labelsHidden()
                            }
                            
                            if graduatedFrequencyEnabled {
                                VStack(spacing: 8) {
                                    HStack {
                                        Text("Fréquence max (très proche)")
                                            .font(.caption)
                                        
                                        Spacer()
                                        
                                        Text("toutes les \(String(format: "%.2f", minCooldown))s")
                                            .font(.caption)
                                            .fontWeight(.bold)
                                            .foregroundColor(.red)
                                    }
                                    
                                    Slider(value: $minCooldown, in: 0.05...0.5, step: 0.05)
                                    
                                    HStack {
                                        Text("Fréquence min (loin)")
                                            .font(.caption)
                                        
                                        Spacer()
                                        
                                        Text("toutes les \(String(format: "%.2f", maxCooldown))s")
                                            .font(.caption)
                                            .fontWeight(.bold)
                                            .foregroundColor(.orange)
                                    }
                                    
                                    Slider(value: $maxCooldown, in: max(minCooldown, 0.3)...2.0, step: 0.1)
                                }
                                .padding(.leading, 16)
                                
                                // Exemples visuels
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Exemples:")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(.secondary)
                                    
                                    HStack {
                                        Text("0.2m:")
                                            .font(.caption2)
                                            .foregroundColor(.red)
                                        Text("████████ toutes les \(String(format: "%.2f", minCooldown))s")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    HStack {
                                        Text("1.0m:")
                                            .font(.caption2)
                                            .foregroundColor(.orange)
                                        Text("████▓▓▓▓ toutes les \(String(format: "%.2f", (minCooldown + maxCooldown) / 2))s")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    HStack {
                                        Text("2.0m:")
                                            .font(.caption2)
                                            .foregroundColor(.green)
                                        Text("██▓▓▓▓▓▓ toutes les \(String(format: "%.2f", maxCooldown))s")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.leading, 16)
                                .padding(.top, 8)
                            }
                            
                            Text(graduatedFrequencyEnabled ?
                                 "Plus l'objet est proche, plus les vibrations sont fréquentes" :
                                 "Fréquence fixe pour toutes les distances")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        // Boutons de test
                        HStack {
                            Button("🧪 Tester vibration danger") {
                                cameraManager.testDangerVibration(intensity: maxIntensity)
                            }
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.red)
                            .cornerRadius(8)
                            
                            Button("🧪 Tester avertissement") {
                                cameraManager.testWarningVibration(intensity: minIntensity)
                            }
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.orange)
                            .cornerRadius(8)
                        }
                    }
                }
                .padding()
                .background(Color.blue.opacity(0.05))
                .cornerRadius(12)
            } else {
                Text("Les alertes de proximité nécessitent un appareil compatible LiDAR (iPhone 12 Pro+, iPad Pro 2020+)")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
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
                        CameraClassRowView(
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
        
        currentPerformanceMode = .rapide  // ← MODIFIÉ
        
        // Réinitialisation des paramètres de vibration
        proximityAlertsEnabled = true
        graduatedVibrationsEnabled = true
        graduatedFrequencyEnabled = true
        dangerDistance = 1.0
        warningDistance = 2.0
        minIntensity = 0.3
        maxIntensity = 1.0
        minCooldown = 0.1
        maxCooldown = 0.8
    }
    
    // MARK: - Méthodes pour les modes de performance (NOUVEAU)
    
    private func updatePerformanceMode(_ mode: PerformanceMode) {
        cameraManager.setSkipFrames(mode.skipFrames)
        cameraManager.playSelectionFeedback()
        print("🎛️ Mode de performance: \(mode.displayName) (skip: \(mode.skipFrames) frames)")
    }
    
    private func loadCurrentPerformanceMode() {
        let currentSkipFrames = cameraManager.getSkipFrames()
        currentPerformanceMode = PerformanceMode.allCases.first { $0.skipFrames == currentSkipFrames } ?? .normal
        print("🔄 Mode de performance chargé: \(currentPerformanceMode.displayName)")
    }
    
    // ✅ MÉTHODE MODIFIÉE - Synchronisation avec les modes
    private func loadCurrentSettings() {
        // Charger le mode de performance
        loadCurrentPerformanceMode()
        
        selectedClasses = Set(cameraManager.getActiveClasses())
        
        // Charger les paramètres de vibration
        proximityAlertsEnabled = cameraManager.isProximityAlertsEnabled()
        graduatedVibrationsEnabled = cameraManager.isGraduatedVibrationsEnabled()
        graduatedFrequencyEnabled = cameraManager.isGraduatedFrequencyEnabled()
        dangerDistance = cameraManager.getDangerDistance()
        warningDistance = cameraManager.getWarningDistance()
        
        let intensityRange = cameraManager.getIntensityRange()
        minIntensity = intensityRange.min
        maxIntensity = intensityRange.max
        
        let frequencyRange = cameraManager.getFrequencyRange()
        minCooldown = frequencyRange.minCooldown
        maxCooldown = frequencyRange.maxCooldown
        
        if selectedClasses.isEmpty {
            resetToDefault()
        }
    }
    
    private func saveSettings() {
        // Sauvegarder le mode de performance
        cameraManager.setSkipFrames(currentPerformanceMode.skipFrames)
        cameraManager.setActiveClasses(Array(selectedClasses))
        
        // Sauvegarder les paramètres de vibration
        cameraManager.enableProximityAlerts(proximityAlertsEnabled)
        cameraManager.enableGraduatedVibrations(graduatedVibrationsEnabled)
        cameraManager.enableGraduatedFrequency(graduatedFrequencyEnabled)
        cameraManager.setDangerDistance(dangerDistance)
        cameraManager.setWarningDistance(warningDistance)
        cameraManager.setIntensityRange(min: minIntensity, max: maxIntensity)
        cameraManager.setFrequencyRange(minCooldown: minCooldown, maxCooldown: maxCooldown)
        
        // Feedback haptique
        cameraManager.playSuccessFeedback()
        
        print("✅ Paramètres sauvegardés:")
        print("   - \(selectedClasses.count) classes actives")
        print("   - Mode performance: \(currentPerformanceMode.displayName) (skip: \(currentPerformanceMode.skipFrames))")
        print("   - Alertes proximité: \(proximityAlertsEnabled)")
        print("   - Vibrations graduées: \(graduatedVibrationsEnabled)")
        print("   - Fréquence graduée: \(graduatedFrequencyEnabled)")
        print("   - Distance danger: \(dangerDistance)m")
        print("   - Distance avertissement: \(warningDistance)m")
        print("   - Intensité: \(minIntensity) - \(maxIntensity)")
        print("   - Fréquence: \(minCooldown)s - \(maxCooldown)s")
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
