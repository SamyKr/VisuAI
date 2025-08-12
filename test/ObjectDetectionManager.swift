//
//  ObjectDetectionManager.swift
//  VizAI Vision
//
//  Gestionnaire principal pour la détection d'objets en temps réel utilisant YOLOv11 et Core ML.
//
//  Architecture:
//  - Détection d'objets temps réel avec modèle YOLOv11 (49 classes)
//  - Integration LiDAR pour mesures de distance précises
//  - Système de tracking multi-objets avec identifiants persistants
//  - Calcul de scores d'importance pour priorisation des alertes
//  - Thread-safe avec queues dédiées pour performance optimale
//
//  Fonctionnalités principales:
//  - Détection simultanée RGB + profondeur LiDAR
//  - Tracking persistant avec couleurs uniques par objet
//  - Système de scoring adaptatif pour l'accessibilité
//  - Gestion dynamique des classes détectées
//  - Statistiques de performance détaillées
//

import CoreML
import Vision
import UIKit
import AVFoundation

class ObjectDetectionManager: ObservableObject {
    
    // MARK: - Properties
    
    private var model: VNCoreMLModel?
    
    /// Classes supportées par le modèle YOLOv11
    static let MODEL_CLASSES: [String] = [
        "sidewalk", "road", "crosswalk", "driveway", "bike_lane", "parking_area",
        "rail_track", "service_lane", "wall", "fence", "curb", "guard_rail",
        "temporary_barrier", "barrier_other", "pole", "car", "truck", "bus",
        "motorcycle", "bicycle", "slow_vehicle", "vehicle_group", "rail_vehicle",
        "boat", "person", "cyclist", "motorcyclist", "traffic_light", "traffic_sign",
        "street_light", "traffic_cone", "bench", "trash_can", "fire_hydrant",
        "mailbox", "parking_meter", "bike_rack", "phone_booth", "pothole",
        "manhole", "catch_basin", "water_valve", "junction_box", "building",
        "bridge", "tunnel", "garage", "vegetation", "water", "terrain", "animals"
    ]
    
    @Published var modelClasses: [String] = MODEL_CLASSES
    
    // Configuration de détection
    private let confidenceThreshold: Float = 0.7
    private let maxDetections = 25
    
    // Gestion des classes
    private var ignoredClasses = Set(["building", "vegetation", "terrain", "water"])
    private var dangerousObjects: Set<String> = []
    
    // Système de tracking
    private let objectTracker = ObjectTracker()
    
    // Statistiques
    private var inferenceHistory: [Double] = []
    private let maxHistorySize = 100
    private var lidarDistanceHistory: [Float] = []
    private var successfulDistanceMeasurements = 0
    private var totalDistanceMeasurements = 0
    
    // Thread safety
    private let processingQueue = DispatchQueue(label: "detection.processing", qos: .userInitiated)
    private let modelQueue = DispatchQueue(label: "model.access", qos: .userInitiated)
    private let statsQueue = DispatchQueue(label: "stats.access", qos: .utility)
    
    /// Poids d'importance par défaut pour chaque classe d'objet
    private var importanceWeights: [String: Float] = [
        "person": 1.0, "cyclist": 0.95, "motorcyclist": 0.9,
        "car": 0.85, "truck": 0.85, "bus": 0.85, "motorcycle": 0.8, "bicycle": 0.8,
        "slow vehicle": 0.75, "vehicle group": 0.8, "rail vehicle": 0.7, "boat": 0.5,
        "traffic light": 0.9, "traffic sign": 0.85, "traffic cone": 0.8,
        "temporary barrier": 0.75, "guardrail": 0.6, "other barrier": 0.65,
        "wall": 0.4, "fence": 0.4, "pole": 0.5,
        "pedestrian crossing": 0.8, "curb": 0.6, "pothole": 0.7, "manhole": 0.6,
        "streetlight": 0.4, "bench": 0.3, "trash can": 0.4, "fire hydrant": 0.5,
        "mailbox": 0.3, "parking meter": 0.3, "bike rack": 0.4, "phone booth": 0.3,
        "water valve": 0.3, "junction box": 0.4,
        "road": 0.2, "sidewalk": 0.2, "driveway": 0.3, "bike lane": 0.4,
        "parking area": 0.3, "railway": 0.5, "service lane": 0.3,
        "building": 0.1, "bridge": 0.2, "tunnel": 0.3, "garage": 0.2,
        "vegetation": 0.1, "water": 0.2, "ground": 0.1, "animals": 0.8
    ]
    
    // MARK: - Initialization
    
    init() {
        loadModel()
    }
    
    /// Charge le modèle YOLOv11 depuis le bundle et l'optimise pour Neural Engine
    private func loadModel() {
        modelQueue.async { [weak self] in
            guard let self = self else { return }
            
            do {
                let config = MLModelConfiguration()
                config.setValue(1, forKey: "experimentalMLE5EngineUsage")
                
                guard let modelURL = Bundle.main.url(forResource: "last", withExtension: "mlmodelc") else {
                    print("Erreur: Modèle YOLOv11 non trouvé dans le bundle")
                    return
                }
                
                let mlModel = try MLModel(contentsOf: modelURL, configuration: config)
                let visionModel = try VNCoreMLModel(for: mlModel)
                
                DispatchQueue.main.async {
                    self.model = visionModel
                    print("Modèle YOLOv11 chargé avec succès (\(ObjectDetectionManager.MODEL_CLASSES.count) classes)")
                }
                
            } catch {
                print("Erreur lors du chargement du modèle: \(error)")
                DispatchQueue.main.async { self.model = nil }
            }
        }
    }
    
    // MARK: - Public Interface
    
    func getAvailableClasses() -> [String] {
        return modelClasses
    }
    
    static func getAllModelClasses() -> [String] {
        return MODEL_CLASSES
    }
    
    /// Configure les classes d'objets à détecter
    /// - Parameter classes: Set des classes à activer
    func setEnabledClasses(_ classes: Set<String>) {
        let allClasses = Set(ObjectDetectionManager.MODEL_CLASSES)
        let classesToIgnore = allClasses.subtracting(classes)
        
        DispatchQueue.main.async { [weak self] in
            self?.ignoredClasses = classesToIgnore
        }
    }
    
    /// Met à jour la liste des objets considérés comme dangereux
    /// - Parameter objects: Set des classes d'objets dangereux
    func updateDangerousObjects(_ objects: Set<String>) {
        dangerousObjects = objects
        // Mettre à jour les poids d'importance pour prioriser les objets dangereux
        updateImportanceWeightsForDangerousObjects()
    }
    
    /// Applique un poids d'importance maximal aux objets dangereux
    private func updateImportanceWeightsForDangerousObjects() {
        for objectClass in dangerousObjects {
            importanceWeights[objectClass.lowercased()] = 1.0
        }
    }
    
    func isModelLoaded() -> Bool {
        return model != nil
    }
    
    // MARK: - Detection Methods
    
    /// Détecte les objets dans une image UIImage
    /// - Parameters:
    ///   - image: Image à analyser
    ///   - completion: Callback avec résultats (bounding boxes + tracking info + temps d'exécution)
    func detectObjects(in image: UIImage, completion: @escaping ([(rect: CGRect, label: String, confidence: Float, distance: Float?, trackingInfo: (id: Int, color: UIColor, opacity: Double))], Double) -> Void) {
        
        processingQueue.async { [weak self] in
            guard let self = self, let model = self.model else {
                DispatchQueue.main.async { completion([], 0.0) }
                return
            }
            
            guard let ciImage = CIImage(image: image) else {
                DispatchQueue.main.async { completion([], 0.0) }
                return
            }
            
            self.performDetection(on: ciImage, with: model) { detections, inferenceTime in
                DispatchQueue.main.async { completion(detections, inferenceTime) }
            }
        }
    }
    
    /// Détecte les objets dans un buffer de pixels de la caméra
    /// - Parameters:
    ///   - pixelBuffer: Buffer de pixels de la caméra
    ///   - completion: Callback avec résultats
    func detectObjects(in pixelBuffer: CVPixelBuffer, completion: @escaping ([(rect: CGRect, label: String, confidence: Float, distance: Float?, trackingInfo: (id: Int, color: UIColor, opacity: Double))], Double) -> Void) {
        
        processingQueue.async { [weak self] in
            guard let self = self, let model = self.model else {
                DispatchQueue.main.async { completion([], 0.0) }
                return
            }
            
            let preprocessStart = CFAbsoluteTimeGetCurrent()
            let ciImage = self.preprocessPixelBuffer(pixelBuffer)
            let preprocessTime = (CFAbsoluteTimeGetCurrent() - preprocessStart) * 1000
            
            self.performDetection(on: ciImage, with: model, preprocessTime: preprocessTime) { detections, inferenceTime in
                DispatchQueue.main.async { completion(detections, inferenceTime) }
            }
        }
    }
    
    /// Détecte les objets avec données LiDAR pour mesures de distance
    /// - Parameters:
    ///   - pixelBuffer: Buffer de pixels RGB
    ///   - depthData: Données de profondeur LiDAR
    ///   - lidarManager: Gestionnaire LiDAR
    ///   - imageSize: Taille de l'image pour correspondance géométrique
    ///   - completion: Callback avec résultats incluant distances
    func detectObjectsWithLiDAR(
        in pixelBuffer: CVPixelBuffer,
        depthData: AVDepthData?,
        lidarManager: LiDARManager,
        imageSize: CGSize,
        completion: @escaping ([(rect: CGRect, label: String, confidence: Float, distance: Float?, trackingInfo: (id: Int, color: UIColor, opacity: Double))], Double) -> Void
    ) {
        
        processingQueue.async { [weak self] in
            guard let self = self, let model = self.model else {
                DispatchQueue.main.async { completion([], 0.0) }
                return
            }
            
            let preprocessStart = CFAbsoluteTimeGetCurrent()
            let ciImage = self.preprocessPixelBuffer(pixelBuffer)
            let preprocessTime = (CFAbsoluteTimeGetCurrent() - preprocessStart) * 1000
            
            self.performDetectionWithLiDARAndTracking(
                on: ciImage, with: model, depthData: depthData,
                lidarManager: lidarManager, imageSize: imageSize,
                preprocessTime: preprocessTime
            ) { detections, inferenceTime in
                DispatchQueue.main.async { completion(detections, inferenceTime) }
            }
        }
    }
    
    /// Prétraite le buffer de pixels pour optimiser la détection
    /// - Parameter pixelBuffer: Buffer source
    /// - Returns: CIImage prétraitée avec ajustements colorimétriques
    private func preprocessPixelBuffer(_ pixelBuffer: CVPixelBuffer) -> CIImage {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let orientedImage = ciImage.oriented(.right)
        
        return orientedImage.applyingFilter("CIColorControls", parameters: [
            "inputSaturation": 1.1,
            "inputBrightness": 0.0,
            "inputContrast": 1.1
        ])
    }
    
    // MARK: - Core Detection Logic
    
    /// Effectue la détection sans LiDAR avec tracking
    private func performDetection(
        on ciImage: CIImage,
        with model: VNCoreMLModel,
        preprocessTime: Double = 0.0,
        completion: @escaping ([(rect: CGRect, label: String, confidence: Float, distance: Float?, trackingInfo: (id: Int, color: UIColor, opacity: Double))], Double) -> Void
    ) {
        let totalStartTime = CFAbsoluteTimeGetCurrent()
        let confidenceThreshold = self.confidenceThreshold
        let maxDetections = self.maxDetections
        
        let request = VNCoreMLRequest(model: model) { [weak self] request, error in
            let totalInferenceTime = (CFAbsoluteTimeGetCurrent() - totalStartTime) * 1000
            
            guard let self = self else {
                completion([], totalInferenceTime)
                return
            }
            
            if let error = error {
                completion([], totalInferenceTime)
                return
            }
            
            guard let results = request.results as? [VNRecognizedObjectObservation] else {
                completion([], totalInferenceTime)
                return
            }
            
            let rawDetections = self.processRawDetections(results, confidenceThreshold: confidenceThreshold, maxDetections: maxDetections)
            let trackedDetections = self.objectTracker.processDetections(rawDetections)
            
            self.updateInferenceStats(totalInferenceTime)
            completion(trackedDetections, totalInferenceTime)
        }
        
        request.imageCropAndScaleOption = VNImageCropAndScaleOption.scaleFill
        
        do {
            let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
            try handler.perform([request])
        } catch {
            let errorTime = (CFAbsoluteTimeGetCurrent() - totalStartTime) * 1000
            completion([], errorTime)
        }
    }
    
    /// Effectue la détection avec LiDAR et tracking
    private func performDetectionWithLiDARAndTracking(
        on ciImage: CIImage,
        with model: VNCoreMLModel,
        depthData: AVDepthData?,
        lidarManager: LiDARManager,
        imageSize: CGSize,
        preprocessTime: Double = 0.0,
        completion: @escaping ([(rect: CGRect, label: String, confidence: Float, distance: Float?, trackingInfo: (id: Int, color: UIColor, opacity: Double))], Double) -> Void
    ) {
        let totalStartTime = CFAbsoluteTimeGetCurrent()
        let confidenceThreshold = self.confidenceThreshold
        let maxDetections = self.maxDetections
        
        let request = VNCoreMLRequest(model: model) { [weak self] request, error in
            let totalInferenceTime = (CFAbsoluteTimeGetCurrent() - totalStartTime) * 1000
            
            guard let self = self else {
                completion([], totalInferenceTime)
                return
            }
            
            if let error = error {
                completion([], totalInferenceTime)
                return
            }
            
            guard let results = request.results as? [VNRecognizedObjectObservation] else {
                completion([], totalInferenceTime)
                return
            }
            
            let rawDetections = self.processDetectionsWithLiDAR(
                results, lidarManager: lidarManager, imageSize: imageSize,
                confidenceThreshold: confidenceThreshold, maxDetections: maxDetections
            )
            
            let trackedDetections = self.objectTracker.processDetections(rawDetections)
            self.updateInferenceStats(totalInferenceTime)
            completion(trackedDetections, totalInferenceTime)
        }
        
        request.imageCropAndScaleOption = VNImageCropAndScaleOption.scaleFill
        
        do {
            let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
            try handler.perform([request])
        } catch {
            let errorTime = (CFAbsoluteTimeGetCurrent() - totalStartTime) * 1000
            completion([], errorTime)
        }
    }
    
    /// Traite les détections brutes sans LiDAR
    /// - Parameters:
    ///   - results: Résultats de Vision Framework
    ///   - confidenceThreshold: Seuil de confiance minimum
    ///   - maxDetections: Nombre maximum de détections à retenir
    /// - Returns: Liste des détections filtrées
    private func processRawDetections(
        _ results: [VNRecognizedObjectObservation],
        confidenceThreshold: Float,
        maxDetections: Int
    ) -> [(rect: CGRect, label: String, confidence: Float, distance: Float?)] {
        
        let filteredResults = results.filter { $0.confidence >= confidenceThreshold }
        let sortedResults = filteredResults.sorted { $0.confidence > $1.confidence }
        let limitedResults = Array(sortedResults.prefix(maxDetections))
        
        return limitedResults.compactMap { observation in
            let topLabel = observation.labels.first?.identifier ?? "Objet"
            let confidence = observation.confidence
            
            guard isClassAllowed(topLabel) else { return nil }
            
            let boundingBox = observation.boundingBox
            guard boundingBox.width > 0.01 && boundingBox.height > 0.01 else { return nil }
            
            return (rect: boundingBox, label: topLabel, confidence: confidence, distance: nil)
        }
    }
    
    /// Traite les détections avec calcul de distance LiDAR
    private func processDetectionsWithLiDAR(
        _ results: [VNRecognizedObjectObservation],
        lidarManager: LiDARManager,
        imageSize: CGSize,
        confidenceThreshold: Float,
        maxDetections: Int
    ) -> [(rect: CGRect, label: String, confidence: Float, distance: Float?)] {
        
        let filteredResults = results.filter { $0.confidence >= confidenceThreshold }
        let sortedResults = filteredResults.sorted { $0.confidence > $1.confidence }
        let limitedResults = Array(sortedResults.prefix(maxDetections))
        
        return limitedResults.compactMap { observation in
            let topLabel = observation.labels.first?.identifier ?? "Objet"
            let confidence = observation.confidence
            
            guard isClassAllowed(topLabel) else { return nil }
            
            let boundingBox = observation.boundingBox
            guard boundingBox.width > 0.01 && boundingBox.height > 0.01 else { return nil }
            
            var distance: Float?
            if lidarManager.isEnabled() {
                statsQueue.async { [weak self] in
                    self?.totalDistanceMeasurements += 1
                }
                
                distance = lidarManager.getDistanceForBoundingBox(boundingBox, imageSize: imageSize)
                
                if let dist = distance {
                    statsQueue.async { [weak self] in
                        guard let self = self else { return }
                        self.successfulDistanceMeasurements += 1
                        self.lidarDistanceHistory.append(dist)
                        
                        if self.lidarDistanceHistory.count > self.maxHistorySize {
                            self.lidarDistanceHistory.removeFirst()
                        }
                    }
                }
            }
            
            return (rect: boundingBox, label: topLabel, confidence: confidence, distance: distance)
        }
    }
    
    // MARK: - Importance Scoring System
    
    /// Calcule le score d'importance d'un objet tracké
    /// - Parameter object: Objet tracké à évaluer
    /// - Returns: Score entre 0.0 et 1.0
    private func calculateImportanceScore(for object: TrackedObject) -> Float {
        var score: Float = 0.0
        
        // 1. Score de base selon le type d'objet (40% du score final)
        let baseWeight = importanceWeights[object.label.lowercased()] ?? 0.2
        score += baseWeight * 0.4
        
        // 2. Score de confiance (20% du score final)
        score += object.confidence * 0.1
        
        // 3. Score de durée de vie - stabilité temporelle (20% du score final)
        let lifetimeScore = min(1.0, Float(object.lifetime) / 10.0)
        score += lifetimeScore * 0.2
        
        // 4. Score de stabilité - fréquence des détections (10% du score final)
        let recentDetections = object.detectionHistory.filter { Date().timeIntervalSince($0) < 5.0 }
        let stabilityScore = min(1.0, Float(recentDetections.count) / 50.0)
        score += stabilityScore * 0.1
        
        // 5. Score de proximité si LiDAR disponible (10% du score final)
        if let distance = object.distance {
            let proximityScore = max(0.0, min(1.0, (10.0 - distance) / 10.0))
            score += proximityScore * 0.2
        } else {
            score += 0.05
        }
        
        return min(1.0, score)
    }
    
    /// Retourne les objets les plus importants triés par score
    /// - Parameter maxCount: Nombre maximum d'objets à retourner
    /// - Returns: Liste des objets avec leurs scores
    func getTopImportantObjects(maxCount: Int = 5) -> [(object: TrackedObject, score: Float)] {
        let allTrackedObjects = objectTracker.getAllTrackedObjects()
        
        let allowedObjects = allTrackedObjects.filter { object in
            return isClassAllowed(object.label)
        }
        
        let scoredObjects = allowedObjects.map { object in
            (object: object, score: calculateImportanceScore(for: object))
        }
        
        let sortedObjects = scoredObjects.sorted { $0.score > $1.score }
        let significantObjects = sortedObjects.filter { $0.score > 0.3 }
        
        return Array(significantObjects.prefix(maxCount))
    }
    
    // MARK: - Statistics and Performance
    
    private func updateInferenceStats(_ inferenceTime: Double) {
        statsQueue.async { [weak self] in
            guard let self = self else { return }
            self.inferenceHistory.append(inferenceTime)
            
            if self.inferenceHistory.count > self.maxHistorySize {
                self.inferenceHistory.removeFirst()
            }
        }
    }
    
    func getAverageInferenceTime() -> Double? {
        return statsQueue.sync { [weak self] in
            guard let self = self, !self.inferenceHistory.isEmpty else { return nil }
            return self.inferenceHistory.reduce(0, +) / Double(self.inferenceHistory.count)
        }
    }
    
    func getPerformanceStats() -> String {
        return statsQueue.sync { [weak self] in
            guard let self = self, !self.inferenceHistory.isEmpty else {
                return "Aucune statistique disponible"
            }
            
            let avg = self.inferenceHistory.reduce(0, +) / Double(self.inferenceHistory.count)
            let min = self.inferenceHistory.min()!
            let max = self.inferenceHistory.max()!
            let avgFPS = 1000.0 / avg
            
            var stats = "Statistiques de performance (\(self.inferenceHistory.count) inférences):\n"
            stats += "   - Temps moyen: \(String(format: "%.1f", avg))ms\n"
            stats += "   - Temps min: \(String(format: "%.1f", min))ms\n"
            stats += "   - Temps max: \(String(format: "%.1f", max))ms\n"
            stats += "   - FPS moyen: \(String(format: "%.1f", avgFPS))\n"
            
            if self.totalDistanceMeasurements > 0 {
                let successRate = Float(self.successfulDistanceMeasurements) / Float(self.totalDistanceMeasurements) * 100
                stats += "\nStatistiques LiDAR:\n"
                stats += "   - Mesures tentées: \(self.totalDistanceMeasurements)\n"
                stats += "   - Mesures réussies: \(self.successfulDistanceMeasurements) (\(String(format: "%.1f", successRate))%)\n"
            }
            
            stats += "\n" + self.objectTracker.getTrackingStats()
            
            return stats
        }
    }
    
    func resetStats() {
        statsQueue.async { [weak self] in
            guard let self = self else { return }
            self.inferenceHistory.removeAll()
            self.lidarDistanceHistory.removeAll()
            self.successfulDistanceMeasurements = 0
            self.totalDistanceMeasurements = 0
        }
        
        objectTracker.resetStats()
    }
    
    // MARK: - Tracking Controls
    
    func resetTracking() {
        objectTracker.reset()
    }
    
    func getTrackingStats() -> String {
        return objectTracker.getDetailedStats()
    }
    
    // MARK: - Class Management
    
    func addIgnoredClass(_ className: String) {
        DispatchQueue.main.async { [weak self] in
            self?.ignoredClasses.insert(className.lowercased())
        }
    }
    
    func removeIgnoredClass(_ className: String) {
        DispatchQueue.main.async { [weak self] in
            self?.ignoredClasses.remove(className.lowercased())
        }
    }
    
    func clearIgnoredClasses() {
        DispatchQueue.main.async { [weak self] in
            self?.ignoredClasses.removeAll()
        }
    }
    
    func getIgnoredClasses() -> [String] {
        return Array(ignoredClasses).sorted()
    }
    
    /// Vérifie si une classe d'objet est autorisée à la détection
    /// - Parameter className: Nom de la classe à vérifier
    /// - Returns: true si la classe n'est pas dans la liste des classes ignorées
    private func isClassAllowed(_ className: String) -> Bool {
        let lowercaseName = className.lowercased()
        return !ignoredClasses.contains(lowercaseName)
    }
}
