import CoreML
import Vision
import UIKit
import AVFoundation

class ObjectDetectionManager {
    private var model: VNCoreMLModel?
    
    // Configuration de détection améliorée
    private let confidenceThreshold: Float = 0.6
    private let maxDetections = 10
    
    // Classes à ignorer par défaut pour conduite autonome (modifiable)
    private var ignoredClasses = Set(["building", "vegetation", "ground", "water"])
    private var activeClasses: Set<String> = []
    
    // Système de tracking intégré
    private let objectTracker = ObjectTracker()
    
    // Statistiques de performance
    private var inferenceHistory: [Double] = []
    private let maxHistorySize = 100
    
    // Statistiques LiDAR
    private var lidarDistanceHistory: [Float] = []
    private var successfulDistanceMeasurements = 0
    private var totalDistanceMeasurements = 0
    
    // MARK: - Thread Safety
    private let processingQueue = DispatchQueue(label: "detection.processing", qos: .userInitiated)
    private let modelQueue = DispatchQueue(label: "model.access", qos: .userInitiated)
    private let statsQueue = DispatchQueue(label: "stats.access", qos: .utility)
    
    // MARK: - Système d'importance des objets
    private var importanceWeights: [String: Float] = [
        // 🚨 SÉCURITÉ CRITIQUE - Personnes et usagers vulnérables
        "person": 1.0,                    // Piéton = priorité absolue
        "cyclist": 0.95,                  // Cycliste = très haute priorité
        "motorcyclist": 0.9,              // Motocycliste = très haute priorité
        
        // 🚗 VÉHICULES MOBILES - Haute priorité
        "car": 0.85,                      // Voiture
        "truck": 0.85,                    // Camion
        "bus": 0.85,                      // Bus
        "motorcycle": 0.8,                // Moto
        "bicycle": 0.8,                   // Vélo
        "slow vehicle": 0.75,             // Véhicule lent
        "vehicle group": 0.8,             // Groupe de véhicules
        "rail vehicle": 0.7,              // Train/tramway
        "boat": 0.5,                      // Bateau (moins prioritaire)
        
        // 🚦 SIGNALISATION & SÉCURITÉ ROUTIÈRE - Priorité élevée
        "traffic light": 0.9,             // Feu de circulation
        "traffic sign": 0.85,             // Panneau de signalisation
        "traffic cone": 0.8,              // Cône de circulation
        
        // 🚧 BARRIÈRES & OBSTACLES - Priorité modérée à élevée
        "temporary barrier": 0.75,        // Barrière temporaire
        "guardrail": 0.6,                 // Glissière de sécurité
        "other barrier": 0.65,            // Autre barrière
        "wall": 0.4,                      // Mur
        "fence": 0.4,                     // Clôture
        "pole": 0.5,                      // Poteau
        
        // 🛣️ INFRASTRUCTURE ROUTIÈRE - Priorité modérée
        "pedestrian crossing": 0.8,       // Passage piéton
        "curb": 0.6,                      // Bordure
        "pothole": 0.7,                   // Nid-de-poule
        "manhole": 0.6,                   // Plaque d'égout
        "storm drain": 0.5,               // Bouche d'égout
        
        // 🏗️ MOBILIER URBAIN - Priorité faible à modérée
        "streetlight": 0.4,               // Éclairage public
        "bench": 0.3,                     // Banc
        "trash can": 0.4,                 // Poubelle
        "fire hydrant": 0.5,              // Bouche d'incendie
        "mailbox": 0.3,                   // Boîte aux lettres
        "parking meter": 0.3,             // Parcomètre
        "bike rack": 0.4,                 // Support vélo
        "phone booth": 0.3,               // Cabine téléphonique
        "water valve": 0.3,               // Vanne d'eau
        "junction box": 0.4,              // Boîtier de jonction
        
        // 🏞️ ZONES & SURFACES - Priorité faible (infrastructure statique)
        "road": 0.2,                      // Route
        "sidewalk": 0.2,                  // Trottoir
        "driveway": 0.3,                  // Allée
        "bike lane": 0.4,                 // Piste cyclable
        "parking area": 0.3,              // Zone de parking
        "railway": 0.5,                   // Voie ferrée
        "service lane": 0.3,              // Voie de service
        
        // 🏢 STRUCTURES - Priorité très faible
        "building": 0.1,                  // Bâtiment
        "bridge": 0.2,                    // Pont
        "tunnel": 0.3,                    // Tunnel
        "garage": 0.2,                    // Garage
        
        // 🌳 ENVIRONNEMENT - Priorité très faible
        "vegetation": 0.1,                // Végétation
        "water": 0.2,                     // Eau
        "ground": 0.1,                    // Sol
        "animals": 0.8                    // Animaux = important pour la sécurité !
    ]
    
    init() {
        loadModel()
    }
    
    private func loadModel() {
        modelQueue.async { [weak self] in
            guard let self = self else { return }
            
            do {
                let config = MLModelConfiguration()
                config.setValue(1, forKey: "experimentalMLE5EngineUsage")
                
                guard let modelURL = Bundle.main.url(forResource: "last", withExtension: "mlmodelc") else {
                    print("❌ Modèle 'last.mlmodelc' non trouvé dans le bundle")
                    return
                }
                
                print("✅ Modèle compilé trouvé: last.mlmodelc")
                
                let mlModel = try MLModel(contentsOf: modelURL, configuration: config)
                let visionModel = try VNCoreMLModel(for: mlModel)
                
                // Assigner le modèle de manière thread-safe
                DispatchQueue.main.async {
                    self.model = visionModel
                    print("✅ Modèle VNCoreMLModel chargé avec succès")
                }
                
            } catch {
                print("❌ Erreur lors du chargement du modèle: \(error)")
                DispatchQueue.main.async {
                    self.model = nil
                }
            }
        }
    }
    
    // MARK: - Detection Methods (Legacy) - Updated for tracking
    func detectObjects(in image: UIImage, completion: @escaping ([(rect: CGRect, label: String, confidence: Float, distance: Float?, trackingInfo: (id: Int, color: UIColor, opacity: Double))], Double) -> Void) {
        
        processingQueue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async {
                    completion([], 0.0)
                }
                return
            }
            
            guard let model = self.model else {
                print("❌ Modèle non chargé")
                DispatchQueue.main.async {
                    completion([], 0.0)
                }
                return
            }
            
            guard let ciImage = CIImage(image: image) else {
                print("❌ Impossible de convertir l'image")
                DispatchQueue.main.async {
                    completion([], 0.0)
                }
                return
            }
            
            self.performDetection(on: ciImage, with: model) { detections, inferenceTime in
                DispatchQueue.main.async {
                    completion(detections, inferenceTime)
                }
            }
        }
    }
    
    func detectObjects(in pixelBuffer: CVPixelBuffer, completion: @escaping ([(rect: CGRect, label: String, confidence: Float, distance: Float?, trackingInfo: (id: Int, color: UIColor, opacity: Double))], Double) -> Void) {
        
        processingQueue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async {
                    completion([], 0.0)
                }
                return
            }
            
            guard let model = self.model else {
                print("❌ Modèle non chargé")
                DispatchQueue.main.async {
                    completion([], 0.0)
                }
                return
            }
            
            let preprocessStart = CFAbsoluteTimeGetCurrent()
            let ciImage = self.preprocessPixelBuffer(pixelBuffer)
            let preprocessTime = (CFAbsoluteTimeGetCurrent() - preprocessStart) * 1000
            
            self.performDetection(on: ciImage, with: model, preprocessTime: preprocessTime) { detections, inferenceTime in
                DispatchQueue.main.async {
                    completion(detections, inferenceTime)
                }
            }
        }
    }
    
    // MARK: - New LiDAR-Enhanced Detection Method with Tracking
    func detectObjectsWithLiDAR(
        in pixelBuffer: CVPixelBuffer,
        depthData: AVDepthData?,
        lidarManager: LiDARManager,
        imageSize: CGSize,
        completion: @escaping ([(rect: CGRect, label: String, confidence: Float, distance: Float?, trackingInfo: (id: Int, color: UIColor, opacity: Double))], Double) -> Void
    ) {
        
        processingQueue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async {
                    completion([], 0.0)
                }
                return
            }
            
            guard let model = self.model else {
                print("❌ Modèle non chargé")
                DispatchQueue.main.async {
                    completion([], 0.0)
                }
                return
            }
            
            let preprocessStart = CFAbsoluteTimeGetCurrent()
            let ciImage = self.preprocessPixelBuffer(pixelBuffer)
            let preprocessTime = (CFAbsoluteTimeGetCurrent() - preprocessStart) * 1000
            
            self.performDetectionWithLiDARAndTracking(
                on: ciImage,
                with: model,
                depthData: depthData,
                lidarManager: lidarManager,
                imageSize: imageSize,
                preprocessTime: preprocessTime
            ) { detections, inferenceTime in
                DispatchQueue.main.async {
                    completion(detections, inferenceTime)
                }
            }
        }
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
    
    // MARK: - Legacy Detection (without LiDAR) with Tracking - THREAD SAFE
    private func performDetection(
        on ciImage: CIImage,
        with model: VNCoreMLModel,
        preprocessTime: Double = 0.0,
        completion: @escaping ([(rect: CGRect, label: String, confidence: Float, distance: Float?, trackingInfo: (id: Int, color: UIColor, opacity: Double))], Double) -> Void
    ) {
        let totalStartTime = CFAbsoluteTimeGetCurrent()
        
        // Créer une copie locale des paramètres pour éviter les accès concurrent
        let confidenceThreshold = self.confidenceThreshold
        let maxDetections = self.maxDetections
        
        let request = VNCoreMLRequest(model: model) { [weak self] request, error in
            let totalInferenceTime = (CFAbsoluteTimeGetCurrent() - totalStartTime) * 1000
            
            guard let self = self else {
                completion([], totalInferenceTime)
                return
            }
            
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
            
            // Traitement des détections brutes (sans LiDAR, donc distance = nil)
            let rawDetections = self.processRawDetections(results, confidenceThreshold: confidenceThreshold, maxDetections: maxDetections)
            
            // Application du tracking
            let trackedDetections = self.objectTracker.processDetections(rawDetections)
            
            let postProcessTime = (CFAbsoluteTimeGetCurrent() - postProcessStart) * 1000
            
            self.updateInferenceStats(totalInferenceTime)
            
            self.printDetectionStats(
                detections: trackedDetections,
                totalTime: totalInferenceTime,
                preprocessTime: preprocessTime,
                postProcessTime: postProcessTime,
                withLiDAR: false
            )
            
            completion(trackedDetections, totalInferenceTime)
        }
        
        request.imageCropAndScaleOption = VNImageCropAndScaleOption.scaleFill
        
        do {
            // Créer le handler sur la queue de traitement
            let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
            try handler.perform([request])
        } catch {
            let errorTime = (CFAbsoluteTimeGetCurrent() - totalStartTime) * 1000
            print("❌ Échec de la détection: \(error)")
            completion([], errorTime)
        }
    }
    
    // MARK: - LiDAR-Enhanced Detection with Tracking - THREAD SAFE
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
        
        // Créer une copie locale des paramètres pour éviter les accès concurrent
        let confidenceThreshold = self.confidenceThreshold
        let maxDetections = self.maxDetections
        
        let request = VNCoreMLRequest(model: model) { [weak self] request, error in
            let totalInferenceTime = (CFAbsoluteTimeGetCurrent() - totalStartTime) * 1000
            
            guard let self = self else {
                completion([], totalInferenceTime)
                return
            }
            
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
            
            // Traitement des détections avec LiDAR
            let rawDetections = self.processDetectionsWithLiDAR(
                results,
                lidarManager: lidarManager,
                imageSize: imageSize,
                confidenceThreshold: confidenceThreshold,
                maxDetections: maxDetections
            )
            
            // Application du tracking
            let trackedDetections = self.objectTracker.processDetections(rawDetections)
            
            let postProcessTime = (CFAbsoluteTimeGetCurrent() - postProcessStart) * 1000
            
            self.updateInferenceStats(totalInferenceTime)
            
            self.printDetectionStats(
                detections: trackedDetections,
                totalTime: totalInferenceTime,
                preprocessTime: preprocessTime,
                postProcessTime: postProcessTime,
                withLiDAR: lidarManager.isEnabled()
            )
            
            completion(trackedDetections, totalInferenceTime)
        }
        
        request.imageCropAndScaleOption = VNImageCropAndScaleOption.scaleFill
        
        do {
            // Créer le handler sur la queue de traitement
            let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
            try handler.perform([request])
        } catch {
            let errorTime = (CFAbsoluteTimeGetCurrent() - totalStartTime) * 1000
            print("❌ Échec de la détection: \(error)")
            completion([], errorTime)
        }
    }
    
    // MARK: - Detection Processing (Raw detections without tracking) - THREAD SAFE
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
                statsQueue.async { [weak self] in
                    self?.totalDistanceMeasurements += 1
                }
                
                distance = lidarManager.getDistanceForBoundingBox(boundingBox, imageSize: imageSize)
                
                if let dist = distance {
                    statsQueue.async { [weak self] in
                        guard let self = self else { return }
                        self.successfulDistanceMeasurements += 1
                        self.lidarDistanceHistory.append(dist)
                        
                        // Maintenir un historique limité
                        if self.lidarDistanceHistory.count > self.maxHistorySize {
                            self.lidarDistanceHistory.removeFirst()
                        }
                    }
                }
            }
            
            return (rect: boundingBox, label: topLabel, confidence: confidence, distance: distance)
        }
    }
    
    // MARK: - Système d'importance des objets - THREAD SAFE
    
    /// Calculer le score d'importance d'un objet
    private func calculateImportanceScore(for object: TrackedObject) -> Float {
        var score: Float = 0.0
        
        // 1. Score de base selon le type d'objet (0.0 - 1.0)
        let baseWeight = importanceWeights[object.label.lowercased()] ?? 0.2
        score += baseWeight * 0.4  // 40% du score final
        
        // 2. Score de confiance (0.0 - 1.0)
        score += object.confidence * 0.2  // 20% du score final
        
        // 3. Score de durée de vie (plus l'objet est tracké longtemps, plus il est important)
        let lifetimeScore = min(1.0, Float(object.lifetime) / 10.0)  // Normaliser sur 10 secondes
        score += lifetimeScore * 0.2  // 20% du score final
        
        // 4. Score de stabilité (fréquence des détections)
        let recentDetections = object.detectionHistory.filter { Date().timeIntervalSince($0) < 5.0 }
        let stabilityScore = min(1.0, Float(recentDetections.count) / 50.0)  // Normaliser sur 50 détections en 5s
        score += stabilityScore * 0.1  // 10% du score final
        
        // 5. Score de proximité (si LiDAR disponible)
        if let distance = object.distance {
            // Plus proche = plus important (inversement proportionnel)
            let proximityScore = max(0.0, min(1.0, (10.0 - distance) / 10.0))  // Normaliser sur 10m
            score += proximityScore * 0.1  // 10% du score final
        } else {
            // Bonus léger si pas de distance disponible (pour ne pas pénaliser)
            score += 0.05
        }
        
        return min(1.0, score)  // S'assurer que le score ne dépasse pas 1.0
    }
    
    /// Obtenir les objets les plus importants (SEULEMENT parmi les classes autorisées) - THREAD SAFE
    func getTopImportantObjects(maxCount: Int = 5) -> [(object: TrackedObject, score: Float)] {
        let allTrackedObjects = objectTracker.getAllTrackedObjects()
        
        // FILTRER seulement les objets des classes autorisées
        let allowedObjects = allTrackedObjects.filter { object in
            return isClassAllowed(object.label)
        }
        
        // Calculer le score pour chaque objet autorisé
        let scoredObjects = allowedObjects.map { object in
            (object: object, score: calculateImportanceScore(for: object))
        }
        
        // Trier par score décroissant et limiter le nombre
        let sortedObjects = scoredObjects.sorted { $0.score > $1.score }
        
        // Filtrer seulement les objets avec un score significatif (> 0.3)
        let significantObjects = sortedObjects.filter { $0.score > 0.3 }
        
        return Array(significantObjects.prefix(maxCount))
    }
    
    /// Obtenir les statistiques d'importance (SEULEMENT pour les classes autorisées) - THREAD SAFE
    func getImportanceStats() -> String {
        let topObjects = getTopImportantObjects(maxCount: 10)
        
        guard !topObjects.isEmpty else {
            return "📊 Aucun objet important détecté (classes autorisées)"
        }
        
        var stats = "📊 Statistiques d'importance (Top \(topObjects.count), classes autorisées):\n"
        
        for (index, item) in topObjects.enumerated() {
            let rank = index + 1
            let scorePercent = item.score * 100
            let lifetime = String(format: "%.1f", item.object.lifetime)
            
            stats += "   \(rank). #\(item.object.trackingNumber) \(item.object.label.capitalized): "
            stats += "\(String(format: "%.1f", scorePercent))% (durée: \(lifetime)s"
            
            if let distance = item.object.distance {
                stats += ", dist: \(String(format: "%.1f", distance))m"
            }
            
            stats += ")\n"
        }
        
        // Ajouter des statistiques globales
        let avgScore = topObjects.reduce(0) { $0 + $1.score } / Float(topObjects.count)
        stats += "\n   Score moyen: \(String(format: "%.1f", avgScore * 100))%"
        
        // Distribution par type d'objet
        let objectTypes = topObjects.map { $0.object.label.lowercased() }
        let uniqueTypes = Set(objectTypes)
        
        if uniqueTypes.count > 1 {
            stats += "\n   Types représentés: \(uniqueTypes.count)"
            for type in uniqueTypes {
                let count = objectTypes.filter { $0 == type }.count
                stats += "\n     - \(type.capitalized): \(count)"
            }
        }
        
        // Ajouter info sur les classes actives/ignorées
        let allowedClasses = getActiveClasses().isEmpty ? "toutes sauf ignorées" : getActiveClasses().joined(separator: ", ")
        let ignoredClasses = getIgnoredClasses().joined(separator: ", ")
        
        stats += "\n\n⚙️ Configuration des classes:"
        stats += "\n   - Classes autorisées: \(allowedClasses)"
        if !ignoredClasses.isEmpty {
            stats += "\n   - Classes ignorées: \(ignoredClasses)"
        }
        
        return stats
    }
    
    // MARK: - Configuration des poids d'importance - THREAD SAFE
    
    /// Définir le poids d'importance pour une classe d'objet
    func setImportanceWeight(for className: String, weight: Float) {
        DispatchQueue.main.async { [weak self] in
            self?.importanceWeights[className.lowercased()] = max(0.0, min(1.0, weight))
        }
    }
    
    /// Obtenir le poids d'importance pour une classe d'objet
    func getImportanceWeight(for className: String) -> Float {
        return importanceWeights[className.lowercased()] ?? 0.2
    }
    
    /// Obtenir tous les poids d'importance configurés
    func getAllImportanceWeights() -> [String: Float] {
        return importanceWeights
    }
    
    /// Réinitialiser les poids d'importance aux valeurs par défaut pour conduite autonome
    func resetImportanceWeights() {
        DispatchQueue.main.async { [weak self] in
            self?.importanceWeights = [
                // 🚨 SÉCURITÉ CRITIQUE - Personnes et usagers vulnérables
                "person": 1.0,                    // Piéton = priorité absolue
                "cyclist": 0.95,                  // Cycliste = très haute priorité
                "motorcyclist": 0.9,              // Motocycliste = très haute priorité
                
                // 🚗 VÉHICULES MOBILES - Haute priorité
                "car": 0.85,                      // Voiture
                "truck": 0.85,                    // Camion
                "bus": 0.85,                      // Bus
                "motorcycle": 0.8,                // Moto
                "bicycle": 0.8,                   // Vélo
                "slow vehicle": 0.75,             // Véhicule lent
                "vehicle group": 0.8,             // Groupe de véhicules
                "rail vehicle": 0.7,              // Train/tramway
                "boat": 0.5,                      // Bateau (moins prioritaire)
                
                // 🚦 SIGNALISATION & SÉCURITÉ ROUTIÈRE - Priorité élevée
                "traffic light": 0.9,             // Feu de circulation
                "traffic sign": 0.85,             // Panneau de signalisation
                "traffic cone": 0.8,              // Cône de circulation
                
                // 🚧 BARRIÈRES & OBSTACLES - Priorité modérée à élevée
                "temporary barrier": 0.75,        // Barrière temporaire
                "guardrail": 0.6,                 // Glissière de sécurité
                "other barrier": 0.65,            // Autre barrière
                "wall": 0.4,                      // Mur
                "fence": 0.4,                     // Clôture
                "pole": 0.5,                      // Poteau
                
                // 🛣️ INFRASTRUCTURE ROUTIÈRE - Priorité modérée
                "pedestrian crossing": 0.8,       // Passage piéton
                "curb": 0.6,                      // Bordure
                "pothole": 0.7,                   // Nid-de-poule
                "manhole": 0.6,                   // Plaque d'égout
                "storm drain": 0.5,               // Bouche d'égout
                
                // 🏗️ MOBILIER URBAIN - Priorité faible à modérée
                "streetlight": 0.4,               // Éclairage public
                "bench": 0.3,                     // Banc
                "trash can": 0.4,                 // Poubelle
                "fire hydrant": 0.5,              // Bouche d'incendie
                "mailbox": 0.3,                   // Boîte aux lettres
                "parking meter": 0.3,             // Parcomètre
                "bike rack": 0.4,                 // Support vélo
                "phone booth": 0.3,               // Cabine téléphonique
                "water valve": 0.3,               // Vanne d'eau
                "junction box": 0.4,              // Boîtier de jonction
                
                // 🏞️ ZONES & SURFACES - Priorité faible (infrastructure statique)
                "road": 0.2,                      // Route
                "sidewalk": 0.2,                  // Trottoir
                "driveway": 0.3,                  // Allée
                "bike lane": 0.4,                 // Piste cyclable
                "parking area": 0.3,              // Zone de parking
                "railway": 0.5,                   // Voie ferrée
                "service lane": 0.3,              // Voie de service
                
                // 🏢 STRUCTURES - Priorité très faible
                "building": 0.1,                  // Bâtiment
                "bridge": 0.2,                    // Pont
                "tunnel": 0.3,                    // Tunnel
                "garage": 0.2,                    // Garage
                
                // 🌳 ENVIRONNEMENT - Priorité très faible
                "vegetation": 0.1,                // Végétation
                "water": 0.2,                     // Eau
                "ground": 0.1,                    // Sol
                "animals": 0.8                    // Animaux = important pour la sécurité !
            ]
        }
    }
    
    // MARK: - Statistics - THREAD SAFE
    private func updateInferenceStats(_ inferenceTime: Double) {
        statsQueue.async { [weak self] in
            guard let self = self else { return }
            self.inferenceHistory.append(inferenceTime)
            
            if self.inferenceHistory.count > self.maxHistorySize {
                self.inferenceHistory.removeFirst()
            }
        }
    }
    
    private func printDetectionStats(
        detections: [(rect: CGRect, label: String, confidence: Float, distance: Float?, trackingInfo: (id: Int, color: UIColor, opacity: Double))],
        totalTime: Double,
        preprocessTime: Double,
        postProcessTime: Double,
        withLiDAR: Bool
    ) {
        let pureInferenceTime = totalTime - postProcessTime - preprocessTime
        
       // print("🎯 YOLOv11\(withLiDAR ? " + LiDAR" : "") + Tracking: \(detections.count) objets détectés")
        //print("⏱️ Temps d'exécution:")
       // if preprocessTime > 0 {
        //    print("   - Préprocessing: \(String(format: "%.1f", preprocessTime))ms")
        //}
        //print("   - Inférence pure: \(String(format: "%.1f", pureInferenceTime))ms")
        //print("   - Post-processing + Tracking: \(String(format: "%.1f", postProcessTime))ms")
        //print("   - TOTAL: \(String(format: "%.1f", totalTime))ms")
        //print("   - FPS estimé: \(String(format: "%.1f", 1000.0 / totalTime))")
        
        if let avgTime = getAverageInferenceTime() {
          //  print("   - Moyenne (dernières \(inferenceHistory.count)): \(String(format: "%.1f", avgTime))ms")
        }
        
        // Statistiques LiDAR
        statsQueue.async { [weak self] in
            guard let self = self else { return }
            if withLiDAR && self.totalDistanceMeasurements > 0 {
                let successRate = Float(self.successfulDistanceMeasurements) / Float(self.totalDistanceMeasurements) * 100
           //     print("📏 LiDAR: \(self.successfulDistanceMeasurements)/\(self.totalDistanceMeasurements) mesures réussies (\(String(format: "%.1f", successRate))%)")
            }
        }
        
        // Afficher les objets avec ID de tracking
        for detection in detections {
            var output = "   - #\(detection.trackingInfo.id) \(detection.label): \(String(format: "%.1f", detection.confidence * 100))%"
            if let distance = detection.distance {
                let lidar = LiDARManager()
                output += " à \(lidar.formatDistance(distance))"
            }
            if detection.trackingInfo.opacity < 1.0 {
                output += " (mémoire)"
            }
            print(output)
        }
        
        // Afficher les objets importants si il y en a
        let importantObjects = getTopImportantObjects(maxCount: 3)
        if !importantObjects.isEmpty {
           // print("🏆 Top objets importants:")
            for (index, item) in importantObjects.enumerated() {
                let score = String(format: "%.1f", item.score * 100)
               // print("   \(index + 1). #\(item.object.trackingNumber) \(item.object.label): \(score)%")
            }
        }
    }
    
    func getAverageInferenceTime() -> Double? {
        return statsQueue.sync { [weak self] in
            guard let self = self, !self.inferenceHistory.isEmpty else { return nil }
            return self.inferenceHistory.reduce(0, +) / Double(self.inferenceHistory.count)
        }
    }
    
    func getMinMaxInferenceTime() -> (min: Double, max: Double)? {
        return statsQueue.sync { [weak self] in
            guard let self = self, !self.inferenceHistory.isEmpty else { return nil }
            return (self.inferenceHistory.min()!, self.inferenceHistory.max()!)
        }
    }
    
    func getPerformanceStats() -> String {
        return statsQueue.sync { [weak self] in
            guard let self = self, !self.inferenceHistory.isEmpty else {
                return "📊 Aucune statistique disponible"
            }
            
            let avg = self.inferenceHistory.reduce(0, +) / Double(self.inferenceHistory.count)
            let min = self.inferenceHistory.min()!
            let max = self.inferenceHistory.max()!
            let avgFPS = 1000.0 / avg
            
            var stats = "📊 Statistiques de performance (\(self.inferenceHistory.count) inférences):\n"
            stats += "   - Temps moyen: \(String(format: "%.1f", avg))ms\n"
            stats += "   - Temps min: \(String(format: "%.1f", min))ms\n"
            stats += "   - Temps max: \(String(format: "%.1f", max))ms\n"
            stats += "   - FPS moyen: \(String(format: "%.1f", avgFPS))\n"
            
            let variance = self.inferenceHistory.map { pow($0 - avg, 2) }.reduce(0, +) / Double(self.inferenceHistory.count)
            let stdDev = sqrt(variance)
            stats += "   - Écart-type: \(String(format: "%.1f", stdDev))ms\n"
            
            // Statistiques LiDAR
            if self.totalDistanceMeasurements > 0 {
                let successRate = Float(self.successfulDistanceMeasurements) / Float(self.totalDistanceMeasurements) * 100
                stats += "\n📏 Statistiques LiDAR:\n"
                stats += "   - Mesures tentées: \(self.totalDistanceMeasurements)\n"
                stats += "   - Mesures réussies: \(self.successfulDistanceMeasurements) (\(String(format: "%.1f", successRate))%)\n"
                
                if !self.lidarDistanceHistory.isEmpty {
                    let avgDistance = self.lidarDistanceHistory.reduce(0, +) / Float(self.lidarDistanceHistory.count)
                    let minDistance = self.lidarDistanceHistory.min()!
                    let maxDistance = self.lidarDistanceHistory.max()!
                    
                    stats += "   - Distance moyenne: \(String(format: "%.1f", avgDistance))m\n"
                    stats += "   - Distance min/max: \(String(format: "%.1f", minDistance))m - \(String(format: "%.1f", maxDistance))m"
                }
            }
            
            // Ajouter les statistiques de tracking
            stats += "\n\n" + self.objectTracker.getTrackingStats()
            
            // Ajouter les statistiques d'importance
            let importantObjectsStats = self.getImportanceStats()
            if !importantObjectsStats.contains("Aucun objet") {
                stats += "\n\n" + importantObjectsStats
            }
            
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
        print("📊 Statistiques de performance et tracking réinitialisées")
    }
    
    // MARK: - Tracking Controls
    
    func resetTracking() {
        objectTracker.reset()
    }
    
    func getTrackingStats() -> String {
        return objectTracker.getDetailedStats()
    }
    
    // MARK: - Class Management - THREAD SAFE
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
    
    func getIgnoredClasses() -> [String] {
        return Array(ignoredClasses).sorted()
    }
    
    func setActiveClasses(_ classes: [String]) {
        DispatchQueue.main.async { [weak self] in
            self?.activeClasses = Set(classes.map { $0.lowercased() })
        }
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
