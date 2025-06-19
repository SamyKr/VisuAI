import SwiftUI
import CoreML
import Vision

struct ContentView: View {
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Text("Détection d'objets YOLOv11")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding()
                
                VStack(spacing: 20) {
                    NavigationLink(destination: ImageDetectionView()) {
                        VStack {
                            Image(systemName: "photo")
                                .font(.system(size: 50))
                                .foregroundColor(.blue)
                            Text("Détecter sur image")
                                .font(.headline)
                                .foregroundColor(.blue)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(30)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(15)
                    }
                    
                    NavigationLink(destination: VideoDetectionView()) {
                        VStack {
                            Image(systemName: "video")
                                .font(.system(size: 50))
                                .foregroundColor(.purple)
                            Text("Détecter sur vidéo")
                                .font(.headline)
                                .foregroundColor(.purple)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(30)
                        .background(Color.purple.opacity(0.1))
                        .cornerRadius(15)
                    }
                    
                    NavigationLink(destination: CameraViewWithDetection()) {
                        VStack {
                            HStack {
                                Image(systemName: "camera")
                                    .font(.system(size: 40))
                                    .foregroundColor(.green)
                                
                                // Indicateur LiDAR sur le bouton principal
                                VStack {
                                    Image(systemName: "location.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(.blue)
                                    Text("LiDAR")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.blue)
                                }
                            }
                            
                            Text("Détecter en temps réel")
                                .font(.headline)
                                .foregroundColor(.green)
                            
                            Text("+ Distances LiDAR")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(30)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.green.opacity(0.1), Color.blue.opacity(0.05)]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .cornerRadius(15)
                        .overlay(
                            RoundedRectangle(cornerRadius: 15)
                                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                        )
                    }
                }
                
                Spacer()
                
                // Information sur le LiDAR
                LiDARAvailabilityView()
            }
            .padding()
            .navigationTitle("YOLOv11 Detector")
            .navigationBarHidden(true)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

// Vue d'information sur la disponibilité du LiDAR
struct LiDARAvailabilityView: View {
    @State private var lidarAvailable = false
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: lidarAvailable ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundColor(lidarAvailable ? .green : .orange)
                
                Text("LiDAR \(lidarAvailable ? "disponible" : "non disponible")")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            
            Text(lidarAvailable ?
                 "Les distances seront affichées en temps réel" :
                 "Compatible iPhone 12 Pro+ / iPad Pro 2020+")
                .font(.caption2)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .padding(12)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
        .onAppear {
            checkLiDARAvailability()
        }
    }
    
    private func checkLiDARAvailability() {
        let lidarManager = LiDARManager()
        lidarAvailable = lidarManager.isAvailable()
    }
}

struct ImageDetectionView: View {
    @State private var image: UIImage? = UIImage(named: "street")
    @State private var boundingBoxes: [(rect: CGRect, label: String, confidence: Float)] = []
    @State private var isDetecting = false
    @State private var inferenceTime: Double = 0.0
    @State private var showingLiDARNote = false
    
    private let objectDetectionManager = ObjectDetectionManager()
    
    var body: some View {
        VStack {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .overlay(
                        GeometryReader { geometry in
                            ForEach(boundingBoxes.indices, id: \.self) { index in
                                let detection = boundingBoxes[index]
                                let rect = detection.rect
                                
                                VStack {
                                    Rectangle()
                                        .stroke(Color.red, lineWidth: 2)
                                        .frame(
                                            width: rect.width * geometry.size.width,
                                            height: rect.height * geometry.size.height
                                        )
                                        .position(
                                            x: rect.midX * geometry.size.width,
                                            y: (1 - rect.midY) * geometry.size.height
                                        )
                                    
                                    Text("\(detection.label) (\(String(format: "%.1f", detection.confidence * 100))%)")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                        .background(Color.white.opacity(0.8))
                                        .cornerRadius(4)
                                        .position(
                                            x: rect.midX * geometry.size.width,
                                            y: (1 - rect.maxY) * geometry.size.height - 10
                                        )
                                }
                            }
                        }
                    )
            } else {
                Text("Image 'street.jpg' non trouvée")
                    .foregroundColor(.red)
            }
            
            VStack(spacing: 15) {
                Button(action: detectObjects) {
                    HStack {
                        if isDetecting {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.white)
                        } else {
                            Image(systemName: "viewfinder")
                        }
                        Text(isDetecting ? "Détection..." : "Détecter les objets")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isDetecting ? Color.gray : Color.blue)
                    .cornerRadius(10)
                }
                .disabled(isDetecting)
                
                // Note sur le LiDAR pour les images
                LiDARImageNoteView()
                
                // Affichage des résultats avec métriques de performance
                if !boundingBoxes.isEmpty {
                    VStack(spacing: 5) {
                        Text("\(boundingBoxes.count) objets détectés")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        HStack(spacing: 20) {
                            VStack {
                                Text("⏱️ Temps d'inférence")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Text("\(String(format: "%.1f", inferenceTime))ms")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.blue)
                            }
                            
                            VStack {
                                Text("🎯 FPS estimé")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Text("\(String(format: "%.1f", 1000.0 / inferenceTime))")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.green)
                            }
                        }
                        .padding(8)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                
                // Bouton pour afficher les statistiques détaillées
                if !boundingBoxes.isEmpty {
                    Button("📊 Voir les statistiques détaillées") {
                        print(objectDetectionManager.getPerformanceStats())
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
            }
            .padding()
        }
        .padding()
        .navigationTitle("Détection sur image")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            detectObjects()
        }
    }
    
    func detectObjects() {
        guard let image = image else {
            print("Aucune image trouvée")
            return
        }
        
        isDetecting = true
        
        objectDetectionManager.detectObjects(in: image) { detections, detectionTime in
            DispatchQueue.main.async {
                self.boundingBoxes = detections
                self.inferenceTime = detectionTime
                self.isDetecting = false
                
                print("YOLOv11 a détecté \(detections.count) objets en \(String(format: "%.1f", detectionTime))ms")
                for detection in detections {
                    print("- \(detection.label): \(String(format: "%.1f", detection.confidence * 100))%")
                }
            }
        }
    }
}

// Vue d'information sur LiDAR pour les images statiques
struct LiDARImageNoteView: View {
    @State private var lidarAvailable = false
    
    var body: some View {
        HStack {
            Image(systemName: "info.circle")
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Distances LiDAR")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text(lidarAvailable ?
                     "Disponible uniquement en mode temps réel" :
                     "Nécessite un appareil compatible LiDAR")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            if lidarAvailable {
                NavigationLink(destination: CameraViewWithDetection()) {
                    Text("Essayer")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(6)
                }
            }
        }
        .padding(10)
        .background(Color.blue.opacity(0.05))
        .cornerRadius(8)
        .onAppear {
            checkLiDARAvailability()
        }
    }
    
    private func checkLiDARAvailability() {
        let lidarManager = LiDARManager()
        lidarAvailable = lidarManager.isAvailable()
    }
}
