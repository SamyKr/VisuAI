//
//  ParametersView.swift
//  Interface de Configuration et Paramètres Avancés
//
//  Vue SwiftUI pour la gestion des paramètres utilisateur et de la configuration
//  des objets dangereux. Permet la modification du profil utilisateur et la
//  sélection des objets considérés comme dangereux pour les alertes vocales.
//
//  🎯 MODIFIÉ: Système d'objets dangereux remplace les classes de détection
//
//  Fonctionnalités:
//  - Gestion du profil utilisateur (questionnaire d'accessibilité simplifié)
//  - Configuration des objets dangereux (12 par défaut)
//  - Paramètre de distance critique modifiable (0.5m - 10m)
//  - Synchronisation DIRECTE avec CameraManager
//  - Interface de recherche et filtrage des objets
//  - Sauvegarde persistante des préférences utilisateur
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

// 🎯 NOUVEAU: DangerousObjectsManager pour gérer les objets considérés comme dangereux
class DangerousObjectsManager: ObservableObject {
    @Published var dangerousObjects: Set<String> = []
    
    // 🔗 Référence directe au CameraManager
    private weak var cameraManager: CameraManager?
    
    // Liste par défaut des objets dangereux
    private let defaultDangerousTypes = Set([
        "person", "cyclist", "motorcyclist",
        "car", "truck", "bus", "motorcycle", "bicycle",
        "pole", "traffic cone", "barrier", "temporary barrier"
    ])
    
    // Accès aux classes détectées via le CameraManager
    var availableClasses: [String] {
        return cameraManager?.getAvailableClasses().sorted() ?? ObjectDetectionManager.getAllModelClasses().sorted()
    }
    
    private let userDefaults = UserDefaults.standard
    private let dangerousObjectsKey = "dangerous_objects_list"
    
    init(cameraManager: CameraManager) {
        self.cameraManager = cameraManager
        loadDangerousObjects()
        
        // Si aucune configuration sauvegardée, utiliser les valeurs par défaut
        if dangerousObjects.isEmpty {
            dangerousObjects = defaultDangerousTypes
            saveDangerousObjects()
        }
        
        synchronizeWithVoiceManager()
    }
    
    // 🔗 Synchronisation avec le système de synthèse vocale
    private func synchronizeWithVoiceManager() {
        // Cette méthode sera appelée pour synchroniser avec le VoiceSynthesisManager
        // via le CameraManager
        cameraManager?.updateDangerousObjects(dangerousObjects)
        
        // 🐛 DEBUG: Vérifier la synchronisation
        print("🔧 DEBUG Synchronisation:")
        print("   - Objets dangereux actuels: \(Array(dangerousObjects).sorted())")
        print("   - CameraManager connecté: \(cameraManager != nil)")
    }
    
    func toggleDangerousObject(_ objectType: String) {
        if dangerousObjects.contains(objectType) {
            dangerousObjects.remove(objectType)
        } else {
            dangerousObjects.insert(objectType)
        }
        saveDangerousObjects()
        synchronizeWithVoiceManager()
    }
    
    func isDangerous(_ objectType: String) -> Bool {
        return dangerousObjects.contains(objectType.lowercased())
    }
    
    private func saveDangerousObjects() {
        let objectsArray = Array(dangerousObjects)
        userDefaults.set(objectsArray, forKey: dangerousObjectsKey)
    }
    
    private func loadDangerousObjects() {
        if let savedObjects = userDefaults.array(forKey: dangerousObjectsKey) as? [String] {
            dangerousObjects = Set(savedObjects)
        }
    }
    
    func resetToDefaults() {
        dangerousObjects = defaultDangerousTypes
        saveDangerousObjects()
        synchronizeWithVoiceManager()
    }
    
    func isModelLoaded() -> Bool {
        return cameraManager?.getAvailableClasses().count ?? 0 > 0
    }
    
    // Obtenir les objets dangereux actuels
    func getDangerousObjectsList() -> [String] {
        return Array(dangerousObjects).sorted()
    }
    
    // Obtenir les objets non-dangereux disponibles
    func getNonDangerousObjects() -> [String] {
        let allClasses = Set(availableClasses.map { $0.lowercased() })
        let nonDangerous = allClasses.subtracting(dangerousObjects)
        return Array(nonDangerous).sorted()
    }
}

struct ParametersView: View {
    @Binding var isPresented: Bool
    
    // 🎯 MODIFICATION PRINCIPALE: Accepter le CameraManager de DetectionView
    let cameraManager: CameraManager
    
    @StateObject private var questionnaireManager = QuestionnaireManager()
    
    // 🔗 MODIFICATION: DangerousObjectsManager au lieu de DetectionClassesManager
    @StateObject private var dangerousObjectsManager: DangerousObjectsManager
    
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
        
        // Initialiser DangerousObjectsManager avec le CameraManager
        self._dangerousObjectsManager = StateObject(wrappedValue: DangerousObjectsManager(cameraManager: cameraManager))
        
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
                    VStack(spacing: 24) {
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
                        
                        // Section Configuration Objets Dangereux
                        DangerousSectionView(
                            dangerousObjectsManager: dangerousObjectsManager,
                            cameraManager: cameraManager
                        )
                    }
                    .padding()
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
        dangerousObjectsManager.resetToDefaults()
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

// MARK: - 🎯 NOUVELLE SECTION: Paramètres de Sécurité

struct SafetySectionView: View {
    @ObservedObject var safetyParametersManager: SafetyParametersManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // En-tête de section
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "shield.checkerboard")
                        .font(.title2)
                        .foregroundColor(.orange)
                    
                    Text("Paramètres de Sécurité")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(Color(hex: "f0fff0"))
                    
                    Spacer()
                }
                
                Text("Configurez les alertes de danger immédiat")
                    .font(.caption)
                    .foregroundColor(.orange.opacity(0.8))
            }
            
            // Section Distance Critique
            VStack(alignment: .leading, spacing: 16) {
                // Titre et valeur actuelle
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Distance d'alerte critique")
                            .font(.headline)
                            .foregroundColor(Color(hex: "f0fff0"))
                        
                        Text("Objets à moins de cette distance déclenchent une alerte vocale")
                            .font(.caption)
                            .foregroundColor(Color(hex: "f0fff0").opacity(0.7))
                    }
                    
                    Spacer()
                    
                    // Valeur actuelle avec badge
                    VStack(spacing: 2) {
                        Text("\(String(format: "%.1f", safetyParametersManager.criticalDistance)) m")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.orange)
                        
                        Text(safetyParametersManager.getDistanceDescription())
                            .font(.caption2)
                            .foregroundColor(.orange.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.orange.opacity(0.15))
                    .cornerRadius(8)
                }
                
                // Slider avec marqueurs
                VStack(spacing: 8) {
                    // Slider principal
                    HStack {
                        Text("\(String(format: "%.1f", safetyParametersManager.minDistance))m")
                            .font(.caption2)
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
                            .font(.caption2)
                            .foregroundColor(Color(hex: "f0fff0").opacity(0.6))
                    }
                    
                    // Marqueurs de valeurs prédéfinies
                    HStack {
                        ForEach([0.5, 1.0, 2.0, 3.0, 5.0, 10.0], id: \.self) { value in
                            Button(action: {
                                safetyParametersManager.setCriticalDistance(Float(value))
                                // Feedback haptique
                                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                impactFeedback.impactOccurred()
                            }) {
                                Text("\(String(format: value.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f", value))m")
                                    .font(.caption2)
                                    .fontWeight(abs(safetyParametersManager.criticalDistance - Float(value)) < 0.1 ? .bold : .regular)
                                    .foregroundColor(abs(safetyParametersManager.criticalDistance - Float(value)) < 0.1 ? .orange : Color(hex: "f0fff0").opacity(0.6))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(abs(safetyParametersManager.criticalDistance - Float(value)) < 0.1 ? .orange.opacity(0.2) : .clear)
                                    .cornerRadius(6)
                            }
                        }
                    }
                }
                
                // Bouton de réinitialisation
                HStack {
                    Spacer()
                    
                    Button(action: {
                        safetyParametersManager.resetToDefault()
                        // Feedback haptique
                        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                        impactFeedback.impactOccurred()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Réinitialiser (2.0m)")
                        }
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.orange.opacity(0.15))
                        .cornerRadius(8)
                    }
                }
                
                // Info explicative
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .font(.caption)
                            .foregroundColor(.blue)
                        
                        Text("Comment ça fonctionne :")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(Color(hex: "f0fff0"))
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("• Objets détectés à moins de \(String(format: "%.1f", safetyParametersManager.criticalDistance))m → Alerte vocale immédiate")
                        Text("• Objets plus éloignés → Aucune alerte (mode silencieux)")
                        Text("• Évite le spam avec intervalle minimum entre alertes")
                    }
                    .font(.caption2)
                    .foregroundColor(Color(hex: "f0fff0").opacity(0.7))
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(.orange.opacity(0.05))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.orange.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - 🎯 NOUVELLE SECTION: Configuration Objets Dangereux

struct DangerousSectionView: View {
    @ObservedObject var dangerousObjectsManager: DangerousObjectsManager
    let cameraManager: CameraManager
    @State private var searchText = ""
    @State private var showingAllObjects = false
    
    var filteredDangerousObjects: [String] {
        let dangerous = dangerousObjectsManager.getDangerousObjectsList()
        if searchText.isEmpty {
            return dangerous
        } else {
            return dangerous.filter { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    var filteredNonDangerousObjects: [String] {
        let nonDangerous = dangerousObjectsManager.getNonDangerousObjects()
        if searchText.isEmpty {
            return nonDangerous
        } else {
            return nonDangerous.filter { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // En-tête de section
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title2)
                        .foregroundColor(.red)
                    
                    Text("Objets Dangereux")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(Color(hex: "f0fff0"))
                    
                    Spacer()
                }
                
                Text("Configurez quels objets déclenchent des alertes vocales")
                    .font(.caption)
                    .foregroundColor(.red.opacity(0.8))
                
                // Statut du modèle
                HStack {
                    Circle()
                        .fill(dangerousObjectsManager.isModelLoaded() ? Color(hex: "5ee852") : .orange)
                        .frame(width: 8, height: 8)
                    
                    Text(dangerousObjectsManager.isModelLoaded() ?
                         "Modèle chargé (\(dangerousObjectsManager.availableClasses.count) types d'objets)" :
                         "Chargement du modèle...")
                        .font(.caption)
                        .foregroundColor(Color(hex: "f0fff0").opacity(0.8))
                }
            }
            
            // Statistiques
            HStack {
                Text("\(dangerousObjectsManager.dangerousObjects.count) objets considérés comme dangereux")
                    .font(.subheadline)
                    .foregroundColor(.red)
                
                Spacer()
                
                Button("Réinitialiser") {
                    dangerousObjectsManager.resetToDefaults()
                    // Feedback haptique
                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                    impactFeedback.impactOccurred()
                }
                .font(.caption)
                .foregroundColor(.red)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.red.opacity(0.2))
                .cornerRadius(8)
            }
            
            // Barre de recherche
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Color(hex: "f0fff0").opacity(0.6))
                
                TextField("Rechercher un type d'objet...", text: $searchText)
                    .foregroundColor(Color(hex: "f0fff0"))
                    .textFieldStyle(PlainTextFieldStyle())
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Color(hex: "f0fff0").opacity(0.6))
                    }
                }
            }
            .padding()
            .background(Color(hex: "0a1f0a").opacity(0.5))
            .cornerRadius(10)
            
            // Toggle pour afficher tous les objets ou seulement les dangereux
            Toggle("Afficher tous les objets détectables", isOn: $showingAllObjects)
                .foregroundColor(Color(hex: "f0fff0"))
                .toggleStyle(SwitchToggleStyle(tint: Color(hex: "5ee852")))
            
            // Liste des objets dangereux
            VStack(alignment: .leading, spacing: 8) {
                Text("🚨 Objets Dangereux (déclenchent des alertes)")
                    .font(.headline)
                    .foregroundColor(.red)
                
                if filteredDangerousObjects.isEmpty {
                    Text("Aucun objet dangereux trouvé avec '\(searchText)'")
                        .font(.caption)
                        .foregroundColor(Color(hex: "f0fff0").opacity(0.6))
                        .padding()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(filteredDangerousObjects, id: \.self) { objectType in
                                DangerousObjectRow(
                                    objectType: objectType,
                                    isDangerous: true,
                                    onToggle: {
                                        dangerousObjectsManager.toggleDangerousObject(objectType)
                                        cameraManager.playSelectionFeedback()
                                    }
                                )
                            }
                        }
                    }
                    .frame(maxHeight: showingAllObjects ? 200 : 300)
                }
            }
            
            // Liste des objets non-dangereux (si toggle activé)
            if showingAllObjects {
                VStack(alignment: .leading, spacing: 8) {
                    Text("✅ Objets Non-Dangereux (détectés mais sans alerte)")
                        .font(.headline)
                        .foregroundColor(Color(hex: "5ee852"))
                    
                    if filteredNonDangerousObjects.isEmpty {
                        Text("Tous les objets sont considérés comme dangereux")
                            .font(.caption)
                            .foregroundColor(Color(hex: "f0fff0").opacity(0.6))
                            .padding()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 6) {
                                ForEach(filteredNonDangerousObjects, id: \.self) { objectType in
                                    DangerousObjectRow(
                                        objectType: objectType,
                                        isDangerous: false,
                                        onToggle: {
                                            dangerousObjectsManager.toggleDangerousObject(objectType)
                                            cameraManager.playSelectionFeedback()
                                        }
                                    )
                                }
                            }
                        }
                        .frame(maxHeight: 200)
                    }
                }
            }
            
            // Info explicative
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .font(.caption)
                        .foregroundColor(.blue)
                    
                    Text("Principe de fonctionnement :")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(Color(hex: "f0fff0"))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("• Objets dangereux = alertes vocales si distance critique atteinte")
                    Text("• Objets non-dangereux = détectés mais aucune alerte")
                    Text("• Tous les objets restent visibles à l'écran")
                }
                .font(.caption2)
                .foregroundColor(Color(hex: "f0fff0").opacity(0.7))
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
        }
        .padding()
        .background(.red.opacity(0.05))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.red.opacity(0.3), lineWidth: 1)
        )
    }
}

struct DangerousObjectRow: View {
    let objectType: String
    let isDangerous: Bool
    let onToggle: () -> Void
    
    var body: some View {
        HStack {
            // Icône représentative
            Image(systemName: getIconForObject(objectType))
                .font(.title3)
                .foregroundColor(isDangerous ? .red : Color(hex: "5ee852"))
                .frame(width: 24, height: 24)
            
            // Nom de l'objet
            Text(objectType.replacingOccurrences(of: "_", with: " ").capitalized)
                .font(.subheadline)
                .foregroundColor(Color(hex: "f0fff0"))
            
            Spacer()
            
            // État textuel
            Text(isDangerous ? "DANGEREUX" : "SANS RISQUE")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(isDangerous ? .red : Color(hex: "5ee852"))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background((isDangerous ? Color.red : Color(hex: "5ee852")).opacity(0.2))
                .cornerRadius(6)
            
            // Toggle
            Toggle("", isOn: Binding(
                get: { isDangerous },
                set: { _ in onToggle() }
            ))
            .toggleStyle(SwitchToggleStyle(tint: .red))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(isDangerous ? Color.red.opacity(0.1) : Color(hex: "5ee852").opacity(0.05))
        .cornerRadius(10)
    }
    
    private func getIconForObject(_ objectType: String) -> String {
        switch objectType.lowercased() {
        case "person": return "person.fill"
        case "cyclist": return "figure.outdoor.cycle"
        case "motorcyclist": return "figure.motorcycling"
        case "car", "truck", "bus": return "car.fill"
        case "bicycle": return "bicycle"
        case "motorcycle": return "bicycle"
        case "traffic light", "traffic_light": return "lightbulb.fill"
        case "traffic sign", "traffic_sign": return "stop.fill"
        case "traffic cone": return "cone.fill"
        case "pole": return "cylinder.fill"
        case "barrier", "temporary barrier", "temporary_barrier": return "rectangle.fill"
        case "chair", "couch": return "chair.fill"
        case "bottle", "cup": return "cup.and.saucer.fill"
        case "book": return "book.fill"
        case "cell phone", "laptop": return "iphone"
        case "dog", "cat", "animals": return "pawprint.fill"
        case "building": return "building.2.fill"
        case "vegetation": return "leaf.fill"
        case "water": return "drop.fill"
        case "terrain", "ground": return "mountain.2.fill"
        case "road", "sidewalk": return "road.lanes"
        case "wall", "fence": return "rectangle.fill"
        default: return "questionmark.circle.fill"
        }
    }
}

// MARK: - Section Profil Utilisateur

struct ProfileSectionView: View {
    @ObservedObject var questionnaireManager: QuestionnaireManager
    let questions: [QuestionItem]
    @Binding var showingDeleteConfirmation: Bool
    @Binding var showingExitConfirmation: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // En-tête de section
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "person.circle.fill")
                        .font(.title2)
                        .foregroundColor(Color(hex: "5ee852"))
                    
                    Text("Profil Utilisateur")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(Color(hex: "f0fff0"))
                    
                    Spacer()
                }
                
                Text("Modifiez vos réponses ou supprimez votre profil")
                    .font(.caption)
                    .foregroundColor(Color(hex: "f0fff0").opacity(0.7))
            }
            
            // 🎯 NOUVEAU: Résumé visuel des configurations actuelles
            if questionnaireManager.responses.count > 0 {
                VStack(spacing: 8) {
                    Text("Configuration actuelle :")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(Color(hex: "f0fff0"))
                    
                    HStack(spacing: 16) {
                        // Alertes vocales
                        HStack(spacing: 6) {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.caption)
                                .foregroundColor(questionnaireManager.responses[1] == true ? Color(hex: "5ee852") : .red)
                            Text("Vocal")
                                .font(.caption2)
                                .foregroundColor(Color(hex: "f0fff0").opacity(0.8))
                        }
                        
                        // Vibrations
                        HStack(spacing: 6) {
                            Image(systemName: "iphone.radiowaves.left.and.right")
                                .font(.caption)
                                .foregroundColor(questionnaireManager.responses[2] == true ? .orange : .red)
                            Text("Vibrations")
                                .font(.caption2)
                                .foregroundColor(Color(hex: "f0fff0").opacity(0.8))
                        }
                        
                        // Communication
                        HStack(spacing: 6) {
                            Image(systemName: "mic.fill")
                                .font(.caption)
                                .foregroundColor(questionnaireManager.responses[3] == true ? .blue : .red)
                            Text("Micro")
                                .font(.caption2)
                                .foregroundColor(Color(hex: "f0fff0").opacity(0.8))
                        }
                        
                        Spacer()
                    }
                }
                .padding()
                .background(Color(hex: "0a1f0a").opacity(0.4))
                .cornerRadius(8)
            }
            
            // Liste des questions modifiables
            VStack(spacing: 12) {
                ForEach(questions, id: \.id) { question in
                    QuestionRowView(
                        question: question,
                        response: questionnaireManager.responses[question.id],
                        onEdit: { }, // Plus utilisé mais gardé pour compatibilité
                        questionnaireManager: questionnaireManager
                    )
                }
            }
            
            // Actions du profil
            VStack(spacing: 12) {
                // Bouton Supprimer Profil
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
                    .padding()
                    .background(Color.red.opacity(0.8))
                    .cornerRadius(12)
                }
                
                // Bouton Fermer Application
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
                    .padding()
                    .background(Color.gray.opacity(0.6))
                    .cornerRadius(12)
                }
            }
        }
        .padding()
        .background(Color(hex: "56c228").opacity(0.1))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(hex: "5ee852").opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Vues de support

struct QuestionRowView: View {
    let question: QuestionItem
    let response: Bool?
    let onEdit: () -> Void
    @ObservedObject var questionnaireManager: QuestionnaireManager
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(question.text)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(Color(hex: "f0fff0"))
                
                Text(question.description)
                    .font(.caption)
                    .foregroundColor(Color(hex: "f0fff0").opacity(0.7))
                    .lineLimit(2)
            }
            
            Spacer()
            
            // Bouton toggle direct
            if let response = response {
                Button(action: {
                    // Toggle direct : OUI → NON ou NON → OUI
                    questionnaireManager.saveResponse(questionId: question.id, response: !response)
                }) {
                    Text(response ? "OUI" : "NON")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(response ? Color(hex: "5ee852") : .red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background((response ? Color(hex: "5ee852") : Color.red).opacity(0.2))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(response ? Color(hex: "5ee852") : Color.red, lineWidth: 1)
                        )
                }
            } else {
                // Si pas de réponse, permettre de choisir
                HStack(spacing: 8) {
                    Button("NON") {
                        questionnaireManager.saveResponse(questionId: question.id, response: false)
                    }
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.2))
                    .cornerRadius(6)
                    
                    Button("OUI") {
                        questionnaireManager.saveResponse(questionId: question.id, response: true)
                    }
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(Color(hex: "5ee852"))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(hex: "5ee852").opacity(0.2))
                    .cornerRadius(6)
                }
            }
        }
        .padding()
        .background(Color(hex: "0a1f0a").opacity(0.3))
        .cornerRadius(10)
    }
}


// MARK: - Preview

struct ParametersView_Previews: PreviewProvider {
    static var previews: some View {
        // Preview avec un CameraManager simulé
        ParametersView(isPresented: .constant(true), cameraManager: CameraManager())
    }
}
