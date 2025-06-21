//
//  CameraView.swift (Version avec LiDAR + Tracking)
//  test
//
//  Created by Samy 📍 on 18/06/2025.
//  Updated with LiDAR integration - 19/06/2025
//  Updated with Object Tracking - 20/06/2025
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
    
    var body: some View {
        ZStack {
            CameraView(cameraManager: cameraManager)
                .onAppear {
                    setupCameraManager()
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
        .animation(.easeInOut(duration: 0.3), value: showingStats)
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
            }
            .font(.caption)
            .foregroundColor(.white)
            .padding(8)
            .background(Color.blue.opacity(0.7))
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
            """
        } else {
            return """
            LiDAR disponible mais désactivé. 
            
            Touchez l'icône de localisation 📍 pour l'activer et bénéficier de:
            • Affichage des distances en temps réel
            • Alertes de proximité par vibration
            • Bounding boxes colorées selon la distance
            
            🎯 Le tracking fonctionne sans LiDAR avec des couleurs persistantes par objet.
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
