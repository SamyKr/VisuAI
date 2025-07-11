//
//  ParametersView.swift
//  Interface de Configuration et Paramètres Avancés
//
//  Vue SwiftUI pour la gestion des paramètres utilisateur et de la configuration
//  de détection d'objets. Permet la modification du profil utilisateur et la
//  sélection des classes d'objets à détecter.
//
//  Fonctionnalités:
//  - Gestion du profil utilisateur (questionnaire d'accessibilité)
//  - Configuration des 49 classes de détection (45 activées par défaut)
//  - NOUVEAU: Paramètre de distance critique modifiable (0.5m - 10m)
//  - Synchronisation DIRECTE avec CameraManager (pas de double ObjectDetectionManager)
//  - Interface de recherche et filtrage des classes
//  - Sauvegarde persistante des préférences utilisateur
//  - Classes ignorées par défaut: building, vegetation, terrain, water
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
        
        print("🔄 INIT SafetyParametersManager: distance chargée = \(criticalDistance)m")
        
    }
    
    func setCriticalDistance(_ distance: Float) {
        let clampedDistance = max(minDistance, min(maxDistance, distance))
        criticalDistance = clampedDistance
        saveCriticalDistance()
        applyCriticalDistance()
        
        print("✅ Distance critique mise à jour: \(String(format: "%.1f", clampedDistance))m")
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
        print("🔄 Distance critique réinitialisée à 2.0m")
    }
    
    func getDistanceDescription() -> String {
        return "Objets détectés à moins de \(String(format: "%.1f", criticalDistance))m"
    }
}

// 🎯 MODIFICATION PRINCIPALE: DetectionClassesManager maintenant utilise le CameraManager directement
class DetectionClassesManager: ObservableObject {
    @Published var enabledClasses: Set<String> = []
    
    // 🔗 Référence directe au CameraManager (pas de copie locale)
    private weak var cameraManager: CameraManager?
    
    // Accès aux classes via le CameraManager
    var availableClasses: [String] {
        return cameraManager?.getAvailableClasses().sorted() ?? ObjectDetectionManager.getAllModelClasses().sorted()
    }
    
    private let userDefaults = UserDefaults.standard
    private let enabledClassesKey = "detection_enabled_classes"
    
    // 🎯 NOUVEAU: Initialisation avec CameraManager
    init(cameraManager: CameraManager) {
        self.cameraManager = cameraManager
        loadEnabledClasses()
        
        // MODIFIÉ: Activer toutes les classes SAUF celles ignorées par défaut
        if enabledClasses.isEmpty {
            let allClasses = Set(ObjectDetectionManager.getAllModelClasses())
            let defaultIgnoredClasses = Set(["building", "vegetation", "terrain", "water"])
            enabledClasses = allClasses.subtracting(defaultIgnoredClasses)
            saveEnabledClasses()
            print("✅ Classes par défaut: \(enabledClasses.count)/\(allClasses.count) activées")
        }
        
        // 🔗 Synchronisation immédiate avec le CameraManager
        synchronizeWithCameraManager()
    }
    
    // 🔗 Synchronisation directe avec CameraManager
    private func synchronizeWithCameraManager() {
        guard let cameraManager = cameraManager else { return }
        
        // Synchroniser l'état initial :
        // - Classes désactivées → ajoutées aux ignoredClasses
        // - Classes activées → retirées des ignoredClasses
        let allClasses = Set(availableClasses)
        let disabledClasses = allClasses.subtracting(enabledClasses)
        
        // Nettoyer d'abord les classes ignorées
        cameraManager.clearIgnoredClasses()
        
        // Ajouter toutes les classes désactivées aux classes ignorées
        for className in disabledClasses {
            cameraManager.addIgnoredClass(className)
        }
        
        print("✅ Synchronisation DIRECTE avec CameraManager: \(enabledClasses.count) classes activées, \(disabledClasses.count) classes ignorées")
    }
    
    func toggleClass(_ className: String) {
        guard let cameraManager = cameraManager else { return }
        
        if enabledClasses.contains(className) {
            // Désactiver la classe → l'ajouter aux classes ignorées du CameraManager
            enabledClasses.remove(className)
            cameraManager.addIgnoredClass(className)
        } else {
            // Activer la classe → la retirer des classes ignorées du CameraManager
            enabledClasses.insert(className)
            cameraManager.removeIgnoredClass(className)
        }
        saveEnabledClasses()
        
        print("✅ Classe '\(className)' \(enabledClasses.contains(className) ? "activée" : "désactivée") - EFFET IMMÉDIAT sur détection")
    }
    
    func isClassEnabled(_ className: String) -> Bool {
        return enabledClasses.contains(className)
    }
    
    private func saveEnabledClasses() {
        let classArray = Array(enabledClasses)
        userDefaults.set(classArray, forKey: enabledClassesKey)
    }
    
    private func loadEnabledClasses() {
        if let savedClasses = userDefaults.array(forKey: enabledClassesKey) as? [String] {
            enabledClasses = Set(savedClasses)
        }
    }
    
    func resetToDefaults() {
        guard let cameraManager = cameraManager else { return }
        
        // MODIFIÉ: Réinitialiser en activant toutes les classes SAUF celles ignorées par défaut
        let allClasses = Set(availableClasses)
        let defaultIgnoredClasses = Set(["building", "vegetation", "terrain", "water"])
        enabledClasses = allClasses.subtracting(defaultIgnoredClasses)
        saveEnabledClasses()
        
        // Synchroniser IMMÉDIATEMENT avec CameraManager
        cameraManager.clearIgnoredClasses()
        
        // Ajouter seulement les classes par défaut ignorées
        for className in defaultIgnoredClasses {
            cameraManager.addIgnoredClass(className)
        }
        
        print("✅ Réinitialisation: \(enabledClasses.count)/\(allClasses.count) classes activées par défaut - EFFET IMMÉDIAT")
    }
    
    // 🔗 Vérifier si le modèle est chargé via CameraManager
    func isModelLoaded() -> Bool {
        return cameraManager?.getAvailableClasses().count ?? 0 > 0
    }
    
    // 🎯 Obtenir les classes actuellement ignorées depuis CameraManager
    func getIgnoredClassesFromCameraManager() -> [String] {
        return cameraManager?.getIgnoredClasses() ?? []
    }
}

struct ParametersView: View {
    @Binding var isPresented: Bool
    
    // 🎯 MODIFICATION PRINCIPALE: Accepter le CameraManager de DetectionView
    let cameraManager: CameraManager
    
    @StateObject private var questionnaireManager = QuestionnaireManager()
    
    // 🔗 MODIFICATION: DetectionClassesManager utilise maintenant le CameraManager passé
    @StateObject private var detectionClassesManager: DetectionClassesManager
    
    // 🎯 NOUVEAU: Gestionnaire des paramètres de sécurité
    @StateObject private var safetyParametersManager: SafetyParametersManager
    
    @State private var showingDeleteConfirmation = false
    @State private var showingExitConfirmation = false
    
    // Questions du questionnaire pour modification
    private let questions = [
        QuestionItem(
            id: 1,
            text: "Applications de navigation",
            description: "Utilisez-vous régulièrement des applications de navigation ?"
        ),
        QuestionItem(
            id: 2,
            text: "Alertes d'obstacles",
            description: "Souhaitez-vous être averti des obstacles à distance ?"
        ),
        QuestionItem(
            id: 3,
            text: "Préférence vocale",
            description: "Préférez-vous les alertes vocales aux vibrations ?"
        ),
        QuestionItem(
            id: 4,
            text: "Transports en commun",
            description: "Utilisez-vous fréquemment les transports en commun ?"
        ),
        QuestionItem(
            id: 5,
            text: "Descriptions détaillées",
            description: "Souhaitez-vous des descriptions détaillées de l'environnement ?"
        )
    ]
    
    // 🎯 NOUVEAU: Custom initializer pour accepter le CameraManager
    init(isPresented: Binding<Bool>, cameraManager: CameraManager) {
        self._isPresented = isPresented
        self.cameraManager = cameraManager
        
        // Initialiser DetectionClassesManager avec le CameraManager
        self._detectionClassesManager = StateObject(wrappedValue: DetectionClassesManager(cameraManager: cameraManager))
        
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
                        
                        // Section Paramètres Avancés
                        AdvancedSectionView(
                            detectionClassesManager: detectionClassesManager,
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
        detectionClassesManager.resetToDefaults()
        safetyParametersManager.resetToDefault()  // 🎯 NOUVEAU: Reset paramètres de sécurité
        
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
            
            // Statut du profil
            HStack {
                Circle()
                    .fill(questionnaireManager.responses.count == 5 ? Color(hex: "5ee852") : .orange)
                    .frame(width: 10, height: 10)
                
                Text("Profil \(questionnaireManager.responses.count == 5 ? "complet" : "incomplet") (\(questionnaireManager.responses.count)/5)")
                    .font(.subheadline)
                    .foregroundColor(Color(hex: "f0fff0"))
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

// MARK: - Section Paramètres Avancés

struct AdvancedSectionView: View {
    @ObservedObject var detectionClassesManager: DetectionClassesManager
    let cameraManager: CameraManager
    @State private var searchText = ""
    
    var filteredClasses: [String] {
        if searchText.isEmpty {
            return detectionClassesManager.availableClasses.sorted()
        } else {
            return detectionClassesManager.availableClasses
                .filter { $0.localizedCaseInsensitiveContains(searchText) }
                .sorted()
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // En-tête de section
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "gear.circle.fill")
                        .font(.title2)
                        .foregroundColor(Color(hex: "56c228"))
                    
                    Text("Paramètres Avancés")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(Color(hex: "f0fff0"))
                    
                    Spacer()
                }
                
                Text("Choisissez les objets à détecter - EFFET IMMÉDIAT")
                    .font(.caption)
                    .foregroundColor(Color(hex: "5ee852"))
                
                // AJOUTÉ: Statut du modèle
                HStack {
                    Circle()
                        .fill(detectionClassesManager.isModelLoaded() ? Color(hex: "5ee852") : .orange)
                        .frame(width: 8, height: 8)
                    
                    Text(detectionClassesManager.isModelLoaded() ?
                         "Modèle chargé (\(detectionClassesManager.availableClasses.count) classes)" :
                         "Chargement du modèle...")
                        .font(.caption)
                        .foregroundColor(Color(hex: "f0fff0").opacity(0.8))
                }
            }
            
            // Statistiques
            HStack {
                Text("\(detectionClassesManager.enabledClasses.count) classes activées")
                    .font(.subheadline)
                    .foregroundColor(Color(hex: "5ee852"))
                
                Spacer()
                
                Button("Réinitialiser") {
                    detectionClassesManager.resetToDefaults()
                }
                .font(.caption)
                .foregroundColor(Color(hex: "56c228"))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(hex: "56c228").opacity(0.2))
                .cornerRadius(8)
            }
            
            // 🔗 AJOUTÉ: Synchronisation en temps réel
            HStack {
                Text("🔗 Lié au CameraManager")
                    .font(.caption2)
                    .foregroundColor(Color(hex: "5ee852"))
                
                Spacer()
                
                let ignoredCount = detectionClassesManager.getIgnoredClassesFromCameraManager().count
                Text("Ignorées: \(ignoredCount)")
                    .font(.caption2)
                    .foregroundColor(.red.opacity(0.8))
            }
            
            // Barre de recherche
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Color(hex: "f0fff0").opacity(0.6))
                
                TextField("Rechercher une classe...", text: $searchText)
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
            
            // Liste des classes avec scroll
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(filteredClasses, id: \.self) { className in
                        ClassToggleRow(
                            className: className,
                            isEnabled: detectionClassesManager.isClassEnabled(className),
                            onToggle: {
                                detectionClassesManager.toggleClass(className)
                                // 🎯 AJOUTÉ: Feedback haptique pour confirmer le changement
                                cameraManager.playSelectionFeedback()
                            }
                        )
                    }
                }
            }
            .frame(maxHeight: 300)
            
            // 🎯 AJOUTÉ: Debug info (optionnel)
            VStack(alignment: .leading, spacing: 4) {
                Text("🔧 Debug:")
                    .font(.caption2)
                    .foregroundColor(.orange)
                
                let ignoredClasses = detectionClassesManager.getIgnoredClassesFromCameraManager()
                if !ignoredClasses.isEmpty {
                    Text("Classes ignorées actuelles: \(ignoredClasses.joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundColor(.red.opacity(0.7))
                        .lineLimit(3)
                } else {
                    Text("Toutes les classes sont activées")
                        .font(.caption2)
                        .foregroundColor(Color(hex: "5ee852").opacity(0.7))
                }
            }
            .padding(.top, 8)
        }
        .padding()
        .background(Color(hex: "0a1f0a").opacity(0.3))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(hex: "56c228").opacity(0.3), lineWidth: 1)
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

struct ClassToggleRow: View {
    let className: String
    let isEnabled: Bool
    let onToggle: () -> Void
    
    var body: some View {
        HStack {
            // Icône représentative (simplifiée)
            Image(systemName: getIconForClass(className))
                .font(.title3)
                .foregroundColor(isEnabled ? Color(hex: "5ee852") : Color(hex: "f0fff0").opacity(0.5))
                .frame(width: 24, height: 24)
            
            // Nom de la classe
            Text(className.replacingOccurrences(of: "_", with: " ").capitalized)
                .font(.subheadline)
                .foregroundColor(Color(hex: "f0fff0"))
            
            Spacer()
            
            // État textuel
            Text(isEnabled ? "ACTIVÉE" : "IGNORÉE")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(isEnabled ? Color(hex: "5ee852") : .red)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background((isEnabled ? Color(hex: "5ee852") : Color.red).opacity(0.2))
                .cornerRadius(6)
            
            // Toggle
            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { _ in onToggle() }
            ))
            .toggleStyle(SwitchToggleStyle(tint: Color(hex: "5ee852")))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(isEnabled ? Color(hex: "5ee852").opacity(0.1) : Color.red.opacity(0.05))
        .cornerRadius(10)
    }
    
    private func getIconForClass(_ className: String) -> String {
        switch className.lowercased() {
        case "person": return "person.fill"
        case "car", "truck", "bus": return "car.fill"
        case "bicycle": return "bicycle"
        case "motorcycle": return "bicycle"
        case "traffic light", "traffic_light": return "lightbulb.fill"
        case "stop sign", "traffic sign", "traffic_sign": return "stop.fill"
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
        case "pole": return "cylinder.fill"
        default: return "cube.fill"
        }
    }
}

// MARK: - Preview

struct ParametersView_Previews: PreviewProvider {
    static var previews: some View {
        // Preview avec un CameraManager simulé
        ParametersView(isPresented: .constant(true), cameraManager: CameraManager())
    }
}

