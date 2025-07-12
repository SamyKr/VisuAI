//
//  VoiceSynthesisManager.swift (Version dangers critiques uniquement)
//  test
//
//  Modified by Assistant - Annonces vocales uniquement pour dangers immédiats
//  Système de synthèse vocale pour piétons aveugles - MODE CRITIQUE SEULEMENT
//

import Foundation
import AVFoundation
import UIKit

// MARK: - Enums et Structures

enum DistanceZone {
    case critical   // < distance critique - SEULE ZONE QUI DÉCLENCHE UNE ANNONCE
    case safe       // >= distance critique - Aucune annonce
    
    static func from(distance: Float?, criticalDistance: Float) -> DistanceZone {
        guard let dist = distance else { return .safe }
        return dist < criticalDistance ? .critical : .safe
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

struct VoiceMessage {
    let text: String
    let objectId: Int
    let timestamp: Date
}

struct ObjectMovement {
    let previousDistance: Float
    let currentDistance: Float
    let isApproaching: Bool
    let isMovingAway: Bool
    
    init(previous: Float, current: Float) {
        self.previousDistance = previous
        self.currentDistance = current
        let threshold: Float = 0.3 // Seuil pour considérer un mouvement significatif
        self.isApproaching = (previous - current) > threshold
        self.isMovingAway = (current - previous) > threshold
    }
}

// MARK: - VoiceSynthesisManager

class VoiceSynthesisManager: NSObject, ObservableObject {
    
    // MARK: - Configuration
    private var criticalDistance: Float = 2.0
    private let minimumRepeatInterval: TimeInterval = 3.0  // Interval plus long pour éviter spam
    private let movementUpdateInterval: TimeInterval = 2.0 // Pour les annonces de mouvement
    
    // 🎯 NOUVEAU: Contrôle du rythme global des annonces
    private let globalAnnouncementCooldown: TimeInterval = 2.5  // Délai minimum entre TOUTES les annonces
    private var lastGlobalAnnouncement: Date = Date.distantPast
    private let maxSimultaneousAnnouncements: Int = 2  // Max 2 annonces dans la queue
    
    // 🎯 NOUVEAU: Liste dynamique des objets dangereux
    private var dangerousObjects: Set<String> = [
        "person", "cyclist", "motorcyclist",
        "car", "truck", "bus", "motorcycle", "bicycle",
        "pole", "traffic cone", "barrier", "temporary barrier"
    ]
    
    // MARK: - État interne
    private var lastCriticalAnnouncements: [Int: Date] = [:]
    private var lastMovementAnnouncements: [Int: Date] = [:] // Séparé pour les mouvements
    private var objectDistanceHistory: [Int: Float] = [:] // Pour tracker le mouvement
    private var messageQueue: [VoiceMessage] = []
    
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
        // Véhicules et usagers
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
        
        // Infrastructure routière
        "sidewalk": "trottoir",
        "road": "route",
        "crosswalk": "passage piéton",
        "driveway": "allée",
        "bike_lane": "piste cyclable",
        "parking_area": "zone de stationnement",
        "rail_track": "voie ferrée",
        "service_lane": "voie de service",
        "curb": "bordure",
        
        // Barrières et obstacles
        "wall": "mur",
        "fence": "clôture",
        "guard_rail": "glissière de sécurité",
        "temporary_barrier": "barrière temporaire",
        "barrier_other": "autre barrière",
        "barrier": "barrière",
        "pole": "poteau",
        
        // Signalisation et équipements
        "traffic_light": "feu de circulation",
        "traffic_sign": "panneau de signalisation",
        "street_light": "lampadaire",
        "traffic_cone": "cône",
        
        // Mobilier urbain
        "bench": "banc",
        "trash_can": "poubelle",
        "fire_hydrant": "bouche d'incendie",
        "mailbox": "boîte aux lettres",
        "parking_meter": "parcmètre",
        "bike_rack": "support à vélos",
        "phone_booth": "cabine téléphonique",
        
        // Éléments de voirie
        "pothole": "nid-de-poule",
        "manhole": "plaque d'égout",
        "catch_basin": "regard d'égout",
        "water_valve": "vanne d'eau",
        "junction_box": "boîtier de jonction",
        
        // Structures et environnement
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
        lastCriticalAnnouncements.removeAll() // Appliquer immédiatement
        lastMovementAnnouncements.removeAll()
        objectDistanceHistory.removeAll()
    }
    
    // 🎯 NOUVEAU: Mise à jour des objets dangereux
    func updateDangerousObjects(_ objects: Set<String>) {
        let oldObjects = dangerousObjects
        dangerousObjects = objects
        
        // 🐛 DEBUG: Vérifier la mise à jour
        print("🔧 DEBUG VoiceSynthesis - Objets dangereux mis à jour:")
        print("   - Anciens: \(Array(oldObjects).sorted())")
        print("   - Nouveaux: \(Array(dangerousObjects).sorted())")
        print("   - 'car' présent: \(dangerousObjects.contains("car"))")
        
        // Vider les caches pour appliquer immédiatement
        lastCriticalAnnouncements.removeAll()
        lastMovementAnnouncements.removeAll()
        objectDistanceHistory.removeAll()
        print("   - Caches vidés pour effet immédiat")
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
            timestamp: Date()
        )
        
        messageQueue.insert(interactionMessage, at: 0)
        
        if !isCurrentlySpeaking {
            processMessageQueue()
        }
    }
    
    // MARK: - Interface principale
    
    func processImportantObjects(_ importantObjects: [(object: TrackedObject, score: Float)]) {
        if isInterrupted {
            return
        }
        
        // Arrêt immédiat si plus rien à détecter
        guard !importantObjects.isEmpty else {
            stopSpeaking() // Arrêt immédiat au lieu d'attendre
            lastCriticalAnnouncements.removeAll()
            lastMovementAnnouncements.removeAll()
            objectDistanceHistory.removeAll()
            return
        }
        
        let currentTime = Date()
        let criticalThreats = detectCriticalThreats(importantObjects, currentTime: currentTime)
        
        if !criticalThreats.isEmpty {
            announceCriticalThreats(criticalThreats, currentTime: currentTime)
        }
        
        // Mettre à jour l'historique des distances
        updateDistanceHistory(importantObjects)
        cleanupOldAnnouncements(currentObjects: importantObjects)
    }
    
    // MARK: - Détection des menaces critiques
    
    private func detectCriticalThreats(_ objects: [(object: TrackedObject, score: Float)], currentTime: Date) -> [TrackedObject] {
        // 🎯 NOUVEAU: Vérifier le cooldown global
        let timeSinceLastGlobalAnnouncement = currentTime.timeIntervalSince(lastGlobalAnnouncement)
        if timeSinceLastGlobalAnnouncement < globalAnnouncementCooldown {
            return [] // Trop tôt pour une nouvelle annonce
        }
        
        // 🎯 NOUVEAU: Vérifier si la queue n'est pas déjà pleine
        if messageQueue.count >= maxSimultaneousAnnouncements {
            return [] // Queue pleine, attendre qu'elle se vide
        }
        
        var newThreats: [TrackedObject] = []
        var movementThreats: [TrackedObject] = []
        
        for (object, _) in objects {
            guard let distance = object.distance else { continue }
            
            // 1. Vérifier si l'objet est à distance critique
            let zone = DistanceZone.from(distance: distance, criticalDistance: criticalDistance)
            guard zone == .critical && isDangerousObject(object) else { continue }
            
            let objectId = object.trackingNumber
            let hasBeenAnnounced = lastCriticalAnnouncements[objectId] != nil
            
            // 2. Objets jamais annoncés = priorité absolue
            if !hasBeenAnnounced {
                newThreats.append(object)
                continue
            }
            
            // 3. Pour objets déjà annoncés, vérifier le timing
            if let lastAnnouncement = lastCriticalAnnouncements[objectId] {
                let timeSinceLastAnnouncement = currentTime.timeIntervalSince(lastAnnouncement)
                if timeSinceLastAnnouncement < minimumRepeatInterval {
                    continue // Trop récent
                }
            }
            
            // 4. Vérifier le mouvement pour objets déjà annoncés
            if let previousDistance = objectDistanceHistory[objectId] {
                let movement = ObjectMovement(previous: previousDistance, current: distance)
                
                // Annoncer mouvement seulement si significatif et pas trop récent
                if (movement.isApproaching || movement.isMovingAway) {
                    if let lastMovement = lastMovementAnnouncements[objectId] {
                        let timeSinceMovement = currentTime.timeIntervalSince(lastMovement)
                        if timeSinceMovement >= movementUpdateInterval {
                            movementThreats.append(object)
                        }
                    } else {
                        movementThreats.append(object)
                    }
                }
            }
        }
        
        // Prioriser: nouveaux objets en premier, puis mouvements
        var result = newThreats
        if result.isEmpty && !movementThreats.isEmpty {
            result = Array(movementThreats.prefix(1)) // 🎯 RÉDUIT: Max 1 mouvement à la fois
        }
        
        // 🎯 NOUVEAU: Limiter à 1 annonce à la fois pour éviter l'enchaînement
        if !result.isEmpty {
            result = Array(result.prefix(1))
        }
        
        return result
    }
    
    private func isDangerousObject(_ object: TrackedObject) -> Bool {
        let label = object.label.lowercased()
        let isDangerous = dangerousObjects.contains(label)
        
        // 🐛 DEBUG: Afficher chaque vérification
        print("🔍 Vérification objet: '\(label)' → \(isDangerous ? "DANGEREUX" : "SAFE")")
        if label == "car" {
            print("   ⚠️ ATTENTION: Objet 'car' détecté - Liste actuelle: \(Array(dangerousObjects).sorted())")
        }
        
        return isDangerous
    }
    
    private func announceCriticalThreats(_ threats: [TrackedObject], currentTime: Date) {
        for threat in threats {
            let message = createCriticalThreatMessage(threat, currentTime: currentTime)
            let voiceMessage = VoiceMessage(
                text: message,
                objectId: threat.trackingNumber,
                timestamp: currentTime
            )
            
            messageQueue.append(voiceMessage)
            lastCriticalAnnouncements[threat.trackingNumber] = currentTime
            
            // Marquer aussi comme annonce de mouvement si c'était un mouvement
            if objectDistanceHistory[threat.trackingNumber] != nil {
                lastMovementAnnouncements[threat.trackingNumber] = currentTime
            }
        }
        
        // 🎯 NOUVEAU: Mettre à jour le timestamp global
        lastGlobalAnnouncement = currentTime
        
        processMessageQueue()
    }
    
    private func createCriticalThreatMessage(_ object: TrackedObject, currentTime: Date) -> String {
        let frenchLabel = translateLabel(object.label)
        let direction = Direction.from(boundingBox: object.lastRect)
        let objectId = object.trackingNumber
        
        // Vérifier si c'est un nouvel objet ou un mouvement
        let isNewObject = lastCriticalAnnouncements[objectId] == nil
        
        if isNewObject {
            // Nouveau danger - message avec distance si proche
            if let distance = object.distance {
                if distance < 1.0 {
                    return "DANGER ! \(frenchLabel) très proche \(direction.rawValue) !"
                } else if distance < 1.5 {
                    let roundedDistance = Int(distance.rounded())
                    let meterText = roundedDistance == 1 ? "mètre" : "mètres"
                    return "ATTENTION ! \(frenchLabel) \(direction.rawValue) à \(roundedDistance) \(meterText) !"
                } else {
                    return "ATTENTION ! \(frenchLabel) \(direction.rawValue) !"
                }
            } else {
                return "ATTENTION ! \(frenchLabel) \(direction.rawValue) !"
            }
        } else {
            // Objet déjà connu - vérifier le mouvement
            if let previousDistance = objectDistanceHistory[objectId],
               let currentDistance = object.distance {
                let movement = ObjectMovement(previous: previousDistance, current: currentDistance)
                
                if movement.isApproaching {
                    return "\(frenchLabel) se rapproche \(direction.rawValue) !"
                } else if movement.isMovingAway {
                    return "\(frenchLabel) s'éloigne \(direction.rawValue)"
                }
            }
            
            // Fallback si pas de mouvement détecté
            return "\(frenchLabel) toujours \(direction.rawValue)"
        }
    }
    
    private func translateLabel(_ englishLabel: String) -> String {
        return translationDictionary[englishLabel.lowercased()] ?? englishLabel
    }
    
    // MARK: - Gestion de la queue et synthèse
    
    private func processMessageQueue() {
        guard !isInterrupted && !isCurrentlySpeaking && !messageQueue.isEmpty else {
            return
        }
        
        let message = messageQueue.removeFirst()
        speakInternal(message.text)
    }
    
    private func speakInternal(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "fr-FR")
        utterance.rate = 0.65
        utterance.volume = 1.0
        utterance.pitchMultiplier = 1.1
        
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
    
    private func updateDistanceHistory(_ objects: [(object: TrackedObject, score: Float)]) {
        for (object, _) in objects {
            if let distance = object.distance {
                objectDistanceHistory[object.trackingNumber] = distance
            }
        }
    }
    
    private func cleanupOldAnnouncements(currentObjects: [(object: TrackedObject, score: Float)]) {
        let currentObjectIds = Set(currentObjects.map { $0.object.trackingNumber })
        
        // Nettoyer les objets qui ne sont plus détectés
        let absentObjectIds = Set(lastCriticalAnnouncements.keys).subtracting(currentObjectIds)
        for objectId in absentObjectIds {
            lastCriticalAnnouncements.removeValue(forKey: objectId)
            lastMovementAnnouncements.removeValue(forKey: objectId)
            objectDistanceHistory.removeValue(forKey: objectId)
        }
    }
    
    func clearAllState() {
        stopSpeaking()
        lastCriticalAnnouncements.removeAll()
        lastMovementAnnouncements.removeAll()
        objectDistanceHistory.removeAll()
        
        // 🎯 NOUVEAU: Réinitialiser le cooldown global
        lastGlobalAnnouncement = Date.distantPast
        
        isInterrupted = false
        interruptionReason = ""
        lastInterruptionTime = Date.distantPast
    }
    
    func getStats() -> String {
        let interruptionStatus = isInterrupted ? "⏸️ Interrompu (\(interruptionReason))" : "🚨 Surveillance active"
        let queueStatus = messageQueue.count >= maxSimultaneousAnnouncements ? "🚫 PLEINE" : "✅ OK"
        
        return """
        🗣️ VoiceSynthesisManager - MODE CRITIQUE OPTIMISÉ:
           - État: \(isCurrentlySpeaking ? "En cours" : "Silencieux")
           - Mode: \(interruptionStatus)
           - Distance critique: \(String(format: "%.2f", criticalDistance))m
           - Messages en attente: \(messageQueue.count)/\(maxSimultaneousAnnouncements) \(queueStatus)
           - Objets surveillés: \(lastCriticalAnnouncements.count)
           - Mouvements trackés: \(objectDistanceHistory.count)
           - Objets dangereux configurés: \(dangerousObjects.count)
           - Cooldown global: \(String(format: "%.1f", globalAnnouncementCooldown))s
        
        🚨 Fonctionnalités optimisées:
           - Arrêt immédiat si plus de détection
           - Messages variés avec distance et mouvement
           - Priorisation nouveaux objets > mouvements
           - Anti-spam intelligent (3s objets, 2s mouvements)
           - Cooldown global de \(String(format: "%.1f", globalAnnouncementCooldown))s entre annonces
           - Max \(maxSimultaneousAnnouncements) annonces simultanées
           - 1 seule annonce à la fois pour éviter l'enchaînement
        """
    }
    
    // 🎯 NOUVEAU: Méthode pour ajuster le rythme des annonces
    func setAnnouncementRate(cooldown: TimeInterval, maxQueue: Int = 2) {
        // Cette méthode pourrait être appelée depuis les paramètres si vous voulez un contrôle utilisateur
        // Pour l'instant, les valeurs sont hardcodées mais facilement modifiables
    }
}

extension VoiceSynthesisManager: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isCurrentlySpeaking = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
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
