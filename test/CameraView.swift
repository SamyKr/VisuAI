//
//  CameraView.swift (Version Optimisée - HUD Compact)
//  test
//
//  Created by Samy 📍 on 18/06/2025.
//  Updated with LiDAR integration - 19/06/2025
//  Updated with Object Tracking - 20/06/2025
//  Updated with ImportantObjectsBoard - 21/06/2025
//  Updated with VoiceSynthesis - 02/07/2025
//  Updated with VoiceInteraction - 02/07/2025 (ERREURS CORRIGÉES)
//  Optimized UI - 03/07/2025
//

import SwiftUI
import AVFoundation
import Speech

struct CameraView: UIViewRepresentable {
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

struct CameraViewWithDetection: View {
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var voiceSynthesisManager = VoiceSynthesisManager()
    @StateObject private var voiceInteractionManager = VoiceInteractionManager()
    
    @State private var boundingBoxes: [(rect: CGRect, label: String, confidence: Float, distance: Float?, trackingInfo: (id: Int, color: UIColor, opacity: Double))] = []
    @State private var showingStats = false
    @State private var showingPermissionAlert = false
    @State private var showingSettings = false
    @State private var showingLiDARInfo = false
    @State private var proximityAlertsEnabled = true
    
    // États pour ImportantObjectsBoard
    @State private var showingImportantObjects = false
    @State private var importantObjects: [(object: TrackedObject, score: Float)] = []
    
    // Timer pour rafraîchir le leaderboard
    @State private var importantObjectsTimer: Timer?
    
    // Configuration initiale
    @State private var showingInitialConfiguration = false
    @State private var hasConfiguredInitially = false
    
    // États pour la synthèse vocale et interaction
    @State private var voiceEnabled = true
    @State private var voiceInteractionEnabled = true
    @State private var showingVoicePermissionAlert = false
    
    // État pour débug (développement seulement)
    @State private var showDebugControls = false
    
    var body: some View {
        ZStack {
            CameraView(cameraManager: cameraManager)
                .onAppear {
                    setupManagers()
                    startImportantObjectsTimer()
                    
                    if cameraManager.hasPermission {
                        cameraManager.startSession()
                    } else {
                        cameraManager.requestPermission()
                    }
                }
                .onReceive(cameraManager.$hasPermission) { hasPermission in
                    if hasPermission {
                        if !hasConfiguredInitially {
                            showingInitialConfiguration = true
                        } else {
                            cameraManager.startSession()
                        }
                    }
                }
                .onDisappear {
                    cameraManager.stopSession()
                    voiceSynthesisManager.stopSpeaking()
                    voiceInteractionManager.stopContinuousListening()
                    stopImportantObjectsTimer()
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
            
            // HUD Compact
            VStack {
                compactHUDView
                
                Spacer()
                
                if showingStats {
                    PerformanceStatsView(
                        cameraManager: cameraManager,
                        voiceSynthesisManager: voiceSynthesisManager,
                        voiceInteractionManager: voiceInteractionManager
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                mainControlsView
                
                // Boutons de debug (masqués par défaut)
                if showDebugControls {
                    debugControlsView
                }
            }
            
            // ImportantObjectsBoard overlay
            if showingImportantObjects {
                ImportantObjectsBoard(
                    importantObjects: importantObjects,
                    isVisible: $showingImportantObjects
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            
            // Bouton ImportantObjectsBoard
            VStack {
                HStack {
                    Spacer()
                    ImportantObjectsButton(
                        isVisible: $showingImportantObjects,
                        objectCount: importantObjects.count
                    )
                    .padding(.top, 100)
                    .padding(.trailing)
                }
                Spacer()
            }
        }
        .navigationTitle("Vision AI + LiDAR + Voice")
        .navigationBarTitleDisplayMode(.inline)
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
            CameraDetectionSettingsView(isPresented: $showingSettings, cameraManager: cameraManager)
        }
        .sheet(isPresented: $showingInitialConfiguration) {
            InitialConfigurationView(
                isPresented: $showingInitialConfiguration,
                hasConfiguredInitially: $hasConfiguredInitially,
                cameraManager: cameraManager,
                proximityAlertsEnabled: $proximityAlertsEnabled,
                voiceInteractionEnabled: $voiceInteractionEnabled
            )
        }
        .animation(.easeInOut(duration: 0.3), value: showingStats)
        .animation(.easeInOut(duration: 0.3), value: showingImportantObjects)
    }
    
    // MARK: - HUD Ultra-Compact (UNE SEULE LIGNE)
    
    private var compactHUDView: some View {
        HStack(spacing: 8) {
            // Status compact tout en ligne
            HStack(spacing: 8) {
                // Status live
                Circle()
                    .fill(cameraManager.isRunning ? Color.green : Color.red)
                    .frame(width: 6, height: 6)
                
                // FPS
                Text("\(String(format: "%.0f", cameraManager.currentFPS))")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                // Objets actifs
                let activeObjects = boundingBoxes.filter { $0.trackingInfo.opacity > 0.5 }.count
                let memoryObjects = boundingBoxes.filter { $0.trackingInfo.opacity <= 0.5 }.count
                
                Text("🎯\(activeObjects)")
                    .font(.caption2)
                    .foregroundColor(.green)
                
                if memoryObjects > 0 {
                    Text("+\(memoryObjects)")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
                
                // VIP objects
                if importantObjects.count > 0 {
                    Text("🏆\(importantObjects.count)")
                        .font(.caption2)
                        .foregroundColor(.yellow)
                }
                
                // Status services ultra-compacts
                Circle()
                    .fill(voiceEnabled ? .blue : .gray)
                    .frame(width: 4, height: 4)
                
                Circle()
                    .fill(getInteractionStatusColor())
                    .frame(width: 4, height: 4)
                
                if cameraManager.lidarAvailable {
                    Circle()
                        .fill(cameraManager.isLiDAREnabled ? .blue : .gray)
                        .frame(width: 4, height: 4)
                    
                    if cameraManager.isLiDAREnabled {
                        Circle()
                            .fill(proximityAlertsEnabled ? .orange : .gray)
                            .frame(width: 4, height: 4)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.7))
            .cornerRadius(8)
            
            Spacer()
            
            // Boutons essentiels seulement
            essentialControlsView
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }
    
    private var essentialControlsView: some View {
        HStack(spacing: 6) {
            // Indicateur d'état vocal (pas un bouton)
            HStack(spacing: 4) {
                Circle()
                    .fill(getInteractionStatusColor())
                    .frame(width: 6, height: 6)
                Image(systemName: voiceInteractionEnabled ? "mic.fill" : "mic.slash")
                    .font(.caption2)
                    .foregroundColor(getInteractionStatusColor())
                Text(voiceInteractionEnabled ? "ON" : "OFF")
                    .font(.caption2)
                    .foregroundColor(getInteractionStatusColor())
                    .fontWeight(.bold)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.7))
            .cornerRadius(6)
            .onTapGesture {
                // Tap pour activer/désactiver le service
                voiceInteractionEnabled.toggle()
                if voiceInteractionEnabled {
                    voiceInteractionManager.startContinuousListening()
                } else {
                    voiceInteractionManager.stopContinuousListening()
                }
                cameraManager.playSelectionFeedback()
            }
            
            // Speaker
            Button(action: {
                voiceEnabled.toggle()
                if !voiceEnabled {
                    voiceSynthesisManager.stopSpeaking()
                }
                cameraManager.playSelectionFeedback()
            }) {
                Image(systemName: voiceEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.caption)
                    .foregroundColor(voiceEnabled ? .blue : .gray)
                    .padding(6)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(6)
            }
            
            // Reset
            Button(action: {
                cameraManager.resetTracking()
                voiceSynthesisManager.clearAllState()
                voiceInteractionManager.stopContinuousListening()
                cameraManager.playSuccessFeedback()
                importantObjects.removeAll()
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(6)
                    .background(Color.purple.opacity(0.8))
                    .cornerRadius(6)
            }
            
            // LiDAR (si disponible)
            if cameraManager.lidarAvailable {
                Button(action: {
                    let success = cameraManager.toggleLiDAR()
                    if success {
                        cameraManager.playSuccessFeedback()
                    }
                }) {
                    Image(systemName: cameraManager.isLiDAREnabled ? "location.fill" : "location")
                        .font(.caption)
                        .foregroundColor(cameraManager.isLiDAREnabled ? .blue : .white)
                        .padding(6)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(6)
                }
                .onLongPressGesture {
                    showingLiDARInfo = true
                }
            }
            
            // Settings
            Button(action: {
                showingSettings = true
                cameraManager.playSelectionFeedback()
            }) {
                Image(systemName: "gear")
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(6)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(6)
            }
        }
    }
    
    private var mainControlsView: some View {
        HStack {
            // Bouton Stats (gauche)
            Button(action: {
                showingStats.toggle()
                cameraManager.playSelectionFeedback()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: showingStats ? "chart.bar.fill" : "chart.bar")
                        .font(.caption)
                    Text("Stats")
                        .font(.caption2)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.7))
                .cornerRadius(6)
            }
            
            // Bouton debug compact
            Button("🔧") {
                showDebugControls.toggle()
            }
            .font(.caption)
            .padding(6)
            .background(Color.black.opacity(0.5))
            .cornerRadius(4)
            
            Spacer()
            
            // Alertes proximité (si LiDAR actif)
            if cameraManager.isLiDAREnabled {
                Button(action: {
                    proximityAlertsEnabled.toggle()
                    cameraManager.enableProximityAlerts(proximityAlertsEnabled)
                    cameraManager.playSelectionFeedback()
                }) {
                    Text(proximityAlertsEnabled ? "📳" : "🔕")
                        .font(.caption)
                        .padding(6)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(6)
                }
            }
            
            Spacer()
            
            // Start/Stop principal
            Button(cameraManager.isRunning ? "■" : "▶") {
                if cameraManager.isRunning {
                    cameraManager.stopSession()
                    voiceSynthesisManager.stopSpeaking()
                    voiceInteractionManager.stopContinuousListening()
                } else {
                    if cameraManager.hasPermission {
                        cameraManager.startSession()
                        
                        // L'utilisateur activera manuellement l'interaction vocale
                    } else {
                        showingPermissionAlert = true
                    }
                }
            }
            .font(.title2)
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(cameraManager.isRunning ? Color.red : Color.green)
            .cornerRadius(8)
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
    
    // MARK: - Debug Controls (ultra-compact)
    
    private var debugControlsView: some View {
        HStack(spacing: 6) {
            Text("🔧")
                .font(.caption2)
                .foregroundColor(.orange)
            
            Button("Reset") {
                cameraManager.resetPerformanceStats()
                voiceSynthesisManager.clearAllState()
                importantObjects.removeAll()
            }
            .font(.caption2)
            .foregroundColor(.white)
            .padding(4)
            .background(Color.blue.opacity(0.7))
            .cornerRadius(4)
            
            Button("Audio") {
                if voiceEnabled {
                    voiceSynthesisManager.speak("Test audio")
                }
            }
            .font(.caption2)
            .foregroundColor(.white)
            .padding(4)
            .background(Color.green.opacity(0.7))
            .cornerRadius(4)
            .disabled(!voiceEnabled)
            
            Button("Voice") {
                if voiceInteractionEnabled {
                    voiceInteractionManager.interruptForInteraction(reason: "Test")
                    voiceInteractionManager.speakInteraction("Test d'interaction - appui long sur l'écran puis posez votre question")
                }
            }
            .font(.caption2)
            .foregroundColor(.white)
            .padding(4)
            .background(Color.purple.opacity(0.7))
            .cornerRadius(4)
            .disabled(!voiceInteractionEnabled)
            
            Button("Config") {
                hasConfiguredInitially = false
                showingInitialConfiguration = true
                cameraManager.stopSession()
                voiceSynthesisManager.stopSpeaking()
                voiceInteractionManager.stopContinuousListening()
            }
            .font(.caption2)
            .foregroundColor(.white)
            .padding(4)
            .background(Color.orange.opacity(0.7))
            .cornerRadius(4)
        }
        .padding(8)
        .background(Color.black.opacity(0.8))
        .cornerRadius(8)
        .padding(.horizontal)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
    
    // MARK: - Detection Labels View (inchangé)
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
    
    // MARK: - Setup Methods (inchangé)
    
    private func setupManagers() {
        cameraManager.delegate = CameraDetectionDelegate { newDetections in
            self.boundingBoxes = newDetections
        }
        
        if cameraManager.lidarAvailable {
            let _ = cameraManager.enableLiDAR()
        }
        
        proximityAlertsEnabled = cameraManager.isProximityAlertsEnabled()
        voiceInteractionManager.setVoiceSynthesisManager(voiceSynthesisManager)
        
        // Plus d'activation automatique - l'utilisateur contrôle manuellement
    }
    
    // MARK: - Timer Management (inchangé)
    
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
    
    // MARK: - Helper Methods pour interaction vocale (inchangé)
    
    private func getInteractionStatusColor() -> Color {
        if !voiceInteractionEnabled { return .gray }
        if !voiceInteractionManager.interactionEnabled { return .red }
        if voiceInteractionManager.isListening { return .green }
        if voiceInteractionManager.isReadyForQuestion() { return .blue }
        return .orange
    }
    
    private func getInteractionButtonColor() -> Color {
        if !voiceInteractionEnabled { return .gray }
        if !voiceInteractionManager.interactionEnabled { return .red }
        if voiceInteractionManager.isListening { return .green }
        if voiceInteractionManager.isReadyForQuestion() { return .blue }
        return .orange
    }
    
    // MARK: - Helper Methods existantes (inchangées)
    
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

// MARK: - Delegate (inchangé)
class CameraDetectionDelegate: CameraManagerDelegate {
    let onDetections: ([(rect: CGRect, label: String, confidence: Float, distance: Float?, trackingInfo: (id: Int, color: UIColor, opacity: Double))]) -> Void
    
    init(onDetections: @escaping ([(rect: CGRect, label: String, confidence: Float, distance: Float?, trackingInfo: (id: Int, color: UIColor, opacity: Double))]) -> Void) {
        self.onDetections = onDetections
    }
    
    func didDetectObjects(_ detections: [(rect: CGRect, label: String, confidence: Float, distance: Float?, trackingInfo: (id: Int, color: UIColor, opacity: Double))]) {
        onDetections(detections)
    }
}

// MARK: - Vue de statistiques consolidée
struct PerformanceStatsView: View {
    let cameraManager: CameraManager
    let voiceSynthesisManager: VoiceSynthesisManager
    let voiceInteractionManager: VoiceInteractionManager
    
    @State private var cameraStats = ""
    @State private var voiceStats = ""
    @State private var interactionStats = ""
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Stats Caméra
                VStack(alignment: .leading, spacing: 8) {
                    Text("📹 Caméra & Détection")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Text(cameraStats)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.white)
                }
                .padding()
                .background(Color.black.opacity(0.8))
                .cornerRadius(12)
                
                // Stats Audio
                VStack(alignment: .leading, spacing: 8) {
                    Text("🗣️ Synthèse Vocale")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Text(voiceStats)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.white)
                }
                .padding()
                .background(Color.orange.opacity(0.8))
                .cornerRadius(12)
                
                // Stats Interaction
                VStack(alignment: .leading, spacing: 8) {
                    Text("🎤 Interaction Vocale")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Text(interactionStats)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.white)
                }
                .padding()
                .background(Color.purple.opacity(0.8))
                .cornerRadius(12)
            }
        }
        .frame(maxHeight: 300)
        .padding(.horizontal)
        .onAppear {
            updateStats()
        }
        .onReceive(Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()) { _ in
            updateStats()
        }
    }
    
    private func updateStats() {
        cameraStats = cameraManager.getPerformanceStats()
        voiceStats = voiceSynthesisManager.getStats()
        interactionStats = voiceInteractionManager.getStats()
    }
}

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

// MARK: - Configuration Initiale (inchangé)
struct InitialConfigurationView: View {
    @Binding var isPresented: Bool
    @Binding var hasConfiguredInitially: Bool
    let cameraManager: CameraManager
    @Binding var proximityAlertsEnabled: Bool
    @Binding var voiceInteractionEnabled: Bool
    
    @State private var enableLiDAR = true
    @State private var enableVibrations = true
    @State private var enableVoiceInteraction = true
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                VStack(spacing: 16) {
                    Image(systemName: "gearshape.2.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    
                    Text("Configuration Initiale")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Configurez votre expérience de détection avec interaction vocale")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top)
                
                VStack(spacing: 20) {
                    ConfigurationOptionView(
                        icon: "location.fill",
                        iconColor: enableLiDAR ? .blue : .gray,
                        title: "LiDAR",
                        description: cameraManager.lidarAvailable ?
                            "Mesure des distances en temps réel et alertes de proximité" :
                            "LiDAR non disponible sur cet appareil",
                        isEnabled: $enableLiDAR,
                        isAvailable: cameraManager.lidarAvailable
                    )
                    
                    ConfigurationOptionView(
                        icon: "iphone.radiowaves.left.and.right",
                        iconColor: enableVibrations ? .orange : .gray,
                        title: "Alertes de Proximité",
                        description: enableLiDAR ?
                            "Vibrations lorsque des objets sont détectés à proximité" :
                            "Nécessite LiDAR pour fonctionner",
                        isEnabled: $enableVibrations,
                        isAvailable: enableLiDAR
                    )
                    
                    ConfigurationOptionView(
                        icon: "mic.fill",
                        iconColor: enableVoiceInteraction ? .purple : .gray,
                        title: "Interaction Vocale",
                        description: "Appui long sur l'écran pour poser des questions : 'Y a-t-il une voiture ?', 'Décris la scène'",
                        isEnabled: $enableVoiceInteraction,
                        isAvailable: true
                    )
                }
                
                VStack(spacing: 16) {
                    Button(action: {
                        applyConfiguration()
                    }) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                            Text("Commencer la Détection")
                                .font(.headline)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                    }
                    
                    Button("Configurer plus tard") {
                        skipConfiguration()
                    }
                    .font(.body)
                    .foregroundColor(.secondary)
                }
                .padding(.bottom)
                
                Spacer()
            }
            .padding(.horizontal)
            .navigationBarHidden(true)
        }
        .onAppear {
            enableLiDAR = cameraManager.lidarAvailable
            enableVibrations = cameraManager.lidarAvailable
            enableVoiceInteraction = true
        }
        .onChange(of: enableLiDAR) { lidarEnabled in
            if !lidarEnabled {
                enableVibrations = false
            }
        }
    }
    
    private func applyConfiguration() {
        if enableLiDAR && cameraManager.lidarAvailable {
            let _ = cameraManager.enableLiDAR()
        } else {
            cameraManager.disableLiDAR()
        }
        
        proximityAlertsEnabled = enableVibrations && enableLiDAR
        cameraManager.enableProximityAlerts(proximityAlertsEnabled)
        voiceInteractionEnabled = enableVoiceInteraction
        
        hasConfiguredInitially = true
        isPresented = false
        
        cameraManager.playSuccessFeedback()
        cameraManager.startSession()
        
        // Plus d'activation automatique de l'interaction vocale
        
        print("✅ Configuration initiale appliquée:")
        print("   - LiDAR: \(enableLiDAR ? "✅" : "❌")")
        print("   - Vibrations: \(enableVibrations ? "✅" : "❌")")
        print("   - Interaction vocale: \(enableVoiceInteraction ? "✅ (touchez le micro)" : "❌")")
    }
    
    private func skipConfiguration() {
        if cameraManager.lidarAvailable {
            let _ = cameraManager.enableLiDAR()
            proximityAlertsEnabled = true
            cameraManager.enableProximityAlerts(true)
        }
        
        voiceInteractionEnabled = true
        hasConfiguredInitially = true
        isPresented = false
        cameraManager.startSession()
        
        print("⚡ Configuration par défaut appliquée: Tout activé (interaction vocale sur demande)")
    }
}

struct ConfigurationOptionView: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    @Binding var isEnabled: Bool
    let isAvailable: Bool
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title)
                .foregroundColor(iconColor)
                .frame(width: 40, height: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(isAvailable ? .primary : .secondary)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
            }
            
            Spacer()
            
            Toggle("", isOn: $isEnabled)
                .disabled(!isAvailable)
                .scaleEffect(1.1)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(UIColor.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
        .opacity(isAvailable ? 1.0 : 0.6)
    }
}
