//
//  VoiceSynthesisManager.swift (Version dangers critiques uniquement)
//  test
//
//  Modified by Assistant - Annonces vocales uniquement pour dangers immédiats
//  Système de synthèse vocale pour piétons aveugles - MODE CRITIQUE SEULEMENT
//  FIXÉ: Distance critique dynamique avec debug complet
//

import Foundation
import AVFoundation
import UIKit

// MARK: - Enums et Structures (simplifiés)

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

// MARK: - VoiceSynthesisManager (Version simplifiée - Critiques seulement)

class VoiceSynthesisManager: NSObject, ObservableObject {
    
    // MARK: - Configuration simplifiée
    private var criticalDistance: Float = 2.0  // ✅ FIXÉ: var au lieu de let
    private let minimumRepeatInterval: TimeInterval = 1.5  // Éviter spam pour même objet
    
    // MARK: - État interne minimal
    private var lastCriticalAnnouncements: [Int: Date] = [:] // Par objet
    private var messageQueue: [VoiceMessage] = []
    
    // MARK: - Support pour interaction vocale (conservé)
    @Published var isInterrupted = false
    private var interruptionReason: String = ""
    private var lastInterruptionTime: Date = Date.distantPast
    private let interruptionCooldown: TimeInterval = 1.0
    
    // MARK: - Synthèse vocale
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var isCurrentlySpeaking = false
    
    // MARK: - Dictionnaire de traduction (simplifié pour objets dangereux)
    private let translationDictionary: [String: String] = [
        "person": "personne",
        "cyclist": "cycliste",
        "motorcyclist": "motocycliste",
        "car": "voiture",
        "truck": "camion",
        "bus": "bus",
        "motorcycle": "moto",
        "bicycle": "vélo",
        "pole": "poteau",
        "traffic cone": "cône",
        "barrier": "barrière"
    ]
    
    override init() {
        super.init()
        speechSynthesizer.delegate = self
        setupAudioSession()
        
        // ✅ CHARGER LA DISTANCE CRITIQUE DEPUIS UserDefaults AU DÉMARRAGE
        loadCriticalDistanceFromUserDefaults()
        
        print("🗣️ VoiceSynthesisManager initialisé - MODE CRITIQUE SEULEMENT")
        print("🎯 Distance critique initiale: \(criticalDistance)m")
    }
    
    // ✅ NOUVELLE MÉTHODE : Charger depuis UserDefaults
    private func loadCriticalDistanceFromUserDefaults() {
        let userDefaults = UserDefaults.standard
        let savedDistance = userDefaults.float(forKey: "safety_critical_distance")  // Même clé que SafetyParametersManager
        
        if savedDistance > 0 {
            criticalDistance = savedDistance
            print("✅ Distance critique chargée depuis UserDefaults: \(String(format: "%.2f", criticalDistance))m")
        } else {
            print("ℹ️ Aucune distance sauvegardée, utilisation valeur par défaut: \(String(format: "%.2f", criticalDistance))m")
        }
    }
    
    // ✅ FIXÉ: Méthode avec debug complet
    func updateCriticalDistance(_ distance: Float) {
        let oldDistance = criticalDistance
        criticalDistance = distance
        print("🚨 DISTANCE CRITIQUE MISE À JOUR:")
        print("   - Ancienne distance: \(String(format: "%.2f", oldDistance))m")
        print("   - Nouvelle distance: \(String(format: "%.2f", criticalDistance))m")
        print("   - Changement effectif: \(oldDistance != criticalDistance ? "✅ OUI" : "❌ NON")")
        
        // Vider le cache des annonces pour appliquer immédiatement
        lastCriticalAnnouncements.removeAll()
        print("   - Cache des annonces vidé pour effet immédiat")
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
            try audioSession.overrideOutputAudioPort(.none) // Laisser le système choisir
            
            print("✅ Session audio configurée pour dangers critiques")
            
        } catch {
            print("❌ Erreur configuration audio: \(error)")
        }
    }
    
    // MARK: - Méthodes d'interaction (conservées)
    
    /// Interrompt immédiatement la synthèse pour permettre l'interaction
    func interruptForInteraction(reason: String = "Interaction utilisateur") {
        let currentTime = Date()
        
        guard currentTime.timeIntervalSince(lastInterruptionTime) >= interruptionCooldown else {
            print("⏸️ Interruption ignorée - cooldown actif")
            return
        }
        
        print("🛑 Interruption pour interaction: \(reason)")
        
        isInterrupted = true
        interruptionReason = reason
        lastInterruptionTime = currentTime
        
        speechSynthesizer.stopSpeaking(at: .immediate)
        messageQueue.removeAll() // Vider complètement - les dangers critiques seront re-détectés
        isCurrentlySpeaking = false
        
        print("📢 Synthèse interrompue")
    }
    
    /// Reprend les annonces automatiques après interaction
    func resumeAfterInteraction() {
        guard isInterrupted else { return }
        
        print("▶️ Reprise de la surveillance critique")
        isInterrupted = false
        interruptionReason = ""
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.processMessageQueue()
        }
    }
    
    /// Méthode pour parler directement (priorité interaction)
    func speakInteraction(_ text: String) {
        let interactionMessage = VoiceMessage(
            text: text,
            objectId: -999, // ID spécial pour interaction
            timestamp: Date()
        )
        
        messageQueue.insert(interactionMessage, at: 0)
        
        if !isCurrentlySpeaking {
            processMessageQueue()
        }
        
        print("🎤 Message d'interaction ajouté: '\(text)'")
    }
    
    // MARK: - Interface principale (SIMPLIFIÉE - Critiques seulement)
    
    func processImportantObjects(_ importantObjects: [(object: TrackedObject, score: Float)]) {
        // Si interrompu pour interaction, suspendre complètement
        if isInterrupted {
            print("⏸️ Surveillance suspendue - interaction en cours")
            return
        }
        
        print("🎯 Analyse de \(importantObjects.count) objets pour dangers critiques (seuil: \(String(format: "%.2f", criticalDistance))m)")
        
        guard !importantObjects.isEmpty else {
            handleEmptyObjectList()
            return
        }
        
        let currentTime = Date()
        let criticalThreats = detectCriticalThreats(importantObjects, currentTime: currentTime)
        
        if !criticalThreats.isEmpty {
            announceCriticalThreats(criticalThreats, currentTime: currentTime)
        }
        
        cleanupOldAnnouncements(currentObjects: importantObjects)
    }
    
    // MARK: - ✅ FIXÉ: Détection des menaces critiques avec debug complet
    
    private func detectCriticalThreats(_ objects: [(object: TrackedObject, score: Float)], currentTime: Date) -> [TrackedObject] {
        var criticalThreats: [TrackedObject] = []
        
        print("🔍 DÉTECTION avec distance critique = \(String(format: "%.2f", criticalDistance))m, \(objects.count) objets à analyser")
        
        for (object, score) in objects {
            // 1. Vérifier si l'objet est à distance critique
            let zone = DistanceZone.from(distance: object.distance, criticalDistance: criticalDistance)
            
            // 🐛 DEBUG TRÈS DÉTAILLÉ
            if let distance = object.distance {
                let isUnderThreshold = distance < criticalDistance
                print("   📏 #\(object.trackingNumber) \(object.label):")
                print("       Distance mesurée: \(String(format: "%.2f", distance))m")
                print("       Seuil critique: \(String(format: "%.2f", criticalDistance))m")
                print("       Test: \(String(format: "%.2f", distance)) < \(String(format: "%.2f", criticalDistance)) = \(isUnderThreshold)")
                print("       Zone calculée: \(zone == .critical ? "🚨 CRITIQUE" : "✅ SÛR")")
            } else {
                print("   📏 #\(object.trackingNumber) \(object.label): ❌ PAS DE DISTANCE LiDAR")
            }
            
            guard zone == .critical else {
                print("       → IGNORÉ (pas critique)")
                continue
            }
            
            // 2. Vérifier qu'on n'a pas déjà annoncé cet objet récemment
            if let lastAnnouncement = lastCriticalAnnouncements[object.trackingNumber] {
                let timeSinceLastAnnouncement = currentTime.timeIntervalSince(lastAnnouncement)
                if timeSinceLastAnnouncement < minimumRepeatInterval {
                    print("       → IGNORÉ (spam protection: \(String(format: "%.1f", timeSinceLastAnnouncement))s < \(minimumRepeatInterval)s)")
                    continue
                }
            }
            
            // 3. Filtrer les objets vraiment dangereux
            if isDangerousObject(object) {
                criticalThreats.append(object)
                print("       → 🚨 AJOUTÉ AUX MENACES CRITIQUES")
            } else {
                print("       → IGNORÉ (pas un type dangereux)")
            }
        }
        
        print("🔍 RÉSULTAT FINAL: \(criticalThreats.count) menace(s) critique(s) détectée(s)")
        if criticalThreats.isEmpty {
            print("   → Aucune annonce vocale ne sera faite")
        } else {
            for threat in criticalThreats {
                print("   → Annonce prévue: \(threat.label) #\(threat.trackingNumber)")
            }
        }
        
        return criticalThreats
    }
    
    private func isDangerousObject(_ object: TrackedObject) -> Bool {
        let label = object.label.lowercased()
        
        // Objets physiques dangereux pour un piéton
        let dangerousTypes = [
            "person", "cyclist", "motorcyclist",
            "car", "truck", "bus", "motorcycle", "bicycle",
            "pole", "traffic cone", "barrier", "temporary barrier"
        ]
        
        let isDangerous = dangerousTypes.contains(label)
        print("           Vérification type dangereux: '\(label)' = \(isDangerous)")
        return isDangerous
    }
    
    private func announceCriticalThreats(_ threats: [TrackedObject], currentTime: Date) {
        print("🚨 PRÉPARATION ANNONCE de \(threats.count) menace(s) critique(s)")
        
        for threat in threats {
            let message = createCriticalThreatMessage(threat)
            let voiceMessage = VoiceMessage(
                text: message,
                objectId: threat.trackingNumber,
                timestamp: currentTime
            )
            
            messageQueue.append(voiceMessage)
            lastCriticalAnnouncements[threat.trackingNumber] = currentTime
            
            print("   → Message ajouté: '\(message)'")
        }
        
        processMessageQueue()
    }
    
    private func createCriticalThreatMessage(_ object: TrackedObject) -> String {
        let frenchLabel = translateLabel(object.label)
        let direction = Direction.from(boundingBox: object.lastRect)
        
        // Message court et urgent pour danger immédiat
        let message = "ATTENTION ! \(frenchLabel) \(direction.rawValue) !"
        
        // Ajouter la distance si disponible pour le debug
        if let distance = object.distance {
            print("           Message pour objet à \(String(format: "%.2f", distance))m: '\(message)'")
        }
        
        return message
    }
    
    private func translateLabel(_ englishLabel: String) -> String {
        return translationDictionary[englishLabel.lowercased()] ?? englishLabel
    }
    
    // MARK: - Gestion de la queue et synthèse
    
    private func processMessageQueue() {
        guard !isInterrupted && !isCurrentlySpeaking && !messageQueue.isEmpty else {
            if isInterrupted {
                print("📢 Queue bloquée: interaction en cours")
            } else if isCurrentlySpeaking {
                print("📢 Queue bloquée: synthèse en cours")
            } else if messageQueue.isEmpty {
                print("📢 Queue vide: rien à dire")
            }
            return
        }
        
        let message = messageQueue.removeFirst()
        speakInternal(message.text)
        print("🗣️ SYNTHÈSE DÉMARRÉE: '\(message.text)'")
    }
    
    private func speakInternal(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "fr-FR")
        utterance.rate = 0.65  // Légèrement plus rapide pour urgence
        utterance.volume = 1.0
        utterance.pitchMultiplier = 1.1  // Légèrement plus aigu pour attirer l'attention
        
        print("🔊 Paramètres synthèse: rate=\(utterance.rate), volume=\(utterance.volume)")
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
        print("🛑 Synthèse arrêtée et queue vidée")
    }
    
    // MARK: - Nettoyage et maintenance
    
    private func handleEmptyObjectList() {
        if isCurrentlySpeaking || !messageQueue.isEmpty {
            print("🔄 Liste d'objets vide - arrêt synthèse en cours")
            stopSpeaking()
        }
        
        // Nettoyer les annonces anciennes après un délai
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            self?.lastCriticalAnnouncements.removeAll()
            print("🧹 Cache des annonces nettoyé (liste vide)")
        }
    }
    
    private func cleanupOldAnnouncements(currentObjects: [(object: TrackedObject, score: Float)]) {
        let currentObjectIds = Set(currentObjects.map { $0.object.trackingNumber })
        let absentObjectIds = Set(lastCriticalAnnouncements.keys).subtracting(currentObjectIds)
        
        for objectId in absentObjectIds {
            lastCriticalAnnouncements.removeValue(forKey: objectId)
            print("🧹 Objet #\(objectId) retiré du cache (plus détecté)")
        }
    }
    
    func clearAllState() {
        stopSpeaking()
        lastCriticalAnnouncements.removeAll()
        
        // Reset état interaction
        isInterrupted = false
        interruptionReason = ""
        lastInterruptionTime = Date.distantPast
        
        print("🔄 État complet réinitialisé - Mode critique seulement")
    }
    
    func getStats() -> String {
        let interruptionStatus = isInterrupted ? "⏸️ Interrompu (\(interruptionReason))" : "🚨 Surveillance active"
        
        return """
        🗣️ VoiceSynthesisManager - MODE CRITIQUE SEULEMENT:
           - État: \(isCurrentlySpeaking ? "En cours" : "Silencieux")
           - Mode: \(interruptionStatus)
           - Distance critique: \(String(format: "%.2f", criticalDistance))m
           - Messages en attente: \(messageQueue.count)
           - Objets surveillés: \(lastCriticalAnnouncements.count)
        
        🚨 UNIQUEMENT: Dangers immédiats (< \(String(format: "%.2f", criticalDistance))m)
        🎤 Support interaction: Interruption + Reprise
        ⚡ Messages urgents et concis
        """
    }
    
    // ✅ AJOUTÉ: Méthode de diagnostic
    func debugCurrentSettings() {
        print("🔧 DIAGNOSTIC VoiceSynthesisManager:")
        print("   - Distance critique actuelle: \(String(format: "%.2f", criticalDistance))m")
        print("   - État interruption: \(isInterrupted)")
        print("   - Synthèse en cours: \(isCurrentlySpeaking)")
        print("   - Messages en queue: \(messageQueue.count)")
        print("   - Cache annonces: \(lastCriticalAnnouncements.count) objets")
        print("   - Intervalle anti-spam: \(minimumRepeatInterval)s")
    }
}

extension VoiceSynthesisManager: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        print("✅ Synthèse terminée: '\(utterance.speechString)'")
        isCurrentlySpeaking = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.processMessageQueue()
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        print("❌ Synthèse annulée: '\(utterance.speechString)'")
        isCurrentlySpeaking = false
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        print("▶️ Synthèse démarrée: '\(utterance.speechString)'")
    }
}
