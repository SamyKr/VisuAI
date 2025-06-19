//
//  CameraView.swift
//  test
//
//  Created by Samy 📍 on 18/06/2025.
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
    @State private var boundingBoxes: [(rect: CGRect, label: String, confidence: Float, distance: Float?)] = []
    @State private var showingStats = false
    @State private var showingPermissionAlert = false
    @State private var showingSettings = false
    
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
            
            // Overlay pour les bounding boxes
            GeometryReader { geometry in
                ForEach(boundingBoxes.indices, id: \.self) { index in
                    let detection = boundingBoxes[index]
                    let rect = detection.rect
                    
                    ZStack {
                        // Bounding box
                        Rectangle()
                            .stroke(Color.red, lineWidth: 3)
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
                    
                    // Label avec confiance et distance
                    VStack(spacing: 2) {
                        HStack(spacing: 4) {
                            Text(detection.label)
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red)
                                .cornerRadius(4)
                            
                            Text("\(String(format: "%.0f", detection.confidence * 100))%")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.red.opacity(0.8))
                                .cornerRadius(3)
                        }
                        
                        // Distance sous la confiance si LiDAR activé et disponible
                        if cameraManager.isLiDAREnabled {
                            if let distance = detection.distance {
                                // Distance réelle du LiDAR
                                Text("📏 \(String(format: "%.1f", distance))m")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.blue)
                                    .cornerRadius(3)
                            } else {
                                // TEST : Distance factice pour vérifier l'interface
                                let testDistance = Float.random(in: 0.5...5.0)
                                Text("📏 \(String(format: "%.1f", testDistance))m TEST")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.orange)  // Orange pour distinguer le test
                                    .cornerRadius(3)
                            }
                        }
                    }
                    .position(
                        x: rect.midX * geometry.size.width,
                        y: (1 - rect.maxY) * geometry.size.height - 15
                    )
                }
            }
            
            // HUD avec métriques de performance
            VStack {
                // Top HUD - Métriques en temps réel
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
                        
                        Text("Objets: \(boundingBoxes.count)")
                            .font(.caption)
                        
                        if cameraManager.isLiDARAvailable {
                            HStack(spacing: 4) {
                                Image(systemName: "dot.radiowaves.left.and.right")
                                    .foregroundColor(cameraManager.isLiDAREnabled ? .blue : .gray)
                                    .font(.caption)
                                Text(cameraManager.isLiDAREnabled ? "LiDAR" : "No LiDAR")
                                    .font(.caption)
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(12)
                    
                    Spacer()
                    
                    // Boutons de contrôle
                    HStack(spacing: 12) {
                        // Bouton paramètres
                        Button(action: { showingSettings = true }) {
                            Image(systemName: "gear")
                                .font(.title2)
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(12)
                        }
                        
                        // Bouton pour les statistiques détaillées
                        Button(action: { showingStats.toggle() }) {
                            Image(systemName: showingStats ? "chart.bar.fill" : "chart.bar")
                                .font(.title2)
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(12)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top)
                
                Spacer()
                
                // Panneau de statistiques détaillées
                if showingStats {
                    PerformanceStatsView(cameraManager: cameraManager)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                // Controls en bas
                HStack {
                    Button("Reset Stats") {
                        cameraManager.resetPerformanceStats()
                    }
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Color.blue.opacity(0.7))
                    .cornerRadius(8)
                    
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
        }
        .navigationTitle("Détection Temps Réel")
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
        .sheet(isPresented: $showingSettings) {
            DetectionSettingsView(isPresented: $showingSettings, cameraManager: cameraManager)
        }
        .animation(.easeInOut(duration: 0.3), value: showingStats)
    }
    
    private func setupCameraManager() {
        cameraManager.delegate = CameraDetectionDelegate { newDetections in
            self.boundingBoxes = newDetections
            
            // Debug : Vérifier les distances reçues
            print("📱 Interface reçoit \(newDetections.count) détections:")
            for detection in newDetections {
                let distanceText = detection.distance != nil ? "\(String(format: "%.1f", detection.distance!))m" : "NO DISTANCE"
                print("   - \(detection.label): \(distanceText)")
            }
        }
    }
}

// Delegate pour gérer les détections avec métriques et distance
class CameraDetectionDelegate: CameraManagerDelegate {
    let onDetections: ([(rect: CGRect, label: String, confidence: Float, distance: Float?)]) -> Void
    
    init(onDetections: @escaping ([(rect: CGRect, label: String, confidence: Float, distance: Float?)]) -> Void) {
        self.onDetections = onDetections
    }
    
    func didDetectObjects(_ detections: [(rect: CGRect, label: String, confidence: Float, distance: Float?)]) {
        onDetections(detections)
    }
}

// Vue pour afficher les statistiques détaillées
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
