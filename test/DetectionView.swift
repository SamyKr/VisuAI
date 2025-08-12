//
//  DetectionView.swift
//  VizAI Vision
//
//  ROLE DANS L'ARCHITECTURE:
//  DetectionView est l'écran principal de détection et le coordinateur central de l'application.
//  Il gère tous les composants système et fournit l'interface utilisateur principale pour la détection d'objets en temps réel.
//
//  ORCHESTRATION DES COMPOSANTS:
//  - Coordonne CameraManager, VoiceSynthesisManager, VoiceInteractionManager et HapticManager
//  - Applique automatiquement la configuration utilisateur depuis les réponses du questionnaire au démarrage
//  - Gère le cycle de vie complet des sessions incluant démarrage, arrêt, pause et reprise
//  - Fournit une interface utilisateur adaptative selon les capacités de l'appareil (disponibilité LiDAR, permissions)
//
//  COMPOSANTS INTERFACE UTILISATEUR:
//  - Prévisualisation caméra en temps réel avec overlay de bounding boxes colorées pour les objets détectés
//  - HUD colonne gauche contenant indicateur FPS et boutons de contrôle (paramètres, microphone, volume, vibration, LiDAR)
//  - Contrôles inférieurs avec bouton principal play/pause
//  - Overlay interaction vocale avec indicateurs visuels d'écoute
//  - Leaderboard des objets importants accessible via panneau coulissant
//
//  SYSTEME INTERACTION VOCALE:
//  - Geste appui long (0.8s) n'importe où sur l'écran active le mode question vocale
//  - Gère l'interruption de la synthèse vocale pendant les interactions utilisateur
//  - Fournit un feedback visuel pour l'état d'écoute et la reconnaissance vocale en temps réel
//  - Supporte les questions intelligentes : présence d'objets, comptage, localisation, sécurité de traversée
//
//  GESTION DE LA CONFIGURATION:
//  - Applique automatiquement les réponses du questionnaire au démarrage
//  - Q1 (Alertes vocales): Active/désactive la synthèse vocale pour les objets détectés
//  - Q2 (Vibrations de proximité): Auto-active le LiDAR et le feedback haptique si demandé
//  - Q3 (Communication vocale): Active/désactive le système d'interaction vocale
//  - Synchronise les types d'objets dangereux depuis le stockage UserDefaults
//
//  GESTION DES ETATS:
//  - Gestion complète du cycle de vie des sessions avec gestion des permissions
//  - Prévention de la mise en veille pendant les sessions de détection actives
//  - Pause/reprise intelligente lors de l'accès aux paramètres
//  - Restauration automatique de l'état après interruptions
//
//  FLUX DE DONNEES:
//  ContentView → DetectionView → [CameraManager + Composants UI] → Expérience utilisateur complète

import SwiftUI
import AVFoundation
import Speech

// MARK: - Composant Prévisualisation Caméra

struct CameraPreviewView: UIViewRepresentable {
    let cameraManager: CameraManager
    
    /// Crée la vue UIKit pour prévisualisation caméra
    /// - Parameter context: Contexte SwiftUI
    /// - Returns: UIView configurée avec layer caméra
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: CGRect.zero)
        view.backgroundColor = UIColor.black
        
        let previewLayer = cameraManager.getPreviewLayer()
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)
        
        return view
    }
    
    /// Met à jour la vue lors changements
    /// - Parameters:
    ///   - uiView: Vue à mettre à jour
    ///   - context: Contexte SwiftUI
    func updateUIView(_ uiView: UIView, context: Context) {
        if let previewLayer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            DispatchQueue.main.async {
                previewLayer.frame = uiView.bounds
            }
        }
    }
}

// MARK: - Vue Principale de Détection

struct DetectionView: View {
    
    // MARK: - Managers Système
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var voiceSynthesisManager = VoiceSynthesisManager()
    @StateObject private var voiceInteractionManager = VoiceInteractionManager()
    @StateObject private var questionnaireManager = QuestionnaireManager()
    
    // MARK: - États Interface Utilisateur
    @State private var boundingBoxes: [(rect: CGRect, label: String, confidence: Float, distance: Float?, trackingInfo: (id: Int, color: UIColor, opacity: Double))] = []
    @State private var showingPermissionAlert = false
    @State private var showingSettings = false
    @State private var showingLiDARInfo = false
    
    // MARK: - États Contrôles Utilisateur
    @State private var proximityAlertsEnabled = true
    @State private var voiceEnabled = true
    @State private var voiceInteractionEnabled = true
    @State private var showingVoicePermissionAlert = false
    
    // MARK: - États Leaderboard Objets Importants
    @State private var showingImportantObjects = false
    @State private var importantObjects: [(object: TrackedObject, score: Float)] = []
    @State private var importantObjectsTimer: Timer?
    
    var body: some View {
        ZStack {
            // Prévisualisation caméra en arrière-plan
            CameraPreviewView(cameraManager: cameraManager)
                .onAppear {
                    setupFromQuestionnaire()
                    setupManagers()
                    startImportantObjectsTimer()
                    disableSleep()
                    
                    if cameraManager.hasPermission {
                        cameraManager.startSession()
                    } else {
                        cameraManager.requestPermission()
                    }
                }
                .onReceive(cameraManager.$hasPermission) { hasPermission in
                    if hasPermission {
                        cameraManager.startSession()
                    }
                }
                .onDisappear {
                    cleanupOnDisappear()
                }
            
            // Overlay transparent pour interaction vocale (appui long)
            voiceInteractionOverlay
            
            // Overlay bounding boxes avec informations objets
            boundingBoxesOverlay
            
            // Indicateur écoute interaction vocale
            if voiceInteractionManager.isListening {
                voiceListeningIndicator
            }
            
            // Indicateur discret appui long (si interaction disponible)
            if voiceInteractionEnabled && voiceInteractionManager.isReadyForQuestion() && !voiceInteractionManager.isListening {
                longPressHintIndicator
            }
            
            // Interface utilisateur principale
            mainUserInterface
            
            // Leaderboard objets importants (overlay sliding)
            if showingImportantObjects {
                ImportantObjectsBoard(
                    importantObjects: importantObjects,
                    isVisible: $showingImportantObjects
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .navigationBarBackButtonHidden(false)
        .alert("Permission Caméra", isPresented: $showingPermissionAlert) {
            Button("Paramètres") {
                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsUrl)
                }
            }
            Button("Annuler", role: .cancel) { }
        } message: {
            Text("L'accès à la caméra est nécessaire pour la détection en temps réel.")
        }
        .alert("Permission Microphone", isPresented: $showingVoicePermissionAlert) {
            Button("Paramètres") {
                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsUrl)
                }
            }
            Button("Annuler", role: .cancel) { }
        } message: {
            Text("L'accès au microphone est nécessaire pour l'interaction vocale.")
        }
        .alert("LiDAR Information", isPresented: $showingLiDARInfo) {
            Button("Compris", role: .cancel) { }
        } message: {
            Text(getLiDARInfoMessage())
        }
        .sheet(isPresented: $showingSettings) {
            ParametersView(isPresented: $showingSettings, cameraManager: cameraManager)
        }
        .onChange(of: showingSettings) { isShowing in
            if isShowing {
                freezeDetection()
            } else {
                unfreezeDetection()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showingImportantObjects)
    }
    
    // MARK: - Overlay Interaction Vocale
    
    /// Overlay transparent couvrant tout l'écran pour détecter appui long
    private var voiceInteractionOverlay: some View {
        Color.clear
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.8) {
                handleLongPressForVoiceInteraction()
            }
    }
    
    /// Gère l'appui long pour activation interaction vocale
    private func handleLongPressForVoiceInteraction() {
        // Arrêt immédiat synthèse vocale
        voiceSynthesisManager.stopSpeaking()
        voiceSynthesisManager.interruptForInteraction(reason: "Question utilisateur")
        
        if voiceInteractionEnabled && voiceInteractionManager.isReadyForQuestion() {
            // Délai pour libération audio puis démarrage question
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                voiceInteractionManager.startSingleQuestion()
            }
            cameraManager.playSelectionFeedback()
        } else if !voiceInteractionEnabled {
            voiceSynthesisManager.speak("Interaction vocale désactivée")
        } else if !voiceInteractionManager.interactionEnabled {
            voiceSynthesisManager.speak("Permission microphone requise")
            showingVoicePermissionAlert = true
        } else {
            voiceSynthesisManager.speak("Service vocal occupé, veuillez patienter")
        }
    }
    
    // MARK: - Overlay Bounding Boxes
    
    /// Overlay géométrique pour affichage bounding boxes avec informations
    private var boundingBoxesOverlay: some View {
        GeometryReader { geometry in
            ForEach(boundingBoxes.indices, id: \.self) { index in
                let detection = boundingBoxes[index]
                let rect = detection.rect
                let tracking = detection.trackingInfo
                
                // Rectangle bounding box avec couleur tracking
                ZStack {
                    Rectangle()
                        .stroke(Color(tracking.color).opacity(tracking.opacity), lineWidth: tracking.opacity > 0.5 ? 3 : 2)
                        .background(Color.clear)
                }
                .frame(
                    width: rect.width * geometry.size.width,
                    height: rect.height * geometry.size.height
                )
                .position(
                    x: rect.midX * geometry.size.width,
                    y: (1 - rect.midY) * geometry.size.height
                )
                
                // Labels informations objet
                detectionLabelsView(for: detection, geometry: geometry, rect: rect)
            }
        }
    }
    
    // MARK: - Indicateurs Interface
    
    /// Indicateur visuel écoute interaction vocale
    private var voiceListeningIndicator: some View {
        VStack {
            HStack {
                Spacer()
                VoiceListeningIndicator(
                    isWaitingForQuestion: voiceInteractionManager.isWaitingForQuestion,
                    lastRecognizedText: voiceInteractionManager.lastRecognizedText
                )
                .padding(.top, 160)
                .padding(.trailing)
            }
            Spacer()
        }
    }
    
    /// Indicateur discret pour appui long si interaction disponible
    private var longPressHintIndicator: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "hand.point.up.left.fill")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                    Text("Appui long pour parler")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.6))
                .cornerRadius(8)
                .padding(.trailing)
                .padding(.bottom, 120)
            }
        }
    }
    
    // MARK: - Interface Utilisateur Principale
    
    /// Interface utilisateur avec HUD colonne gauche + contrôles bas + bouton leaderboard
    private var mainUserInterface: some View {
        VStack {
            leftControlsColumnView
            Spacer()
            bottomControlsView
        }
        .overlay(alignment: .topTrailing) {
            // Bouton leaderboard objets importants (top droite)
            VStack {
                HStack {
                    Spacer()
                    ImportantObjectsButton(
                        isVisible: $showingImportantObjects,
                        objectCount: importantObjects.count
                    )
                    .padding(.top, 50)
                    .padding(.trailing)
                }
                Spacer()
            }
        }
    }
    
    // MARK: - HUD Colonne Gauche
    
    /// Colonne contrôles gauche avec FPS + boutons configuration
    private var leftControlsColumnView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 12) {
                // Indicateur FPS en haut
                fpsIndicatorView
                
                // Boutons contrôle verticaux
                VStack(alignment: .leading, spacing: 10) {
                    settingsButtonView
                    microphoneButtonView
                    speakerButtonView
                    
                    if cameraManager.isLiDAREnabled {
                        vibrationButtonView
                    }
                    
                    if cameraManager.lidarAvailable {
                        lidarButtonView
                    }
                }
            }
            .padding(.leading, 16)
            .padding(.top, 50)
            
            Spacer()
        }
    }
    
    // MARK: - Composants Individuels HUD
    
    /// Indicateur FPS avec statut session
    private var fpsIndicatorView: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(cameraManager.isRunning ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            
            Text("\(String(format: "%.0f", cameraManager.currentFPS)) FPS")
                .font(.system(.body, design: .monospaced))
                .fontWeight(.bold)
                .foregroundColor(.white)
                .onTapGesture {
                    if voiceEnabled {
                        let fps = String(format: "%.0f", cameraManager.currentFPS)
                        let status = cameraManager.isRunning ? "en cours" : "arrêté"
                        voiceSynthesisManager.speak("\(fps) images par seconde, statut \(status)")
                    }
                }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.8))
        .cornerRadius(10)
    }
    
    /// Bouton paramètres
    private var settingsButtonView: some View {
        Button(action: {
            showingSettings = true
            cameraManager.playSelectionFeedback()
        }) {
            HStack(spacing: 8) {
                Image(systemName: "gear")
                    .font(.title3)
                    .foregroundColor(.white)
                Text("Paramètres")
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.8))
            .cornerRadius(12)
        }
    }
    
    /// Bouton microphone avec état interaction vocale
    private var microphoneButtonView: some View {
        Button(action: {
            voiceInteractionEnabled.toggle()
            if voiceInteractionEnabled {
                voiceInteractionManager.startContinuousListening()
            } else {
                voiceInteractionManager.stopContinuousListening()
            }
            cameraManager.playSelectionFeedback()
        }) {
            HStack(spacing: 8) {
                Image(systemName: voiceInteractionEnabled ? "mic.fill" : "mic.slash.fill")
                    .font(.title3)
                    .foregroundColor(getInteractionStatusColor())
                Text("Micro")
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(getInteractionStatusColor())
                    .onTapGesture {
                        if voiceEnabled {
                            let status = voiceInteractionEnabled ? "activé" : "désactivé"
                            voiceSynthesisManager.speak("Micro \(status)")
                        }
                    }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.8))
            .cornerRadius(12)
        }
    }
    
    /// Bouton volume/synthèse vocale
    private var speakerButtonView: some View {
        Button(action: {
            voiceEnabled.toggle()
            if !voiceEnabled {
                voiceSynthesisManager.stopSpeaking()
            }
            cameraManager.playSelectionFeedback()
        }) {
            HStack(spacing: 8) {
                Image(systemName: voiceEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.title3)
                    .foregroundColor(voiceEnabled ? .blue : .gray)
                Text("Volume")
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(voiceEnabled ? .blue : .gray)
                    .onTapGesture {
                        if voiceEnabled {
                            let status = voiceEnabled ? "activé" : "désactivé"
                            voiceSynthesisManager.speak("Volume \(status)")
                        }
                    }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.8))
            .cornerRadius(12)
        }
    }
    
    /// Bouton vibrations (si LiDAR activé)
    private var vibrationButtonView: some View {
        Button(action: {
            proximityAlertsEnabled.toggle()
            cameraManager.enableProximityAlerts(proximityAlertsEnabled)
            cameraManager.playSelectionFeedback()
        }) {
            HStack(spacing: 8) {
                Image(systemName: proximityAlertsEnabled ? "iphone.radiowaves.left.and.right" : "iphone.slash")
                    .font(.title3)
                    .foregroundColor(proximityAlertsEnabled ? .orange : .gray)
                Text("Vibration")
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(proximityAlertsEnabled ? .orange : .gray)
                    .onTapGesture {
                        if voiceEnabled {
                            let status = proximityAlertsEnabled ? "activée" : "désactivée"
                            voiceSynthesisManager.speak("Vibration \(status)")
                        }
                    }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.8))
            .cornerRadius(12)
        }
    }
    
    /// Bouton LiDAR (si disponible)
    private var lidarButtonView: some View {
        Button(action: {
            let success = cameraManager.toggleLiDAR()
            if success {
                cameraManager.playSuccessFeedback()
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: cameraManager.isLiDAREnabled ? "location.fill" : "location")
                    .font(.title3)
                    .foregroundColor(cameraManager.isLiDAREnabled ? .blue : .gray)
                Text("LiDAR")
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(cameraManager.isLiDAREnabled ? .blue : .gray)
                    .onTapGesture {
                        if voiceEnabled {
                            let status = cameraManager.isLiDAREnabled ? "activé" : "désactivé"
                            voiceSynthesisManager.speak("LiDAR \(status)")
                        }
                    }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.8))
            .cornerRadius(12)
        }
        .onLongPressGesture {
            showingLiDARInfo = true
        }
    }
    
    // MARK: - Contrôles Bas
    
    /// Bouton principal start/stop centré en bas
    private var bottomControlsView: some View {
        HStack {
            Spacer()
            
            Button(action: {
                if cameraManager.isRunning {
                    cameraManager.stopSession()
                    voiceSynthesisManager.stopSpeaking()
                    voiceInteractionManager.stopContinuousListening()
                    enableSleep()
                } else {
                    if cameraManager.hasPermission {
                        cameraManager.startSession()
                        disableSleep()
                    } else {
                        showingPermissionAlert = true
                    }
                }
            }) {
                Image(systemName: cameraManager.isRunning ? "pause.fill" : "play.fill")
                    .font(.title)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .background(cameraManager.isRunning ? Color.red.opacity(0.8) : Color.green.opacity(0.8))
                    .cornerRadius(16)
            }
            
            Spacer()
        }
        .padding(.bottom, 50)
    }
    
    // MARK: - Configuration depuis Questionnaire
    
    /// Applique automatiquement la configuration depuis les réponses questionnaire
    private func setupFromQuestionnaire() {
        let responses = questionnaireManager.responses
        
        // Q1: Alertes vocales d'objets proches
        if let wantsVoiceAlerts = responses[1] {
            voiceEnabled = wantsVoiceAlerts
        } else {
            voiceEnabled = true // Par défaut activé
        }
        
        // Q2: Vibrations pour proximité
        if let wantsVibrations = responses[2] {
            proximityAlertsEnabled = wantsVibrations
            cameraManager.enableProximityAlerts(wantsVibrations)
            
            // Si vibrations demandées ET LiDAR disponible → activation auto
            if wantsVibrations && cameraManager.lidarAvailable {
                _ = cameraManager.enableLiDAR()
            }
        } else {
            proximityAlertsEnabled = false // Par défaut désactivé
            cameraManager.enableProximityAlerts(false)
        }
        
        // Q3: Communication vocale
        if let wantsCommunication = responses[3] {
            voiceInteractionEnabled = wantsCommunication
            if wantsCommunication {
                voiceInteractionManager.startContinuousListening()
            } else {
                voiceInteractionManager.stopContinuousListening()
            }
        } else {
            voiceInteractionEnabled = true // Par défaut activé
            voiceInteractionManager.startContinuousListening()
        }
        
        // Connection VoiceSynthesisManager au CameraManager
        cameraManager.setVoiceSynthesisManager(voiceSynthesisManager)
        
        // Synchronisation objets dangereux depuis UserDefaults
        let userDefaults = UserDefaults.standard
        if let savedObjects = userDefaults.array(forKey: "dangerous_objects_list") as? [String] {
            let dangerousSet = Set(savedObjects)
            cameraManager.updateDangerousObjects(dangerousSet)
        } else {
            // Valeurs par défaut si rien sauvegardé
            let defaultDangerous: Set<String> = [
                "person", "cyclist", "motorcyclist",
                "car", "truck", "bus", "motorcycle", "bicycle",
                "pole", "traffic cone", "barrier", "temporary barrier"
            ]
            cameraManager.updateDangerousObjects(defaultDangerous)
        }
        
        // Feedback vocal initial après délai
        if voiceEnabled {
            let statusMessage = buildConfigurationMessage()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                voiceSynthesisManager.speak(statusMessage)
            }
        }
    }
    
    /// Construit le message de confirmation configuration
    /// - Returns: Message résumant la configuration appliquée
    private func buildConfigurationMessage() -> String {
        var components: [String] = []
        
        if voiceEnabled {
            components.append("alertes vocales activées")
        }
        
        if proximityAlertsEnabled {
            components.append("vibrations activées")
        }
        
        if voiceInteractionEnabled {
            components.append("communication vocale activée")
        }
        
        if cameraManager.isLiDAREnabled {
            components.append("LiDAR activé")
        }
        
        if components.isEmpty {
            return "Configuration minimale appliquée"
        } else if components.count == 1 {
            return "Configuration: \(components[0])"
        } else {
            let lastComponent = components.removeLast()
            return "Configuration: \(components.joined(separator: ", ")) et \(lastComponent)"
        }
    }
    
    // MARK: - Labels Détections
    
    /// Crée les labels d'information pour chaque détection
    /// - Parameters:
    ///   - detection: Détection avec infos complètes
    ///   - geometry: Géométrie pour positionnement
    ///   - rect: Rectangle bounding box
    /// - Returns: Vue labels positionnée
    private func detectionLabelsView(for detection: (rect: CGRect, label: String, confidence: Float, distance: Float?, trackingInfo: (id: Int, color: UIColor, opacity: Double)), geometry: GeometryProxy, rect: CGRect) -> some View {
        HStack(spacing: 4) {
            // ID tracking avec couleur
            Text("#\(detection.trackingInfo.id)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(detection.trackingInfo.color).opacity(detection.trackingInfo.opacity))
                .cornerRadius(4)
            
            // Badge objet important
            if isObjectImportant(trackingId: detection.trackingInfo.id) {
                Text("🏆")
                    .font(.caption2)
            }
            
            // Nom objet
            Text(detection.label)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(detection.trackingInfo.color).opacity(detection.trackingInfo.opacity * 0.8))
                .cornerRadius(4)
            
            // Confiance
            Text("\(String(format: "%.0f", detection.confidence * 100))%")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color(detection.trackingInfo.color).opacity(detection.trackingInfo.opacity * 0.6))
                .cornerRadius(3)
            
            // Distance LiDAR
            if let distance = detection.distance {
                Text(formatDistance(distance))
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.9 * detection.trackingInfo.opacity))
                    .cornerRadius(3)
            } else if cameraManager.isLiDAREnabled {
                Text("--")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.6 * detection.trackingInfo.opacity))
                    .cornerRadius(3)
            }
            
            // Indicateur objet fantôme
            if detection.trackingInfo.opacity <= 0.5 {
                Text("👻")
                    .font(.caption2)
                    .opacity(0.7)
            }
        }
        .position(
            x: rect.midX * geometry.size.width,
            y: (1 - rect.maxY) * geometry.size.height - 10
        )
    }
    
    // MARK: - Gestion Pause/Reprise
    
    /// Gèle la détection lors ouverture paramètres
    private func freezeDetection() {
        cameraManager.stopSession()
        voiceSynthesisManager.stopSpeaking()
        voiceInteractionManager.stopContinuousListening()
        stopImportantObjectsTimer()
        enableSleep()
        
        if voiceEnabled {
            voiceSynthesisManager.speak("Détection en pause")
        }
    }
    
    /// Reprend la détection lors fermeture paramètres
    private func unfreezeDetection() {
        if cameraManager.hasPermission {
            cameraManager.startSession()
            disableSleep()
        }
        
        if voiceInteractionEnabled {
            voiceInteractionManager.startContinuousListening()
        }
        
        startImportantObjectsTimer()
        
        if voiceEnabled {
            voiceSynthesisManager.speak("Détection reprise")
        }
    }
    
    // MARK: - Setup et Cleanup
    
    /// Configure les connections entre managers
    private func setupManagers() {
        cameraManager.delegate = CameraDetectionDelegate { newDetections in
            self.boundingBoxes = newDetections
        }
        
        voiceInteractionManager.setVoiceSynthesisManager(voiceSynthesisManager)
        cameraManager.setVoiceSynthesisManager(voiceSynthesisManager)
    }
    
    /// Nettoyage lors disparition vue
    private func cleanupOnDisappear() {
        cameraManager.stopSession()
        voiceSynthesisManager.stopSpeaking()
        voiceInteractionManager.stopContinuousListening()
        stopImportantObjectsTimer()
        enableSleep()
    }
    
    // MARK: - Gestion Mise en Veille
    
    /// Désactive la mise en veille pendant détection
    private func disableSleep() {
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = true
        }
    }
    
    /// Réactive la mise en veille
    private func enableSleep() {
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
    
    // MARK: - Timer Objets Importants
    
    /// Démarre le timer de mise à jour objets importants
    private func startImportantObjectsTimer() {
        importantObjectsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            updateImportantObjects()
        }
    }
    
    /// Arrête le timer objets importants
    private func stopImportantObjectsTimer() {
        importantObjectsTimer?.invalidate()
        importantObjectsTimer = nil
    }
    
    /// Met à jour la liste des objets importants
    private func updateImportantObjects() {
        let newImportantObjects = cameraManager.getTopImportantObjects(maxCount: 15)
        voiceInteractionManager.updateImportantObjects(newImportantObjects)
        
        if voiceEnabled && !newImportantObjects.isEmpty {
            voiceSynthesisManager.processImportantObjects(newImportantObjects)
        }
        
        if !areImportantObjectsEqual(newImportantObjects, importantObjects) {
            withAnimation(.easeInOut(duration: 0.3)) {
                importantObjects = newImportantObjects
            }
        }
    }
    
    // MARK: - Méthodes Utilitaires
    
    /// Retourne la couleur du statut interaction vocale
    /// - Returns: Couleur selon état (gris=off, rouge=erreur, vert=écoute, bleu=prêt, orange=occupé)
    private func getInteractionStatusColor() -> Color {
        if !voiceInteractionEnabled { return .gray }
        if !voiceInteractionManager.interactionEnabled { return .red }
        if voiceInteractionManager.isListening { return .green }
        if voiceInteractionManager.isReadyForQuestion() { return .blue }
        return .orange
    }
    
    /// Vérifie si un objet est dans le leaderboard des importants
    /// - Parameter trackingId: ID tracking de l'objet
    /// - Returns: true si objet important
    private func isObjectImportant(trackingId: Int) -> Bool {
        return importantObjects.contains { $0.object.trackingNumber == trackingId }
    }
    
    /// Compare deux listes d'objets importants pour détecter changements
    /// - Parameters:
    ///   - list1: Première liste
    ///   - list2: Seconde liste
    /// - Returns: true si listes identiques
    private func areImportantObjectsEqual(
        _ list1: [(object: TrackedObject, score: Float)],
        _ list2: [(object: TrackedObject, score: Float)]
    ) -> Bool {
        guard list1.count == list2.count else { return false }
        
        for i in 0..<list1.count {
            if list1[i].object.trackingNumber != list2[i].object.trackingNumber ||
               abs(list1[i].score - list2[i].score) > 0.01 {
                return false
            }
        }
        return true
    }
    
    /// Formate une distance pour affichage
    /// - Parameter distance: Distance en mètres
    /// - Returns: String formatée (ex: "45cm", "1.2m", "15m")
    private func formatDistance(_ distance: Float) -> String {
        if distance < 1.0 {
            return "\(Int(distance * 100))cm"
        } else if distance < 10.0 {
            return "\(String(format: "%.1f", distance))m"
        } else {
            return "\(Int(distance))m"
        }
    }
    
    /// Génère le message d'information LiDAR selon disponibilité et état
    /// - Returns: Message détaillé sur LiDAR et fonctionnalités
    private func getLiDARInfoMessage() -> String {
        if !cameraManager.lidarAvailable {
            return "LiDAR non disponible sur cet appareil. Les distances et alertes de proximité ne peuvent pas être mesurées."
        } else if cameraManager.isLiDAREnabled {
            let dangerDist = cameraManager.getDangerDistance()
            let alertsStatus = proximityAlertsEnabled ? "activées" : "désactivées"
            return """
            LiDAR activé! Les distances sont affichées en bleu à côté de la confiance.
            
            📳 Alertes de proximité \(alertsStatus):
            • Vibrations si objet < \(String(format: "%.1f", dangerDist))m
            
            🎯 Tracking d'objets:
            • Chaque objet a un ID unique (#1, #2, etc.)
            • Couleur persistante même si temporairement perdu
            • Objets fantômes (👻) = en mémoire 3s
            
            🗣️ Interaction Vocale:
            • Appui long n'importe où sur l'écran pour poser une question
            • Questions supportées : "Y a-t-il une voiture ?", "Est-ce que je peux traverser ?"
            • 100% privé et local, aucune donnée envoyée sur internet
            """
        } else {
            return """
            LiDAR disponible mais désactivé.
            
            Touchez l'icône de localisation 📍 pour l'activer et bénéficier de:
            • Affichage des distances en temps réel
            • Alertes de proximité par vibration
            """
        }
    }
}

// MARK: - Delegate Communication CameraManager

class CameraDetectionDelegate: CameraManagerDelegate {
    let onDetections: ([(rect: CGRect, label: String, confidence: Float, distance: Float?, trackingInfo: (id: Int, color: UIColor, opacity: Double))]) -> Void
    
    /// Initialise le delegate avec callback
    /// - Parameter onDetections: Callback appelé lors nouvelles détections
    init(onDetections: @escaping ([(rect: CGRect, label: String, confidence: Float, distance: Float?, trackingInfo: (id: Int, color: UIColor, opacity: Double))]) -> Void) {
        self.onDetections = onDetections
    }
    
    /// Transmet les détections à l'interface utilisateur
    /// - Parameter detections: Array détections avec infos tracking complètes
    func didDetectObjects(_ detections: [(rect: CGRect, label: String, confidence: Float, distance: Float?, trackingInfo: (id: Int, color: UIColor, opacity: Double))]) {
        onDetections(detections)
    }
}

// MARK: - Indicateur Écoute Vocale

struct VoiceListeningIndicator: View {
    let isWaitingForQuestion: Bool
    let lastRecognizedText: String
    
    @State private var pulseAnimation = false
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 12, height: 12)
                    .scaleEffect(pulseAnimation ? 1.3 : 1.0)
                    .animation(.easeInOut(duration: 1.0).repeatForever(), value: pulseAnimation)
                
                Image(systemName: "mic.fill")
                    .font(.title2)
                    .foregroundColor(.green)
                
                Text("Écoute en cours...")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
            
            if !lastRecognizedText.isEmpty && !lastRecognizedText.contains("touchez") {
                Text("« \(lastRecognizedText) »")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.8))
                    .italic()
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .background(Color.black.opacity(0.8))
        .cornerRadius(12)
        .onAppear {
            pulseAnimation = true
        }
    }
}
