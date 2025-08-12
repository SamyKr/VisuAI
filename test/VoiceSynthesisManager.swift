//
//  VoiceSynthesisManager.swift
//  VizAI Vision
//
//  Système de synthèse vocale OPTIMISÉ avec OBJETS STATIQUES/DYNAMIQUES
//  NOUVELLE RÈGLE : Objets dynamiques annoncés à distance critique + 2m
//                   Objets statiques annoncés à distance critique exacte
//

import Foundation
import AVFoundation
import UIKit

// MARK: - Enums et Structures

enum DistanceZone {
    case farDynamic     // Pour objets dynamiques uniquement : critique + 2m
    case critical       // < distance critique
    case safe           // >= distance critique
    
    static func from(distance: Float?, criticalDistance: Float, isStatique: Bool) -> DistanceZone {
        guard let dist = distance else { return .safe }
        
        if dist < criticalDistance {
            return .critical
        } else if !isStatique && dist < (criticalDistance + 2.0) {
            return .farDynamic
        } else {
            return .safe
        }
    }
}

enum Direction: String, CaseIterable {
    case front = "devant"
    case left = "à gauche"
    case right = "à droite"
    case frontLeft = "devant à gauche"
    case frontRight = "devant à droite"
    
    static func from(boundingBox: CGRect) -> Direction {
        let centerX = boundingBox.midX
        let centerY = boundingBox.midY
        
        if centerX < 0.3 {
            if centerY < 0.4 {
                return .frontLeft
            } else {
                return .left
            }
        } else if centerX > 0.7 {
            if centerY < 0.4 {
                return .frontRight
            } else {
                return .right
            }
        } else {
            return .front
        }
    }
}

// Structure de message simplifiée
struct VoiceMessage {
    let text: String
    let objectId: Int
    let objectType: String
    let isStatique: Bool
    let timestamp: Date
    let expirationTime: Date
    
    init(text: String, objectId: Int, objectType: String, isStatique: Bool, timestamp: Date, lifetimeSeconds: TimeInterval = 3.0) {
        self.text = text
        self.objectId = objectId
        self.objectType = objectType.lowercased()
        self.isStatique = isStatique
        self.timestamp = timestamp
        self.expirationTime = timestamp.addingTimeInterval(lifetimeSeconds)
    }
    
    func isExpired(at currentTime: Date) -> Bool {
        return currentTime > expirationTime
    }
}

struct ObjectMovement {
    let previousDistance: Float
    let currentDistance: Float
    let isApproaching: Bool
    let isMovingAway: Bool
    
    init(previous: Float, current: Float) {
        self.previousDistance = previous
        self.currentDistance = current
        let threshold: Float = 0.3
        self.isApproaching = (previous - current) > threshold
        self.isMovingAway = (current - previous) > threshold
    }
}

// MARK: - VoiceSynthesisManager

class VoiceSynthesisManager: NSObject, ObservableObject {
    
    // MARK: - Configuration PROXIMITÉ avec OBJETS STATIQUES/DYNAMIQUES
    private var criticalDistance: Float = 2.0
    private let minimumRepeatInterval: TimeInterval = 3.0
    private let movementUpdateInterval: TimeInterval = 2.0
    private let globalAnnouncementCooldown: TimeInterval = 1.0
    private var lastGlobalAnnouncement: Date = Date.distantPast
    
    // NOUVEAU : Configuration priorité proximité avec distinction statique/dynamique
    private let maxSimultaneousAnnouncements: Int = 3
    private let messageLifetime: TimeInterval = 2.0
    private let proximityPriorityThreshold: Float = 1.5  // Seuil priorité absolue
    private let dynamicObjectExtraDistance: Float = 2.0  // Distance supplémentaire pour objets dynamiques
    
    // Variables pour diversification (secondaire)
    private var lastAnnouncedTypes: [String: Date] = [:]
    private let typeAnnouncementCooldown: TimeInterval = 3.0
    
    // NOUVEAU : Listes séparées pour objets statiques et dynamiques
    private var dangerousObjects: Set<String> = []
    private var dynamicDangerousObjects: Set<String> = []  // Objets mobiles
    private var statiquesDangerousObjects: Set<String> = []   // Objets statiques
    
    // NOUVEAU : Référence au gestionnaire de configuration des objets
    private weak var objectConfigManager: ObjectConfigurationManager?
    
    // MARK: - État interne
    private var lastCriticalAnnouncements: [Int: Date] = [:]
    private var lastMovementAnnouncements: [Int: Date] = [:]
    private var objectDistanceHistory: [Int: Float] = [:]
    private var messageQueue: [VoiceMessage] = []
    
    // NOUVEAU : Référence aux objets actuels pour distance temps réel
    private var currentTrackedObjects: [Int: TrackedObject] = [:]
    
    // MARK: - Support pour interaction vocale
    @Published var isInterrupted = false
    private var interruptionReason: String = ""
    private var lastInterruptionTime: Date = Date.distantPast
    private let interruptionCooldown: TimeInterval = 1.0
    
    // MARK: - Synthèse vocale
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var isCurrentlySpeaking = false
    
    // MARK: - Dictionnaire de traduction
    private let translationDictionary: [String: String] = [
        "person": "personne",
        "cyclist": "cycliste",
        "motorcyclist": "motocycliste",
        "car": "voiture",
        "truck": "camion",
        "bus": "bus",
        "motorcycle": "moto",
        "bicycle": "vélo",
        "slow_vehicle": "véhicule lent",
        "vehicle_group": "groupe de véhicules",
        "rail_vehicle": "véhicule ferroviaire",
        "boat": "bateau",
        "sidewalk": "trottoir",
        "road": "route",
        "crosswalk": "passage piéton",
        "driveway": "allée",
        "bike_lane": "piste cyclable",
        "parking_area": "zone de stationnement",
        "rail_track": "voie ferrée",
        "service_lane": "voie de service",
        "curb": "bordure",
        "wall": "mur",
        "fence": "clôture",
        "guard_rail": "glissière de sécurité",
        "temporary_barrier": "barrière temporaire",
        "barrier_other": "autre barrière",
        "barrier": "barrière",
        "pole": "poteau",
        "traffic_light": "feu de circulation",
        "traffic_sign": "panneau de signalisation",
        "street_light": "lampadaire",
        "traffic_cone": "cône",
        "bench": "banc",
        "trash_can": "poubelle",
        "fire_hydrant": "bouche d'incendie",
        "mailbox": "boîte aux lettres",
        "parking_meter": "parcmètre",
        "bike_rack": "support à vélos",
        "phone_booth": "cabine téléphonique",
        "pothole": "nid-de-poule",
        "manhole": "plaque d'égout",
        "catch_basin": "regard d'égout",
        "water_valve": "vanne d'eau",
        "junction_box": "boîtier de jonction",
        "building": "bâtiment",
        "bridge": "pont",
        "tunnel": "tunnel",
        "garage": "garage",
        "vegetation": "végétation",
        "water": "eau",
        "terrain": "terrain",
        "animals": "animaux"
    ]
    
    override init() {
        super.init()
        speechSynthesizer.delegate = self
        setupAudioSession()
        loadCriticalDistanceFromUserDefaults()
    }
    
    // MARK: - Configuration
    
    private func loadCriticalDistanceFromUserDefaults() {
        let userDefaults = UserDefaults.standard
        let savedDistance = userDefaults.float(forKey: "safety_critical_distance")
        
        if savedDistance > 0 {
            criticalDistance = savedDistance
        }
    }
    
    func updateCriticalDistance(_ distance: Float) {
        criticalDistance = distance
        lastCriticalAnnouncements.removeAll()
        lastMovementAnnouncements.removeAll()
        objectDistanceHistory.removeAll()
    }
    
    // NOUVEAU : Mise à jour séparée pour objets dangereux et objets dynamiques
    func updateDangerousObjects(_ objects: Set<String>) {
        dangerousObjects = objects
        lastCriticalAnnouncements.removeAll()
        lastMovementAnnouncements.removeAll()
        objectDistanceHistory.removeAll()
        lastAnnouncedTypes.removeAll()
    }
    
    func updateDynamicDangerousObjects(_ objects: Set<String>) {
        dynamicDangerousObjects = objects
        statiquesDangerousObjects = dangerousObjects.subtracting(dynamicDangerousObjects)
        lastCriticalAnnouncements.removeAll()
        lastMovementAnnouncements.removeAll()
        objectDistanceHistory.removeAll()
        lastAnnouncedTypes.removeAll()
    }
    
    func setObjectConfigManager(_ manager: ObjectConfigurationManager) {
        objectConfigManager = manager
    }
    
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            try audioSession.setCategory(
                .playback,
                mode: .spokenAudio,
                options: [
                    .duckOthers,
                    .allowBluetooth,
                    .allowBluetoothA2DP,
                    .allowAirPlay,
                    .interruptSpokenAudioAndMixWithOthers
                ]
            )
            
            try audioSession.setActive(true)
            try audioSession.overrideOutputAudioPort(.none)
            
        } catch {
            print("❌ Erreur configuration audio: \(error)")
        }
    }
    
    // MARK: - Méthodes d'interaction
    
    func interruptForInteraction(reason: String = "Interaction utilisateur") {
        let currentTime = Date()
        
        guard currentTime.timeIntervalSince(lastInterruptionTime) >= interruptionCooldown else {
            return
        }
        
        isInterrupted = true
        interruptionReason = reason
        lastInterruptionTime = currentTime
        
        speechSynthesizer.stopSpeaking(at: .immediate)
        messageQueue.removeAll()
        isCurrentlySpeaking = false
    }
    
    func resumeAfterInteraction() {
        guard isInterrupted else { return }
        
        isInterrupted = false
        interruptionReason = ""
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.processMessageQueue()
        }
    }
    
    func speakInteraction(_ text: String) {
        let interactionMessage = VoiceMessage(
            text: text,
            objectId: -999,
            objectType: "interaction",
            isStatique: true,
            timestamp: Date()
        )
        
        messageQueue.insert(interactionMessage, at: 0)
        
        if !isCurrentlySpeaking {
            processMessageQueue()
        }
    }
    
    // MARK: - Interface principale OPTIMISÉE STATIQUE/DYNAMIQUE
    
    func processImportantObjects(_ importantObjects: [(object: TrackedObject, score: Float)]) {
        if isInterrupted {
            return
        }
        
        let currentTime = Date()
        
        // NOUVEAU : Mettre à jour les références d'objets pour distance temps réel
        updateCurrentObjectReferences(importantObjects)
        
        // 1. Nettoyer la queue
        cleanupMessageQueue(currentObjects: importantObjects, currentTime: currentTime)
        
        // 2. Arrêt si plus rien
        guard !importantObjects.isEmpty else {
            stopSpeaking()
            clearAllAnnouncements()
            return
        }
        
        // 3. NOUVELLE LOGIQUE : Détecter menaces par PROXIMITÉ avec distinction statique/dynamique
        let proximityThreats = detectProximityThreatsWithStaticDynamic(importantObjects, currentTime: currentTime)
        
        if !proximityThreats.isEmpty {
            announceProximityThreats(proximityThreats, currentTime: currentTime)
        }
        
        // 4. Mettre à jour l'historique
        updateDistanceHistory(importantObjects)
        cleanupOldAnnouncements(currentObjects: importantObjects)
    }
    
    // Mettre à jour les références d'objets
    private func updateCurrentObjectReferences(_ objects: [(object: TrackedObject, score: Float)]) {
        currentTrackedObjects.removeAll()
        for (object, _) in objects {
            currentTrackedObjects[object.trackingNumber] = object
        }
    }
    
    // NOUVEAU : Détection basée sur la PROXIMITÉ avec objets statiques/dynamiques
    private func detectProximityThreatsWithStaticDynamic(_ objects: [(object: TrackedObject, score: Float)], currentTime: Date) -> [TrackedObject] {
        // Vérifier cooldown global
        let timeSinceLastGlobalAnnouncement = currentTime.timeIntervalSince(lastGlobalAnnouncement)
        if timeSinceLastGlobalAnnouncement < globalAnnouncementCooldown {
            return []
        }
        
        // Vérifier si queue pleine
        if messageQueue.count >= maxSimultaneousAnnouncements {
            return []
        }
        
        var candidates: [TrackedObject] = []
        
        // PRIORITÉ 1 : Objets TRÈS PROCHES (< 1.5m) = ALERTE IMMÉDIATE
        var veryCloseObjects: [TrackedObject] = []
        
        // PRIORITÉ 2 : Objets dans leur zone d'alerte respective
        var criticalObjects: [TrackedObject] = []       // Statiques à distance critique
        var dynamicFarObjects: [TrackedObject] = []     // Dynamiques à distance critique + 2m
        
        // PRIORITÉ 3 : Nouveaux objets
        var newObjects: [TrackedObject] = []
        
        // PRIORITÉ 4 : Mouvements d'approche
        var movementObjects: [TrackedObject] = []
        
        for (object, _) in objects {
            guard let distance = object.distance else { continue }
            guard isDangerousObject(object) else { continue }
            
            let objectType = object.label.lowercased()
            let isStatique = isStatiqueObject(object)
            let hasBeenAnnounced = lastCriticalAnnouncements[object.trackingNumber] != nil
            
            // 🐛 DEBUG: Log pour diagnostiquer
            if objectType.contains("trash") || objectType == "trash_can" {
                print("🗑️ DEBUG Poubelle:")
                print("   - Distance: \(distance)m")
                print("   - Distance critique: \(criticalDistance)m")
                print("   - Est statique: \(isStatique)")
                print("   - Est dangereuse: \(isDangerousObject(object))")
                print("   - Label détecté: '\(object.label)'")
                print("   - ObjectType: '\(objectType)'")
            }
            
            // 🎯 RÈGLE STRICTE : Vérifier selon type d'objet D'ABORD
            var shouldAnnounce = false
            
            if isStatique {
                // Objet statique : SEULEMENT si distance < distance critique
                shouldAnnounce = distance < criticalDistance
                // 🐛 DEBUG
                if objectType.contains("trash") || objectType == "trash_can" {
                    print("   - Statique: shouldAnnounce = \(distance) < \(criticalDistance) = \(shouldAnnounce)")
                }
            } else {
                // Objet dynamique : si distance < (distance critique + 2m)
                shouldAnnounce = distance < (criticalDistance + dynamicObjectExtraDistance)
                // 🐛 DEBUG
                if objectType.contains("trash") || objectType == "trash_can" {
                    print("   - Mobile: shouldAnnounce = \(distance) < \(criticalDistance + dynamicObjectExtraDistance) = \(shouldAnnounce)")
                }
            }
            
            // Si l'objet n'est pas dans sa zone d'alerte, l'ignorer complètement
            guard shouldAnnounce else {
                // 🐛 DEBUG
                if objectType.contains("trash") || objectType == "trash_can" {
                    print("   ✅ Poubelle IGNORÉE (hors zone)")
                }
                continue
            }
            
            // PRIORITÉ ABSOLUE : Distance < 1.5m (pour objets qui passent déjà le filtre)
            if distance < proximityPriorityThreshold {
                // 🐛 DEBUG
                if objectType.contains("trash") || objectType == "trash_can" {
                    print("   ❌ Poubelle < 1.5m -> ALERTE PRIORITÉ ABSOLUE")
                }
                // Cooldown normal même pour objets très proches
                if hasBeenAnnounced {
                    if let lastAnnouncement = lastCriticalAnnouncements[object.trackingNumber] {
                        let timeSince = currentTime.timeIntervalSince(lastAnnouncement)
                        if timeSince < minimumRepeatInterval {
                            continue
                        }
                    }
                }
                veryCloseObjects.append(object)
                continue
            }
            
            // 🐛 DEBUG
            if objectType.contains("trash") || objectType == "trash_can" {
                print("   ❌ Poubelle SERA ANNONCÉE (dans zone)")
            }
            
            // L'objet passe le filtre de distance, maintenant traiter selon le type d'annonce
            if !hasBeenAnnounced {
                // Nouvel objet dans sa zone d'alerte
                newObjects.append(object)
                continue
            }
            
            // Objet déjà annoncé - vérifier cooldowns pour re-annonce
            if let lastAnnouncement = lastCriticalAnnouncements[object.trackingNumber] {
                let timeSinceLastAnnouncement = currentTime.timeIntervalSince(lastAnnouncement)
                if timeSinceLastAnnouncement < minimumRepeatInterval {
                    continue
                }
            }
            
            // Vérifier cooldown par type (diversification secondaire)
            if let lastTypeAnnouncement = lastAnnouncedTypes[objectType] {
                let timeSinceType = currentTime.timeIntervalSince(lastTypeAnnouncement)
                if timeSinceType < typeAnnouncementCooldown {
                    continue
                }
            }
            
            // Classer selon la zone pour la re-annonce
            if distance < criticalDistance {
                criticalObjects.append(object)
            } else {
                // Zone étendue pour objets dynamiques uniquement
                dynamicFarObjects.append(object)
            }
            
            // Vérifier mouvement d'approche pour objets déjà annoncés
            if let previousDistance = objectDistanceHistory[object.trackingNumber] {
                let movement = ObjectMovement(previous: previousDistance, current: distance)
                
                if movement.isApproaching {
                    if let lastMovement = lastMovementAnnouncements[object.trackingNumber] {
                        let timeSinceMovement = currentTime.timeIntervalSince(lastMovement)
                        if timeSinceMovement >= movementUpdateInterval {
                            movementObjects.append(object)
                        }
                    } else {
                        movementObjects.append(object)
                    }
                }
            }
        }
        
        // NOUVEAU : Priorisation par PROXIMITÉ avec distinction statique/dynamique
        return prioritizeByProximityWithStaticDynamic(
            veryClose: veryCloseObjects,
            critical: criticalObjects,
            dynamicFar: dynamicFarObjects,
            new: newObjects,
            movement: movementObjects
        )
    }
    
    // NOUVEAU : Priorisation par proximité avec objets statiques/dynamiques
    private func prioritizeByProximityWithStaticDynamic(
        veryClose: [TrackedObject],
        critical: [TrackedObject],
        dynamicFar: [TrackedObject],
        new: [TrackedObject],
        movement: [TrackedObject]
    ) -> [TrackedObject] {
        var result: [TrackedObject] = []
        let remainingSlots = maxSimultaneousAnnouncements - messageQueue.count
        
        // PRIORITÉ 1 : Objets TRÈS proches (< 1.5m) - TOUS annoncés
        let sortedVeryClose = veryClose.sorted { obj1, obj2 in
            guard let dist1 = obj1.distance, let dist2 = obj2.distance else { return false }
            return dist1 < dist2
        }
        result.append(contentsOf: sortedVeryClose)
        
        if result.count >= remainingSlots {
            return Array(result.prefix(remainingSlots))
        }
        
        // PRIORITÉ 2 : Nouveaux objets (statiques + dynamiques), triés par distance
        let sortedNew = new.sorted { obj1, obj2 in
            guard let dist1 = obj1.distance, let dist2 = obj2.distance else { return false }
            return dist1 < dist2
        }
        
        let newSlotsUsed = min(sortedNew.count, remainingSlots - result.count)
        result.append(contentsOf: Array(sortedNew.prefix(newSlotsUsed)))
        
        if result.count >= remainingSlots {
            return result
        }
        
        // PRIORITÉ 3 : Objets critiques (statiques à distance critique)
        let usedTypes = Set(result.map { $0.label.lowercased() })
        let filteredCritical = critical.filter { !usedTypes.contains($0.label.lowercased()) }
        let sortedCritical = filteredCritical.sorted { obj1, obj2 in
            guard let dist1 = obj1.distance, let dist2 = obj2.distance else { return false }
            return dist1 < dist2
        }
        
        let criticalSlotsUsed = min(sortedCritical.count, remainingSlots - result.count)
        result.append(contentsOf: Array(sortedCritical.prefix(criticalSlotsUsed)))
        
        if result.count >= remainingSlots {
            return result
        }
        
        // PRIORITÉ 4 : Objets dynamiques lointains (à distance critique + 2m)
        let finalUsedTypes = Set(result.map { $0.label.lowercased() })
        let filteredDynamicFar = dynamicFar.filter { !finalUsedTypes.contains($0.label.lowercased()) }
        let sortedDynamicFar = filteredDynamicFar.sorted { obj1, obj2 in
            guard let dist1 = obj1.distance, let dist2 = obj2.distance else { return false }
            return dist1 < dist2
        }
        
        let dynamicFarSlotsUsed = min(sortedDynamicFar.count, remainingSlots - result.count)
        result.append(contentsOf: Array(sortedDynamicFar.prefix(dynamicFarSlotsUsed)))
        
        if result.count >= remainingSlots {
            return result
        }
        
        // PRIORITÉ 5 : Mouvements d'approche
        let movementUsedTypes = Set(result.map { $0.label.lowercased() })
        let filteredMovement = movement.filter { !movementUsedTypes.contains($0.label.lowercased()) }
        let sortedMovement = filteredMovement.sorted { obj1, obj2 in
            guard let dist1 = obj1.distance, let dist2 = obj2.distance else { return false }
            return dist1 < dist2
        }
        
        let movementSlotsUsed = min(sortedMovement.count, remainingSlots - result.count)
        result.append(contentsOf: Array(sortedMovement.prefix(movementSlotsUsed)))
        
        return result
    }
    
    private func isDangerousObject(_ object: TrackedObject) -> Bool {
        let label = object.label.lowercased()
        return dangerousObjects.contains(label)
    }
    
    // NOUVEAU : Détermine si un objet est statique
    private func isStatiqueObject(_ object: TrackedObject) -> Bool {
        // Utiliser le gestionnaire de configuration si disponible
        if let configManager = objectConfigManager {
            return configManager.isStatique(object.label)
        }
        
        // Fallback : utiliser la liste des objets dynamiques
        let label = object.label.lowercased()
        return !dynamicDangerousObjects.contains(label)
    }
    
    // NOUVEAU : Annonces optimisées avec distinction statique/dynamique
    private func announceProximityThreats(_ threats: [TrackedObject], currentTime: Date) {
        for threat in threats {
            let isStatique = isStatiqueObject(threat)
            let message = createProximityMessageWithStatiquesDynamic(threat, currentTime: currentTime, isStatique: isStatique)
            let voiceMessage = VoiceMessage(
                text: message,
                objectId: threat.trackingNumber,
                objectType: threat.label,
                isStatique: isStatique,
                timestamp: currentTime,
                lifetimeSeconds: messageLifetime
            )
            
            messageQueue.append(voiceMessage)
            lastCriticalAnnouncements[threat.trackingNumber] = currentTime
            lastAnnouncedTypes[threat.label.lowercased()] = currentTime
            
            if objectDistanceHistory[threat.trackingNumber] != nil {
                lastMovementAnnouncements[threat.trackingNumber] = currentTime
            }
        }
        
        lastGlobalAnnouncement = currentTime
        processMessageQueue()
    }
    
    // NOUVEAU : Messages optimisés pour proximité avec contexte statique/dynamique
    private func createProximityMessageWithStatiquesDynamic(_ object: TrackedObject, currentTime: Date, isStatique: Bool) -> String {
        let frenchLabel = translateLabel(object.label)
        let direction = Direction.from(boundingBox: object.lastRect)
        let objectId = object.trackingNumber
        
        let isNewObject = lastCriticalAnnouncements[objectId] == nil
        
        if isNewObject {
            // Nouveau danger
            if let distance = object.distance {
                if distance < 1.5 {
                    // Distance précise si < 1.5m + ATTENTION
                    let distanceText = formatProximityDistance(distance)
                    return "ATTENTION ! \(frenchLabel) \(direction.rawValue) à \(distanceText) !"
                } else if distance > 3.0 {
                    // "au loin" si > 3m
                    if isStatique {
                        return "\(frenchLabel) \(direction.rawValue) au loin"
                    } else {
                        return "\(frenchLabel) mobile \(direction.rawValue) au loin"
                    }
                } else {
                    // Pas de distance si 1.5m - 3m, mais indiquer si mobile
                    if isStatique {
                        return "\(frenchLabel) \(direction.rawValue)"
                    } else {
                        return "\(frenchLabel) mobile \(direction.rawValue)"
                    }
                }
            } else {
                if isStatique {
                    return "\(frenchLabel) \(direction.rawValue)"
                } else {
                    return "\(frenchLabel) mobile \(direction.rawValue)"
                }
            }
        } else {
            // Objet déjà connu - mouvement d'approche
            if let previousDistance = objectDistanceHistory[objectId],
               let currentDistance = object.distance {
                let movement = ObjectMovement(previous: previousDistance, current: currentDistance)
                
                if movement.isApproaching {
                    if currentDistance < 1.5 {
                        // Distance précise si < 1.5m
                        let distanceText = formatProximityDistance(currentDistance)
                        return "\(frenchLabel) se rapproche \(direction.rawValue) à \(distanceText) !"
                    } else if currentDistance > 3.0 {
                        // "au loin" si > 3m
                        return "\(frenchLabel) se rapproche \(direction.rawValue) au loin !"
                    } else {
                        return "\(frenchLabel) se rapproche \(direction.rawValue) !"
                    }
                }
            }
            
            // Re-annonce normale
            if isStatique {
                return "\(frenchLabel) \(direction.rawValue)"
            } else {
                return "\(frenchLabel) mobile \(direction.rawValue)"
            }
        }
    }
    
    // NOUVEAU : Formatage distance seulement < 1.5m
    private func formatProximityDistance(_ distance: Float) -> String {
        if distance < 0.5 {
            return "moins de 50 centimètres"
        } else if distance < 1.0 {
            let roundedDistance = round(distance * 10) / 10
            return "\(String(format: "%.1f", roundedDistance)) mètre"
        } else {
            // 1.0m - 1.5m
            let roundedDistance = round(distance * 2) / 2
            let meterText = roundedDistance == 1.0 ? "mètre" : "mètres"
            
            if roundedDistance == floor(roundedDistance) {
                return "\(Int(roundedDistance)) \(meterText)"
            } else {
                return "\(String(format: "%.1f", roundedDistance)) \(meterText)"
            }
        }
    }
    
    private func translateLabel(_ englishLabel: String) -> String {
        return translationDictionary[englishLabel.lowercased()] ?? englishLabel
    }
    
    // MARK: - Gestion de la queue avec distance temps réel
    
    // NOUVEAU : Processus avec mise à jour distance temps réel
    private func processMessageQueue() {
        guard !isInterrupted && !isCurrentlySpeaking && !messageQueue.isEmpty else {
            return
        }
        
        let currentTime = Date()
        
        // Nettoyer messages expirés
        if messageQueue.first?.isExpired(at: currentTime) == true {
            messageQueue.removeFirst()
            processMessageQueue()
            return
        }
        
        let message = messageQueue.removeFirst()
        
        // NOUVEAU : Mettre à jour le message avec la distance actuelle
        let finalText = updateMessageWithCurrentDistance(message)
        
        speakInternal(finalText)
    }
    
    // NOUVEAU : Mise à jour distance ET direction en temps réel
    private func updateMessageWithCurrentDistance(_ message: VoiceMessage) -> String {
        // Trouver l'objet correspondant dans la liste actuelle
        guard let currentObject = currentTrackedObjects[message.objectId],
              let currentDistance = currentObject.distance else {
            // Pas d'objet actuel, utiliser message sans distance ni direction mise à jour
            return removeDistanceFromMessage(message.text)
        }
        
        // Recalculer le message avec distance ET direction actuelles
        let frenchLabel = translateLabel(currentObject.label)
        let direction = Direction.from(boundingBox: currentObject.lastRect) // Direction temps réel
        
        if message.text.contains("ATTENTION") {
            if currentDistance < 1.5 {
                let distanceText = formatProximityDistance(currentDistance)
                return "ATTENTION ! \(frenchLabel) \(direction.rawValue) à \(distanceText) !"
            } else if currentDistance > 3.0 {
                let statiqueText = message.isStatique ? "" : "mobile "
                return "ATTENTION ! \(frenchLabel) \(statiqueText)\(direction.rawValue) au loin !"
            } else {
                let statiqueText = message.isStatique ? "" : "mobile "
                return "ATTENTION ! \(frenchLabel) \(statiqueText)\(direction.rawValue) !"
            }
        } else if message.text.contains("se rapproche") {
            if currentDistance < 1.5 {
                let distanceText = formatProximityDistance(currentDistance)
                return "\(frenchLabel) se rapproche \(direction.rawValue) à \(distanceText) !"
            } else if currentDistance > 3.0 {
                return "\(frenchLabel) se rapproche \(direction.rawValue) au loin !"
            } else {
                return "\(frenchLabel) se rapproche \(direction.rawValue) !"
            }
        } else {
            if currentDistance < 1.5 {
                let distanceText = formatProximityDistance(currentDistance)
                return "\(frenchLabel) \(direction.rawValue) à \(distanceText)"
            } else if currentDistance > 3.0 {
                let statiqueText = message.isStatique ? "" : "mobile "
                return "\(frenchLabel) \(statiqueText)\(direction.rawValue) au loin"
            } else {
                let statiqueText = message.isStatique ? "" : "mobile "
                return "\(frenchLabel) \(statiqueText)\(direction.rawValue)"
            }
        }
    }
    
    // NOUVEAU : Supprimer distance d'un message si plus pertinente
    private func removeDistanceFromMessage(_ originalText: String) -> String {
        // Supprimer les parties "à X mètre(s)" du message
        let distancePattern = " à [^!]*"
        let result = originalText.replacingOccurrences(of: distancePattern, with: "", options: .regularExpression)
        return result.replacingOccurrences(of: "  ", with: " ") // Nettoyer doubles espaces
    }
    
    private func speakInternal(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "fr-FR")
        utterance.rate = 0.55
        utterance.volume = 1.0
        utterance.pitchMultiplier = 1
        
        isCurrentlySpeaking = true
        speechSynthesizer.speak(utterance)
    }
    
    func speak(_ text: String) {
        if isInterrupted {
            speakInteraction(text)
            return
        }
        speakInternal(text)
    }
    
    func stopSpeaking() {
        speechSynthesizer.stopSpeaking(at: .immediate)
        messageQueue.removeAll()
        isCurrentlySpeaking = false
    }
    
    // MARK: - Nettoyage et maintenance
    
    private func cleanupMessageQueue(currentObjects: [(object: TrackedObject, score: Float)], currentTime: Date) {
        let currentObjectIds = Set(currentObjects.map { $0.object.trackingNumber })
        
        messageQueue = messageQueue.filter { message in
            let isNotExpired = !message.isExpired(at: currentTime)
            let objectStillExists = currentObjectIds.contains(message.objectId) || message.objectId == -999
            return isNotExpired && objectStillExists
        }
    }
    
    private func updateDistanceHistory(_ objects: [(object: TrackedObject, score: Float)]) {
        for (object, _) in objects {
            if let distance = object.distance {
                objectDistanceHistory[object.trackingNumber] = distance
            }
        }
    }
    
    private func cleanupOldAnnouncements(currentObjects: [(object: TrackedObject, score: Float)]) {
        let currentObjectIds = Set(currentObjects.map { $0.object.trackingNumber })
        
        let absentObjectIds = Set(lastCriticalAnnouncements.keys).subtracting(currentObjectIds)
        for objectId in absentObjectIds {
            lastCriticalAnnouncements.removeValue(forKey: objectId)
            lastMovementAnnouncements.removeValue(forKey: objectId)
            objectDistanceHistory.removeValue(forKey: objectId)
        }
    }
    
    private func clearAllAnnouncements() {
        lastCriticalAnnouncements.removeAll()
        lastMovementAnnouncements.removeAll()
        objectDistanceHistory.removeAll()
        currentTrackedObjects.removeAll()
    }
    
    func clearAllState() {
        stopSpeaking()
        clearAllAnnouncements()
        lastAnnouncedTypes.removeAll()
        lastGlobalAnnouncement = Date.distantPast
        
        isInterrupted = false
        interruptionReason = ""
        lastInterruptionTime = Date.distantPast
    }
    
    // Statistiques mises à jour
    func getStats() -> String {
        let interruptionStatus = isInterrupted ? "⏸️ Interrompu" : "🚨 Surveillance active"
        let queueStatus = messageQueue.count >= maxSimultaneousAnnouncements ? "🚫 PLEINE" : "✅ OK"
        
        let queueTypes = messageQueue.map { "\($0.objectType)(\($0.isStatique ? "S" : "D"))" }.joined(separator: ", ")
        let typeCooldowns = lastAnnouncedTypes.map { type, date in
            let timeSince = Date().timeIntervalSince(date)
            return "\(type)(\(String(format: "%.1f", timeSince))s)"
        }.joined(separator: ", ")
        
        return """
        🗣️ VoiceSynthesisManager - OBJETS STATIQUES/DYNAMIQUES:
           - État: \(isCurrentlySpeaking ? "En cours" : "Silencieux")
           - Mode: \(interruptionStatus)
           - Distance critique: \(String(format: "%.2f", criticalDistance))m
           - Distance dynamique: \(String(format: "%.2f", criticalDistance + dynamicObjectExtraDistance))m
           - Seuil priorité: \(String(format: "%.1f", proximityPriorityThreshold))m
           - Messages en attente: \(messageQueue.count)/\(maxSimultaneousAnnouncements) \(queueStatus)
           - Types en queue: [\(queueTypes)]
           - Objets surveillés: \(lastCriticalAnnouncements.count)
           - Objets dangereux: \(dangerousObjects.count)
           - Objets dynamiques: \(dynamicDangerousObjects.count)
           - Objets statiques: \(statiquesDangerousObjects.count)
        
        🎯 Nouvelles Règles STATIQUES/DYNAMIQUES:
           - Objets statiques → Alerte à \(String(format: "%.2f", criticalDistance))m
           - Objets dynamiques → Alerte à \(String(format: "%.2f", criticalDistance + dynamicObjectExtraDistance))m  
           - Priorité: Distance < \(String(format: "%.1f", proximityPriorityThreshold))m (tous objets)
           - Distance précise: < \(String(format: "%.1f", proximityPriorityThreshold))m
           - "au loin": > 3.0m
           - Indication "mobile" pour objets dynamiques
           - Mise à jour TEMPS RÉEL: distance + direction
        """
    }
}

extension VoiceSynthesisManager: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isCurrentlySpeaking = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.processMessageQueue()
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        isCurrentlySpeaking = false
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        // Synthèse démarrée
    }
}
