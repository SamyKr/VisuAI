//
//  DetectionView.swift
//  test
//
//  Created by Samy 📍 on 04/07/2025.
//  Modified to pass CameraManager to ParametersView - 08/07/2025
//
import SwiftUI
import AVFoundation
import Speech

// MARK: - CameraView UIViewRepresentable
struct CameraPreviewView: UIViewRepresentable {
    let cameraManager: CameraManager
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: CGRect.zero)
        view.backgroundColor = UIColor.black
        
        let previewLayer = cameraManager.getPreviewLayer()
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if let previewLayer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            DispatchQueue.main.async {
                previewLayer.frame = uiView.bounds
            }
        }
    }
}

struct DetectionView: View {
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var voiceSynthesisManager = VoiceSynthesisManager()
    @StateObject private var voiceInteractionManager = VoiceInteractionManager()
    @StateObject private var questionnaireManager = QuestionnaireManager()
    
    @State private var boundingBoxes: [(rect: CGRect, label: String, confidence: Float, distance: Float?, trackingInfo: (id: Int, color: UIColor, opacity: Double))] = []
    @State private var showingPermissionAlert = false
    @State private var showingSettings = false
    @State private var showingLiDARInfo = false
    @State private var proximityAlertsEnabled = true
    
    // États pour ImportantObjectsBoard
    @State private var showingImportantObjects = false
    @State private var importantObjects: [(object: TrackedObject, score: Float)] = []
    
    // Timer pour rafraîchir le leaderboard
    @State private var importantObjectsTimer: Timer?
    
    // États pour la synthèse vocale et interaction
    @State private var voiceEnabled = true
    @State private var voiceInteractionEnabled = true
    @State private var showingVoicePermissionAlert = false
    
    var body: some View {
        ZStack {
            CameraPreviewView(cameraManager: cameraManager)
                .onAppear {
                    setupFromQuestionnaire()
                    setupManagers()
                    startImportantObjectsTimer()
                    
                    // Désactiver la mise en veille
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
                    cameraManager.stopSession()
                    voiceSynthesisManager.stopSpeaking()
                    voiceInteractionManager.stopContinuousListening()
                    stopImportantObjectsTimer()
                    
                    // Réactiver la mise en veille
                    enableSleep()
                }
            
            // 🎤 OVERLAY TRANSPARENT POUR APPUI LONG SUR TOUT L'ÉCRAN
            Color.clear
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: 0.8) {
                    // 🛑 COUPER IMMÉDIATEMENT TOUTE SYNTHÈSE VOCALE
                    voiceSynthesisManager.stopSpeaking()
                    voiceSynthesisManager.interruptForInteraction(reason: "Question utilisateur")
                    
                    if voiceInteractionEnabled && voiceInteractionManager.isReadyForQuestion() {
                        print("🎤 Appui long détecté - arrêt synthèse et démarrage question")
                        
                        // Petit délai pour s'assurer que l'audio est libéré
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            voiceInteractionManager.startSingleQuestion()
                        }
                        
                        cameraManager.playSelectionFeedback()
                    } else if !voiceInteractionEnabled {
                        print("⚠️ Interaction vocale désactivée")
                        voiceSynthesisManager.speak("Interaction vocale désactivée")
                    } else if !voiceInteractionManager.interactionEnabled {
                        print("⚠️ Permission microphone requise")
                        voiceSynthesisManager.speak("Permission microphone requise")
                        showingVoicePermissionAlert = true
                    } else {
                        print("⚠️ Service vocal occupé")
                        voiceSynthesisManager.speak("Service vocal occupé, veuillez patienter")
                    }
                }
            
            // Overlay pour les bounding boxes
            GeometryReader { geometry in
                ForEach(boundingBoxes.indices, id: \.self) { index in
                    let detection = boundingBoxes[index]
                    let rect = detection.rect
                    let tracking = detection.trackingInfo
                    
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
                    
                    detectionLabelsView(for: detection, geometry: geometry, rect: rect)
                }
            }
            
            // Indicateur d'écoute d'interaction vocale
            if voiceInteractionManager.isListening {
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
            
            // Indicateur discret d'appui long (si interaction vocale activée et prête)
            if voiceInteractionEnabled && voiceInteractionManager.isReadyForQuestion() && !voiceInteractionManager.isListening {
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
            
            // HUD Amélioré - Colonne gauche
            VStack {
                leftControlsColumnView
                Spacer()
                bottomControlsView
            }
            
            // ImportantObjectsBoard overlay
            if showingImportantObjects {
                ImportantObjectsBoard(
                    importantObjects: importantObjects,
                    isVisible: $showingImportantObjects
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            
            // Bouton ImportantObjectsBoard (reste en haut à droite)
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
                // Geler la détection quand on ouvre les paramètres
                freezeDetection()
            } else {
                // Reprendre la détection quand on ferme les paramètres
                unfreezeDetection()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showingImportantObjects)
    }
    
    // MARK: - Sleep Management Methods
    private func disableSleep() {
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = true
            print("🔒 Mise en veille désactivée")
        }
    }
    
    private func enableSleep() {
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = false
            print("💤 Mise en veille réactivée")
        }
    }
    
    // MARK: - HUD Amélioré - Colonne gauche
    
    private var leftControlsColumnView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 12) {
                // FPS en haut
                fpsIndicatorView
                
                // Boutons de contrôle en colonne
                VStack(alignment: .leading, spacing: 10) {
                    // Paramètres
                    settingsButtonView
                    
                    // Microphone
                    microphoneButtonView
                    
                    // Volume/Speaker
                    speakerButtonView
                    
                    // Vibrations (si LiDAR actif)
                    if cameraManager.isLiDAREnabled {
                        vibrationButtonView
                    }
                    
                    // LiDAR (si disponible)
                    if cameraManager.lidarAvailable {
                        lidarButtonView
                    }
                }
            }
            .padding(.leading, 16)
            .padding(.top, 50)
            
            Spacer() // Force l'alignement à gauche
        }
    }
    
    // MARK: - Composants individuels
    
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
    
    // MARK: - Contrôles du bas (bouton pause seulement)
    
    private var bottomControlsView: some View {
        HStack {
            Spacer()
            
            // Bouton Start/Stop principal centré
            Button(action: {
                if cameraManager.isRunning {
                    cameraManager.stopSession()
                    voiceSynthesisManager.stopSpeaking()
                    voiceInteractionManager.stopContinuousListening()
                    
                    // Réactiver la mise en veille quand on arrête
                    enableSleep()
                    
                } else {
                    if cameraManager.hasPermission {
                        cameraManager.startSession()
                        
                        // Désactiver la mise en veille quand on démarre
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
    
    // MARK: - Configuration depuis le questionnaire - NOUVELLE VERSION
    
    private func setupFromQuestionnaire() {
        let responses = questionnaireManager.responses
        
        print("🎯 Configuration depuis le questionnaire simplifié (3 questions):")
        
        // 🎯 QUESTION 1: Alertes vocales d'objets proches
        if let wantsVoiceAlerts = responses[1] {
            voiceEnabled = wantsVoiceAlerts
            if wantsVoiceAlerts {
                print("✅ Q1: Alertes vocales ACTIVÉES")
            } else {
                print("❌ Q1: Alertes vocales DÉSACTIVÉES")
            }
        } else {
            // Par défaut: alertes vocales activées
            voiceEnabled = true
            print("🔄 Q1: Alertes vocales par défaut (ACTIVÉES)")
        }
        
        // 🎯 QUESTION 2: Vibrations pour proximité
        if let wantsVibrations = responses[2] {
            proximityAlertsEnabled = wantsVibrations
            cameraManager.enableProximityAlerts(wantsVibrations)
            
            // Si vibrations demandées ET LiDAR disponible → activer LiDAR automatiquement
            if wantsVibrations && cameraManager.lidarAvailable {
                let success = cameraManager.enableLiDAR()
                if success {
                    print("✅ Q2: Vibrations ACTIVÉES + LiDAR ACTIVÉ automatiquement")
                } else {
                    print("⚠️ Q2: Vibrations ACTIVÉES mais échec activation LiDAR")
                }
            } else if wantsVibrations {
                print("✅ Q2: Vibrations ACTIVÉES (LiDAR non disponible)")
            } else {
                print("❌ Q2: Vibrations DÉSACTIVÉES")
            }
        } else {
            // Par défaut: vibrations désactivées
            proximityAlertsEnabled = false
            cameraManager.enableProximityAlerts(false)
            print("🔄 Q2: Vibrations par défaut (DÉSACTIVÉES)")
        }
        
        // 🎯 QUESTION 3: Communication vocale
        if let wantsCommunication = responses[3] {
            voiceInteractionEnabled = wantsCommunication
            if wantsCommunication {
                // Démarrer l'écoute continue si activée
                voiceInteractionManager.startContinuousListening()
                print("✅ Q3: Communication vocale ACTIVÉE")
            } else {
                // Arrêter l'écoute si désactivée
                voiceInteractionManager.stopContinuousListening()
                print("❌ Q3: Communication vocale DÉSACTIVÉE")
            }
        } else {
            // Par défaut: communication vocale activée
            voiceInteractionEnabled = true
            voiceInteractionManager.startContinuousListening()
            print("🔄 Q3: Communication vocale par défaut (ACTIVÉE)")
        }
        
        // 🎯 RÉCAPITULATIF FINAL
        print("🎯 Configuration finale appliquée:")
        print("   - 🔊 Alertes vocales: \(voiceEnabled ? "✅ ACTIVÉES" : "❌ DÉSACTIVÉES")")
        print("   - 📳 Vibrations: \(proximityAlertsEnabled ? "✅ ACTIVÉES" : "❌ DÉSACTIVÉES")")
        print("   - 🎤 Communication vocale: \(voiceInteractionEnabled ? "✅ ACTIVÉE" : "❌ DÉSACTIVÉE")")
        print("   - 📍 LiDAR: \(cameraManager.isLiDAREnabled ? "✅ ACTIVÉ" : "❌ DÉSACTIVÉ")")
        
        // ✅ NOUVEAU: Connecter le VoiceSynthesisManager au CameraManager (CRITIQUE!)
        cameraManager.setVoiceSynthesisManager(voiceSynthesisManager)
        print("🔗 VoiceSynthesisManager connecté au CameraManager")
        
        // ✅ NOUVEAU: Synchroniser les objets dangereux depuis UserDefaults
        let userDefaults = UserDefaults.standard
        if let savedObjects = userDefaults.array(forKey: "dangerous_objects_list") as? [String] {
            let dangerousSet = Set(savedObjects)
            cameraManager.updateDangerousObjects(dangerousSet)
            print("🔄 Objets dangereux synchronisés: \(savedObjects.count) objets")
            print("   - Liste: \(savedObjects.sorted())")
        } else {
            // Utiliser les valeurs par défaut si rien n'est sauvegardé
            let defaultDangerous: Set<String> = [
                "person", "cyclist", "motorcyclist",
                "car", "truck", "bus", "motorcycle", "bicycle",
                "pole", "traffic cone", "barrier", "temporary barrier"
            ]
            cameraManager.updateDangerousObjects(defaultDangerous)
            print("🔄 Objets dangereux par défaut appliqués: \(defaultDangerous.count) objets")
        }
        
        // 🎯 FEEDBACK VOCAL INITIAL (si activé)
        if voiceEnabled {
            let statusMessage = buildConfigurationMessage()
            // Délai pour éviter la collision avec d'autres messages au démarrage
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                voiceSynthesisManager.speak(statusMessage)
            }
        }
    }

    // 🎯 NOUVELLE MÉTHODE: Construire le message de configuration
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
    // MARK: - Detection Labels View
    private func detectionLabelsView(for detection: (rect: CGRect, label: String, confidence: Float, distance: Float?, trackingInfo: (id: Int, color: UIColor, opacity: Double)), geometry: GeometryProxy, rect: CGRect) -> some View {
        HStack(spacing: 4) {
            Text("#\(detection.trackingInfo.id)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(detection.trackingInfo.color).opacity(detection.trackingInfo.opacity))
                .cornerRadius(4)
            
            if isObjectImportant(trackingId: detection.trackingInfo.id) {
                Text("🏆")
                    .font(.caption2)
            }
            
            Text(detection.label)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(detection.trackingInfo.color).opacity(detection.trackingInfo.opacity * 0.8))
                .cornerRadius(4)
            
            Text("\(String(format: "%.0f", detection.confidence * 100))%")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color(detection.trackingInfo.color).opacity(detection.trackingInfo.opacity * 0.6))
                .cornerRadius(3)
            
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
    
    // MARK: - Freeze/Unfreeze Detection
    
    private func freezeDetection() {
        print("🧊 Gel de la détection - ouverture des paramètres")
        
        // Arrêter la session caméra
        cameraManager.stopSession()
        
        // Arrêter tous les services audio
        voiceSynthesisManager.stopSpeaking()
        voiceInteractionManager.stopContinuousListening()
        
        // Arrêter le timer des objets importants
        stopImportantObjectsTimer()
        
        // Réactiver la mise en veille pendant les paramètres
        enableSleep()
        
        // Feedback sonore si audio activé
        if voiceEnabled {
            voiceSynthesisManager.speak("Détection en pause")
        }
    }
    
    private func unfreezeDetection() {
        print("🔄 Reprise de la détection - fermeture des paramètres")
        
        // Reprendre la session caméra si on a les permissions
        if cameraManager.hasPermission {
            cameraManager.startSession()
            
            // Désactiver à nouveau la mise en veille
            disableSleep()
        }
        
        // Reprendre l'interaction vocale si elle était activée
        if voiceInteractionEnabled {
            voiceInteractionManager.startContinuousListening()
        }
        
        // Reprendre le timer des objets importants
        startImportantObjectsTimer()
        
        // Feedback sonore si audio activé
        if voiceEnabled {
            voiceSynthesisManager.speak("Détection reprise")
        }
    }
    
    // MARK: - Setup Methods
    
    private func setupManagers() {
        cameraManager.delegate = CameraDetectionDelegate { newDetections in
            self.boundingBoxes = newDetections
        }
        
        voiceInteractionManager.setVoiceSynthesisManager(voiceSynthesisManager)
        cameraManager.setVoiceSynthesisManager(voiceSynthesisManager)
    }
    
    // MARK: - Timer Management
    
    private func startImportantObjectsTimer() {
        importantObjectsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            updateImportantObjects()
        }
    }
    
    private func stopImportantObjectsTimer() {
        importantObjectsTimer?.invalidate()
        importantObjectsTimer = nil
    }
    
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
    
    // MARK: - Helper Methods pour interaction vocale
    
    private func getInteractionStatusColor() -> Color {
        if !voiceInteractionEnabled { return .gray }
        if !voiceInteractionManager.interactionEnabled { return .red }
        if voiceInteractionManager.isListening { return .green }
        if voiceInteractionManager.isReadyForQuestion() { return .blue }
        return .orange
    }
    
    // MARK: - Helper Methods existantes
    
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
    
    private func isObjectImportant(trackingId: Int) -> Bool {
        return importantObjects.contains { $0.object.trackingNumber == trackingId }
    }
    
    private func getLiDARInfoMessage() -> String {
        if !cameraManager.lidarAvailable {
            return "LiDAR non disponible sur cet appareil. Les distances et alertes de proximité ne peuvent pas être mesurées."
        } else if cameraManager.isLiDAREnabled {
            let dangerDist = cameraManager.getDangerDistance()
            let alertsStatus = proximityAlertsEnabled ? "activées" : "désactivées"
            return """
            LiDAR activé! Les distances sont affichées en bleu à côté de la confiance.
            
            🎨 Les bounding boxes utilisent les couleurs de tracking pour identifier les objets de manière persistante.
            
            📳 Alertes de proximité \(alertsStatus):
            • Vibrations si objet < \(String(format: "%.1f", dangerDist))m
            • Touchez l'icône 🔔 pour activer/désactiver
            
            🎯 Tracking d'objets:
            • Chaque objet a un ID unique (#1, #2, etc.)
            • Couleur persistante même si temporairement perdu
            • Objets fantômes (👻) = en mémoire 3s
            
            🏆 Objets Importants:
            • Les objets avec un score d'importance élevé apparaissent dans le leaderboard
            • Touchez le bouton 'Top' pour voir le classement
            • Les objets VIP sont marqués d'un 🏆 sur les bounding boxes
            
            🗣️ Synthèse Vocale:
            • Annonces automatiques des objets importants
            • Touchez l'icône 🔊 pour activer/désactiver
            • Fréquence intelligente pour éviter la surcharge
            
            🎤 Interaction Vocale:
            • Appui long n'importe où sur l'écran pour poser une question
            • Parlez après le bip sonore : "Y a-t-il une voiture ?", "Où est le feu ?", "Décris la scène"
            • Une question à la fois, pas d'écoute continue
            • 100% privé et local, aucune donnée envoyée sur internet
            
            ⚙️ Configuration automatique:
            • Vos préférences du questionnaire sont appliquées automatiquement
            • Question 2 (alertes obstacles) → Active LiDAR + vibrations
            • Question 3 (préférence vocale) → Active/désactive synthèse vocale
            """
        } else {
            return """
            LiDAR disponible mais désactivé.
            
            Touchez l'icône de localisation 📍 pour l'activer et bénéficier de:
            • Affichage des distances en temps réel
            • Alertes de proximité par vibration
            • Bounding boxes colorées selon la distance
            
            🎯 Le tracking fonctionne sans LiDAR avec des couleurs persistantes par objet.
            
            🏆 Le leaderboard des objets importants fonctionne avec ou sans LiDAR.
            
            🗣️ La synthèse vocale fonctionne avec ou sans LiDAR.
            
            🎤 L'interaction vocale fonctionne avec ou sans LiDAR.
            
            ⚙️ Configuration automatique:
            • Vos préférences du questionnaire sont appliquées automatiquement
            • Vous pouvez modifier manuellement ces réglages ici
            """
        }
    }
    
    private func formatDistance(_ distance: Float) -> String {
        if distance < 1.0 {
            return "\(Int(distance * 100))cm"
        } else if distance < 10.0 {
            return "\(String(format: "%.1f", distance))m"
        } else {
            return "\(Int(distance))m"
        }
    }
}

// MARK: - Delegate
class CameraDetectionDelegate: CameraManagerDelegate {
    let onDetections: ([(rect: CGRect, label: String, confidence: Float, distance: Float?, trackingInfo: (id: Int, color: UIColor, opacity: Double))]) -> Void
    
    init(onDetections: @escaping ([(rect: CGRect, label: String, confidence: Float, distance: Float?, trackingInfo: (id: Int, color: UIColor, opacity: Double))]) -> Void) {
        self.onDetections = onDetections
    }
    
    func didDetectObjects(_ detections: [(rect: CGRect, label: String, confidence: Float, distance: Float?, trackingInfo: (id: Int, color: UIColor, opacity: Double))]) {
        onDetections(detections)
    }
}

// MARK: - Vues supplémentaires

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
 
