//
//  VideoDetectionManager.swift
//  test
//
//  Created by Samy 📍 on 18/06/2025.
//  Updated with color tracking - 20/06/2025
//

import Foundation
import AVFoundation
import Vision
import SwiftUI

// Structure pour les statistiques de processing
struct ProcessingStats {
    let processedFrames: Int
    let totalFrames: Int
    let progress: Double
    let averageInferenceTime: Double
}

class VideoDetectionManager: ObservableObject {
    // Mise à jour avec le nouveau format de tracking
    @Published var currentDetections: [(rect: CGRect, label: String, confidence: Float, distance: Float?, trackingInfo: (id: Int, color: UIColor, opacity: Double))] = []
    @Published var processingStats = ProcessingStats(processedFrames: 0, totalFrames: 0, progress: 0.0, averageInferenceTime: 0.0)
    
    private let objectDetectionManager = ObjectDetectionManager()
    private var videoAsset: AVAsset?
    private var currentPlayer: AVPlayer?  // Référence au player pour la synchronisation
    private var isProcessing = false
    private var processingQueue = DispatchQueue(label: "video.processing.queue", qos: .userInitiated)
    
    // Stockage des détections par timestamp - format mis à jour
    private var detectionsByTime: [Double: [(rect: CGRect, label: String, confidence: Float, distance: Float?, trackingInfo: (id: Int, color: UIColor, opacity: Double))]] = [:]
    private var processedTimestamps: Set<Double> = []
    
    // Configuration
    private var skipFrames = 10  // Traiter 1 frame sur 11 par défaut pour les vidéos
    private var activeClasses: Set<String> = []
    
    // Stats de traitement
    private var inferenceHistory: [Double] = []
    private var processedFrameCount = 0
    private var totalFrameCount = 0
    
    func setupVideo(url: URL, player: AVPlayer? = nil) {
        videoAsset = AVAsset(url: url)
        currentPlayer = player
        resetStats()
    }
    
    func processVideo(url: URL, completion: @escaping (Bool) -> Void) {
        guard !isProcessing else { return }
        
        isProcessing = true
        resetStats()
        
        processingQueue.async { [weak self] in
            self?.processVideoFrames(url: url, completion: completion)
        }
    }
    
    func stopProcessing() {
        isProcessing = false
        DispatchQueue.main.async {
            self.processingStats = ProcessingStats(
                processedFrames: self.processedFrameCount,
                totalFrames: self.totalFrameCount,
                progress: 1.0,
                averageInferenceTime: self.getAverageInferenceTime()
            )
        }
    }
    
    private func processVideoFrames(url: URL, completion: @escaping (Bool) -> Void) {
        let asset = AVAsset(url: url)
        
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            print("❌ Impossible de trouver la piste vidéo")
            DispatchQueue.main.async {
                completion(false)
            }
            return
        }
        
        // Récupérer les dimensions natives de la vidéo
        let videoSize = videoTrack.naturalSize.applying(videoTrack.preferredTransform)
        let nativeWidth = abs(videoSize.width)
        let nativeHeight = abs(videoSize.height)
        
        print("📐 Dimensions natives de la vidéo: \(nativeWidth) x \(nativeHeight)")
        
        // Configuration du générateur d'images
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceAfter = .zero
        imageGenerator.requestedTimeToleranceBefore = .zero
        
        // Calcul des timestamps à traiter
        let duration = asset.duration.seconds
        let frameRate = videoTrack.nominalFrameRate
        let totalFrames = Int(duration * Double(frameRate))
        let framesToProcess = totalFrames / (skipFrames + 1)
        
        self.totalFrameCount = framesToProcess
        
        DispatchQueue.main.async {
            self.processingStats = ProcessingStats(
                processedFrames: 0,
                totalFrames: framesToProcess,
                progress: 0.0,
                averageInferenceTime: 0.0
            )
        }
        
        var timestamps: [CMTime] = []
        for i in 0..<framesToProcess {
            let timeSeconds = Double(i * (skipFrames + 1)) / Double(frameRate)
            let time = CMTime(seconds: timeSeconds, preferredTimescale: 600)
            timestamps.append(time)
        }
        
        print("🎬 Traitement de \(framesToProcess) frames sur \(totalFrames) (\(skipFrames + 1) skip)")
        print("🎨 Tracking coloré activé pour les vidéos")
        
        // Traitement des frames
        var processedCount = 0
        let group = DispatchGroup()
        
        for (index, timestamp) in timestamps.enumerated() {
            guard isProcessing else { break }
            
            group.enter()
            
            imageGenerator.generateCGImagesAsynchronously(forTimes: [NSValue(time: timestamp)]) { [weak self] _, cgImage, _, result, error in
                defer { group.leave() }
                
                guard let self = self,
                      let cgImage = cgImage,
                      result == .succeeded else {
                    if let error = error {
                        print("❌ Erreur génération image à \(timestamp.seconds)s: \(error.localizedDescription)")
                    } else {
                        print("❌ Échec génération image à \(timestamp.seconds)s - result: \(result.rawValue)")
                    }
                    return
                }
                
                // Conversion plus robuste en CIImage
                let ciImage = CIImage(cgImage: cgImage)
                
                // Vérification de la validité de l'image
                guard !ciImage.extent.isEmpty else {
                    print("❌ Image vide à \(timestamp.seconds)s")
                    return
                }
                
                // Mesure du temps d'inférence
                let startTime = CFAbsoluteTimeGetCurrent()
                
                // Détection synchrone pour le traitement vidéo avec tracking
                self.performSyncDetection(on: ciImage, originalSize: CGSize(width: nativeWidth, height: nativeHeight)) { detections in
                    let inferenceTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                    self.inferenceHistory.append(inferenceTime)
                    
                    // Stocker les détections avec leur timestamp
                    let timeSeconds = timestamp.seconds
                    self.detectionsByTime[timeSeconds] = detections
                    self.processedTimestamps.insert(timeSeconds)
                    
                    processedCount += 1
                    self.processedFrameCount = processedCount
                    
                    // Mise à jour des stats ET des détections sur le main thread
                    DispatchQueue.main.async {
                        // IMPORTANT: Mettre à jour les détections en temps réel pour l'affichage
                        self.currentDetections = detections
                        
                        // Synchroniser la vidéo avec la frame traitée
                        if let player = self.getCurrentPlayer() {
                            player.seek(to: timestamp)
                        }
                        
                        // Mettre à jour les statistiques
                        self.processingStats = ProcessingStats(
                            processedFrames: processedCount,
                            totalFrames: framesToProcess,
                            progress: Double(processedCount) / Double(framesToProcess),
                            averageInferenceTime: self.getAverageInferenceTime()
                        )
                    }
                    
                    if processedCount % 10 == 0 {
                        let activeObjects = detections.filter { $0.trackingInfo.opacity > 0.5 }.count
                        let memoryObjects = detections.filter { $0.trackingInfo.opacity <= 0.5 }.count
                        print("📊 Traité: \(processedCount)/\(framesToProcess) frames - Avg: \(String(format: "%.1f", self.getAverageInferenceTime()))ms - Objets: \(activeObjects) + \(memoryObjects) mémoire")
                    }
                }
            }
            
            // Attendre un peu entre les frames pour permettre l'affichage
            Thread.sleep(forTimeInterval: 0.1)  // 100ms entre chaque frame pour voir les détections
        }
        
        // Attendre que toutes les détections soient terminées
        group.notify(queue: DispatchQueue.main) {
            self.isProcessing = false
            print("✅ Traitement vidéo terminé: \(processedCount) frames traitées avec tracking coloré")
            completion(true)
        }
    }
    
    // Mise à jour de la signature pour le nouveau format avec tracking
    private func performSyncDetection(on ciImage: CIImage, originalSize: CGSize, completion: @escaping ([(rect: CGRect, label: String, confidence: Float, distance: Float?, trackingInfo: (id: Int, color: UIColor, opacity: Double))]) -> Void) {
        // Version synchrone de la détection pour le traitement vidéo avec tracking
        let semaphore = DispatchSemaphore(value: 0)
        var result: [(rect: CGRect, label: String, confidence: Float, distance: Float?, trackingInfo: (id: Int, color: UIColor, opacity: Double))] = []
        
        // Convertir CIImage en UIImage de manière plus robuste
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            print("❌ Impossible de créer CGImage depuis CIImage")
            completion([])
            semaphore.signal()
            return
        }
        
        let uiImage = UIImage(cgImage: cgImage)
        
        // Utiliser la nouvelle méthode avec tracking (pas de LiDAR pour les vidéos, donc distance = nil)
        objectDetectionManager.detectObjects(in: uiImage) { detections, _ in
            // Convertir les coordonnées du modèle (640x640) vers la taille native de la vidéo
            let convertedDetections = self.convertDetectionsToNativeSize(detections,
                                                                         originalSize: originalSize,
                                                                         modelSize: CGSize(width: 640, height: 640))
            result = convertedDetections
            semaphore.signal()
        }
        
        semaphore.wait()
        completion(result)
    }
    
    // Convertit les coordonnées des détections du modèle vers la taille native - Mise à jour pour le tracking
    private func convertDetectionsToNativeSize(_ detections: [(rect: CGRect, label: String, confidence: Float, distance: Float?, trackingInfo: (id: Int, color: UIColor, opacity: Double))],
                                               originalSize: CGSize,
                                               modelSize: CGSize) -> [(rect: CGRect, label: String, confidence: Float, distance: Float?, trackingInfo: (id: Int, color: UIColor, opacity: Double))] {
        
        // Le modèle utilise 640x640 avec aspect ratio préservé
        let scaleX = modelSize.width / originalSize.width
        let scaleY = modelSize.height / originalSize.height
        let scale = min(scaleX, scaleY)
        
        // Taille réelle utilisée par le modèle (avec aspect ratio préservé)
        let scaledWidth = originalSize.width * scale
        let scaledHeight = originalSize.height * scale
        
        // Offset pour centrer l'image dans le carré 640x640
        let offsetX = (modelSize.width - scaledWidth) / 2
        let offsetY = (modelSize.height - scaledHeight) / 2
        
        return detections.map { detection in
            var rect = detection.rect
            
            // Convertir de coordonnées normalisées (0-1) vers pixels du modèle
            let modelX = rect.origin.x * modelSize.width
            let modelY = rect.origin.y * modelSize.height
            let modelWidth = rect.width * modelSize.width
            let modelHeight = rect.height * modelSize.height
            
            // Ajuster pour l'offset et le scaling
            let adjustedX = (modelX - offsetX) / scale
            let adjustedY = (modelY - offsetY) / scale
            let adjustedWidth = modelWidth / scale
            let adjustedHeight = modelHeight / scale
            
            // Reconvertir en coordonnées normalisées pour la taille native
            rect.origin.x = adjustedX / originalSize.width
            rect.origin.y = adjustedY / originalSize.height
            rect.size.width = adjustedWidth / originalSize.width
            rect.size.height = adjustedHeight / originalSize.height
            
            // Assurer que les coordonnées restent dans les limites [0, 1]
            rect.origin.x = max(0, min(1, rect.origin.x))
            rect.origin.y = max(0, min(1, rect.origin.y))
            rect.size.width = max(0, min(1 - rect.origin.x, rect.size.width))
            rect.size.height = max(0, min(1 - rect.origin.y, rect.size.height))
            
            return (rect: rect, label: detection.label, confidence: detection.confidence, distance: detection.distance, trackingInfo: detection.trackingInfo)
        }
    }
    
    private func getAverageInferenceTime() -> Double {
        guard !inferenceHistory.isEmpty else { return 0.0 }
        return inferenceHistory.reduce(0, +) / Double(inferenceHistory.count)
    }
    
    private func resetStats() {
        inferenceHistory.removeAll()
        processedFrameCount = 0
        totalFrameCount = 0
        detectionsByTime.removeAll()
        processedTimestamps.removeAll()
        
        // Reset du tracking pour les nouvelles vidéos
        objectDetectionManager.resetTracking()
        
        DispatchQueue.main.async {
            self.processingStats = ProcessingStats(
                processedFrames: 0,
                totalFrames: 0,
                progress: 0.0,
                averageInferenceTime: 0.0
            )
            self.currentDetections = []
        }
    }
    
    // MARK: - Configuration
    
    func setSkipFrames(_ count: Int) {
        skipFrames = max(0, count)
        print("⚙️ Skip frames vidéo défini à: \(skipFrames)")
    }
    
    func getSkipFrames() -> Int {
        return skipFrames
    }
    
    func setActiveClasses(_ classes: [String]) {
        objectDetectionManager.setActiveClasses(classes)
    }
    
    func getActiveClasses() -> [String] {
        return objectDetectionManager.getActiveClasses()
    }
    
    func resetTracking() {
        objectDetectionManager.resetTracking()
        print("🔄 Tracking vidéo réinitialisé")
    }
    
    func getPerformanceStats() -> String {
        guard !inferenceHistory.isEmpty else {
            return "📊 Aucune statistique vidéo disponible"
        }
        
        let avg = getAverageInferenceTime()
        let min = inferenceHistory.min() ?? 0
        let max = inferenceHistory.max() ?? 0
        
        var stats = "📹 Statistiques de traitement vidéo:\n"
        stats += "   - Frames traitées: \(processedFrameCount)\n"
        stats += "   - Temps moyen: \(String(format: "%.1f", avg))ms/frame\n"
        stats += "   - Temps min: \(String(format: "%.1f", min))ms\n"
        stats += "   - Temps max: \(String(format: "%.1f", max))ms\n"
        stats += "   - Skip frames: \(skipFrames)\n"
        
        // Ajouter les stats de tracking
        stats += "\n" + objectDetectionManager.getTrackingStats()
        
        return stats
    }
    
    private func getCurrentPlayer() -> AVPlayer? {
        return currentPlayer
    }
    
    // MARK: - Détections en temps réel pendant la lecture (Mise à jour avec tracking)
    
    func getDetectionsForTime(_ time: Double) -> [(rect: CGRect, label: String, confidence: Float, distance: Float?, trackingInfo: (id: Int, color: UIColor, opacity: Double))] {
        // Trouver le timestamp le plus proche qui a été traité
        let tolerance = 0.5 // Tolérance de 0.5 secondes
        
        let closestTime = processedTimestamps.min { abs($0 - time) < abs($1 - time) }
        
        if let timestamp = closestTime, abs(timestamp - time) <= tolerance {
            return detectionsByTime[timestamp] ?? []
        }
        
        return []
    }
    
    func updateDetectionsForCurrentTime(_ time: Double) {
        let detections = getDetectionsForTime(time)
        DispatchQueue.main.async {
            self.currentDetections = detections
        }
    }
}
