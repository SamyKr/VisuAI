//
//  ParametersView.swift
//  Interface de Configuration et Paramètres Avancés - VERSION OPTIMISÉE
//
//  Vue SwiftUI pour la gestion des paramètres utilisateur et de la configuration
//  des objets avec propriétés statiques/dynamiques unifiées.
//
//  🎯 AMÉLIORATIONS: Espacement optimisé et tailles réduites
//

import SwiftUI

// Structure pour les questions (réutilisée du questionnaire)
struct QuestionItem {
    let id: Int
    let text: String
    let description: String
}

// 🎯 NOUVEAU: Gestionnaire pour les paramètres de sécurité
class SafetyParametersManager: ObservableObject {
    @Published var criticalDistance: Float = 2.0  // Distance critique en mètres
    
    private let userDefaults = UserDefaults.standard
    private let criticalDistanceKey = "safety_critical_distance"
    
    // Référence au CameraManager pour synchronisation
    private weak var cameraManager: CameraManager?
    
    // Limites pour le slider
    let minDistance: Float = 0.5   // 50cm minimum
    let maxDistance: Float = 10.0  // 10m maximum
    
    init(cameraManager: CameraManager) {
        self.cameraManager = cameraManager
        loadCriticalDistance()
    }
    
    func setCriticalDistance(_ distance: Float) {
        let clampedDistance = max(minDistance, min(maxDistance, distance))
        criticalDistance = clampedDistance
        saveCriticalDistance()
        applyCriticalDistance()
    }
    
    private func saveCriticalDistance() {
        userDefaults.set(criticalDistance, forKey: criticalDistanceKey)
    }
    
    private func loadCriticalDistance() {
        let savedDistance = userDefaults.float(forKey: criticalDistanceKey)
        if savedDistance > 0 {
            criticalDistance = savedDistance
        }
        // Sinon garder la valeur par défaut (2.0m)
    }
    
    private func applyCriticalDistance() {
        // 🔗 Synchroniser avec le système de synthèse vocale via CameraManager
        cameraManager?.updateCriticalDistance(criticalDistance)
    }
    
    func resetToDefault() {
        setCriticalDistance(2.0)
    }
    
    func getDistanceDescription() -> String {
        return "Objets détectés à moins de \(String(format: "%.1f", criticalDistance))m"
    }
}

struct ParametersView: View {
    @Binding var isPresented: Bool
    
    // 🎯 MODIFICATION PRINCIPALE: Accepter le CameraManager de DetectionView
    let cameraManager: CameraManager
    
    @StateObject private var questionnaireManager = QuestionnaireManager()
    
    // 🔗 NOUVEAU: ObjectConfigurationManager unifié
    @StateObject private var objectConfigManager: ObjectConfigurationManager
    
    // 🎯 NOUVEAU: Gestionnaire des paramètres de sécurité
    @StateObject private var safetyParametersManager: SafetyParametersManager
    
    @State private var showingDeleteConfirmation = false
    @State private var showingExitConfirmation = false
    
    // 🎯 MODIFIÉ: Questions du questionnaire pour modification - SIMPLIFIÉ À 3 QUESTIONS
    private let questions = [
        QuestionItem(
            id: 1,
            text: "Alertes vocales d'objets proches",
            description: "Voulez-vous être averti vocalement des objets proches ?"
        ),
        QuestionItem(
            id: 2,
            text: "Vibrations de proximité",
            description: "Voulez-vous des vibrations pour les alertes de proximité ?"
        ),
        QuestionItem(
            id: 3,
            text: "Communication vocale",
            description: "Voulez-vous pouvoir communiquer vocalement avec l'application ?"
        )
    ]
    
    // 🎯 NOUVEAU: Custom initializer pour accepter le CameraManager
    init(isPresented: Binding<Bool>, cameraManager: CameraManager) {
        self._isPresented = isPresented
        self.cameraManager = cameraManager
        
        // Initialiser ObjectConfigurationManager avec le CameraManager
        self._objectConfigManager = StateObject(wrappedValue: ObjectConfigurationManager(cameraManager: cameraManager))
        
        // Initialiser SafetyParametersManager avec le CameraManager
        self._safetyParametersManager = StateObject(wrappedValue: SafetyParametersManager(cameraManager: cameraManager))
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Fond avec la même charte graphique
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(hex: "0a1f0a"),
                        Color(hex: "56c228").opacity(0.08),
                        Color(hex: "5ee852").opacity(0.06),
                        Color(hex: "0a1f0a")
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 16) { // 📐 Réduit de 24 à 16
                        // Section Profil Utilisateur
                        ProfileSectionView(
                            questionnaireManager: questionnaireManager,
                            questions: questions,
                            showingDeleteConfirmation: $showingDeleteConfirmation,
                            showingExitConfirmation: $showingExitConfirmation
                        )
                        
                        // 🎯 NOUVELLE SECTION: Paramètres de Sécurité
                        SafetySectionView(
                            safetyParametersManager: safetyParametersManager
                        )
                        
                        // 🎯 NOUVELLE SECTION: Configuration Objets Unifiée
                        UnifiedObjectsSectionView(
                            objectConfigManager: objectConfigManager,
                            cameraManager: cameraManager
                        )
                    }
                    .padding(.horizontal, 16) // 📐 Réduit le padding horizontal
                    .padding(.vertical, 12)    // 📐 Réduit le padding vertical
                }
            }
            .navigationTitle("Paramètres")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fermer") {
                        isPresented = false
                    }
                    .foregroundColor(Color(hex: "5ee852"))
                }
            }
        }
        .alert("Supprimer le profil", isPresented: $showingDeleteConfirmation) {
            Button("Supprimer", role: .destructive) {
                deleteProfile()
            }
            Button("Annuler", role: .cancel) { }
        } message: {
            Text("Cette action supprimera définitivement votre profil et fermera l'application. Êtes-vous sûr ?")
        }
        .alert("Fermer l'application", isPresented: $showingExitConfirmation) {
            Button("Fermer", role: .destructive) {
                exitApplication()
            }
            Button("Annuler", role: .cancel) { }
        } message: {
            Text("Voulez-vous fermer l'application ?")
        }
    }
    
    private func deleteProfile() {
        questionnaireManager.clearResponses()
        objectConfigManager.resetToDefaults()
        safetyParametersManager.resetToDefault()
        
        // Fermer l'application après suppression
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            exitApplication()
        }
    }
    
    private func exitApplication() {
        UIApplication.shared.perform(#selector(NSXPCConnection.suspend))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            exit(0)
        }
    }
}

// MARK: - 🎯 SECTION OPTIMISÉE: Configuration Objets Unifiée

struct UnifiedObjectsSectionView: View {
    @ObservedObject var objectConfigManager: ObjectConfigurationManager
    let cameraManager: CameraManager
    @State private var filterMode: FilterMode = .all
    
    enum FilterMode: String, CaseIterable {
        case all = "Tous"
        case dangerous = "Dangereux"
        case safe = "Sûrs"
        case dynamic = "Mobiles"
        case statique = "Statiques"
    }
    
    var filteredObjects: [ObjectConfig] {
        let allObjects = objectConfigManager.getAllConfigurations()
        
        // Filtrer par mode seulement
        switch filterMode {
        case .all:
            return allObjects
        case .dangerous:
            return allObjects.filter { $0.isDangerous }
        case .safe:
            return allObjects.filter { !$0.isDangerous }
        case .dynamic:
            return allObjects.filter { !$0.isStatiqueByDefault }
        case .statique:
            return allObjects.filter { $0.isStatiqueByDefault }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { // 📐 Réduit de 20 à 12
            // En-tête de section - Plus compact
            VStack(alignment: .leading, spacing: 6) { // 📐 Réduit de 10 à 6
                HStack {
                    Image(systemName: "gearshape.2.fill")
                        .font(.title2) // 📐 Réduit de .title à .title2
                        .foregroundColor(Color(hex: "5ee852"))
                    
                    Text("Configuration des Objets")
                        .font(.title2) // 📐 Réduit de .title à .title2
                        .fontWeight(.bold)
                        .foregroundColor(Color(hex: "f0fff0"))
                    
                    Spacer()
                }
                
                Text("Sélectionnez les objets qui déclenchent des alertes vocales")
                    .font(.caption) // 📐 Réduit de .subheadline à .caption
                    .foregroundColor(Color(hex: "f0fff0").opacity(0.8))
                    .fontWeight(.medium)
            }
            
            // Statistiques compactes
            let stats = objectConfigManager.getStats()
            HStack(spacing: 12) { // 📐 Réduit de 20 à 12
                CompactStatBadge(
                    icon: "exclamationmark.triangle.fill",
                    color: .red,
                    value: "\(stats.dangerous)",
                    label: "Dangereux"
                )
                
                CompactStatBadge(
                    icon: "figure.walk",
                    color: .orange,
                    value: "\(stats.dynamic)",
                    label: "Mobiles"
                )
                
                CompactStatBadge(
                    icon: "building.2.fill",
                    color: .blue,
                    value: "\(stats.statiques)",
                    label: "Statiques"
                )
                
                Spacer()
                
                // Bouton de réinitialisation compact
                Button("Reset") {
                    objectConfigManager.resetToDefaults()
                    cameraManager.playSelectionFeedback()
                }
                .font(.caption) // 📐 Réduit la taille
                .fontWeight(.semibold)
                .foregroundColor(Color(hex: "0a1f0a"))
                .padding(.horizontal, 12) // 📐 Réduit de 20 à 12
                .padding(.vertical, 8)    // 📐 Réduit de 12 à 8
                .background(Color(hex: "5ee852"))
                .cornerRadius(8) // 📐 Réduit de 12 à 8
                .shadow(color: Color(hex: "5ee852").opacity(0.3), radius: 4) // 📐 Réduit le radius
            }
            
            // Filtres par catégorie - Plus compacts
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) { // 📐 Réduit de 15 à 10
                    ForEach(FilterMode.allCases, id: \.self) { mode in
                        Button(action: {
                            filterMode = mode
                            cameraManager.playSelectionFeedback()
                        }) {
                            HStack(spacing: 4) { // 📐 Réduit de 8 à 4
                                Image(systemName: getFilterIcon(mode))
                                    .font(.caption) // 📐 Réduit de .subheadline à .caption
                                    .fontWeight(.semibold)
                                
                                Text(mode.rawValue)
                                    .font(.caption) // 📐 Réduit de .subheadline à .caption
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(filterMode == mode ? Color(hex: "0a1f0a") : Color(hex: "f0fff0"))
                            .padding(.horizontal, 10) // 📐 Réduit de 16 à 10
                            .padding(.vertical, 6)    // 📐 Réduit de 10 à 6
                            .background(
                                RoundedRectangle(cornerRadius: 12) // 📐 Réduit de 20 à 12
                                    .fill(filterMode == mode ? Color(hex: "5ee852") : Color(hex: "5ee852").opacity(0.15))
                                    .shadow(color: filterMode == mode ? Color(hex: "5ee852").opacity(0.4) : .clear, radius: 3) // 📐 Réduit le radius
                            )
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            
            // Liste unifiée des objets - Plus compacte
            if filteredObjects.isEmpty {
                VStack(spacing: 12) { // 📐 Réduit de 20 à 12
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 40)) // 📐 Réduit de 60 à 40
                        .foregroundColor(Color(hex: "f0fff0").opacity(0.3))
                    
                    Text("Aucun objet dans cette catégorie")
                        .font(.headline) // 📐 Réduit de .title2 à .headline
                        .fontWeight(.medium)
                        .foregroundColor(Color(hex: "f0fff0").opacity(0.6))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30) // 📐 Réduit de 60 à 30
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) { // 📐 Réduit de 12 à 8
                        ForEach(filteredObjects, id: \.type) { config in
                            CompactObjectRow(
                                config: config,
                                onToggle: {
                                    objectConfigManager.toggleDangerous(for: config.type)
                                    cameraManager.playSelectionFeedback()
                                },
                                onTypeChange: { isStatique in
                                    objectConfigManager.setStatiqueType(for: config.type, isStatique: isStatique)
                                }
                            )
                        }
                    }
                    .padding(.vertical, 4) // 📐 Réduit de 8 à 4
                }
                .frame(maxHeight: 300) // 📐 Réduit de 450 à 300
            }
            
            // Explication du système - Plus compacte
            VStack(alignment: .leading, spacing: 8) { // 📐 Réduit de 12 à 8
                HStack {
                    Image(systemName: "lightbulb.fill")
                        .font(.subheadline) // 📐 Réduit de .title3 à .subheadline
                        .foregroundColor(.yellow)
                    
                    Text("Mode d'emploi")
                        .font(.subheadline) // 📐 Réduit de .headline à .subheadline
                        .fontWeight(.bold)
                        .foregroundColor(Color(hex: "f0fff0"))
                }
                
                VStack(alignment: .leading, spacing: 4) { // 📐 Réduit de 8 à 4
                    CompactInfoRow(icon: "checkmark.circle.fill", color: .green, text: "Objets cochés → Alertes vocales")
                    CompactInfoRow(icon: "figure.walk", color: .orange, text: "Mobiles → Zone étendue (+2m)")
                    CompactInfoRow(icon: "building.2.fill", color: .blue, text: "Statiques → Zone normale")
                    CompactInfoRow(icon: "hand.tap.fill", color: .purple, text: "Appui long → Changer type")
                }
            }
            .padding(12) // 📐 Réduit de 20 à 12
            .background(
                RoundedRectangle(cornerRadius: 12) // 📐 Réduit de 16 à 12
                    .fill(Color.blue.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .padding(12) // 📐 Réduit de 20 à 12
        .background(
            RoundedRectangle(cornerRadius: 16) // 📐 Réduit de 20 à 16
                .fill(Color(hex: "5ee852").opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color(hex: "5ee852").opacity(0.2), lineWidth: 2)
                )
        )
    }
    
    private func getFilterIcon(_ mode: FilterMode) -> String {
        switch mode {
        case .all: return "list.bullet"
        case .dangerous: return "exclamationmark.triangle.fill"
        case .safe: return "checkmark.shield.fill"
        case .dynamic: return "figure.walk"
        case .statique: return "building.2.fill"
        }
    }
}

// MARK: - Composants helper compacts

struct CompactStatBadge: View {
    let icon: String
    let color: Color
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 4) { // 📐 Réduit de 8 à 4
            HStack(spacing: 4) { // 📐 Réduit de 6 à 4
                Image(systemName: icon)
                    .font(.headline) // 📐 Réduit de .title2 à .headline
                    .foregroundColor(color)
                
                Text(value)
                    .font(.title2) // 📐 Réduit de .title à .title2
                    .fontWeight(.black)
                    .foregroundColor(color)
            }
            
            Text(label)
                .font(.caption2) // 📐 Réduit de .caption à .caption2
                .fontWeight(.semibold)
                .foregroundColor(Color(hex: "f0fff0").opacity(0.9))
        }
        .padding(.horizontal, 10) // 📐 Réduit de 16 à 10
        .padding(.vertical, 8)    // 📐 Réduit de 12 à 8
        .background(
            RoundedRectangle(cornerRadius: 8) // 📐 Réduit de 12 à 8
                .fill(color.opacity(0.15))
                .shadow(color: color.opacity(0.2), radius: 2) // 📐 Réduit le radius
        )
    }
}

struct CompactInfoRow: View {
    let icon: String
    let color: Color
    let text: String
    
    var body: some View {
        HStack(spacing: 8) { // 📐 Réduit de 12 à 8
            Image(systemName: icon)
                .font(.caption) // 📐 Réduit de .subheadline à .caption
                .foregroundColor(color)
                .frame(width: 16) // 📐 Réduit de 20 à 16
            
            Text(text)
                .font(.caption) // 📐 Réduit de .subheadline à .caption
                .foregroundColor(Color(hex: "f0fff0").opacity(0.9))
        }
    }
}

struct CompactObjectRow: View {
    let config: ObjectConfig
    let onToggle: () -> Void
    let onTypeChange: (Bool) -> Void
    
    var body: some View {
        HStack(spacing: 12) { // 📐 Réduit de 16 à 12
            // Icône plus compacte
            Image(systemName: getIconForObject(config.type))
                .font(.headline) // 📐 Réduit de .title à .headline
                .foregroundColor(config.isDangerous ? .red : Color(hex: "f0fff0").opacity(0.6))
                .frame(width: 30, height: 30) // 📐 Réduit de 40x40 à 30x30
            
            VStack(alignment: .leading, spacing: 4) { // 📐 Réduit de 8 à 4
                // Nom de l'objet plus compact
                Text(config.displayName)
                    .font(.subheadline) // 📐 Réduit de .headline à .subheadline
                    .fontWeight(.semibold)
                    .foregroundColor(Color(hex: "f0fff0"))
                
                // Badges de propriétés avec espacement amélioré
                HStack(spacing: 14) { // 📐 Augmenté de 6 à 12 pour plus d'espace
                    // Badge statique/dynamique compact avec long press
                    HStack(spacing: 3) {
                        Image(systemName: config.isStatiqueByDefault ? "building.2.fill" : "figure.walk")
                            .font(.caption2)
                            .fontWeight(.semibold)
                        Text(config.isStatiqueByDefault ? "Stat" : "Mob")
                            .font(.caption2)
                            .fontWeight(.semibold)
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption2)
                            .opacity(0.6)
                    }
                    .foregroundColor(config.isStatiqueByDefault ? .blue : .orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill((config.isStatiqueByDefault ? Color.blue : Color.orange).opacity(0.2))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(config.isStatiqueByDefault ? Color.blue : Color.orange, lineWidth: 1)
                            )
                    )
                    .onLongPressGesture(minimumDuration: 0.6) {
                        onTypeChange(!config.isStatiqueByDefault)
                        
                        // Feedback haptique plus marqué
                        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
                        impactFeedback.impactOccurred()
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            let lightFeedback = UIImpactFeedbackGenerator(style: .medium)
                            lightFeedback.impactOccurred()
                        }
                    }
                    
                    // Badge distance d'annonce simplifié avec juste l'icône volume
                    if config.isDangerous {
                        HStack(spacing: 3) {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.caption)
                                .fontWeight(.semibold)
                            
                            // Indicateur visuel du type de distance
                            if !config.isStatiqueByDefault {
                                Image(systemName: "plus")
                                    .font(.caption2)
                                    .opacity(0.8)
                            }
                        }
                        .foregroundColor(.purple)
                        .padding(.horizontal, 8) // 📐 Augmenté pour équilibrer
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.purple.opacity(0.2))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.purple.opacity(0.4), lineWidth: 1)
                                )
                        )
                    }
                }
            }
            
            Spacer()
            
            // Toggle compact
            Toggle("", isOn: Binding(
                get: { config.isDangerous },
                set: { _ in onToggle() }
            ))
            .toggleStyle(SwitchToggleStyle(tint: .red))
            .scaleEffect(0.9) // 📐 Réduit de 1.2 à 0.9
        }
        .padding(.horizontal, 12) // 📐 Réduit de 20 à 12
        .padding(.vertical, 10)   // 📐 Réduit de 16 à 10
        .background(
            RoundedRectangle(cornerRadius: 12) // 📐 Réduit de 16 à 12
                .fill(config.isDangerous ? Color.red.opacity(0.08) : Color(hex: "0a1f0a").opacity(0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(config.isDangerous ? Color.red.opacity(0.4) : Color(hex: "f0fff0").opacity(0.1), lineWidth: config.isDangerous ? 2 : 1)
                )
        )
    }
    
    private func getIconForObject(_ objectType: String) -> String {
        switch objectType.lowercased() {
        case "person": return "person.fill"
        case "cyclist": return "figure.outdoor.cycle"
        case "motorcyclist": return "figure.motorcycling"
        case "car", "truck", "bus": return "car.fill"
        case "bicycle": return "bicycle"
        case "motorcycle": return "bicycle"
        case "slow_vehicle", "vehicle_group": return "car.2.fill"
        case "rail_vehicle": return "tram.fill"
        case "boat": return "ferry.fill"
        case "traffic_light": return "lightbulb.fill"
        case "traffic_sign": return "stop.fill"
        case "traffic_cone": return "cone.fill"
        case "pole": return "cylinder.fill"
        case "barrier", "temporary_barrier", "barrier_other": return "rectangle.fill"
        case "wall", "fence": return "rectangle.fill"
        case "chair", "couch": return "chair.fill"
        case "bottle", "cup": return "cup.and.saucer.fill"
        case "book": return "book.fill"
        case "cell phone", "laptop": return "iphone"
        case "animals": return "pawprint.fill"
        case "building": return "building.2.fill"
        case "bridge": return "building.columns.fill"
        case "tunnel": return "mountain.2.fill"
        case "vegetation": return "leaf.fill"
        case "water": return "drop.fill"
        case "terrain", "ground": return "mountain.2.fill"
        case "road", "sidewalk": return "road.lanes"
        case "crosswalk": return "figure.walk"
        case "parking_area": return "parkingsign"
        case "rail_track": return "tram.fill"
        case "curb": return "road.lanes"
        case "street_light": return "lightbulb.max.fill"
        case "bench": return "chair.fill"
        case "trash_can": return "trash.fill"
        case "fire_hydrant": return "flame.fill"
        case "mailbox": return "envelope.fill"
        case "parking_meter": return "timer"
        case "bike_rack": return "bicycle"
        case "phone_booth": return "phone.fill"
        case "pothole": return "exclamationmark.triangle.fill"
        case "manhole", "catch_basin": return "circle.grid.cross.fill"
        case "water_valve": return "drop.circle.fill"
        case "junction_box": return "square.grid.3x3.fill"
        default: return "questionmark.circle.fill"
        }
    }
}

// MARK: - 🎯 SECTION OPTIMISÉE: Paramètres de Sécurité

struct SafetySectionView: View {
    @ObservedObject var safetyParametersManager: SafetyParametersManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { // 📐 Réduit de 16 à 10
            // En-tête de section compact
            VStack(alignment: .leading, spacing: 4) { // 📐 Réduit de 8 à 4
                HStack {
                    Image(systemName: "shield.checkerboard")
                        .font(.headline) // 📐 Réduit de .title2 à .headline
                        .foregroundColor(.orange)
                    
                    Text("Paramètres de Sécurité")
                        .font(.headline) // 📐 Réduit de .title2 à .headline
                        .fontWeight(.bold)
                        .foregroundColor(Color(hex: "f0fff0"))
                    
                    Spacer()
                }
                
                Text("Configurez les alertes de danger immédiat")
                    .font(.caption2) // 📐 Réduit de .caption à .caption2
                    .foregroundColor(.orange.opacity(0.8))
            }
            
            // Section Distance Critique compacte
            VStack(alignment: .leading, spacing: 10) { // 📐 Réduit de 16 à 10
                // Titre et valeur actuelle compact
                HStack {
                    VStack(alignment: .leading, spacing: 2) { // 📐 Réduit de 4 à 2
                        Text("Distance d'alerte critique")
                            .font(.subheadline) // 📐 Réduit de .headline à .subheadline
                            .foregroundColor(Color(hex: "f0fff0"))
                        
                        Text("Objets à moins de cette distance déclenchent une alerte vocale")
                            .font(.caption2) // 📐 Réduit de .caption à .caption2
                            .foregroundColor(Color(hex: "f0fff0").opacity(0.7))
                    }
                    
                    Spacer()
                    
                    // Valeur actuelle avec badge compact
                    VStack(spacing: 1) { // 📐 Réduit de 2 à 1
                        Text("\(String(format: "%.1f", safetyParametersManager.criticalDistance)) m")
                            .font(.headline) // 📐 Réduit de .title2 à .headline
                            .fontWeight(.bold)
                            .foregroundColor(.orange)
                        
                        Text(safetyParametersManager.getDistanceDescription())
                            .font(.caption2) // Maintenu petit
                            .foregroundColor(.orange.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 8) // 📐 Réduit de 12 à 8
                    .padding(.vertical, 6)   // 📐 Réduit de 8 à 6
                    .background(.orange.opacity(0.15))
                    .cornerRadius(6) // 📐 Réduit de 8 à 6
                }
                
                // Slider avec marqueurs compact
                VStack(spacing: 6) { // 📐 Réduit de 8 à 6
                    // Slider principal
                    HStack {
                        Text("\(String(format: "%.1f", safetyParametersManager.minDistance))m")
                            .font(.caption2) // Maintenu petit
                            .foregroundColor(Color(hex: "f0fff0").opacity(0.6))
                        
                        Slider(
                            value: Binding(
                                get: { safetyParametersManager.criticalDistance },
                                set: { safetyParametersManager.setCriticalDistance($0) }
                            ),
                            in: safetyParametersManager.minDistance...safetyParametersManager.maxDistance,
                            step: 0.1
                        )
                        .accentColor(.orange)
                        
                        Text("\(String(format: "%.1f", safetyParametersManager.maxDistance))m")
                            .font(.caption2) // Maintenu petit
                            .foregroundColor(Color(hex: "f0fff0").opacity(0.6))
                    }
                    
                    // Marqueurs de valeurs prédéfinies compacts
                    HStack {
                        ForEach([0.5, 1.0, 2.0, 3.0, 5.0, 10.0], id: \.self) { value in
                            Button(action: {
                                safetyParametersManager.setCriticalDistance(Float(value))
                                // Feedback haptique
                                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                impactFeedback.impactOccurred()
                            }) {
                                Text("\(String(format: value.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f", value))m")
                                    .font(.caption2) // Maintenu petit
                                    .fontWeight(abs(safetyParametersManager.criticalDistance - Float(value)) < 0.1 ? .bold : .regular)
                                    .foregroundColor(abs(safetyParametersManager.criticalDistance - Float(value)) < 0.1 ? .orange : Color(hex: "f0fff0").opacity(0.6))
                                    .padding(.horizontal, 6) // 📐 Réduit de 8 à 6
                                    .padding(.vertical, 3)   // 📐 Réduit de 4 à 3
                                    .background(abs(safetyParametersManager.criticalDistance - Float(value)) < 0.1 ? .orange.opacity(0.2) : .clear)
                                    .cornerRadius(4) // 📐 Réduit de 6 à 4
                            }
                        }
                    }
                }
                
                // Bouton de réinitialisation compact
                HStack {
                    Spacer()
                    
                    Button(action: {
                        safetyParametersManager.resetToDefault()
                        // Feedback haptique
                        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                        impactFeedback.impactOccurred()
                    }) {
                        HStack(spacing: 4) { // 📐 Réduit de 6 à 4
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset (2.0m)") // 📐 Texte abrégé
                        }
                        .font(.caption) // Maintenu
                        .foregroundColor(.orange)
                        .padding(.horizontal, 8) // 📐 Réduit de 12 à 8
                        .padding(.vertical, 4)   // 📐 Réduit de 6 à 4
                        .background(.orange.opacity(0.15))
                        .cornerRadius(6) // 📐 Réduit de 8 à 6
                    }
                }
                
                // Info explicative avec nouveau système compact
                VStack(alignment: .leading, spacing: 6) { // 📐 Réduit de 8 à 6
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .font(.caption) // Maintenu
                            .foregroundColor(.blue)
                        
                        Text("Nouveau système d'annonces :")
                            .font(.caption) // Maintenu
                            .fontWeight(.semibold)
                            .foregroundColor(Color(hex: "f0fff0"))
                    }
                    
                    VStack(alignment: .leading, spacing: 2) { // 📐 Réduit de 4 à 2
                        Text("• Statiques → \(String(format: "%.1f", safetyParametersManager.criticalDistance))m")
                        Text("• Mobiles → \(String(format: "%.1f", safetyParametersManager.criticalDistance + 2.0))m")
                        Text("• Mise à jour temps réel avec anti-spam")
                    }
                    .font(.caption2) // 📐 Réduit de .caption2 (maintenu mais simplifié)
                    .foregroundColor(Color(hex: "f0fff0").opacity(0.7))
                }
                .padding(8) // 📐 Réduit de padding à 8
                .background(Color.blue.opacity(0.1))
                .cornerRadius(6) // 📐 Réduit de 8 à 6
            }
        }
        .padding(10) // 📐 Réduit de padding à 10
        .background(.orange.opacity(0.05))
        .cornerRadius(12) // 📐 Réduit de 16 à 12
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.orange.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Section Profil Utilisateur Optimisée

struct ProfileSectionView: View {
    @ObservedObject var questionnaireManager: QuestionnaireManager
    let questions: [QuestionItem]
    @Binding var showingDeleteConfirmation: Bool
    @Binding var showingExitConfirmation: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { // 📐 Réduit de 16 à 10
            // En-tête de section compact
            VStack(alignment: .leading, spacing: 4) { // 📐 Réduit de 8 à 4
                HStack {
                    Image(systemName: "person.circle.fill")
                        .font(.headline) // 📐 Réduit de .title2 à .headline
                        .foregroundColor(Color(hex: "5ee852"))
                    
                    Text("Profil Utilisateur")
                        .font(.headline) // 📐 Réduit de .title2 à .headline
                        .fontWeight(.bold)
                        .foregroundColor(Color(hex: "f0fff0"))
                    
                    Spacer()
                }
                
                Text("Modifiez vos réponses ou supprimez votre profil")
                    .font(.caption2) // 📐 Réduit de .caption à .caption2
                    .foregroundColor(Color(hex: "f0fff0").opacity(0.7))
            }
            
            // 🎯 NOUVEAU: Résumé visuel des configurations actuelles compact
            if questionnaireManager.responses.count > 0 {
                VStack(spacing: 6) { // 📐 Réduit de 8 à 6
                    Text("Configuration actuelle :")
                        .font(.caption) // Maintenu
                        .fontWeight(.semibold)
                        .foregroundColor(Color(hex: "f0fff0"))
                    
                    HStack(spacing: 12) { // 📐 Réduit de 16 à 12
                        // Alertes vocales
                        HStack(spacing: 4) { // 📐 Réduit de 6 à 4
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.caption) // Maintenu
                                .foregroundColor(questionnaireManager.responses[1] == true ? Color(hex: "5ee852") : .red)
                            Text("Vocal")
                                .font(.caption2) // Maintenu
                                .foregroundColor(Color(hex: "f0fff0").opacity(0.8))
                        }
                        
                        // Vibrations
                        HStack(spacing: 4) { // 📐 Réduit de 6 à 4
                            Image(systemName: "iphone.radiowaves.left.and.right")
                                .font(.caption) // Maintenu
                                .foregroundColor(questionnaireManager.responses[2] == true ? .orange : .red)
                            Text("Vibrations")
                                .font(.caption2) // Maintenu
                                .foregroundColor(Color(hex: "f0fff0").opacity(0.8))
                        }
                        
                        // Communication
                        HStack(spacing: 4) { // 📐 Réduit de 6 à 4
                            Image(systemName: "mic.fill")
                                .font(.caption) // Maintenu
                                .foregroundColor(questionnaireManager.responses[3] == true ? .blue : .red)
                            Text("Micro")
                                .font(.caption2) // Maintenu
                                .foregroundColor(Color(hex: "f0fff0").opacity(0.8))
                        }
                        
                        Spacer()
                    }
                }
                .padding(8) // 📐 Réduit de padding à 8
                .background(Color(hex: "0a1f0a").opacity(0.4))
                .cornerRadius(6) // 📐 Réduit de 8 à 6
            }
            
            // Liste des questions modifiables compacte
            VStack(spacing: 8) { // 📐 Réduit de 12 à 8
                ForEach(questions, id: \.id) { question in
                    CompactQuestionRowView(
                        question: question,
                        response: questionnaireManager.responses[question.id],
                        onEdit: { }, // Plus utilisé mais gardé pour compatibilité
                        questionnaireManager: questionnaireManager
                    )
                }
            }
            
            // Actions du profil compactes
            VStack(spacing: 8) { // 📐 Réduit de 12 à 8
                // Bouton Supprimer Profil compact
                Button(action: {
                    showingDeleteConfirmation = true
                }) {
                    HStack {
                        Image(systemName: "trash.fill")
                        Text("Supprimer le profil")
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10) // 📐 Réduit de padding à 10
                    .background(Color.red.opacity(0.8))
                    .cornerRadius(8) // 📐 Réduit de 12 à 8
                }
                
                // Bouton Fermer Application compact
                Button(action: {
                    showingExitConfirmation = true
                }) {
                    HStack {
                        Image(systemName: "power")
                        Text("Fermer l'application")
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10) // 📐 Réduit de padding à 10
                    .background(Color.gray.opacity(0.6))
                    .cornerRadius(8) // 📐 Réduit de 12 à 8
                }
            }
        }
        .padding(10) // 📐 Réduit de padding à 10
        .background(Color(hex: "56c228").opacity(0.1))
        .cornerRadius(12) // 📐 Réduit de 16 à 12
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(hex: "5ee852").opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Vues de support compactes

struct CompactQuestionRowView: View {
    let question: QuestionItem
    let response: Bool?
    let onEdit: () -> Void
    @ObservedObject var questionnaireManager: QuestionnaireManager
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) { // 📐 Réduit de 4 à 2
                Text(question.text)
                    .font(.caption) // 📐 Réduit de .subheadline à .caption
                    .fontWeight(.medium)
                    .foregroundColor(Color(hex: "f0fff0"))
                
                Text(question.description)
                    .font(.caption2) // 📐 Réduit de .caption à .caption2
                    .foregroundColor(Color(hex: "f0fff0").opacity(0.7))
                    .lineLimit(2)
            }
            
            Spacer()
            
            // Bouton toggle direct compact
            if let response = response {
                Button(action: {
                    // Toggle direct : OUI → NON ou NON → OUI
                    questionnaireManager.saveResponse(questionId: question.id, response: !response)
                }) {
                    Text(response ? "OUI" : "NON")
                        .font(.caption2) // 📐 Réduit de .caption à .caption2
                        .fontWeight(.bold)
                        .foregroundColor(response ? Color(hex: "5ee852") : .red)
                        .padding(.horizontal, 8) // 📐 Réduit de 12 à 8
                        .padding(.vertical, 4)   // 📐 Réduit de 6 à 4
                        .background((response ? Color(hex: "5ee852") : Color.red).opacity(0.2))
                        .cornerRadius(6) // 📐 Réduit de 8 à 6
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(response ? Color(hex: "5ee852") : Color.red, lineWidth: 1)
                        )
                }
            } else {
                // Si pas de réponse, permettre de choisir compact
                HStack(spacing: 6) { // 📐 Réduit de 8 à 6
                    Button("NON") {
                        questionnaireManager.saveResponse(questionId: question.id, response: false)
                    }
                    .font(.caption2) // 📐 Réduit de .caption à .caption2
                    .fontWeight(.bold)
                    .foregroundColor(.red)
                    .padding(.horizontal, 6) // 📐 Réduit de 8 à 6
                    .padding(.vertical, 3)   // 📐 Réduit de 4 à 3
                    .background(Color.red.opacity(0.2))
                    .cornerRadius(4) // 📐 Réduit de 6 à 4
                    
                    Button("OUI") {
                        questionnaireManager.saveResponse(questionId: question.id, response: true)
                    }
                    .font(.caption2) // 📐 Réduit de .caption à .caption2
                    .fontWeight(.bold)
                    .foregroundColor(Color(hex: "5ee852"))
                    .padding(.horizontal, 6) // 📐 Réduit de 8 à 6
                    .padding(.vertical, 3)   // 📐 Réduit de 4 à 3
                    .background(Color(hex: "5ee852").opacity(0.2))
                    .cornerRadius(4) // 📐 Réduit de 6 à 4
                }
            }
        }
        .padding(8) // 📐 Réduit de padding à 8
        .background(Color(hex: "0a1f0a").opacity(0.3))
        .cornerRadius(8) // 📐 Réduit de 10 à 8
    }
}

// MARK: - Preview

struct ParametersView_Previews: PreviewProvider {
    static var previews: some View {
        // Preview avec un CameraManager simulé
        ParametersView(isPresented: .constant(true), cameraManager: CameraManager())
    }
}
