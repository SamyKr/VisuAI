import CoreML
import Vision
import UIKit
import AVFoundation

class ObjectDetectionManager {
    private var model: VNCoreMLModel?
    
    // Configuration de détection améliorée
    private let confidenceThreshold: Float = 0.5  // Plus strict
    private let maxDetections = 10  // Limite le nombre de détections
    
    // Classes à ignorer par défaut (modifiable)
    private var ignoredClasses = Set(["building", "vegetation", "road", "sidewalk", "ground", "wall", "fence"])
    private var activeClasses: Set<String> = []  // Si vide, toutes les classes sont actives
    
    // Configuration LiDAR
    private var isLiDAREnabled = false
    private var currentDepthData: CVPixelBuffer?
    
    // Statistiques de performance
    private var inferenceHistory: [Double] = []
    private let maxHistorySize = 100
    
    // Taille du modèle
    private let modelInputSize = CGSize(width: 640, height: 640)
    
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
    
    // MARK: - Méthodes publiques de détection
    
    // Version pour images (sans LiDAR)
    func detectObjects(in image: UIImage, completion: @escaping ([(rect: CGRect, label: String, confidence: Float)], Double) -> Void) {
        detectObjectsWithDistance(in: image) { detectionsWithDistance, time in
            // Convertir vers l'ancien format sans distance
            let detections = detectionsWithDistance.map { (rect: $0.rect, label: $0.label, confidence: $0.confidence) }
            completion(detections, time)
        }
    }
    
    // Version pour pixelBuffer avec LiDAR optionnel
    func detectObjects(in pixelBuffer: CVPixelBuffer, depthData: CVPixelBuffer? = nil, completion: @escaping ([(rect: CGRect, label: String, confidence: Float, distance: Float?)], Double) -> Void) {
        guard let model = model else {
            print("❌ Modèle non chargé")
            completion([], 0.0)
            return
        }
        
        // Stocker les données de profondeur pour le calcul de distance
        currentDepthData = depthData
        if depthData != nil {
            print("📡 ObjectDetectionManager: Données depth reçues")
        }
        
        // Mesure du temps de préprocessing
        let preprocessStart = CFAbsoluteTimeGetCurrent()
        let ciImage = preprocessPixelBuffer(pixelBuffer)
        let preprocessTime = (CFAbsoluteTimeGetCurrent() - preprocessStart) * 1000
        
        let originalSize = CGSize(width: CVPixelBufferGetWidth(pixelBuffer),
                                 height: CVPixelBufferGetHeight(pixelBuffer))
        
        // Préprocessing optimisé pour 640x640
        let preprocessedImage = preprocessImageFor640x640(ciImage)
        performDetectionWithDistance(on: preprocessedImage, with: model, originalImageSize: originalSize, preprocessTime: preprocessTime, completion: completion)
    }
    
    // Version pour vidéo (utilisée par VideoDetectionManager)
    func detectObjectsInVideo(in image: UIImage, completion: @escaping ([(rect: CGRect, label: String, confidence: Float, distance: Float?)], Double) -> Void) {
        detectObjectsWithDistance(in: image, completion: completion)
    }
    
    // MARK: - Méthodes privées de détection avec distance
    
    private func detectObjectsWithDistance(in image: UIImage, completion: @escaping ([(rect: CGRect, label: String, confidence: Float, distance: Float?)], Double) -> Void) {
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
        
        // Préprocessing pour adapter à 640x640
        let preprocessedImage = preprocessImageFor640x640(ciImage)
        performDetectionWithDistance(on: preprocessedImage, with: model, originalImageSize: image.size, completion: completion)
    }
    
    private func performDetectionWithDistance(on ciImage: CIImage, with model: VNCoreMLModel, originalImageSize: CGSize, preprocessTime: Double = 0.0, completion: @escaping ([(rect: CGRect, label: String, confidence: Float, distance: Float?)], Double) -> Void) {
        
        // Démarrage du chrono pour l'inférence complète
        let totalStartTime = CFAbsoluteTimeGetCurrent()
        
        let request = VNCoreMLRequest(model: model) { request, error in
            // Fin du chrono
            let totalInferenceTime = (CFAbsoluteTimeGetCurrent() - totalStartTime) * 1000 // en ms
            
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
            
            // Mesure du temps de post-processing
            let postProcessStart = CFAbsoluteTimeGetCurrent()
            let detections = self.processDetectionsWithDistance(results, originalImageSize: originalImageSize)
            let postProcessTime = (CFAbsoluteTimeGetCurrent() - postProcessStart) * 1000
            
            // Calcul du temps d'inférence pure (sans post-processing)
            let pureInferenceTime = totalInferenceTime - postProcessTime - preprocessTime
            
            // Stockage des statistiques
            self.updateInferenceStats(totalInferenceTime)
            
            // Affichage détaillé des temps
            print("🎯 YOLOv11 (640x640): \(detections.count) objets détectés")
            print("⏱️ Temps d'exécution:")
            if preprocessTime > 0 {
                print("   - Préprocessing: \(String(format: "%.1f", preprocessTime))ms")
            }
            print("   - Inférence pure: \(String(format: "%.1f", pureInferenceTime))ms")
            print("   - Post-processing: \(String(format: "%.1f", postProcessTime))ms")
            print("   - TOTAL: \(String(format: "%.1f", totalInferenceTime))ms")
            print("   - FPS estimé: \(String(format: "%.1f", 1000.0 / totalInferenceTime))")
            
            // Affichage des statistiques moyennes
            if let avgTime = self.getAverageInferenceTime() {
                print("   - Moyenne (dernières \(self.inferenceHistory.count)): \(String(format: "%.1f", avgTime))ms")
            }
            
            // DEBUG: Affichage détaillé des détections avec distance
            for detection in detections {
                let distanceText = detection.distance != nil ? " - \(String(format: "%.1f", detection.distance!))m" : " - NO DIST"
                print("   - \(detection.label): \(String(format: "%.1f", detection.confidence * 100))%\(distanceText)")
            }
            
            completion(detections, totalInferenceTime)
        }
        
        // Configuration de la requête
        request.imageCropAndScaleOption = .scaleFit  // Maintient l'aspect ratio
        
        // Configuration additionnelle pour améliorer les performances
        if #available(iOS 14.0, *) {
            request.usesCPUOnly = false  // Utilise le GPU/Neural Engine
        }
        
        do {
            let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
            try handler.perform([request])
        } catch {
            let errorTime = (CFAbsoluteTimeGetCurrent() - totalStartTime) * 1000
            print("❌ Échec de la détection: \(error)")
            completion([], errorTime)
        }
    }
    
    // MARK: - Preprocessing
    
    private func preprocessPixelBuffer(_ pixelBuffer: CVPixelBuffer) -> CIImage {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        // Correction d'orientation pour la caméra
        let orientedImage = ciImage.oriented(.right)  // Ajuste selon ton setup
        
        // Optionnel : amélioration de l'image
        return orientedImage
            .applyingFilter("CIColorControls", parameters: [
                "inputSaturation": 1.1,  // Légère amélioration des couleurs
                "inputBrightness": 0.0,
                "inputContrast": 1.1
            ])
    }
    
    private func preprocessImageFor640x640(_ ciImage: CIImage) -> CIImage {
        let imageSize = ciImage.extent.size
        
        // Calcul du ratio pour maintenir l'aspect ratio
        let scaleX = modelInputSize.width / imageSize.width
        let scaleY = modelInputSize.height / imageSize.height
        let scale = min(scaleX, scaleY)  // Utilise le plus petit ratio pour éviter la déformation
        
        // Redimensionnement en gardant l'aspect ratio
        let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        
        // Centrage dans un carré 640x640
        let scaledSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let offsetX = (modelInputSize.width - scaledSize.width) / 2
        let offsetY = (modelInputSize.height - scaledSize.height) / 2
        
        let centeredImage = scaledImage.transformed(by: CGAffineTransform(translationX: offsetX, y: offsetY))
        
        // Création d'un fond noir 640x640
        let blackBackground = CIImage(color: CIColor.black).cropped(to: CGRect(origin: .zero, size: modelInputSize))
        
        // Composition de l'image centrée sur le fond noir
        let finalImage = centeredImage.composited(over: blackBackground)
        
        return finalImage
    }
    
    // MARK: - Processing avec distance
    
    private func processDetectionsWithDistance(_ results: [VNRecognizedObjectObservation], originalImageSize: CGSize) -> [(rect: CGRect, label: String, confidence: Float, distance: Float?)] {
        
        // Calcul des ratios pour reconvertir les coordonnées
        let scaleX = modelInputSize.width / originalImageSize.width
        let scaleY = modelInputSize.height / originalImageSize.height
        let scale = min(scaleX, scaleY)
        
        let scaledSize = CGSize(width: originalImageSize.width * scale, height: originalImageSize.height * scale)
        let offsetX = (modelInputSize.width - scaledSize.width) / 2
        let offsetY = (modelInputSize.height - scaledSize.height) / 2
        
        // Filtrage par confiance
        let filteredResults = results.filter { $0.confidence >= confidenceThreshold }
        
        // Tri par confiance (meilleurs d'abord)
        let sortedResults = filteredResults.sorted { $0.confidence > $1.confidence }
        
        // Limitation du nombre de détections
        let limitedResults = Array(sortedResults.prefix(maxDetections))
        
        // Conversion avec correction des coordonnées et calcul de distance
        return limitedResults.compactMap { observation in
            let topLabel = observation.labels.first?.identifier ?? "object"
            let confidence = observation.confidence
            
            // Vérifier si la classe est autorisée
            if !isClassAllowed(topLabel) {
                print("🚫 Classe filtrée: \(topLabel)")
                return nil
            }
            
            // Récupération de la bounding box (normalisée 0-1)
            var boundingBox = observation.boundingBox
            
            // Correction des coordonnées pour l'image originale
            // Vision utilise un système de coordonnées avec origine en bas-gauche
            boundingBox.origin.y = 1.0 - boundingBox.origin.y - boundingBox.height
            
            // Validation de la taille minimale
            guard boundingBox.width > 0.01 && boundingBox.height > 0.01 else {
                return nil
            }
            
            // Calcul de la distance si LiDAR est activé et disponible
            let distance = calculateDistance(for: boundingBox, imageSize: originalImageSize)
            
            return (rect: boundingBox, label: topLabel, confidence: confidence, distance: distance)
        }
    }
    
    // MARK: - Méthodes de statistiques de performance
    
    private func updateInferenceStats(_ inferenceTime: Double) {
        inferenceHistory.append(inferenceTime)
        
        // Maintenir un historique limité
        if inferenceHistory.count > maxHistorySize {
            inferenceHistory.removeFirst()
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
        
        // Calcul de la variance pour la stabilité
        let variance = inferenceHistory.map { pow($0 - avg, 2) }.reduce(0, +) / Double(inferenceHistory.count)
        let stdDev = sqrt(variance)
        stats += "   - Écart-type: \(String(format: "%.1f", stdDev))ms"
        
        return stats
    }
    
    func resetStats() {
        inferenceHistory.removeAll()
        print("📊 Statistiques de performance réinitialisées")
    }
    
    // MARK: - Configuration des classes ignorées
    
    func addIgnoredClass(_ className: String) {
        ignoredClasses.insert(className.lowercased())
        print("🚫 Classe ajoutée à la liste d'ignorés: \(className)")
    }
    
    func removeIgnoredClass(_ className: String) {
        ignoredClasses.remove(className.lowercased())
        print("✅ Classe retirée de la liste d'ignorés: \(className)")
    }
    
    func getIgnoredClasses() -> [String] {
        return Array(ignoredClasses).sorted()
    }
    
    // MARK: - Configuration des classes actives
    
    func setActiveClasses(_ classes: [String]) {
        activeClasses = Set(classes.map { $0.lowercased() })
        print("⚙️ Classes actives définies: \(classes.count) classes")
    }
    
    func getActiveClasses() -> [String] {
        return Array(activeClasses).sorted()
    }
    
    private func isClassAllowed(_ className: String) -> Bool {
        let lowercaseName = className.lowercased()
        
        // Vérifier si la classe est ignorée
        if ignoredClasses.contains(lowercaseName) {
            return false
        }
        
        // Si activeClasses est vide, toutes les classes non-ignorées sont autorisées
        if activeClasses.isEmpty {
            return true
        }
        
        // Sinon, vérifier si la classe est dans la liste active
        return activeClasses.contains(lowercaseName)
    }
    
    // MARK: - LiDAR Distance Calculation
    
    func setLiDAREnabled(_ enabled: Bool) {
        isLiDAREnabled = enabled
        print("📡 LiDAR \(enabled ? "activé" : "désactivé")")
    }
    
    func isLiDARSupported() -> Bool {
        // Vérifier si l'appareil supporte le LiDAR
        if #available(iOS 14.0, *) {
            return AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back) != nil
        }
        return false
    }
    
    private func calculateDistance(for boundingBox: CGRect, imageSize: CGSize) -> Float? {
        guard isLiDAREnabled, let depthData = currentDepthData else {
            print("🚫 LiDAR: Pas de données depth (enabled: \(isLiDAREnabled), data: \(currentDepthData != nil))")
            return nil
        }
        
        print("📡 LiDAR: Calcul distance pour box: \(boundingBox)")
        
        // Convertir la bounding box en coordonnées pixel
        let centerX = Int((boundingBox.midX * imageSize.width).rounded())
        let centerY = Int((boundingBox.midY * imageSize.height).rounded())
        
        print("📡 LiDAR: Centre de la box: (\(centerX), \(centerY))")
        
        // Échantillonner plusieurs points dans la bounding box pour obtenir une distance moyenne
        var depths: [Float] = []
        let sampleSize = 5 // Grille 5x5 dans la bounding box
        
        let boxWidth = Int((boundingBox.width * imageSize.width).rounded())
        let boxHeight = Int((boundingBox.height * imageSize.height).rounded())
        
        for i in 0..<sampleSize {
            for j in 0..<sampleSize {
                let x = centerX - boxWidth/4 + (i * boxWidth) / (sampleSize * 2)
                let y = centerY - boxHeight/4 + (j * boxHeight) / (sampleSize * 2)
                
                if let depth = getDepthValue(at: CGPoint(x: x, y: y), from: depthData, imageSize: imageSize) {
                    depths.append(depth)
                    print("📡 LiDAR: Point (\(x), \(y)) = \(depth)m")
                }
            }
        }
        
        // Retourner la médiane pour éviter les valeurs aberrantes
        guard !depths.isEmpty else {
            print("🚫 LiDAR: Aucune valeur de profondeur trouvée")
            return nil
        }
        
        depths.sort()
        let medianIndex = depths.count / 2
        let distance = depths[medianIndex]
        print("✅ LiDAR: Distance calculée: \(distance)m")
        return distance
    }
    
    private func getDepthValue(at point: CGPoint, from depthData: CVPixelBuffer, imageSize: CGSize) -> Float? {
        let depthWidth = CVPixelBufferGetWidth(depthData)
        let depthHeight = CVPixelBufferGetHeight(depthData)
        
        // Normaliser les coordonnées vers la résolution du depth buffer
        let normalizedX = point.x / imageSize.width
        let normalizedY = point.y / imageSize.height
        
        let depthX = Int((normalizedX * CGFloat(depthWidth)).rounded())
        let depthY = Int((normalizedY * CGFloat(depthHeight)).rounded())
        
        // Vérifier les limites
        guard depthX >= 0, depthX < depthWidth, depthY >= 0, depthY < depthHeight else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(depthData, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthData, .readOnly) }
        
        let baseAddress = CVPixelBufferGetBaseAddress(depthData)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthData)
        
        // Le format de depth est généralement kCVPixelFormatType_DepthFloat32
        let pixelFormat = CVPixelBufferGetPixelFormatType(depthData)
        
        if pixelFormat == kCVPixelFormatType_DepthFloat32 {
            let depthPointer = baseAddress!.assumingMemoryBound(to: Float32.self)
            let pixelIndex = depthY * (bytesPerRow / MemoryLayout<Float32>.size) + depthX
            let depth = depthPointer[pixelIndex]
            
            // Filtrer les valeurs invalides (NaN, infini, ou trop grandes)
            guard depth.isFinite, depth > 0, depth < 50 else { return nil }
            
            return depth
        }
        
        return nil
    }
}
