//
//  ObjectTracker.swift
//  test
//
//  Created by Samy 📍 on 20/06/2025.
//  Object tracking system with color persistence
//  Updated with importance system support - 21/06/2025
//

import Foundation
import UIKit

struct TrackedObject {
    let id: UUID                    // ID unique
    let trackingNumber: Int         // Numéro d'affichage (1, 2, 3...)
    var lastSeen: Date             // Timestamp dernière détection
    let color: UIColor             // Couleur assignée (persistante)
    var label: String              // Type d'objet (person, car, etc.)
    var lastPosition: CGPoint      // Dernière position (centre)
    var lastRect: CGRect           // Dernière bounding box
    var confidence: Float          // Dernière confiance
    var distance: Float?           // Dernière distance LiDAR
    var framesNotSeen: Int         // Compteur frames perdues
    var isActive: Bool             // Actuellement détecté ou en mémoire
    var detectionHistory: [Date]   // Historique pour analyse de stabilité
    let firstDetectionTime: Date   // Première fois que l'objet a été détecté
    
    // Calculer l'opacité selon l'état
    var opacity: Double {
        return isActive ? 1.0 : 0.3
    }
    
    // Calculer la durée de vie de l'objet (depuis première détection)
    var lifetime: TimeInterval {
        return lastSeen.timeIntervalSince(firstDetectionTime)
    }
    
    // Vérifier si l'objet est expiré
    func isExpired(timeout: TimeInterval) -> Bool {
        return Date().timeIntervalSince(lastSeen) > timeout
    }
    
    // Vérifier si l'objet mérite d'être gardé en mémoire
    func shouldKeepInMemory(minimumLifetime: TimeInterval = 2.0) -> Bool {
        return lifetime >= minimumLifetime
    }
}

class ObjectTracker: ObservableObject {
    // Configuration
    private let proximityThreshold: CGFloat = 0.15      // 15% de la largeur d'écran
    private let maxFramesLost = 10                      // ~0.5s à 20fps
    private let memoryTimeout: TimeInterval = 3.0       // 3 secondes
    private let minimumLifetimeForMemory: TimeInterval = 2.0  // 2 secondes minimum pour être gardé en mémoire
    private let maxTrackedObjects = 20                  // Performance
    
    // Palette de couleurs prédéfinie
    private let colorPalette: [UIColor] = [
        .systemRed, .systemBlue, .systemGreen, .systemOrange, .systemPurple, .systemPink,
        .systemYellow, .systemTeal, .systemMint, .systemIndigo, .systemBrown,
        UIColor(red: 0.8, green: 0.2, blue: 0.6, alpha: 1.0),     // Magenta
        UIColor(red: 0.2, green: 0.8, blue: 0.4, alpha: 1.0),     // Vert lime
        UIColor(red: 0.9, green: 0.6, blue: 0.1, alpha: 1.0),     // Orange foncé
        UIColor(red: 0.3, green: 0.3, blue: 0.9, alpha: 1.0),     // Bleu roi
        UIColor(red: 0.7, green: 0.9, blue: 0.2, alpha: 1.0),     // Jaune-vert
        UIColor(red: 0.9, green: 0.3, blue: 0.3, alpha: 1.0),     // Rouge corail
        UIColor(red: 0.4, green: 0.8, blue: 0.8, alpha: 1.0),     // Turquoise
        UIColor(red: 0.8, green: 0.4, blue: 0.9, alpha: 1.0)      // Violet clair
    ]
    
    // État du tracker
    @Published private var trackedObjects: [TrackedObject] = []
    private var nextTrackingNumber = 1
    private var colorIndex = 0
    
    // Statistiques
    private var totalObjectsTracked = 0
    private var activeTrackingSessions = 0
    
    init() {
        print("🎯 ObjectTracker initialisé avec critère de durée de vie intelligente")
        print("   - Durée min. pour mémoire: \(minimumLifetimeForMemory)s")
        print("   - Objets < \(minimumLifetimeForMemory)s → suppression directe")
        print("   - Objets ≥ \(minimumLifetimeForMemory)s → mémoire \(memoryTimeout)s")
    }
    
    // MARK: - Interface publique
    
    /// Point d'entrée principal : traiter une nouvelle frame de détections
    func processDetections(_ detections: [(rect: CGRect, label: String, confidence: Float, distance: Float?)])
    -> [(rect: CGRect, label: String, confidence: Float, distance: Float?, trackingInfo: (id: Int, color: UIColor, opacity: Double))] {
        
        let frameStartTime = Date()
        
        // Phase 1: MATCHING - Associer détections aux objets existants
        let (matchedObjects, newDetections) = matchDetectionsToObjects(detections)
        
        // Phase 2: UPDATE - Mettre à jour objets matchés et créer nouveaux objets
        updateMatchedObjects(matchedObjects)
        createNewObjects(newDetections, frameTime: frameStartTime)
        
        // Phase 3: CLEANUP - Gérer objets perdus et expirés
        cleanupLostObjects(frameTime: frameStartTime)
        
        // Retourner les détections enrichies avec infos de tracking
        return generateEnrichedDetections()
    }
    
    /// Réinitialiser le tracker
    func reset() {
        trackedObjects.removeAll()
        nextTrackingNumber = 1
        colorIndex = 0
        totalObjectsTracked = 0
        activeTrackingSessions = 0
        shortTermObjects = 0
        longTermObjects = 0
        print("🔄 ObjectTracker réinitialisé avec critère de durée de vie")
    }
    
    /// Obtenir tous les objets trackés (pour le système d'importance)
    func getAllTrackedObjects() -> [TrackedObject] {
        return trackedObjects
    }
    
    /// Obtenir seulement les objets actifs
    func getActiveTrackedObjects() -> [TrackedObject] {
        return trackedObjects.filter { $0.isActive }
    }
    
    /// Obtenir seulement les objets en mémoire
    func getMemoryTrackedObjects() -> [TrackedObject] {
        return trackedObjects.filter { !$0.isActive }
    }
    
    /// Obtenir un objet spécifique par son ID de tracking
    func getTrackedObject(by trackingNumber: Int) -> TrackedObject? {
        return trackedObjects.first { $0.trackingNumber == trackingNumber }
    }
    
    /// Obtenir le nombre total d'objets trackés
    func getTrackedObjectCount() -> (active: Int, memory: Int, total: Int) {
        let active = trackedObjects.filter { $0.isActive }.count
        let memory = trackedObjects.filter { !$0.isActive }.count
        return (active: active, memory: memory, total: trackedObjects.count)
    }
    
    /// Obtenir les statistiques du tracker
    func getTrackingStats() -> String {
        let activeCount = trackedObjects.filter { $0.isActive }.count
        let memoryCount = trackedObjects.filter { !$0.isActive }.count
        
        var stats = "🎯 Statistiques de tracking:\n"
        stats += "   - Objets actifs: \(activeCount)\n"
        stats += "   - Objets en mémoire: \(memoryCount)\n"
        stats += "   - Total trackés: \(totalObjectsTracked)\n"
        stats += "   - Sessions actives: \(activeTrackingSessions)\n"
        stats += "   - Timeout mémoire: \(String(format: "%.1f", memoryTimeout))s\n"
        stats += "   - Durée min. pour mémoire: \(String(format: "%.1f", minimumLifetimeForMemory))s\n"
        stats += "   - Seuil proximité: \(String(format: "%.0f", proximityThreshold * 100))%"
        
        return stats
    }
    
    // MARK: - Phase 1: MATCHING
    
    private func matchDetectionsToObjects(_ detections: [(rect: CGRect, label: String, confidence: Float, distance: Float?)])
    -> (matched: [(TrackedObject, (rect: CGRect, label: String, confidence: Float, distance: Float?))], unmatched: [(rect: CGRect, label: String, confidence: Float, distance: Float?)]) {
        
        var matchedPairs: [(TrackedObject, (rect: CGRect, label: String, confidence: Float, distance: Float?))] = []
        var unmatchedDetections = detections
        var usedObjectIndices: Set<Int> = []
        
        // Pour chaque détection, chercher le meilleur match
        for (detectionIndex, detection) in detections.enumerated() {
            var bestMatch: (objectIndex: Int, score: Double)? = nil
            
            // Chercher parmi les objets de même classe
            for (objectIndex, trackedObject) in trackedObjects.enumerated() {
                guard !usedObjectIndices.contains(objectIndex) else { continue }
                guard trackedObject.label.lowercased() == detection.label.lowercased() else { continue }
                
                // Calculer le score de matching (proximité)
                let score = calculateMatchingScore(detection: detection, trackedObject: trackedObject)
                
                // Garder le meilleur score si supérieur au seuil
                if score > Double(proximityThreshold) {
                    if bestMatch == nil || score > bestMatch!.score {
                        bestMatch = (objectIndex, score)
                    }
                }
            }
            
            // Si un match a été trouvé
            if let match = bestMatch {
                let trackedObject = trackedObjects[match.objectIndex]
                matchedPairs.append((trackedObject, detection))
                usedObjectIndices.insert(match.objectIndex)
                
                // Retirer de la liste des non-matchés
                if let index = unmatchedDetections.firstIndex(where: {
                    $0.rect == detection.rect && $0.label == detection.label
                }) {
                    unmatchedDetections.remove(at: index)
                }
            }
        }
        
        return (matchedPairs, unmatchedDetections)
    }
    
    private func calculateMatchingScore(detection: (rect: CGRect, label: String, confidence: Float, distance: Float?), trackedObject: TrackedObject) -> Double {
        // Calculer les centres des bounding boxes
        let detectionCenter = CGPoint(
            x: detection.rect.midX,
            y: detection.rect.midY
        )
        
        let trackedCenter = trackedObject.lastPosition
        
        // Distance euclidienne normalisée
        let distance = sqrt(pow(detectionCenter.x - trackedCenter.x, 2) + pow(detectionCenter.y - trackedCenter.y, 2))
        
        // Convertir en score (plus la distance est petite, plus le score est élevé)
        let normalizedDistance = distance / proximityThreshold
        let score = max(0.0, 1.0 - Double(normalizedDistance))
        
        return score
    }
    
    // MARK: - Phase 2: UPDATE
    
    private func updateMatchedObjects(_ matchedPairs: [(TrackedObject, (rect: CGRect, label: String, confidence: Float, distance: Float?))]) {
        for (trackedObject, detection) in matchedPairs {
            if let index = trackedObjects.firstIndex(where: { $0.id == trackedObject.id }) {
                // Mettre à jour l'objet existant
                trackedObjects[index].lastSeen = Date()
                trackedObjects[index].lastPosition = CGPoint(x: detection.rect.midX, y: detection.rect.midY)
                trackedObjects[index].lastRect = detection.rect
                trackedObjects[index].confidence = detection.confidence
                trackedObjects[index].distance = detection.distance
                trackedObjects[index].framesNotSeen = 0
                trackedObjects[index].isActive = true
                trackedObjects[index].detectionHistory.append(Date())
                
                // Limiter l'historique pour la performance
                if trackedObjects[index].detectionHistory.count > 30 {
                    trackedObjects[index].detectionHistory.removeFirst()
                }
            }
        }
    }
    
    private func createNewObjects(_ newDetections: [(rect: CGRect, label: String, confidence: Float, distance: Float?)], frameTime: Date) {
        // Vérifier la limite d'objets
        let currentObjectCount = trackedObjects.count
        let newObjectsToCreate = min(newDetections.count, maxTrackedObjects - currentObjectCount)
        
        for i in 0..<newObjectsToCreate {
            let detection = newDetections[i]
            
            let newObject = TrackedObject(
                id: UUID(),
                trackingNumber: nextTrackingNumber,
                lastSeen: frameTime,
                color: getNextColor(),
                label: detection.label,
                lastPosition: CGPoint(x: detection.rect.midX, y: detection.rect.midY),
                lastRect: detection.rect,
                confidence: detection.confidence,
                distance: detection.distance,
                framesNotSeen: 0,
                isActive: true,
                detectionHistory: [frameTime],
                firstDetectionTime: frameTime  // Enregistrer le moment de première détection
            )
            
            trackedObjects.append(newObject)
            nextTrackingNumber += 1
            totalObjectsTracked += 1
            activeTrackingSessions += 1
            
            print("✨ Nouvel objet tracké #\(newObject.trackingNumber): \(detection.label) (couleur: \(getColorName(newObject.color)))")
        }
        
        if newDetections.count > newObjectsToCreate {
            print("⚠️ Limite d'objets atteinte (\(maxTrackedObjects)), \(newDetections.count - newObjectsToCreate) détections ignorées")
        }
    }
    
    // MARK: - Phase 3: CLEANUP avec critère de durée de vie
    
    private func cleanupLostObjects(frameTime: Date) {
        var objectsToRemove: [UUID] = []
        
        for (index, trackedObject) in trackedObjects.enumerated() {
            // Vérifier si l'objet n'a pas été matché dans cette frame
            if trackedObject.lastSeen < frameTime {
                trackedObjects[index].framesNotSeen += 1
                
                // Marquer comme inactif si trop de frames perdues
                if trackedObjects[index].framesNotSeen >= maxFramesLost {
                    trackedObjects[index].isActive = false
                    
                    // NOUVELLE LOGIQUE : Vérifier si l'objet mérite d'être gardé en mémoire
                    if !trackedObject.shouldKeepInMemory(minimumLifetime: minimumLifetimeForMemory) {
                        // Objet détecté < 2 secondes → Suppression directe
                        objectsToRemove.append(trackedObject.id)
                        activeTrackingSessions -= 1
                        shortTermObjects += 1  // Incrémenter compteur objets court terme
                        
                        print("🗑️ Objet #\(trackedObject.trackingNumber) (\(trackedObject.label)) supprimé directement (durée de vie: \(String(format: "%.1f", trackedObject.lifetime))s < \(minimumLifetimeForMemory)s)")
                        continue
                    } else {
                        longTermObjects += 1  // Incrémenter compteur objets long terme
                        print("👻 Objet #\(trackedObject.trackingNumber) (\(trackedObject.label)) gardé en mémoire (durée de vie: \(String(format: "%.1f", trackedObject.lifetime))s)")
                    }
                }
                
                // Vérifier expiration pour les objets en mémoire
                if !trackedObject.isActive && trackedObject.isExpired(timeout: memoryTimeout) {
                    objectsToRemove.append(trackedObject.id)
                    activeTrackingSessions -= 1
                    
                    print("🗑️ Objet #\(trackedObject.trackingNumber) (\(trackedObject.label)) supprimé après mémoire (\(String(format: "%.1f", frameTime.timeIntervalSince(trackedObject.lastSeen)))s)")
                }
            }
        }
        
        // Supprimer les objets expirés
        trackedObjects.removeAll { objectsToRemove.contains($0.id) }
    }
    
    // MARK: - Génération des résultats
    
    private func generateEnrichedDetections() -> [(rect: CGRect, label: String, confidence: Float, distance: Float?, trackingInfo: (id: Int, color: UIColor, opacity: Double))] {
        var enrichedDetections: [(rect: CGRect, label: String, confidence: Float, distance: Float?, trackingInfo: (id: Int, color: UIColor, opacity: Double))] = []
        
        for trackedObject in trackedObjects {
            let trackingInfo = (
                id: trackedObject.trackingNumber,
                color: trackedObject.color,
                opacity: trackedObject.opacity
            )
            
            let enrichedDetection = (
                rect: trackedObject.lastRect,
                label: trackedObject.label,
                confidence: trackedObject.confidence,
                distance: trackedObject.distance,
                trackingInfo: trackingInfo
            )
            
            enrichedDetections.append(enrichedDetection)
        }
        
        return enrichedDetections
    }
    
    // MARK: - Helpers
    
    private func getNextColor() -> UIColor {
        let color = colorPalette[colorIndex % colorPalette.count]
        colorIndex += 1
        return color
    }
    
    private func getColorName(_ color: UIColor) -> String {
        // Approximation pour le debug
        if color == .systemRed { return "rouge" }
        if color == .systemBlue { return "bleu" }
        if color == .systemGreen { return "vert" }
        if color == .systemOrange { return "orange" }
        if color == .systemPurple { return "violet" }
        if color == .systemPink { return "rose" }
        if color == .systemYellow { return "jaune" }
        if color == .systemTeal { return "cyan" }
        return "couleur_\(colorIndex)"
    }
    
    // MARK: - Configuration avancée
    
    // Statistiques avec objets court terme vs long terme
    private var shortTermObjects = 0  // Objets supprimés < 2s
    private var longTermObjects = 0   // Objets gardés en mémoire
    
    // Configurer la durée minimum pour la mémoire (non exposé pour l'instant)
    private func setMinimumLifetimeForMemory(_ duration: TimeInterval) {
        // Cette méthode pourrait être exposée plus tard si besoin
    }
    
    // Obtenir les ratios de survie des objets
    func getSurvivalStats() -> String {
        let total = shortTermObjects + longTermObjects
        guard total > 0 else { return "Aucune donnée de survie" }
        
        let shortTermPercent = Float(shortTermObjects) / Float(total) * 100
        let longTermPercent = Float(longTermObjects) / Float(total) * 100
        
        var stats = "📈 Statistiques de survie:\n"
        stats += "   - Objets court terme (< \(minimumLifetimeForMemory)s): \(shortTermObjects) (\(String(format: "%.1f", shortTermPercent))%)\n"
        stats += "   - Objets long terme (≥ \(minimumLifetimeForMemory)s): \(longTermObjects) (\(String(format: "%.1f", longTermPercent))%)"
        
        return stats
    }
    
    func getDetailedStats() -> String {
        let activeObjects = trackedObjects.filter { $0.isActive }
        let memoryObjects = trackedObjects.filter { !$0.isActive }
        
        var stats = getTrackingStats()
        
        // Ajouter les statistiques de survie
        if shortTermObjects + longTermObjects > 0 {
            stats += "\n\n" + getSurvivalStats()
        }
        
        stats += "\n\n🎨 Objets actifs:"
        
        for obj in activeObjects {
            let lifetimeStr = String(format: "%.1f", obj.lifetime)
            let qualifier = obj.lifetime >= minimumLifetimeForMemory ? "✅" : "⏳"
            stats += "\n   - #\(obj.trackingNumber) \(obj.label) \(qualifier) (durée: \(lifetimeStr)s)"
        }
        
        if !memoryObjects.isEmpty {
            stats += "\n\n👻 Objets en mémoire:"
            for obj in memoryObjects {
                let lostTime = String(format: "%.1f", Date().timeIntervalSince(obj.lastSeen))
                let lifetimeStr = String(format: "%.1f", obj.lifetime)
                stats += "\n   - #\(obj.trackingNumber) \(obj.label) (vécu: \(lifetimeStr)s, perdu: \(lostTime)s)"
            }
        }
        
        return stats
    }
    
    func resetStats() {
        totalObjectsTracked = 0
        activeTrackingSessions = 0
        shortTermObjects = 0
        longTermObjects = 0
        print("📊 Statistiques de tracking réinitialisées")
    }
}
