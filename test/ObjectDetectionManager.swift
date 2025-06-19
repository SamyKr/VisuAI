import CoreML
import Vision
import UIKit

class ObjectDetectionManager {
    private var model: VNCoreMLModel?
    
    // Configuration de détection améliorée
    private let confidenceThreshold: Float = 0.5  // Plus strict
    private let maxDetections = 10  // Limite le nombre de détections
    
    // Classes à ignorer par défaut (modifiable)
    private var ignoredClasses = Set(["building", "vegetation", "road", "sidewalk", "ground", "wall", "fence"])
    private var activeClasses: Set<String> = []  // Si vide, toutes les classes sont actives
    
    // Statistiques de performance
    private var inferenceHistory: [Double] = []
    private let maxHistorySize = 100
    
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
        
        performDetection(on: ciImage, with: model, completion: completion)
    }
    
    func detectObjects(in pixelBuffer: CVPixelBuffer, completion: @escaping ([(rect: CGRect, label: String, confidence: Float)], Double) -> Void) {
        guard let model = model else {
            print("❌ Modèle non chargé")
            completion([], 0.0)
            return
        }
        
        // Mesure du temps de préprocessing
        let preprocessStart = CFAbsoluteTimeGetCurrent()
        let ciImage = preprocessPixelBuffer(pixelBuffer)
        let preprocessTime = (CFAbsoluteTimeGetCurrent() - preprocessStart) * 1000
        
        performDetection(on: ciImage, with: model, preprocessTime: preprocessTime, completion: completion)
    }
    
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
    
    private func performDetection(on ciImage: CIImage, with model: VNCoreMLModel, preprocessTime: Double = 0.0, completion: @escaping ([(rect: CGRect, label: String, confidence: Float)], Double) -> Void) {
        
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
            let detections = self.processDetections(results)
            let postProcessTime = (CFAbsoluteTimeGetCurrent() - postProcessStart) * 1000
            
            // Calcul du temps d'inférence pure (sans post-processing)
            let pureInferenceTime = totalInferenceTime - postProcessTime - preprocessTime
            
            // Stockage des statistiques
            self.updateInferenceStats(totalInferenceTime)
            
            // Affichage détaillé des temps
            print("🎯 YOLOv11: \(detections.count) objets détectés avec confiance > \(self.confidenceThreshold)")
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
            
            for detection in detections {
                print("   - \(detection.label): \(String(format: "%.1f", detection.confidence * 100))%")
            }
            
            completion(detections, totalInferenceTime)
        }
        
        // Configuration de la requête
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
    
    private func processDetections(_ results: [VNRecognizedObjectObservation]) -> [(rect: CGRect, label: String, confidence: Float)] {
        
        // Filtrage par confiance
        let filteredResults = results.filter { $0.confidence >= confidenceThreshold }
        
        // Tri par confiance (meilleurs d'abord)
        let sortedResults = filteredResults.sorted { $0.confidence > $1.confidence }
        
        // Limitation du nombre de détections
        let limitedResults = Array(sortedResults.prefix(maxDetections))
        
        // Conversion en format final avec filtrage des classes ignorées
        return limitedResults.compactMap { observation in
            let topLabel = observation.labels.first?.identifier ?? "Objet"
            let confidence = observation.confidence
            
            // Vérifier si la classe est autorisée
            if !isClassAllowed(topLabel) {
                print("🚫 Classe filtrée: \(topLabel)")
                return nil
            }
            
            // Validation de la bounding box
            let boundingBox = observation.boundingBox
            guard boundingBox.width > 0.01 && boundingBox.height > 0.01 else {
                print("⚠️ Bounding box trop petite ignorée: \(boundingBox)")
                return nil
            }
            
            return (rect: boundingBox, label: topLabel, confidence: confidence)
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
}
