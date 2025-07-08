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
//  - Synchronisation avec ObjectDetectionManager
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

// Gestionnaire des classes détectables
class DetectionClassesManager: ObservableObject {
    @Published var enabledClasses: Set<String> = []
    
    // MODIFIÉ: Utilisation directe de la liste statique des classes du modèle
    var availableClasses: [String] {
        return ObjectDetectionManager.getAllModelClasses().sorted()
    }
    
    private let userDefaults = UserDefaults.standard
    private let enabledClassesKey = "detection_enabled_classes"
    
    // AJOUTÉ: Référence au ObjectDetectionManager pour synchronisation
    private var objectDetectionManager: ObjectDetectionManager?
    
    init() {
        loadEnabledClasses()
        // MODIFIÉ: Activer toutes les classes SAUF celles ignorées par défaut
        if enabledClasses.isEmpty {
            let allClasses = Set(ObjectDetectionManager.getAllModelClasses())
            let defaultIgnoredClasses = Set(["building", "vegetation", "terrain", "water"])
            enabledClasses = allClasses.subtracting(defaultIgnoredClasses)
            saveEnabledClasses()
            print("✅ Classes par défaut: \(enabledClasses.count)/\(allClasses.count) activées")
        }
    }
    
    // AJOUTÉ: Méthode pour connecter au ObjectDetectionManager
    func connectToObjectDetectionManager(_ manager: ObjectDetectionManager) {
        self.objectDetectionManager = manager
        
        // Synchroniser l'état initial :
        // - Classes désactivées → ajoutées aux ignoredClasses
        // - Classes activées → retirées des ignoredClasses
        let allClasses = Set(availableClasses)
        let disabledClasses = allClasses.subtracting(enabledClasses)
        
        // Ajouter toutes les classes désactivées aux classes ignorées
        for className in disabledClasses {
            manager.addIgnoredClass(className)
        }
        
        // Retirer toutes les classes activées des classes ignorées
        for className in enabledClasses {
            manager.removeIgnoredClass(className)
        }
        
        print("✅ Synchronisation initiale: \(enabledClasses.count) classes activées, \(disabledClasses.count) classes ignorées")
    }
    
    func toggleClass(_ className: String) {
        if enabledClasses.contains(className) {
            // Désactiver la classe → l'ajouter aux classes ignorées
            enabledClasses.remove(className)
            objectDetectionManager?.addIgnoredClass(className)
        } else {
            // Activer la classe → la retirer des classes ignorées
            enabledClasses.insert(className)
            objectDetectionManager?.removeIgnoredClass(className)
        }
        saveEnabledClasses()
        
        print("✅ Classe '\(className)' \(enabledClasses.contains(className) ? "activée" : "désactivée")")
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
        // MODIFIÉ: Réinitialiser en activant toutes les classes SAUF celles ignorées par défaut
        let allClasses = Set(availableClasses)
        let defaultIgnoredClasses = Set(["building", "vegetation", "terrain", "water"])
        enabledClasses = allClasses.subtracting(defaultIgnoredClasses)
        saveEnabledClasses()
        
        // Synchroniser avec ObjectDetectionManager en appliquant la logique ignoredClasses
        if let manager = objectDetectionManager {
            // Réinitialiser les classes ignorées aux valeurs par défaut
            manager.clearIgnoredClasses()
            
            // Ajouter seulement les classes par défaut ignorées
            for className in defaultIgnoredClasses {
                manager.addIgnoredClass(className)
            }
            
            print("✅ Réinitialisation: \(enabledClasses.count)/\(allClasses.count) classes activées par défaut")
        }
    }
    
    // AJOUTÉ: Méthode pour vérifier si le modèle est chargé
    func isModelLoaded() -> Bool {
        return objectDetectionManager?.isModelLoaded() ?? false
    }
}

struct ParametersView: View {
    @Binding var isPresented: Bool
    @StateObject private var questionnaireManager = QuestionnaireManager()
    @StateObject private var detectionClassesManager = DetectionClassesManager()
    
    // AJOUTÉ: Référence au ObjectDetectionManager
    @StateObject private var objectDetectionManager = ObjectDetectionManager()
    
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
                        
                        // Section Paramètres Avancés
                        AdvancedSectionView(
                            detectionClassesManager: detectionClassesManager
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
        .onAppear {
            // AJOUTÉ: Connecter les managers lors de l'apparition de la vue
            detectionClassesManager.connectToObjectDetectionManager(objectDetectionManager)
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
                
                Text("Choisissez les objets à détecter")
                    .font(.caption)
                    .foregroundColor(Color(hex: "f0fff0").opacity(0.7))
                
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
                            onToggle: { detectionClassesManager.toggleClass(className) }
                        )
                    }
                }
            }
            .frame(maxHeight: 300)
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
            
            // Toggle
            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { _ in onToggle() }
            ))
            .toggleStyle(SwitchToggleStyle(tint: Color(hex: "5ee852")))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(isEnabled ? Color(hex: "5ee852").opacity(0.1) : Color.clear)
        .cornerRadius(10)
    }
    
    private func getIconForClass(_ className: String) -> String {
        switch className.lowercased() {
        case "person": return "person.fill"
        case "car", "truck", "bus": return "car.fill"
        case "bicycle": return "bicycle"
        case "motorcycle": return "bicycle"
        case "traffic light": return "lightbulb.fill"
        case "stop sign": return "stop.fill"
        case "chair", "couch": return "chair.fill"
        case "bottle", "cup": return "cup.and.saucer.fill"
        case "book": return "book.fill"
        case "cell phone", "laptop": return "iphone"
        case "dog", "cat": return "pawprint.fill"
        default: return "cube.fill"
        }
    }
}

// MARK: - Modification d'une question

struct QuestionEditItem: Identifiable {
    let id = UUID()
    let question: QuestionItem
    let currentResponse: Bool?
}

struct QuestionEditView: View {
    let question: QuestionItem
    let currentResponse: Bool?
    @ObservedObject var questionnaireManager: QuestionnaireManager
    @Binding var isPresented: Bool
    
    @State private var selectedResponse: Bool?
    
    var body: some View {
        NavigationView {
            ZStack {
                // Fond cohérent
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
                
                VStack(spacing: 40) {
                    Spacer()
                    
                    // Question
                    VStack(spacing: 20) {
                        Text("Question \(question.id)")
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundColor(Color(hex: "5ee852"))
                        
                        Text(question.description)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(Color(hex: "f0fff0"))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                    
                    // Boutons de réponse
                    HStack(spacing: 20) {
                        // NON
                        Button(action: {
                            selectedResponse = false
                        }) {
                            VStack(spacing: 12) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 50))
                                    .foregroundColor(.red)
                                
                                Text("NON")
                                    .font(.title)
                                    .fontWeight(.bold)
                                    .foregroundColor(.red)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(30)
                            .background(
                                (selectedResponse == false) ?
                                Color.red.opacity(0.3) : Color.red.opacity(0.1)
                            )
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(
                                        (selectedResponse == false) ? Color.red : Color.red.opacity(0.3),
                                        lineWidth: (selectedResponse == false) ? 3 : 1
                                    )
                            )
                        }
                        
                        // OUI
                        Button(action: {
                            selectedResponse = true
                        }) {
                            VStack(spacing: 12) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 50))
                                    .foregroundColor(Color(hex: "5ee852"))
                                
                                Text("OUI")
                                    .font(.title)
                                    .fontWeight(.bold)
                                    .foregroundColor(Color(hex: "5ee852"))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(30)
                            .background(
                                (selectedResponse == true) ?
                                Color(hex: "5ee852").opacity(0.3) : Color(hex: "5ee852").opacity(0.1)
                            )
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(
                                        (selectedResponse == true) ? Color(hex: "5ee852") : Color(hex: "5ee852").opacity(0.3),
                                        lineWidth: (selectedResponse == true) ? 3 : 1
                                    )
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    Spacer()
                    
                    // Bouton Sauvegarder
                    if selectedResponse != nil {
                        Button(action: {
                            if let response = selectedResponse {
                                questionnaireManager.saveResponse(questionId: question.id, response: response)
                                isPresented = false
                            }
                        }) {
                            Text("Sauvegarder")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(Color(hex: "0a1f0a"))
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(hex: "5ee852"))
                                .cornerRadius(12)
                        }
                        .padding(.horizontal, 40)
                        .padding(.bottom, 40)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .navigationTitle("Modifier la réponse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Annuler") {
                        isPresented = false
                    }
                    .foregroundColor(Color(hex: "5ee852"))
                }
            }
        }
        .onAppear {
            selectedResponse = currentResponse
        }
    }
}

// MARK: - Preview

struct ParametersView_Previews: PreviewProvider {
    static var previews: some View {
        ParametersView(isPresented: .constant(true))
    }
}
