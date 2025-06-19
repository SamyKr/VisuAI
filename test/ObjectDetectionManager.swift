import CoreML
import Vision
import UIKit
import AVFoundation

class ObjectDetectionManager {
    private var model: VNCoreMLModel?
    
    // Configuration de détection améliorée
    private let confidenceThreshold: Float = 0.5
    private let maxDetections = 10
    
    // Classes à ignorer par défaut (modifiable)
    private var ignoredClasses = Set(["building", "vegetation", "road", "sidewalk", "ground", "wall", "fence"])
    private var activeClasses: Set<String> = []
    
    // Statistiques de performance
    private var inferenceHistory: [Double] = []
    private let maxHistorySize = 100
    
    // Statistiques LiDAR
    private var lidarDistanceHistory: [Float] = []
    private var successfulDistanceMeasurements = 0
    private var totalDistanceMeasurements = 0
    
    init() {
        loadModel()
    }
    
    private func loadModel() {
        do {
            let config = MLModelConfiguration()
            config.setValue(1, forKey: "experimentalMLE5EngineUsage")
            
            guard let modelURL = Bundle.main.url(forResource: "last", withExtension: "mlmodelc") else {
                print("❌ Modèle 'last.mlmodelc' non trouvé dans le bundle")
                return
            }
            
            print("✅ Modèle compilé trouvé: last.mlmodelc")
            
            let mlModel = try MLModel(contentsOf: modelURL, configuration: config)
            self.model = try VNCoreMLModel(for: mlModel)
            
        } catch {
            print("❌ Erreur lors du chargement du modèle: \(error)")
        }
    }
    
    // MARK: - Detection Methods (Legacy)
    func detectObjects(in image: UIImage, completion: @escaping ([(rect: CGRect, label: String, confidence: Float)], Double) -> Void) {
        guard let model = model else {
            print("❌ Modèle non chargé")
            completion([], 0.0)
            return
        }
        
        guard let ciImage = CIImage(image: image) else {
            print("❌ Impossible de convertir l'image")
            completion([], 0.0)
            return
        }
        
        performDetection(on: ciImage, with: model) { detections, inferenceTime in
            // Convertir au format legacy (sans distance)
            let legacyDetections = detections.map { (rect: $0.rect, label: $0.label, confidence: $0.confidence) }
            completion(legacyDetections, inferenceTime)
        }
    }
    
    func detectObjects(in pixelBuffer: CVPixelBuffer, completion: @escaping ([(rect: CGRect, label: String, confidence: Float)], Double) -> Void) {
        guard let model = model else {
            print("❌ Modèle non chargé")
            completion([], 0.0)
            return
        }
        
        let preprocessStart = CFAbsoluteTimeGetCurrent()
        let ciImage = preprocessPixelBuffer(pixelBuffer)
        let preprocessTime = (CFAbsoluteTimeGetCurrent() - preprocessStart) * 1000
        
        performDetection(on: ciImage, with: model, preprocessTime: preprocessTime) { detections, inferenceTime in
            // Convertir au format legacy (sans distance)
            let legacyDetections = detections.map { (rect: $0.rect, label: $0.label, confidence: $0.confidence) }
            completion(legacyDetections, inferenceTime)
        }
    }
    
    // MARK: - New LiDAR-Enhanced Detection Method
    func detectObjectsWithLiDAR(
        in pixelBuffer: CVPixelBuffer,
        depthData: AVDepthData?,
        lidarManager: LiDARManager,
        imageSize: CGSize,
        completion: @escaping ([(rect: CGRect, label: String, confidence: Float, distance: Float?)], Double) -> Void
    ) {
        guard let model = model else {
            print("❌ Modèle non chargé")
            completion([], 0.0)
            return
        }
        
        let preprocessStart = CFAbsoluteTimeGetCurrent()
        let ciImage = preprocessPixelBuffer(pixelBuffer)
        let preprocessTime = (CFAbsoluteTimeGetCurrent() - preprocessStart) * 1000
        
        performDetectionWithLiDAR(
            on: ciImage,
            with: model,
            depthData: depthData,
            lidarManager: lidarManager,
            imageSize: imageSize,
            preprocessTime: preprocessTime,
            completion: completion
        )
    }
    
    private func preprocessPixelBuffer(_ pixelBuffer: CVPixelBuffer) -> CIImage {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let orientedImage = ciImage.oriented(.right)
        
        return orientedImage
            .applyingFilter("CIColorControls", parameters: [
                "inputSaturation": 1.1,
                "inputBrightness": 0.0,
                "inputContrast": 1.1
            ])
    }
    
    // MARK: - Legacy Detection (without LiDAR)
    private func performDetection(
        on ciImage: CIImage,
        with model: VNCoreMLModel,
        preprocessTime: Double = 0.0,
        completion: @escaping ([(rect: CGRect, label: String, confidence: Float, distance: Float?)], Double) -> Void
    ) {
        let totalStartTime = CFAbsoluteTimeGetCurrent()
        
        let request = VNCoreMLRequest(model: model) { request, error in
            let totalInferenceTime = (CFAbsoluteTimeGetCurrent() - totalStartTime) * 1000
            
            if let error = error {
                print("❌ Erreur de détection: \(error)")
                completion([], totalInferenceTime)
                return
            }
            
            guard let results = request.results as? [VNRecognizedObjectObservation] else {
                print("❌ Aucun résultat de détection")
                completion([], totalInferenceTime)
                return
            }
            
            let postProcessStart = CFAbsoluteTimeGetCurrent()
            let detections = self.processDetectionsWithoutLiDAR(results)
            let postProcessTime = (CFAbsoluteTimeGetCurrent() - postProcessStart) * 1000
            
            self.updateInferenceStats(totalInferenceTime)
            
            self.printDetectionStats(
                detections: detections,
                totalTime: totalInferenceTime,
                preprocessTime: preprocessTime,
                postProcessTime: postProcessTime,
                withLiDAR: false
            )
            
            completion(detections, totalInferenceTime)
        }
        
        request.imageCropAndScaleOption = .scaleFill
        
        do {
            let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
            try handler.perform([request])
        } catch {
            let errorTime = (CFAbsoluteTimeGetCurrent() - totalStartTime) * 1000
            print("❌ Échec de la détection: \(error)")
            completion([], errorTime)
        }
    }
    
    // MARK: - LiDAR-Enhanced Detection
    private func performDetectionWithLiDAR(
        on ciImage: CIImage,
        with model: VNCoreMLModel,
        depthData: AVDepthData?,
        lidarManager: LiDARManager,
        imageSize: CGSize,
        preprocessTime: Double = 0.0,
        completion: @escaping ([(rect: CGRect, label: String, confidence: Float, distance: Float?)], Double) -> Void
    ) {
        let totalStartTime = CFAbsoluteTimeGetCurrent()
        
        let request = VNCoreMLRequest(model: model) { request, error in
            let totalInferenceTime = (CFAbsoluteTimeGetCurrent() - totalStartTime) * 1000
            
            if let error = error {
                print("❌ Erreur de détection: \(error)")
                completion([], totalInferenceTime)
                return
            }
            
            guard let results = request.results as? [VNRecognizedObjectObservation] else {
                print("❌ Aucun résultat de détection")
                completion([], totalInferenceTime)
                return
            }
            
            let postProcessStart = CFAbsoluteTimeGetCurrent()
            let detections = self.processDetectionsWithLiDAR(
                results,
                lidarManager: lidarManager,
                imageSize: imageSize
            )
            let postProcessTime = (CFAbsoluteTimeGetCurrent() - postProcessStart) * 1000
            
            self.updateInferenceStats(totalInferenceTime)
            
            self.printDetectionStats(
                detections: detections,
                totalTime: totalInferenceTime,
                preprocessTime: preprocessTime,
                postProcessTime: postProcessTime,
                withLiDAR: lidarManager.isEnabled()
            )
            
            completion(detections, totalInferenceTime)
        }
        
        request.imageCropAndScaleOption = .scaleFill
        
        do {
            let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
            try handler.perform([request])
        } catch {
            let errorTime = (CFAbsoluteTimeGetCurrent() - totalStartTime) * 1000
            print("❌ Échec de la détection: \(error)")
            completion([], errorTime)
        }
    }
    
    // MARK: - Detection Processing
    private func processDetectionsWithoutLiDAR(_ results: [VNRecognizedObjectObservation]) -> [(rect: CGRect, label: String, confidence: Float, distance: Float?)] {
        let filteredResults = results.filter { $0.confidence >= confidenceThreshold }
        let sortedResults = filteredResults.sorted { $0.confidence > $1.confidence }
        let limitedResults = Array(sortedResults.prefix(maxDetections))
        
        return limitedResults.compactMap { observation in
            let topLabel = observation.labels.first?.identifier ?? "Objet"
            let confidence = observation.confidence
            
            guard isClassAllowed(topLabel) else {
                return nil
            }
            
            let boundingBox = observation.boundingBox
            guard boundingBox.width > 0.01 && boundingBox.height > 0.01 else {
                return nil
            }
            
            return (rect: boundingBox, label: topLabel, confidence: confidence, distance: nil)
        }
    }
    
    private func processDetectionsWithLiDAR(
        _ results: [VNRecognizedObjectObservation],
        lidarManager: LiDARManager,
        imageSize: CGSize
    ) -> [(rect: CGRect, label: String, confidence: Float, distance: Float?)] {
        
        let filteredResults = results.filter { $0.confidence >= confidenceThreshold }
        let sortedResults = filteredResults.sorted { $0.confidence > $1.confidence }
        let limitedResults = Array(sortedResults.prefix(maxDetections))
        
        return limitedResults.compactMap { observation in
            let topLabel = observation.labels.first?.identifier ?? "Objet"
            let confidence = observation.confidence
            
            guard isClassAllowed(topLabel) else {
                return nil
            }
            
            let boundingBox = observation.boundingBox
            guard boundingBox.width > 0.01 && boundingBox.height > 0.01 else {
                return nil
            }
            
            // Calculer la distance LiDAR si disponible
            var distance: Float?
            if lidarManager.isEnabled() {
                totalDistanceMeasurements += 1
                
                distance = lidarManager.getDistanceForBoundingBox(boundingBox, imageSize: imageSize)
                
                if let dist = distance {
                    successfulDistanceMeasurements += 1
                    lidarDistanceHistory.append(dist)
                    
                    // Maintenir un historique limité
                    if lidarDistanceHistory.count > maxHistorySize {
                        lidarDistanceHistory.removeFirst()
                    }
                }
            }
            
            return (rect: boundingBox, label: topLabel, confidence: confidence, distance: distance)
        }
    }
    
    // MARK: - Statistics
    private func updateInferenceStats(_ inferenceTime: Double) {
        inferenceHistory.append(inferenceTime)
        
        if inferenceHistory.count > maxHistorySize {
            inferenceHistory.removeFirst()
        }
    }
    
    private func printDetectionStats(
        detections: [(rect: CGRect, label: String, confidence: Float, distance: Float?)],
        totalTime: Double,
        preprocessTime: Double,
        postProcessTime: Double,
        withLiDAR: Bool
    ) {
        let pureInferenceTime = totalTime - postProcessTime - preprocessTime
        
        print("🎯 YOLOv11\(withLiDAR ? " + LiDAR" : ""): \(detections.count) objets détectés avec confiance > \(confidenceThreshold)")
        print("⏱️ Temps d'exécution:")
        if preprocessTime > 0 {
            print("   - Préprocessing: \(String(format: "%.1f", preprocessTime))ms")
        }
        print("   - Inférence pure: \(String(format: "%.1f", pureInferenceTime))ms")
        print("   - Post-processing: \(String(format: "%.1f", postProcessTime))ms")
        print("   - TOTAL: \(String(format: "%.1f", totalTime))ms")
        print("   - FPS estimé: \(String(format: "%.1f", 1000.0 / totalTime))")
        
        if let avgTime = getAverageInferenceTime() {
            print("   - Moyenne (dernières \(inferenceHistory.count)): \(String(format: "%.1f", avgTime))ms")
        }
        
        // Statistiques LiDAR
        if withLiDAR && totalDistanceMeasurements > 0 {
            let successRate = Float(successfulDistanceMeasurements) / Float(totalDistanceMeasurements) * 100
            print("📏 LiDAR: \(successfulDistanceMeasurements)/\(totalDistanceMeasurements) mesures réussies (\(String(format: "%.1f", successRate))%)")
        }
        
        for detection in detections {
            var output = "   - \(detection.label): \(String(format: "%.1f", detection.confidence * 100))%"
            if let distance = detection.distance {
                let lidar = LiDARManager()
                output += " à \(lidar.formatDistance(distance))"
            }
            print(output)
        }
    }
    
    func getAverageInferenceTime() -> Double? {
        guard !inferenceHistory.isEmpty else { return nil }
        return inferenceHistory.reduce(0, +) / Double(inferenceHistory.count)
    }
    
    func getMinMaxInferenceTime() -> (min: Double, max: Double)? {
        guard !inferenceHistory.isEmpty else { return nil }
        return (inferenceHistory.min()!, inferenceHistory.max()!)
    }
    
    func getPerformanceStats() -> String {
        guard !inferenceHistory.isEmpty else {
            return "📊 Aucune statistique disponible"
        }
        
        let avg = getAverageInferenceTime()!
        let (min, max) = getMinMaxInferenceTime()!
        let avgFPS = 1000.0 / avg
        
        var stats = "📊 Statistiques de performance (\(inferenceHistory.count) inférences):\n"
        stats += "   - Temps moyen: \(String(format: "%.1f", avg))ms\n"
        stats += "   - Temps min: \(String(format: "%.1f", min))ms\n"
        stats += "   - Temps max: \(String(format: "%.1f", max))ms\n"
        stats += "   - FPS moyen: \(String(format: "%.1f", avgFPS))\n"
        
        let variance = inferenceHistory.map { pow($0 - avg, 2) }.reduce(0, +) / Double(inferenceHistory.count)
        let stdDev = sqrt(variance)
        stats += "   - Écart-type: \(String(format: "%.1f", stdDev))ms\n"
        
        // Statistiques LiDAR
        if totalDistanceMeasurements > 0 {
            let successRate = Float(successfulDistanceMeasurements) / Float(totalDistanceMeasurements) * 100
            stats += "\n📏 Statistiques LiDAR:\n"
            stats += "   - Mesures tentées: \(totalDistanceMeasurements)\n"
            stats += "   - Mesures réussies: \(successfulDistanceMeasurements) (\(String(format: "%.1f", successRate))%)\n"
            
            if !lidarDistanceHistory.isEmpty {
                let avgDistance = lidarDistanceHistory.reduce(0, +) / Float(lidarDistanceHistory.count)
                let minDistance = lidarDistanceHistory.min()!
                let maxDistance = lidarDistanceHistory.max()!
                
                stats += "   - Distance moyenne: \(String(format: "%.1f", avgDistance))m\n"
                stats += "   - Distance min/max: \(String(format: "%.1f", minDistance))m - \(String(format: "%.1f", maxDistance))m"
            }
        }
        
        return stats
    }
    
    func resetStats() {
        inferenceHistory.removeAll()
        lidarDistanceHistory.removeAll()
        successfulDistanceMeasurements = 0
        totalDistanceMeasurements = 0
        print("📊 Statistiques de performance réinitialisées")
    }
    
    // MARK: - Class Management
    func addIgnoredClass(_ className: String) {
        ignoredClasses.insert(className.lowercased())
    }
    
    func removeIgnoredClass(_ className: String) {
        ignoredClasses.remove(className.lowercased())
    }
    
    func getIgnoredClasses() -> [String] {
        return Array(ignoredClasses).sorted()
    }
    
    func setActiveClasses(_ classes: [String]) {
        activeClasses = Set(classes.map { $0.lowercased() })
    }
    
    func getActiveClasses() -> [String] {
        return Array(activeClasses).sorted()
    }
    
    private func isClassAllowed(_ className: String) -> Bool {
        let lowercaseName = className.lowercased()
        
        if ignoredClasses.contains(lowercaseName) {
            return false
        }
        
        if activeClasses.isEmpty {
            return true
        }
        
        return activeClasses.contains(lowercaseName)
    }
}
