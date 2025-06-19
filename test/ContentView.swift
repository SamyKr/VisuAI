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
                            Image(systemName: "camera")
                                .font(.system(size: 50))
                                .foregroundColor(.green)
                            Text("Détecter en temps réel")
                                .font(.headline)
                                .foregroundColor(.green)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(30)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(15)
                    }
                }
                
                Spacer()
                
                Text("Choisissez un mode de détection")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .padding()
            .navigationTitle("YOLOv11 Detector")
            .navigationBarHidden(true)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

struct ImageDetectionView: View {
    @State private var image: UIImage? = UIImage(named: "street")
    @State private var boundingBoxes: [(rect: CGRect, label: String, confidence: Float)] = []
    @State private var isDetecting = false
    @State private var inferenceTime: Double = 0.0
    
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
                                            y: (1 - rect.midY) * geometry.size.height // Inversion Y
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
        
        // CORRECTION : Ajout du paramètre inferenceTime dans la closure
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
