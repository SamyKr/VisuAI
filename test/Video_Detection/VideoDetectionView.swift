//
//  VideoDetectionView.swift
//  test
//
//  Created by Samy 📍 on 18/06/2025.
//

import SwiftUI
import AVFoundation
import PhotosUI
import UniformTypeIdentifiers

struct VideoDetectionView: View {
    @State private var selectedVideoURL: URL?
    @State private var isPickerPresented = false
    @State private var isProcessing = false
    @State private var detections: [(rect: CGRect, label: String, confidence: Float)] = []
    @State private var showingSettings = false
    
    // Video player
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    
    // Processing stats
    @State private var processedFrames = 0
    @State private var totalFrames = 0
    @State private var processingProgress: Double = 0
    @State private var averageInferenceTime: Double = 0
    
    // Managers
    @StateObject private var videoManager = VideoDetectionManager()
    
    var body: some View {
        VStack(spacing: 0) {
            if let player = player {
                videoPlayerSection(player: player)
                videoControlsSection
            } else {
                videoSelectionSection
            }
            
            Spacer()
        }
        .navigationTitle("Détection sur Vidéo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingSettings = true }) {
                    Image(systemName: "gear")
                }
            }
        }
        .sheet(isPresented: $isPickerPresented) {
            VideoPicker(selectedURL: $selectedVideoURL)
        }
        .sheet(isPresented: $showingSettings) {
            VideoDetectionSettingsView(
                isPresented: $showingSettings,
                videoManager: videoManager
            )
        }
        .onChange(of: selectedVideoURL) { url in
            if let url = url {
                setupVideo(url: url)
            }
        }
        .onReceive(videoManager.$currentDetections) { detections in
            self.detections = detections
        }
        .onReceive(videoManager.$processingStats) { stats in
            self.processedFrames = stats.processedFrames
            self.totalFrames = stats.totalFrames
            self.processingProgress = stats.progress
            self.averageInferenceTime = stats.averageInferenceTime
        }
    }
    
    // MARK: - Video Player Section
    @ViewBuilder
    private func videoPlayerSection(player: AVPlayer) -> some View {
        GeometryReader { geometry in
            ZStack {
                VideoPlayerView(player: player, currentTime: $currentTime, duration: $duration)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .background(Color.black)
                
                // Overlay des détections avec les mêmes dimensions
                ForEach(detections.indices, id: \.self) { index in
                    let detection = detections[index]
                    let rect = detection.rect
                    
                    ZStack {
                        Rectangle()
                            .stroke(Color.green, lineWidth: 2)
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
                    
                    // Label
                    HStack(spacing: 4) {
                        Text(detection.label)
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.green)
                            .cornerRadius(3)
                        
                        Text("\(String(format: "%.0f", detection.confidence * 100))%")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.8))
                            .cornerRadius(2)
                    }
                    .position(
                        x: rect.midX * geometry.size.width,
                        y: (1 - rect.maxY) * geometry.size.height - 8
                    )
                }
                
                // Processing overlay
                if isProcessing {
                    processingOverlayView
                }
                
                // HUD avec stats
                videoHUDView
            }
        }
        .background(Color.black)
    }
    
    // MARK: - Video Selection Section
    @ViewBuilder
    private var videoSelectionSection: some View {
        VStack(spacing: 30) {
            Image(systemName: "video.badge.plus")
                .font(.system(size: 80))
                .foregroundColor(.purple)
            
            Text("Sélectionner une vidéo")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Choisissez une vidéo depuis votre galerie pour y appliquer la détection d'objets")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button(action: { isPickerPresented = true }) {
                HStack {
                    Image(systemName: "photo.on.rectangle")
                    Text("Ouvrir la galerie")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.purple)
                .cornerRadius(12)
            }
            .padding(.horizontal)
            
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Accès direct à votre galerie")
                            .font(.caption)
                    }
                    
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Tous formats vidéo supportés")
                            .font(.caption)
                    }
                    
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Traitement optimisé")
                            .font(.caption)
                    }
                }
                .foregroundColor(.secondary)
                
                Spacer()
            }
            .padding(.horizontal)
        }
        .padding()
    }
    
    // MARK: - Video HUD
    @ViewBuilder
    private var videoHUDView: some View {
        VStack {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Circle()
                            .fill(isProcessing ? Color.orange : (isPlaying ? Color.green : Color.red))
                            .frame(width: 8, height: 8)
                        
                        Text(isProcessing ? "ANALYSING" : (isPlaying ? "PLAYING" : "PAUSED"))
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                    
                    Text("Objets: \(detections.count)")
                        .font(.caption)
                        .foregroundColor(.white)
                    
                    if isProcessing {
                        Text("Frame: \(processedFrames)/\(totalFrames)")
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                    
                    if averageInferenceTime > 0 {
                        Text("Inf: \(String(format: "%.1f", averageInferenceTime))ms")
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                }
                .padding(8)
                .background(Color.black.opacity(0.6))
                .cornerRadius(8)
                
                Spacer()
            }
            .padding()
            
            Spacer()
        }
    }
    
    // MARK: - Processing Overlay
    @ViewBuilder
    private var processingOverlayView: some View {
        ZStack {
            Color.black.opacity(0.7)
            
            VStack(spacing: 16) {
                ProgressView(value: processingProgress)
                    .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                    .frame(width: 200)
                
                Text("Traitement en cours...")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text("\(processedFrames)/\(totalFrames) frames")
                    .font(.caption)
                    .foregroundColor(.white)
                
                if averageInferenceTime > 0 {
                    Text("Temps moyen: \(String(format: "%.1f", averageInferenceTime))ms/frame")
                        .font(.caption)
                        .foregroundColor(.white)
                }
                
                Button("Annuler") {
                    videoManager.stopProcessing()
                }
                .font(.caption)
                .foregroundColor(.red)
                .padding(.top)
            }
        }
    }
    
    // MARK: - Video Controls
    @ViewBuilder
    private var videoControlsSection: some View {
        VStack(spacing: 12) {
            // Timeline
            if duration > 0 {
                HStack {
                    Text(timeString(currentTime))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Slider(value: Binding(
                        get: { currentTime },
                        set: { newValue in
                            player?.seek(to: CMTime(seconds: newValue, preferredTimescale: 600))
                        }
                    ), in: 0...duration)
                    
                    Text(timeString(duration))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
            }
            
            // Control buttons
            HStack(spacing: 24) {
                Button(action: {
                    selectedVideoURL = nil
                    player = nil
                    detections = []
                    isProcessing = false
                }) {
                    Image(systemName: "xmark.circle")
                        .font(.title2)
                        .foregroundColor(.red)
                }
                
                Button(action: togglePlayPause) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title)
                        .foregroundColor(.blue)
                }
                
                Button(action: startProcessing) {
                    HStack {
                        if isProcessing {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "brain")
                        }
                        Text(isProcessing ? "Traitement..." : "Détecter")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(isProcessing ? Color.gray : Color.green)
                    .cornerRadius(20)
                }
                .disabled(isProcessing)
            }
            .padding()
        }
        .background(Color(.systemGray6))
    }
    
    // MARK: - Methods
    private func setupVideo(url: URL) {
        player = AVPlayer(url: url)
        
        // Passer le player au manager pour la synchronisation
        videoManager.setupVideo(url: url, player: player)
        
        // Observer pour le temps de lecture avec mise à jour des détections
        player?.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { time in
            let timeSeconds = time.seconds
            self.currentTime = timeSeconds
            
            // Mettre à jour les détections pour le temps courant (seulement si on ne traite pas)
            if !self.isProcessing {
                self.videoManager.updateDetectionsForCurrentTime(timeSeconds)
            }
        }
        
        // Observer pour la durée
        if let duration = player?.currentItem?.asset.duration.seconds, !duration.isNaN {
            self.duration = duration
        }
    }
    
    private func togglePlayPause() {
        if isPlaying {
            player?.pause()
        } else {
            player?.play()
        }
        isPlaying.toggle()
    }
    
    private func startProcessing() {
        guard let url = selectedVideoURL else { return }
        isProcessing = true
        videoManager.processVideo(url: url) { completed in
            DispatchQueue.main.async {
                isProcessing = false
                if completed {
                    print("✅ Traitement vidéo terminé")
                }
            }
        }
    }
    
    private func timeString(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Video Picker avec accès à la galerie
struct VideoPicker: UIViewControllerRepresentable {
    @Binding var selectedURL: URL?
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .videos  // Seulement les vidéos
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current
        
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: VideoPicker
        
        init(_ parent: VideoPicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let result = results.first else {
                parent.dismiss()
                return
            }
            
            // Obtenir l'URL de la vidéo
            if result.itemProvider.canLoadObject(ofClass: URL.self) {
                result.itemProvider.loadObject(ofClass: URL.self) { [weak self] url, error in
                    DispatchQueue.main.async {
                        if let videoURL = url as? URL {
                            self?.parent.selectedURL = videoURL
                        } else if let error = error {
                            print("❌ Erreur lors du chargement de la vidéo: \(error)")
                        }
                        self?.parent.dismiss()
                    }
                }
            } else {
                // Alternative : copier le fichier vers un dossier temporaire
                result.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { [weak self] url, error in
                    guard let url = url, error == nil else {
                        print("❌ Erreur lors du chargement: \(error?.localizedDescription ?? "Inconnue")")
                        DispatchQueue.main.async {
                            self?.parent.dismiss()
                        }
                        return
                    }
                    
                    // Copier vers un dossier temporaire accessible
                    let tempDirectory = FileManager.default.temporaryDirectory
                    let tempURL = tempDirectory.appendingPathComponent(UUID().uuidString + ".mov")
                    
                    do {
                        try FileManager.default.copyItem(at: url, to: tempURL)
                        DispatchQueue.main.async {
                            self?.parent.selectedURL = tempURL
                            self?.parent.dismiss()
                        }
                    } catch {
                        print("❌ Erreur lors de la copie: \(error)")
                        DispatchQueue.main.async {
                            self?.parent.dismiss()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Video Player View
struct VideoPlayerView: UIViewRepresentable {
    let player: AVPlayer
    @Binding var currentTime: Double
    @Binding var duration: Double
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspect
        view.layer.addSublayer(playerLayer)
        
        // Observer pour la durée
        if let item = player.currentItem {
            let duration = item.asset.duration.seconds
            if !duration.isNaN {
                DispatchQueue.main.async {
                    self.duration = duration
                }
            }
        }
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if let playerLayer = uiView.layer.sublayers?.first as? AVPlayerLayer {
            playerLayer.frame = uiView.bounds
        }
    }
}
