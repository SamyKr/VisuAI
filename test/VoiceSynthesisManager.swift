//
//  VoiceSynthesisManager.swift (Version modifiée avec support interaction)
//  test
//
//  Created by Samy 📍 on 02/07/2025.
//  Système de synthèse vocale pour piétons aveugles
//  Version finale corrigée - Diversité + Anti-répétition + Interaction vocale
//

import Foundation
import AVFoundation
import UIKit

// MARK: - Enums et Structures (inchangés)

enum DistanceZone {
    case critical   // < 2m
    case warning    // 2-5m
    case info       // > 5m
    
    static func from(distance: Float?) -> DistanceZone {
        guard let dist = distance else { return .info }
        if dist < 2.0 { return .critical }
        if dist < 5.0 { return .warning }
        return .info
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

enum SituationContext {
    case calm, normal, dense, critical
    
    static func from(objectCount: Int, criticalCount: Int) -> SituationContext {
        if criticalCount > 0 { return .critical }
        if objectCount >= 4 { return .dense }
        if objectCount <= 1 { return .calm }
        return .normal
    }
}

enum ChangeType {
    case newDanger, approaching, newNavigation, contextShift, groupUpdate
}

struct VoiceTemplate {
    let critical: String
    let warning: String
    let info: String
    let priority: Int
    let cooldown: TimeInterval
    let isRepeatable: Bool
    
    func getMessage(for zone: DistanceZone) -> String {
        switch zone {
        case .critical: return critical
        case .warning: return warning
        case .info: return info
        }
    }
}

struct VoiceMessage {
    let text: String
    let priority: Int
    let objectId: Int
    let timestamp: Date
    let changeType: ChangeType
}

struct ContextualState {
    var lastObjectIds: Set<Int> = []
    var lastSituation: SituationContext = .calm
    var lastCriticalObjects: Set<Int> = []
    var lastNavigationObjects: Set<Int> = []
    var lastContextAnnouncement: Date = Date.distantPast
    var vehicleCount: Int = 0
    var navigationCount: Int = 0
}

// MARK: - VoiceSynthesisManager (Version modifiée)

class VoiceSynthesisManager: NSObject, ObservableObject {
    
    // MARK: - Configuration
    private let minimumAnnouncementInterval: TimeInterval = 2.0
    private let maxMessagesPerUpdate = 2
    private let periodicAnnouncementInterval: TimeInterval = 8.0
    private let contextAnnouncementCooldown: TimeInterval = 8.0
    private let maxTypeHistory = 3
    
    // MARK: - État interne
    private var lastAnnouncements: [Int: Date] = [:]
    private var lastGlobalAnnouncement: Date = Date.distantPast
    private var lastPeriodicAnnouncement: Date = Date.distantPast
    private var messageQueue: [VoiceMessage] = []
    private var contextualState = ContextualState()
    private var recentlyAnnouncedTypes: [String] = []
    private var periodicAnnouncementsEnabled = true
    
    // ← NOUVEAU : Support pour interaction vocale
    @Published var isInterrupted = false
    private var interruptionReason: String = ""
    private var lastInterruptionTime: Date = Date.distantPast
    private let interruptionCooldown: TimeInterval = 1.0
    
    // MARK: - Synthèse vocale
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var isCurrentlySpeaking = false
    
    // MARK: - Dictionnaire de traduction (inchangé)
    private let translationDictionary: [String: String] = [
        "person": "personne", "cyclist": "cycliste", "motorcyclist": "motocycliste",
        "car": "voiture", "truck": "camion", "bus": "bus", "motorcycle": "moto", "bicycle": "vélo",
        "traffic light": "feu de circulation", "traffic sign": "panneau de signalisation", "pedestrian crossing": "passage piéton",
        "traffic cone": "cône de circulation", "temporary barrier": "barrière temporaire", "pole": "poteau",
        "curb": "bordure de trottoir", "pothole": "nid-de-poule", "animals": "animal"
    ]
    
    // MARK: - Templates de phrases (inchangés)
    private let voiceTemplates: [String: VoiceTemplate] = [
        "person": VoiceTemplate(
            critical: "ATTENTION ! Personne très proche {direction} !",
            warning: "Personne {direction} à {distance}",
            info: "Personne visible {direction}",
            priority: 10, cooldown: 3.0, isRepeatable: true
        ),
        "traffic light": VoiceTemplate(
            critical: "Feu de circulation juste {direction} !",
            warning: "Feu de circulation {direction} à {distance}",
            info: "Feu de circulation {direction}",
            priority: 9, cooldown: 6.0, isRepeatable: false
        ),
        "car": VoiceTemplate(
            critical: "ATTENTION ! Voiture très proche {direction} !",
            warning: "Voiture {direction} à {distance}",
            info: "Circulation automobile {direction}",
            priority: 7, cooldown: 5.0, isRepeatable: true
        ),
        "pole": VoiceTemplate(
            critical: "ATTENTION ! Poteau très proche {direction} !",
            warning: "Poteau {direction} à {distance}",
            info: "Poteau {direction}",
            priority: 5, cooldown: 8.0, isRepeatable: true
        )
    ]
    
    override init() {
        super.init()
        speechSynthesizer.delegate = self
        setupAudioSession()
        print("🗣️ VoiceSynthesisManager initialisé avec support interaction")
    }
    
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            // ✅ NOUVELLE CONFIGURATION : Privilégier AirPods pour la synthèse vocale
            try audioSession.setCategory(
                .playback,
                mode: .spokenAudio,            // ← CHANGÉ : .spokenAudio au lieu de .voicePrompt
                options: [
                    .duckOthers,
                    .allowBluetooth,           // ← NOUVEAU : Autoriser Bluetooth
                    .allowBluetoothA2DP,       // ← NOUVEAU : Autoriser AirPods
                    .allowAirPlay,             // ← NOUVEAU : Autoriser AirPlay
                    .interruptSpokenAudioAndMixWithOthers  // ← NOUVEAU : Meilleure gestion interruptions
                ]
            )
            
            try audioSession.setActive(true)
            
            // ✅ NOUVEAU : S'assurer que la route n'est PAS forcée vers le haut-parleur
            try audioSession.overrideOutputAudioPort(.none) // Laisser le système choisir (AirPods prioritaires)
            
            print("✅ Session audio configurée - Synthèse via AirPods")
            
            // 🔍 Debug : Vérifier la route actuelle
            checkCurrentAudioRoute()
            
        } catch {
            print("❌ Erreur configuration audio: \(error)")
        }
    }
    private func forceAirPodsOutput() {
        let audioSession = AVAudioSession.sharedInstance()
        
        // Chercher des AirPods/Bluetooth dans les sorties disponibles
        let hasBluetoothOutput = audioSession.currentRoute.outputs.contains { output in
            output.portType == .bluetoothA2DP || output.portType == .bluetoothHFP
        }
        
        if hasBluetoothOutput {
            // ✅ AirPods détectés → Laisser le système utiliser les AirPods
            do {
                try audioSession.overrideOutputAudioPort(.none) // Utiliser AirPods
                print("✅ AirPods actifs - Route automatique")
            } catch {
                print("❌ Erreur configuration AirPods: \(error)")
            }
        } else {
            // ⚠️ Pas d'AirPods → Forcer vers les HAUT-PARLEURS (pas l'écouteur interne)
            do {
                try audioSession.overrideOutputAudioPort(.speaker) // ← FORCER HAUT-PARLEURS
                print("🔊 Pas d'AirPods - Forçage vers haut-parleurs")
            } catch {
                print("❌ Erreur forçage haut-parleurs: \(error)")
            }
        }
    }

    // ✅ NOUVELLE MÉTHODE : Vérifier la route audio actuelle
    private func checkCurrentAudioRoute() {
        let audioSession = AVAudioSession.sharedInstance()
        let outputs = audioSession.currentRoute.outputs
        
        print("🎧 Route audio actuelle :")
        for output in outputs {
            print("  - \(output.portName) (\(output.portType.rawValue))")
            
            switch output.portType {
            case .bluetoothA2DP:
                print("    ✅ AirPods/Casque Bluetooth A2DP")
            case .bluetoothHFP:
                print("    ✅ AirPods/Casque Bluetooth HFP")
            case .builtInSpeaker:
                print("    ⚠️ Haut-parleur interne (pas souhaité)")
            case .builtInReceiver:
                print("    ⚠️ Écouteur interne (pas souhaité)")
            case .headphones:
                print("    ✅ Casque filaire")
            default:
                print("    ℹ️ Autre type: \(output.portType.rawValue)")
            }
        }
    }


    // MARK: - Nouvelles méthodes pour interaction vocale
    
    /// Interrompt immédiatement la synthèse pour permettre l'interaction
    func interruptForInteraction(reason: String = "Interaction utilisateur") {
        let currentTime = Date()
        
        // Éviter les interruptions trop fréquentes
        guard currentTime.timeIntervalSince(lastInterruptionTime) >= interruptionCooldown else {
            print("⏸️ Interruption ignorée - cooldown actif")
            return
        }
        
        print("🛑 Interruption pour interaction: \(reason)")
        
        isInterrupted = true
        interruptionReason = reason
        lastInterruptionTime = currentTime
        
        // Arrêter immédiatement la synthèse
        speechSynthesizer.stopSpeaking(at: .immediate)
        
        // Vider la queue des messages non critiques
        let criticalMessages = messageQueue.filter { $0.priority >= 9 }
        messageQueue = criticalMessages
        
        // Notifications
        isCurrentlySpeaking = false
        
        print("📢 Synthèse interrompue, \(messageQueue.count) messages critiques conservés")
    }
    
    /// Reprend les annonces automatiques après interaction
    func resumeAfterInteraction() {
        guard isInterrupted else { return }
        
        print("▶️ Reprise des annonces automatiques")
        isInterrupted = false
        interruptionReason = ""
        
        // Reprendre le traitement de la queue si nécessaire
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.processMessageQueue()
        }
    }
    
    /// Méthode pour parler directement (priorité interaction)
    func speakInteraction(_ text: String, priority: Int = 15) {
        let interactionMessage = VoiceMessage(
            text: text,
            priority: priority,
            objectId: -999, // ID spécial pour interaction
            timestamp: Date(),
            changeType: .contextShift
        )
        
        // Insérer en priorité dans la queue
        messageQueue.insert(interactionMessage, at: 0)
        
        // Si on n'est pas en train de parler, traiter immédiatement
        if !isCurrentlySpeaking {
            processMessageQueue()
        }
        
        print("🎤 Message d'interaction ajouté: '\(text)'")
    }
    
    /// Méthode speak améliorée pour gérer les interruptions
    func speak(_ text: String) {
        // Si on est interrompu, utiliser la méthode d'interaction
        if isInterrupted {
            speakInteraction(text)
            return
        }
        
        // Utilisation normale
        speakInternal(text)
    }
    
    private func speakInternal(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "fr-FR")
        utterance.rate = 0.55
        utterance.volume = 1.0
        utterance.pitchMultiplier = 1.0
        
        print("🔊 Synthèse: '\(text)'")
        isCurrentlySpeaking = true
        speechSynthesizer.speak(utterance)
    }
    
    // MARK: - Interface principale (méthodes existantes avec vérification interruption)
    
    func processImportantObjects(_ importantObjects: [(object: TrackedObject, score: Float)]) {
        // Si interrompu pour interaction, suspendre les annonces automatiques
        if isInterrupted {
            print("⏸️ Traitement suspendu - interaction en cours")
            return
        }
        
        print("🎯 processImportantObjects appelé avec \(importantObjects.count) objets")
        
        guard !importantObjects.isEmpty else {
            handleEmptyObjectList()
            return
        }
        
        let currentTime = Date()
        reactivatePeriodicAnnouncements(currentTime)
        
        let currentContext = analyzeSituation(importantObjects)
        let significantChanges = detectSignificantChanges(importantObjects, context: currentContext, currentTime: currentTime)
        
        if significantChanges.isEmpty {
            print("😴 Aucun changement significatif détecté")
            return
        }
        
        let hasUrgentChange = significantChanges.contains { $0.changeType == .newDanger }
        if !hasUrgentChange && currentTime.timeIntervalSince(lastGlobalAnnouncement) < minimumAnnouncementInterval {
            print("⏸️ Cooldown global actif")
            return
        }
        
        var candidateMessages: [VoiceMessage] = []
        for change in significantChanges {
            if let message = createMessageForChange(change, currentTime: currentTime) {
                candidateMessages.append(message)
            }
        }
        
        cleanupAbsentObjectCooldowns(currentObjects: importantObjects)
        
        if !candidateMessages.isEmpty {
            announceMessages(candidateMessages, currentTime: currentTime)
        }
        
        updateContextualState(importantObjects, context: currentContext, currentTime: currentTime)
    }
    
    // Méthode stopSpeaking modifiée
    func stopSpeaking() {
        speechSynthesizer.stopSpeaking(at: .immediate)
        messageQueue.removeAll()
        isCurrentlySpeaking = false
        print("🛑 Synthèse arrêtée")
    }
    
    // MARK: - Méthodes privées existantes (inchangées mais avec vérification interruption)
    
    private func handleEmptyObjectList() {
        print("⚠️ Aucun objet important à traiter")
        
        if isCurrentlySpeaking || !messageQueue.isEmpty {
            print("🛑 Arrêt immédiat de la synthèse")
            stopSpeaking()
        }
        
        if !contextualState.lastObjectIds.isEmpty {
            print("🧹 Nettoyage complet")
            let previousSituation = contextualState.lastSituation
            
            lastAnnouncements.removeAll()
            contextualState = ContextualState()
            recentlyAnnouncedTypes.removeAll()
            lastPeriodicAnnouncement = Date.distantPast
            periodicAnnouncementsEnabled = false
            
            if previousSituation == .dense || previousSituation == .critical {
                speak("Zone calme")
                print("📢 Transition vers zone calme")
            }
        }
    }
    
    private func processMessageQueue() {
        // Vérifier si on est interrompu avant de traiter
        guard !isInterrupted && !isCurrentlySpeaking && !messageQueue.isEmpty else { return }
        
        let message = messageQueue.removeFirst()
        speakInternal(message.text)
        print("🗣️ Annonce [\(message.changeType)]: \(message.text)")
    }
    
    // MARK: - Toutes les autres méthodes privées restent identiques...
    // (Je ne les recopie pas pour économiser l'espace, mais elles sont inchangées)
    
    private func reactivatePeriodicAnnouncements(_ currentTime: Date) {
        if !periodicAnnouncementsEnabled {
            periodicAnnouncementsEnabled = true
            lastPeriodicAnnouncement = currentTime
            print("▶️ Annonces périodiques réactivées")
        }
    }
    
    private func analyzeSituation(_ objects: [(object: TrackedObject, score: Float)]) -> SituationContext {
        let criticalObjects = objects.filter { $0.score > 0.7 }
        return SituationContext.from(objectCount: objects.count, criticalCount: criticalObjects.count)
    }
    
    private func detectSignificantChanges(_ objects: [(object: TrackedObject, score: Float)], context: SituationContext, currentTime: Date) -> [SignificantChange] {
        var changes: [SignificantChange] = []
        
        let currentCriticalIds = Set(objects.filter { $0.score > 0.7 }.map { $0.object.trackingNumber })
        let currentNavigationIds = Set(objects.filter {
            ["traffic light", "traffic sign", "pedestrian crossing"].contains($0.object.label.lowercased())
        }.map { $0.object.trackingNumber })
        
        // 1. Nouveaux objets critiques
        let newCriticalObjects = currentCriticalIds.subtracting(contextualState.lastCriticalObjects)
        for objectId in newCriticalObjects {
            if let objTuple = objects.first(where: { $0.object.trackingNumber == objectId }) {
                changes.append(SignificantChange(type: .newDanger, object: objTuple.object, message: nil, priority: 10))
            }
        }
        
        // 2. Nouvelle signalisation
        let newNavigationObjects = currentNavigationIds.subtracting(contextualState.lastNavigationObjects)
        for objectId in newNavigationObjects {
            if let objTuple = objects.first(where: { $0.object.trackingNumber == objectId }) {
                changes.append(SignificantChange(type: .newNavigation, object: objTuple.object, message: nil, priority: 9))
            }
        }
        
        // 3. Changement de contexte
        if context != contextualState.lastSituation {
            let shouldAnnounceContext = currentTime.timeIntervalSince(contextualState.lastContextAnnouncement) >= contextAnnouncementCooldown
            if shouldAnnounceContext {
                let contextMessage = generateContextualMessage(context, objects: objects)
                changes.append(SignificantChange(type: .contextShift, object: nil, message: contextMessage, priority: contextMessage.priority))
            }
        }
        
        // 4. Annonces périodiques avec diversité
        let shouldMakePeriodicAnnouncement = periodicAnnouncementsEnabled && currentTime.timeIntervalSince(lastPeriodicAnnouncement) >= periodicAnnouncementInterval
        
        if shouldMakePeriodicAnnouncement && !objects.isEmpty {
            if let selectedObject = selectDiverseObjectForAnnouncement(objects) {
                changes.append(SignificantChange(type: .groupUpdate, object: selectedObject.object, message: nil, priority: 5))
                lastPeriodicAnnouncement = currentTime
                addToTypeHistory(selectedObject.object.label)
                print("📢 Annonce périodique: \(selectedObject.object.label)")
            }
        }
        
        return changes
    }
    
    private struct SignificantChange {
        let type: ChangeType
        let changeType: ChangeType
        let object: TrackedObject?
        let message: (text: String, priority: Int)?
        let priority: Int
        
        init(type: ChangeType, object: TrackedObject?, message: (text: String, priority: Int)?, priority: Int) {
            self.type = type
            self.changeType = type
            self.object = object
            self.message = message
            self.priority = priority
        }
    }
    
    // [Toutes les autres méthodes utilitaires restent identiques...]
    
    private func selectDiverseObjectForAnnouncement(_ objects: [(object: TrackedObject, score: Float)]) -> (object: TrackedObject, score: Float)? {
        let objectsByType = Dictionary(grouping: objects) { $0.object.label.lowercased() }
        let availableTypes = Set(objectsByType.keys)
        
        let unAnnouncedTypes = availableTypes.subtracting(Set(recentlyAnnouncedTypes))
        
        if !unAnnouncedTypes.isEmpty {
            let selectedType = unAnnouncedTypes.min { type1, type2 in
                let bestScore1 = objectsByType[type1]?.max { $0.score < $1.score }?.score ?? 0
                let bestScore2 = objectsByType[type2]?.max { $0.score < $1.score }?.score ?? 0
                return bestScore1 < bestScore2
            }!
            return objectsByType[selectedType]!.max { $0.score < $1.score }!
        }
        
        return objects.first
    }
    
    private func addToTypeHistory(_ objectType: String) {
        recentlyAnnouncedTypes.append(objectType.lowercased())
        if recentlyAnnouncedTypes.count > maxTypeHistory {
            recentlyAnnouncedTypes.removeFirst()
        }
    }
    
    private func generateContextualMessage(_ context: SituationContext, objects: [(object: TrackedObject, score: Float)]) -> (text: String, priority: Int) {
        let vehicleCount = objects.filter { ["car", "truck", "bus", "motorcycle"].contains($0.object.label.lowercased()) }.count
        let criticalCount = objects.filter { $0.score > 0.7 }.count
        
        switch context {
        case .critical:
            return criticalCount > 1 ? ("Attention ! Plusieurs objets très proches", 9) : ("Situation critique détectée", 9)
        case .dense:
            return vehicleCount >= 3 ? ("Circulation dense détectée", 6) : ("Environnement chargé", 6)
        case .calm:
            return ("Zone calme", 3)
        case .normal:
            return ("Circulation normale", 4)
        }
    }
    
    private func createMessageForChange(_ change: SignificantChange, currentTime: Date) -> VoiceMessage? {
        if let contextMessage = change.message {
            return VoiceMessage(text: contextMessage.text, priority: contextMessage.priority, objectId: -1, timestamp: currentTime, changeType: change.type)
        }
        
        guard let object = change.object else { return nil }
        guard let template = voiceTemplates[object.label.lowercased()] else { return nil }
        
        let frenchLabel = translateLabel(object.label)
        let messageText: String
        let priority: Int
        
        switch change.type {
        case .newDanger:
            messageText = "NOUVEAU DANGER ! \(frenchLabel) très proche \(Direction.from(boundingBox: object.lastRect).rawValue) !"
            priority = 10
        case .newNavigation, .groupUpdate:
            let zone = DistanceZone.from(distance: object.distance)
            let direction = Direction.from(boundingBox: object.lastRect)
            let templateMessage = template.getMessage(for: zone)
            messageText = formatMessage(template: templateMessage, direction: direction.rawValue, distance: object.distance)
            priority = change.type == .newNavigation ? template.priority : 5
        default:
            return nil
        }
        
        return VoiceMessage(text: messageText, priority: priority, objectId: object.trackingNumber, timestamp: currentTime, changeType: change.type)
    }
    
    private func translateLabel(_ englishLabel: String) -> String {
        return translationDictionary[englishLabel.lowercased()] ?? englishLabel
    }
    
    private func formatMessage(template: String, direction: String, distance: Float?) -> String {
        var message = template.replacingOccurrences(of: "{direction}", with: direction)
        
        if let dist = distance {
            let formattedDistance = formatDistance(dist)
            message = message.replacingOccurrences(of: "{distance}", with: formattedDistance)
        } else {
            message = message.replacingOccurrences(of: " à {distance}", with: "")
            message = message.replacingOccurrences(of: " {distance}", with: "")
        }
        
        return message
    }
    
    private func formatDistance(_ distance: Float) -> String {
        if distance < 1.0 {
            return "\(Int(distance * 100)) centimètres"
        } else if distance < 10.0 {
            return "\(String(format: "%.1f", distance)) mètres"
        } else {
            return "\(Int(distance)) mètres"
        }
    }
    
    private func updateContextualState(_ objects: [(object: TrackedObject, score: Float)], context: SituationContext, currentTime: Date) {
        contextualState.lastObjectIds = Set(objects.map { $0.object.trackingNumber })
        contextualState.lastSituation = context
        contextualState.lastCriticalObjects = Set(objects.filter { $0.score > 0.7 }.map { $0.object.trackingNumber })
        contextualState.lastNavigationObjects = Set(objects.filter {
            ["traffic light", "traffic sign", "pedestrian crossing"].contains($0.object.label.lowercased())
        }.map { $0.object.trackingNumber })
        
        if context != contextualState.lastSituation {
            contextualState.lastContextAnnouncement = currentTime
        }
    }
    
    private func cleanupAbsentObjectCooldowns(currentObjects: [(object: TrackedObject, score: Float)]) {
        let currentObjectIds = Set(currentObjects.map { $0.object.trackingNumber })
        let absentObjectIds = Set(lastAnnouncements.keys).subtracting(currentObjectIds)
        
        for objectId in absentObjectIds {
            lastAnnouncements.removeValue(forKey: objectId)
        }
    }
    
    private func announceMessages(_ messages: [VoiceMessage], currentTime: Date) {
        guard !messages.isEmpty else { return }
        
        let sortedMessages = messages.sorted { $0.priority > $1.priority }
        let messagesToAnnounce = Array(sortedMessages.prefix(maxMessagesPerUpdate))
        
        messageQueue.append(contentsOf: messagesToAnnounce)
        
        for message in messagesToAnnounce {
            if message.objectId != -1 {
                lastAnnouncements[message.objectId] = currentTime
            }
        }
        
        lastGlobalAnnouncement = currentTime
        processMessageQueue()
    }
    
    func clearAllState() {
        stopSpeaking()
        lastAnnouncements.removeAll()
        lastGlobalAnnouncement = Date.distantPast
        contextualState = ContextualState()
        lastPeriodicAnnouncement = Date.distantPast
        recentlyAnnouncedTypes.removeAll()
        periodicAnnouncementsEnabled = true
        
        // ← NOUVEAU : Reset état interaction
        isInterrupted = false
        interruptionReason = ""
        lastInterruptionTime = Date.distantPast
        
        print("🔄 État complet réinitialisé (incluant interaction)")
    }
    
    func getStats() -> String {
        let interruptionStatus = isInterrupted ? "⏸️ Interrompu (\(interruptionReason))" : "▶️ Actif"
        
        return """
        🗣️ Statistiques de synthèse vocale intelligente:
           - État: \(isCurrentlySpeaking ? "En cours" : "Silencieux")
           - Mode: \(interruptionStatus)
           - Messages en attente: \(messageQueue.count)
           - Annonces périodiques: \(periodicAnnouncementsEnabled ? "✅ Activées" : "⏸️ Désactivées")
           - Types récents: \(recentlyAnnouncedTypes.joined(separator: ", "))
        
        🎯 Mode intelligent: Détection des changements + Diversité des types
        🎤 Support interaction: Interruption automatique + Reprises intelligentes
        """
    }
}

extension VoiceSynthesisManager: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isCurrentlySpeaking = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.processMessageQueue()
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        isCurrentlySpeaking = false
    }
}
