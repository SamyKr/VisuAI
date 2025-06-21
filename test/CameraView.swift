//
//  CameraView.swift (Version avec LiDAR + Tracking + ImportantObjectsBoard)
//  test
//
//  Created by Samy 📍 on 18/06/2025.
//  Updated with LiDAR integration - 19/06/2025
//  Updated with Object Tracking - 20/06/2025
//  Updated with ImportantObjectsBoard - 21/06/2025
//

import SwiftUI
import AVFoundation

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
    
    // NOUVELLE FONCTIONNALITÉ : Configuration initiale
    @State private var showingInitialConfiguration = false
    @State private var hasConfiguredInitially = false
    
    var body: some View {
        ZStack {
            CameraView(cameraManager: cameraManager)
                .onAppear {
                    setupCameraManager()
                    startImportantObjectsTimer()
                    if cameraManager.hasPermission {
                        cameraManager.startSession()
                    } else {
                        cameraManager.requestPermission()
                    }
                }
                .onReceive(cameraManager.$hasPermission) { hasPermission in
                    if hasPermission {
                        // Vérifier si on doit montrer la configuration initiale
                        if !hasConfiguredInitially {
                            showingInitialConfiguration = true
                        } else {
                            cameraManager.startSession()
                        }
                    }
                }
                .onDisappear {
                    cameraManager.stopSession()
                    stopImportantObjectsTimer()
                }
            
            // Overlay pour les bounding boxes avec couleurs de tracking
            GeometryReader { geometry in
                ForEach(boundingBoxes.indices, id: \.self) { index in
                    let detection = boundingBoxes[index]
                    let rect = detection.rect
                    let tracking = detection.trackingInfo
                    
                    ZStack {
                        // Bounding box avec couleur de tracking et opacité
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
                    
                    // Labels avec tracking ID et couleur
                    detectionLabelsView(for: detection, geometry: geometry, rect: rect)
                }
            }
            
            // HUD avec métriques de performance et contrôles LiDAR + Tracking
            VStack {
                // Top HUD - Métriques en temps réel
                topHUDView
                
                Spacer()
                
                // Panneau de statistiques détaillées
                if showingStats {
                    PerformanceStatsView(cameraManager: cameraManager)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                // Controls en bas avec LiDAR et Tracking
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
            
            // Bouton ImportantObjectsBoard (en haut à droite)
            VStack {
                HStack {
                    Spacer()
                    ImportantObjectsButton(
                        isVisible: $showingImportantObjects,
                        objectCount: importantObjects.count
                    )
                    .padding(.top, 100) // Ajuster selon la hauteur de votre topHUD
                    .padding(.trailing)
                }
                Spacer()
            }
        }
        .navigationTitle("Détection + LiDAR + Tracking")
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
                proximityAlertsEnabled: $proximityAlertsEnabled
            )
        }
        .animation(.easeInOut(duration: 0.3), value: showingStats)
        .animation(.easeInOut(duration: 0.3), value: showingImportantObjects)
    }
    
    // MARK: - View Components
    
    private var topHUDView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Circle()
                        .fill(cameraManager.isRunning ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(cameraManager.isRunning ? "LIVE" : "STOPPED")
                        .font(.caption)
                        .fontWeight(.bold)
                }
                
                Text("FPS: \(String(format: "%.1f", cameraManager.currentFPS))")
                    .font(.caption)
                    .fontWeight(.bold)
                
                // Compteur d'objets avec distinction actifs/mémoire
                let activeObjects = boundingBoxes.filter { $0.trackingInfo.opacity > 0.5 }.count
                let memoryObjects = boundingBoxes.filter { $0.trackingInfo.opacity <= 0.5 }.count
                
                HStack(spacing: 4) {
                    Text("🎯")
                        .font(.caption2)
                    Text("\(activeObjects)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                    if memoryObjects > 0 {
                        Text("+\(memoryObjects)")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
                
                // Compteur objets importants
                if importantObjects.count > 0 {
                    HStack(spacing: 4) {
                        Text("🏆")
                            .font(.caption2)
                        Text("\(importantObjects.count)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.yellow)
                        Text("VIP")
                            .font(.caption2)
                            .foregroundColor(.yellow)
                    }
                }
                
                // Status LiDAR et vibrations
                HStack(spacing: 4) {
                    Circle()
                        .fill(getLiDARStatusColor())
                        .frame(width: 6, height: 6)
                    Text("LiDAR")
                        .font(.caption2)
                        .fontWeight(.bold)
                    Text(getLiDARStatusText())
                        .font(.caption2)
                }
                
                // Status des alertes de proximité
                if cameraManager.lidarAvailable && cameraManager.isLiDAREnabled {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(proximityAlertsEnabled ? .orange : .gray)
                            .frame(width: 6, height: 6)
                        Text("📳")
                            .font(.caption2)
                        Text(proximityAlertsEnabled ? "ON" : "OFF")
                            .font(.caption2)
                            .fontWeight(.bold)
                    }
                }
            }
            .foregroundColor(.white)
            .padding(12)
            .background(Color.black.opacity(0.6))
            .cornerRadius(12)
            
            Spacer()
            
            // Boutons de contrôle avec LiDAR et Tracking
            controlButtonsView
        }
        .padding(.horizontal)
        .padding(.top)
    }
    
    private var controlButtonsView: some View {
        HStack(spacing: 12) {
            // Bouton reset tracking
            Button(action: {
                cameraManager.resetTracking()
                cameraManager.playSuccessFeedback()
                // Réinitialiser aussi le leaderboard
                importantObjects.removeAll()
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Color.purple.opacity(0.8))
                    .cornerRadius(12)
            }
            .onLongPressGesture {
                // Afficher les stats de tracking
                showingStats.toggle()
            }
            
            // Bouton LiDAR
            if cameraManager.lidarAvailable {
                Button(action: {
                    let success = cameraManager.toggleLiDAR()
                    if success {
                        cameraManager.playSuccessFeedback()
                    }
                }) {
                    Image(systemName: cameraManager.isLiDAREnabled ? "location.fill" : "location")
                        .font(.title2)
                        .foregroundColor(cameraManager.isLiDAREnabled ? .blue : .white)
                        .padding(12)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(12)
                }
                .onLongPressGesture {
                    showingLiDARInfo = true
                }
                
                // Bouton alertes de proximité (seulement si LiDAR activé)
                if cameraManager.isLiDAREnabled {
                    Button(action: {
                        proximityAlertsEnabled.toggle()
                        cameraManager.enableProximityAlerts(proximityAlertsEnabled)
                        cameraManager.playSelectionFeedback()
                    }) {
                        Image(systemName: proximityAlertsEnabled ? "bell.fill" : "bell.slash.fill")
                            .font(.title2)
                            .foregroundColor(proximityAlertsEnabled ? .orange : .gray)
                            .padding(12)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(12)
                    }
                    .onLongPressGesture {
                        showingLiDARInfo = true
                    }
                }
            }
            
            // Bouton paramètres
            Button(action: {
                showingSettings = true
                cameraManager.playSelectionFeedback()
            }) {
                Image(systemName: "gear")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(12)
            }
            
            // Bouton pour les statistiques détaillées
            Button(action: {
                showingStats.toggle()
                cameraManager.playSelectionFeedback()
            }) {
                Image(systemName: showingStats ? "chart.bar.fill" : "chart.bar")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(12)
            }
        }
    }
    
    private var bottomControlsView: some View {
        HStack {
            Button("Reset Stats") {
                cameraManager.resetPerformanceStats()
                // Réinitialiser aussi le leaderboard
                importantObjects.removeAll()
            }
            .font(.caption)
            .foregroundColor(.white)
            .padding(8)
            .background(Color.blue.opacity(0.7))
            .cornerRadius(8)
            
            Button("Reset Config") {
                hasConfiguredInitially = false
                showingInitialConfiguration = true
                cameraManager.stopSession()
            }
            .font(.caption)
            .foregroundColor(.white)
            .padding(8)
            .background(Color.purple.opacity(0.7))
            .cornerRadius(8)
            
            // Indicateurs compacts avec tracking
            HStack(spacing: 8) {
                // Indicateur tracking
                HStack(spacing: 4) {
                    Text("🎯")
                        .font(.caption)
                    
                    let activeCount = boundingBoxes.filter { $0.trackingInfo.opacity > 0.5 }.count
                    let memoryCount = boundingBoxes.filter { $0.trackingInfo.opacity <= 0.5 }.count
                    
                    Text("\(activeCount)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                    
                    if memoryCount > 0 {
                        Text("+\(memoryCount)")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.orange)
                    }
                }
                .padding(6)
                .background(Color.black.opacity(0.5))
                .cornerRadius(6)
                
                // Indicateur objets importants
                if importantObjects.count > 0 {
                    HStack(spacing: 4) {
                        Text("🏆")
                            .font(.caption)
                        
                        Text("\(importantObjects.count)")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.yellow)
                    }
                    .padding(6)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(6)
                    .onTapGesture {
                        showingImportantObjects.toggle()
                        cameraManager.playSelectionFeedback()
                    }
                }
                
                // Indicateurs LiDAR
                if cameraManager.lidarAvailable {
                    // Indicateur LiDAR
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .font(.caption)
                            .foregroundColor(cameraManager.isLiDAREnabled ? .blue : .gray)
                        
                        Text(cameraManager.isLiDAREnabled ? "ON" : "OFF")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(cameraManager.isLiDAREnabled ? .blue : .gray)
                    }
                    .padding(6)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(6)
                    
                    // Indicateur alertes de proximité (seulement si LiDAR activé)
                    if cameraManager.isLiDAREnabled {
                        HStack(spacing: 4) {
                            Text("📳")
                                .font(.caption)
                            
                            Text(proximityAlertsEnabled ? "ON" : "OFF")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(proximityAlertsEnabled ? .orange : .gray)
                        }
                        .padding(6)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(6)
                    }
                }
            }
            
            Spacer()
            
            Button(cameraManager.isRunning ? "Stop" : "Start") {
                if cameraManager.isRunning {
                    cameraManager.stopSession()
                } else {
                    if cameraManager.hasPermission {
                        cameraManager.startSession()
                    } else {
                        showingPermissionAlert = true
                    }
                }
            }
            .font(.headline)
            .foregroundColor(.white)
            .padding()
            .background(cameraManager.isRunning ? Color.red : Color.green)
            .cornerRadius(10)
        }
        .padding()
    }
    
    // MARK: - Detection Labels View avec Tracking
    private func detectionLabelsView(for detection: (rect: CGRect, label: String, confidence: Float, distance: Float?, trackingInfo: (id: Int, color: UIColor, opacity: Double)), geometry: GeometryProxy, rect: CGRect) -> some View {
        HStack(spacing: 4) {
            // ID de tracking avec couleur
            Text("#\(detection.trackingInfo.id)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(detection.trackingInfo.color).opacity(detection.trackingInfo.opacity))
                .cornerRadius(4)
            
            // Indicateur VIP si l'objet est dans le leaderboard
            if isObjectImportant(trackingId: detection.trackingInfo.id) {
                Text("🏆")
                    .font(.caption2)
            }
            
            // Label de l'objet
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
            
            // Distance LiDAR si disponible
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
                // Indicateur que la distance n'est pas disponible
                Text("--")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.6 * detection.trackingInfo.opacity))
                    .cornerRadius(3)
            }
            
            // Indicateur de statut (actif/mémoire)
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
    
    // MARK: - Helper Methods
    
    private func setupCameraManager() {
        cameraManager.delegate = CameraDetectionDelegate { newDetections in
            self.boundingBoxes = newDetections
        }
        
        // Activer automatiquement le LiDAR si disponible
        if cameraManager.lidarAvailable {
            let _ = cameraManager.enableLiDAR()
        }
        
        // Synchroniser l'état des alertes de proximité
        proximityAlertsEnabled = cameraManager.isProximityAlertsEnabled()
    }
    
    // MARK: - ImportantObjects Timer Management
    
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
        // Récupérer les objets importants du CameraManager
        let newImportantObjects = cameraManager.getTopImportantObjects(maxCount: 5)
        
        // Mettre à jour seulement si il y a des changements significatifs
        if !areImportantObjectsEqual(newImportantObjects, importantObjects) {
            withAnimation(.easeInOut(duration: 0.3)) {
                importantObjects = newImportantObjects
            }
        }
    }
    
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
    
    private func getLiDARStatusColor() -> Color {
        if !cameraManager.lidarAvailable {
            return .gray
        }
        return cameraManager.isLiDAREnabled ? .blue : .orange
    }
    
    private func getLiDARStatusText() -> String {
        if !cameraManager.lidarAvailable {
            return "N/A"
        }
        return cameraManager.isLiDAREnabled ? "ON" : "OFF"
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

// Delegate pour gérer les détections avec tracking et LiDAR
class CameraDetectionDelegate: CameraManagerDelegate {
    let onDetections: ([(rect: CGRect, label: String, confidence: Float, distance: Float?, trackingInfo: (id: Int, color: UIColor, opacity: Double))]) -> Void
    
    init(onDetections: @escaping ([(rect: CGRect, label: String, confidence: Float, distance: Float?, trackingInfo: (id: Int, color: UIColor, opacity: Double))]) -> Void) {
        self.onDetections = onDetections
    }
    
    func didDetectObjects(_ detections: [(rect: CGRect, label: String, confidence: Float, distance: Float?, trackingInfo: (id: Int, color: UIColor, opacity: Double))]) {
        onDetections(detections)
    }
}

// Vue pour afficher les statistiques détaillées avec LiDAR et Tracking
struct PerformanceStatsView: View {
    let cameraManager: CameraManager
    @State private var statsText = ""
    
    var body: some View {
        ScrollView {
            Text(statsText)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.white)
                .padding()
                .background(Color.black.opacity(0.8))
                .cornerRadius(12)
        }
        .frame(maxHeight: 200)
        .padding(.horizontal)
        .onAppear {
            updateStats()
        }
        .onReceive(Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()) { _ in
            updateStats()
        }
    }
    
    private func updateStats() {
        statsText = cameraManager.getPerformanceStats()
    }
}

// MARK: - Vue de Configuration Initiale (Version avec modes de performance)
struct InitialConfigurationView: View {
    @Binding var isPresented: Bool
    @Binding var hasConfiguredInitially: Bool
    let cameraManager: CameraManager
    @Binding var proximityAlertsEnabled: Bool
    
    @State private var enableLiDAR = true
    @State private var enableVibrations = true
    @State private var selectedPerformanceMode: PerformanceMode = .normal  // NOUVEAU
    
    var body: some View {
        NavigationView {
            ScrollView {  // Changé en ScrollView pour éviter les problèmes d'espace
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 16) {
                        Image(systemName: "gearshape.2.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)
                        
                        Text("Configuration Initiale")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("Configurez votre expérience de détection")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top)
                    
                    // NOUVELLE SECTION : Mode de Performance
                    VStack(spacing: 16) {
                        HStack {
                            Image(systemName: "speedometer")
                                .font(.title2)
                                .foregroundColor(.blue)
                            
                            Text("Mode de Performance")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            Spacer()
                        }
                        
                        Text("Choisissez l'équilibre entre performance et autonomie")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        // Sélecteur de modes
                        HStack(spacing: 12) {
                            ForEach(PerformanceMode.allCases, id: \.self) { mode in
                                InitialPerformanceModeButton(
                                    mode: mode,
                                    isSelected: selectedPerformanceMode == mode
                                ) {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        selectedPerformanceMode = mode
                                    }
                                }
                            }
                        }
                        
                        // Description du mode sélectionné
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: selectedPerformanceMode.icon)
                                    .foregroundColor(selectedPerformanceMode.color)
                                Text("Mode \(selectedPerformanceMode.displayName)")
                                    .fontWeight(.medium)
                                    .foregroundColor(selectedPerformanceMode.color)
                                Spacer()
                            }
                            
                            Text(selectedPerformanceMode.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        .padding()
                        .background(selectedPerformanceMode.color.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    
                    // Options de configuration existantes
                    VStack(spacing: 20) {
                        // Option LiDAR
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
                        
                        // Option Vibrations
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
                    }
                    
                    // Boutons d'action
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
                }
                .padding(.horizontal)
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            // Initialiser avec les capacités de l'appareil
            enableLiDAR = cameraManager.lidarAvailable
            enableVibrations = cameraManager.lidarAvailable
            
            // Initialiser le mode de performance selon la valeur actuelle
            let currentSkipFrames = cameraManager.getSkipFrames()
            selectedPerformanceMode = PerformanceMode.allCases.first { $0.skipFrames == currentSkipFrames } ?? .normal
        }
        .onChange(of: enableLiDAR) { lidarEnabled in
            // Si LiDAR est désactivé, désactiver aussi les vibrations
            if !lidarEnabled {
                enableVibrations = false
            }
        }
    }
    
    private func applyConfiguration() {
        // NOUVEAU : Appliquer le mode de performance
        cameraManager.setSkipFrames(selectedPerformanceMode.skipFrames)
        
        // Appliquer la configuration LiDAR
        if enableLiDAR && cameraManager.lidarAvailable {
            let _ = cameraManager.enableLiDAR()
        } else {
            cameraManager.disableLiDAR()
        }
        
        // Appliquer la configuration des vibrations
        proximityAlertsEnabled = enableVibrations && enableLiDAR
        cameraManager.enableProximityAlerts(proximityAlertsEnabled)
        
        // Marquer comme configuré et démarrer
        hasConfiguredInitially = true
        isPresented = false
        
        // Feedback de succès
        cameraManager.playSuccessFeedback()
        
        // Démarrer la session
        cameraManager.startSession()
        
        print("✅ Configuration initiale appliquée:")
        print("   - Mode performance: \(selectedPerformanceMode.displayName) (skip: \(selectedPerformanceMode.skipFrames))")
        print("   - LiDAR: \(enableLiDAR ? "✅" : "❌")")
        print("   - Vibrations: \(enableVibrations ? "✅" : "❌")")
    }
    
    private func skipConfiguration() {
        // Configuration par défaut avec mode normal
        selectedPerformanceMode = .normal
        cameraManager.setSkipFrames(selectedPerformanceMode.skipFrames)
        
        if cameraManager.lidarAvailable {
            let _ = cameraManager.enableLiDAR()
            proximityAlertsEnabled = true
            cameraManager.enableProximityAlerts(true)
        }
        
        hasConfiguredInitially = true
        isPresented = false
        cameraManager.startSession()
        
        print("⚡ Configuration par défaut appliquée: Mode \(selectedPerformanceMode.displayName)")
    }
}

// MARK: - Bouton de Mode de Performance pour Configuration Initiale
struct InitialPerformanceModeButton: View {
    let mode: PerformanceMode
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                Image(systemName: mode.icon)
                    .font(.title3)
                    .foregroundColor(isSelected ? .white : mode.color)
                
                Text(mode.displayName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(isSelected ? .white : mode.color)
                
                Text("\(mode.skipFrames)")
                    .font(.caption2)
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? mode.color : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(mode.color, lineWidth: isSelected ? 0 : 2)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Vue d'option de configuration (inchangée)
struct ConfigurationOptionView: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    @Binding var isEnabled: Bool
    let isAvailable: Bool
    
    var body: some View {
        HStack(spacing: 16) {
            // Icône
            Image(systemName: icon)
                .font(.title)
                .foregroundColor(iconColor)
                .frame(width: 40, height: 40)
            
            // Contenu
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
            
            // Toggle
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

