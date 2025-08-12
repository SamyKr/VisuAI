//
//  VoiceInteractionManager.swift
//  VizAI Vision
//
//  🎤 GESTIONNAIRE D'INTERACTION VOCALE INTELLIGENTE
//
//  RÔLE DANS L'ARCHITECTURE :
//  - Point d'entrée unique pour toutes les interactions vocales utilisateur
//  - Interface entre la reconnaissance vocale Apple et le système de réponse contextuelle
//  - Analyseur sémantique des questions en français naturel
//  - Générateur de réponses adaptées au contexte visuel détecté
//
//  FONCTIONNALITÉS PRINCIPALES :
//  ✅ Reconnaissance vocale 100% locale (aucune donnée envoyée sur internet)
//  ✅ Questions spécialisées aide à la traversée ("Puis-je traverser ?")
//  ✅ Analyse de scène par plans de profondeur (proche/moyen/loin)
//  ✅ Dictionnaire complet français-anglais (49 types d'objets)
//  ✅ Parsing intelligent avec synonymes et variantes linguistiques
//  ✅ Gestion d'erreurs robuste avec récupération automatique
//  ✅ Support AirPods et routage audio intelligent
//
//  TYPES DE QUESTIONS SUPPORTÉES :
//  1. Présence : "Y a-t-il une voiture ?"
//  2. Comptage : "Combien de personnes ?"
//  3. Localisation : "Où est le feu ?"
//  4. Description : "Décris la scène"
//  5. Traversée : "Puis-je traverser ?" (analyse sécurité)
//  6. Vue d'ensemble : "Qu'est-ce qui m'entoure ?"

import Foundation
import AVFoundation
import Speech
import UIKit

// MARK: - Structures de Données

enum QuestionType {
    case presence, count, location, description, sceneOverview, specific, crossing, unknown
}

struct ParsedQuestion {
    let type: QuestionType
    let targetObject: String?
    let confidence: Float
    let originalText: String
}

struct SceneAnalysis {
    let totalObjects: Int
    let objectsByType: [String: Int]
    let objectsByZone: [String: [String]]
    let distances: [String: Float]
    let criticalObjects: [String]
    let navigationObjects: [String]
}

// MARK: - Gestionnaire Principal

class VoiceInteractionManager: NSObject, ObservableObject {
    
    // MARK: - Configuration
    private let emergencyTimeoutDuration: TimeInterval = 30.0
    private let maxRetryAttempts = 3
    private let retryDelay: TimeInterval = 2.0
    
    // MARK: - État Observable
    @Published var isListening = false
    @Published var isWaitingForQuestion = false
    @Published var lastRecognizedText = ""
    @Published var interactionEnabled = true
    
    // MARK: - Gestion d'Erreurs
    private var currentRetryCount = 0
    private var lastErrorTime: Date?
    private var isRecovering = false
    private var speechAvailable = true
    
    // MARK: - Reconnaissance Vocale Apple
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "fr-FR"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    // MARK: - Audio et Timers
    private var beepPlayer: AVAudioPlayer?
    private var questionTimer: Timer?
    private var recoveryTimer: Timer?
    
    // MARK: - Gestion Résultats Partiels
    private var lastPartialUpdate: Date?
    private var lastPartialResult: String = ""
    private var partialResultTimer: Timer?
    
    // MARK: - Système de Mémorisation 3 Secondes
    private var isCollectingObjects = false
    private var collectedObjects: [(object: TrackedObject, score: Float, timestamp: Date)] = []
    private var collectionTimer: Timer?
    private var pendingQuestion: ParsedQuestion?
    private var collectionStartTime: Date?
    
    // MARK: - Références Externes
    weak var voiceSynthesisManager: VoiceSynthesisManager?
    private var currentImportantObjects: [(object: TrackedObject, score: Float)] = []
    
    // MARK: - Dictionnaire de Traduction Complet (49 objets)
    private let objectTranslations: [String: [String]] = [
        // Véhicules et usagers
        "person": ["personne", "personnes", "gens", "piéton", "piétons", "homme", "femme", "enfant", "individu"],
        "cyclist": ["cycliste", "cyclistes", "vélo", "cyclisme"],
        "motorcyclist": ["motocycliste", "motocyclistes", "motard", "motards"],
        "car": ["voiture", "voitures", "auto", "autos", "véhicule", "véhicules", "bagnole", "caisse", "automobile"],
        "truck": ["camion", "camions", "poids lourd", "poids lourds", "semi", "semi-remorque", "camionnette"],
        "bus": ["bus", "autobus", "car", "transport en commun"],
        "motorcycle": ["moto", "motos", "motocyclette", "motocyclettes", "scooter", "scooters", "deux-roues"],
        "bicycle": ["vélo", "vélos", "bicyclette", "bicyclettes", "bike", "cycle"],
        "slow_vehicle": ["véhicule lent", "véhicule ralenti", "voiture lente"],
        "vehicle_group": ["groupe de véhicules", "convoi", "files de voitures"],
        "rail_vehicle": ["véhicule ferroviaire", "train", "tramway", "métro"],
        "boat": ["bateau", "bateaux", "embarcation", "navire"],
        
        // Infrastructure routière
        "sidewalk": ["trottoir", "trottoirs", "chaussée piétonne"],
        "road": ["route", "routes", "rue", "rues", "chaussée", "voie", "avenue", "boulevard"],
        "crosswalk": ["passage piéton", "passage piétons", "passage clouté", "zebra", "traversée"],
        "driveway": ["allée", "allées", "entrée", "accès"],
        "bike_lane": ["piste cyclable", "voie cyclable", "bande cyclable"],
        "parking_area": ["zone de stationnement", "parking", "place de parking", "stationnement"],
        "rail_track": ["voie ferrée", "rails", "chemin de fer"],
        "service_lane": ["voie de service", "bande de service"],
        "curb": ["bordure", "bordures", "trottoir", "rebord"],
        
        // Barrières et obstacles
        "wall": ["mur", "murs", "muraille", "cloison"],
        "fence": ["clôture", "clôtures", "grillage", "barrière"],
        "guard_rail": ["glissière de sécurité", "garde-corps", "barrière de sécurité"],
        "temporary_barrier": ["barrière temporaire", "barrière de chantier", "obstacle temporaire"],
        "barrier_other": ["autre barrière", "obstacle", "barrière"],
        "barrier": ["barrière", "barrières", "obstacle", "obstacles"],
        "pole": ["poteau", "poteaux", "pilier", "piliers", "mât", "borne"],
        
        // Signalisation et équipements
        "traffic_light": ["feu", "feux", "feu de circulation", "feux de circulation", "feu tricolore", "signal", "signalisation lumineuse"],
        "traffic_sign": ["panneau", "panneaux", "panneau de signalisation", "signalisation", "stop", "signal routier"],
        "street_light": ["lampadaire", "lampadaires", "éclairage public", "réverbère"],
        "traffic_cone": ["cône", "cônes", "plot", "balise"],
        
        // Mobilier urbain
        "bench": ["banc", "bancs", "siège"],
        "trash_can": ["poubelle", "poubelles", "benne", "conteneur"],
        "fire_hydrant": ["bouche d'incendie", "borne incendie", "hydrant"],
        "mailbox": ["boîte aux lettres", "boîte postale", "courrier"],
        "parking_meter": ["parcmètre", "horodateur", "compteur parking"],
        "bike_rack": ["support à vélos", "rack vélo", "stationnement vélo"],
        "phone_booth": ["cabine téléphonique", "cabine", "téléphone public"],
        
        // Éléments de voirie
        "pothole": ["nid-de-poule", "trou", "défaut chaussée"],
        "manhole": ["plaque d'égout", "bouche d'égout", "regard"],
        "catch_basin": ["regard d'égout", "avaloir", "grille d'évacuation"],
        "water_valve": ["vanne d'eau", "robinet", "valve"],
        "junction_box": ["boîtier de jonction", "coffret électrique", "boîtier"],
        
        // Structures et environnement
        "building": ["bâtiment", "bâtiments", "immeuble", "immeubles", "maison", "maisons", "construction"],
        "bridge": ["pont", "ponts", "passerelle", "viaduc"],
        "tunnel": ["tunnel", "tunnels", "passage souterrain"],
        "garage": ["garage", "garages", "abri"],
        "vegetation": ["végétation", "plante", "plantes", "verdure", "feuillage"],
        "water": ["eau", "rivière", "lac", "étang", "cours d'eau"],
        "terrain": ["terrain", "sol", "surface", "ground"],
        "animals": ["animaux", "animal", "bête", "bêtes"]
    ]
    
    // MARK: - Mots-clés Questions
    private func getPresenceKeywords() -> [String] {
        return ["y a-t-il", "ya-t-il", "est-ce qu'il y a", "il y a", "vois-tu", "détectes-tu","tu vois"]
    }
    
    private func getCountKeywords() -> [String] {
        return ["combien", "nombre", "quantité"]
    }
    
    private func getLocationKeywords() -> [String] {
        return ["où", "position", "située", "situé", "place", "localisation", "emplacement"]
    }
    
    private func getDescriptionKeywords() -> [String] {
        return ["qu'est-ce qui", "que vois-tu", "devant moi", "autour"]
    }
    
    private func getCrossingKeywords() -> [String] {
        return ["peux traverser", "puis traverser", "peut traverser", "traverser", "passer", "croiser", "sûr de traverser", "sécurisé pour traverser"]
    }
    
    private func getSceneKeywords() -> [String] {
        return ["décris", "décris la scène", "que se passe-t-il", "situation"]
    }
    
    private func getQuestionKeywords() -> [QuestionType: [String]] {
        return [
            .presence: getPresenceKeywords(),
            .count: getCountKeywords(),
            .location: getLocationKeywords(),
            .description: getDescriptionKeywords(),
            .sceneOverview: getSceneKeywords(),
            .crossing: getCrossingKeywords()
        ]
    }
    
    // MARK: - Initialisation
    
    override init() {
        super.init()
        setupAudio()
        requestSpeechPermission()
        setupBeepSound()
        checkSpeechAvailability()
    }
    
    deinit {
        cleanupResources()
    }
    
    // MARK: - Configuration Audio Intelligente
    
    /// Configure la session audio avec support AirPods et Bluetooth
    private func setupAudio() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            try audioSession.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [
                    .duckOthers,
                    .allowBluetooth,
                    .allowBluetoothA2DP,
                ]
            )
            
            try audioSession.setActive(false)
            
            // Route audio intelligente selon les périphériques connectés
            let hasAirPods = audioSession.currentRoute.outputs.contains {
                $0.portType == .bluetoothA2DP || $0.portType == .bluetoothHFP
            }
            
            if hasAirPods {
                try audioSession.overrideOutputAudioPort(.none) // AirPods
            } else {
                try audioSession.overrideOutputAudioPort(.speaker) // Haut-parleurs
            }
            
        } catch {
            print("❌ Erreur configuration audio: \(error)")
        }
    }
    
    /// Vérifie la disponibilité de la reconnaissance locale sécurisée
    private func checkSpeechAvailability() {
        guard let speechRecognizer = speechRecognizer else {
            speechAvailable = false
            interactionEnabled = false
            return
        }
        
        speechAvailable = speechRecognizer.isAvailable
        
        if !speechAvailable {
            interactionEnabled = false
            return
        }
        
        // Vérification reconnaissance locale obligatoire (sécurité/confidentialité)
        if #available(iOS 13.0, *) {
            if speechRecognizer.supportsOnDeviceRecognition {
                interactionEnabled = true
            } else {
                interactionEnabled = false
            }
        } else {
            interactionEnabled = false
        }
    }
    
    /// Nettoie toutes les ressources audio et timers
    private func cleanupResources() {
        stopListening()
        resetCollection() // Nettoyer le système de collection
        recoveryTimer?.invalidate()
        recoveryTimer = nil
        
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            // Ignorer les erreurs de nettoyage
        }
    }
    
    // MARK: - Son d'Activation Personnalisé
    
    /// Configure le son d'activation (personnalisé ou généré)
    private func setupBeepSound() {
        let customSoundURL = getCustomSoundURL()
        
        do {
            if FileManager.default.fileExists(atPath: customSoundURL.path) {
                beepPlayer = try AVAudioPlayer(contentsOf: customSoundURL)
            } else {
                let beepURL = createBeepSound()
                beepPlayer = try AVAudioPlayer(contentsOf: beepURL)
            }
            
            beepPlayer?.prepareToPlay()
            beepPlayer?.volume = 1.0
        } catch {
            print("❌ Erreur création son: \(error)")
        }
    }
    
    /// Recherche un fichier son personnalisé dans le bundle ou Documents
    /// @return URL du fichier son à utiliser
    private func getCustomSoundURL() -> URL {
        let possibleBaseNames = ["indicvoca"]
        let possibleExtensions = ["wav", "mp3", "m4a"]
        
        // Recherche dans le bundle
        for baseName in possibleBaseNames {
            for ext in possibleExtensions {
                if let bundleURL = Bundle.main.url(forResource: baseName, withExtension: ext) {
                    return bundleURL
                }
            }
        }
        
        // Recherche dans Documents
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        for baseName in possibleBaseNames {
            for ext in possibleExtensions {
                let soundURL = documentsPath.appendingPathComponent("\(baseName).\(ext)")
                if FileManager.default.fileExists(atPath: soundURL.path) {
                    return soundURL
                }
            }
        }
        
        // Fallback vers bip généré
        return documentsPath.appendingPathComponent("custom_beep.wav")
    }
    
    /// Génère un son bip sinusoïdal simple
    /// @return URL du fichier audio généré
    private func createBeepSound() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioFilename = documentsPath.appendingPathComponent("interaction_beep.wav")
        
        if FileManager.default.fileExists(atPath: audioFilename.path) {
            return audioFilename
        }
        
        let sampleRate: Double = 44100
        let duration: Double = 0.3
        let frequency: Double = 880.0
        let amplitude: Float = 0.5
        
        let frameCount = UInt32(sampleRate * duration)
        let bytesPerFrame = 2
        let totalBytes = frameCount * UInt32(bytesPerFrame)
        
        var audioData = Data(count: Int(totalBytes))
        
        audioData.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
            let samples = bytes.bindMemory(to: Int16.self)
            let frameCountInt = Int(frameCount)
            
            for i in 0..<frameCountInt {
                let timeValue = Double(i) / sampleRate
                let sinValue = sin(2.0 * Double.pi * frequency * timeValue)
                let scaledValue = amplitude * 32767.0 * Float(sinValue)
                let sample = Int16(scaledValue)
                samples[i] = sample
            }
        }
        
        try? audioData.write(to: audioFilename)
        return audioFilename
    }
    
    /// Demande l'autorisation d'accès au microphone
    private func requestSpeechPermission() {
        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            DispatchQueue.main.async {
                switch authStatus {
                case .authorized:
                    self?.interactionEnabled = self?.speechAvailable ?? false
                case .denied, .restricted, .notDetermined:
                    self?.interactionEnabled = false
                @unknown default:
                    self?.interactionEnabled = false
                }
            }
        }
    }
    
    // MARK: - Interface Publique
    
    /// Connecte le gestionnaire de synthèse vocale
    /// @param manager Instance de VoiceSynthesisManager
    func setVoiceSynthesisManager(_ manager: VoiceSynthesisManager) {
        self.voiceSynthesisManager = manager
    }
    
    /// Met à jour la liste des objets importants détectés
    /// @param objects Liste des objets avec leurs scores d'importance
    func updateImportantObjects(_ objects: [(object: TrackedObject, score: Float)]) {
        self.currentImportantObjects = objects
        
        // Si on est en mode collection pour traversée
        if isCollectingObjects {
            let now = Date()
            print("📦 COLLECTION - Nouveaux objets reçus: \(objects.count)")
            
            // Ajouter les nouveaux objets avec timestamp
            for item in objects {
                collectedObjects.append((object: item.object, score: item.score, timestamp: now))
                print("   + Ajouté: \(item.object.label) (score: \(item.score))")
            }
            
            print("📊 COLLECTION - Total collecté: \(collectedObjects.count) objets")
            
            // Pendant la collection, on ne fait PAS de réponse anticipée ni d'autres annonces
            // On attend juste que le timer se termine
            print("🔒 COLLECTION - Mode gelé, pas d'annonces supplémentaires")
            
        } else {
            // Pas en mode collection, juste une mise à jour normale
            if objects.count > 0 {
                print("📱 UPDATE NORMAL - \(objects.count) objets détectés")
            }
        }
    }
    
    /// Vérifie le support de la reconnaissance locale
    /// @return true si la reconnaissance locale est supportée
    func isLocalRecognitionSupported() -> Bool {
        if #available(iOS 13.0, *) {
            return speechRecognizer?.supportsOnDeviceRecognition ?? false
        }
        return false
    }
    
    /// Retourne la version iOS minimum requise
    /// @return String de la version iOS minimale
    func getMinimumIOSVersion() -> String {
        return "iOS 13.0+"
    }
    
    /// Active le mode écoute (préparation seulement)
    func startContinuousListening() {
        guard interactionEnabled && speechAvailable else { return }
        currentRetryCount = 0
        lastRecognizedText = "Prêt - appui long pour parler"
    }
    
    /// Désactive le mode écoute
    func stopContinuousListening() {
        stopListening()
        resetCollection() // Nettoyer le système de collection
        isRecovering = false
        recoveryTimer?.invalidate()
        recoveryTimer = nil
        lastRecognizedText = ""
    }
    
    /// Démarre l'écoute pour UNE question (appelé par appui long)
    func startSingleQuestion() {
        guard interactionEnabled && speechAvailable else {
            voiceSynthesisManager?.speak("Interaction vocale non disponible")
            return
        }
        
        guard !isListening else { return }
        
        // Arrêt total de la synthèse vocale pour libérer l'audio
        voiceSynthesisManager?.stopSpeaking()
        voiceSynthesisManager?.interruptForInteraction(reason: "Question utilisateur")
        
        // Attente libération audio puis démarrage écoute
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.playBeep()
            self?.isWaitingForQuestion = true
            
            // Délai fixe court pour réactivité immédiate (son de 1s max)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.startListening()
                
                // Timeout d'urgence uniquement (Apple gère la finalisation)
                self?.questionTimer = Timer.scheduledTimer(withTimeInterval: self?.emergencyTimeoutDuration ?? 30.0, repeats: false) { _ in
                    self?.handleEmergencyTimeout()
                }
            }
        }
    }
    
    // MARK: - Méthodes d'Interaction avec Synthèse Vocale
    
    /// Interrompt la synthèse pour interaction
    /// @param reason Raison de l'interruption
    func interruptForInteraction(reason: String = "Interaction utilisateur") {
        voiceSynthesisManager?.interruptForInteraction(reason: reason)
    }
    
    /// Fait parler une réponse d'interaction
    /// @param text Texte à vocaliser
    /// @param priority Priorité du message
    func speakInteraction(_ text: String, priority: Int = 15) {
        voiceSynthesisManager?.speakInteraction(text)
    }
    
    /// Reprend la synthèse normale après interaction
    func resumeAfterInteraction() {
        voiceSynthesisManager?.resumeAfterInteraction()
    }
    
    // MARK: - Reconnaissance Vocale Core
    
    /// Démarre l'écoute avec reconnaissance Apple
    private func startListening() {
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            handleSpeechError(NSError(domain: "SpeechRecognizer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Service non disponible"]))
            return
        }
        
        // Vérification période de récupération
        if let lastError = lastErrorTime, Date().timeIntervalSince(lastError) < retryDelay {
            scheduleRetry()
            return
        }
        
        stopListening()
        
        // Activation session audio
        do {
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            handleSpeechError(error)
            return
        }
        
        isListening = true
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            handleSpeechError(NSError(domain: "SpeechRecognizer", code: -2, userInfo: [NSLocalizedDescriptionKey: "Impossible de créer la requête"]))
            return
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        // Forçage mode local obligatoire pour confidentialité
        if #available(iOS 13.0, *) {
            recognitionRequest.requiresOnDeviceRecognition = true
            
            if !speechRecognizer.supportsOnDeviceRecognition {
                handleSpeechError(NSError(domain: "SpeechRecognizer", code: -3, userInfo: [NSLocalizedDescriptionKey: "Mode local requis non supporté"]))
                return
            }
        } else {
            handleSpeechError(NSError(domain: "SpeechRecognizer", code: -4, userInfo: [NSLocalizedDescriptionKey: "iOS 13+ requis"]))
            return
        }
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.removeTap(onBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
        } catch {
            handleSpeechError(error)
            return
        }
        
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            self?.handleRecognitionResult(result: result, error: error)
        }
    }
    
    /// Traite les résultats de reconnaissance vocale Apple
    /// @param result Résultat de SFSpeechRecognitionTask
    /// @param error Erreur éventuelle
    private func handleRecognitionResult(result: SFSpeechRecognitionResult?, error: Error?) {
        if let error = error {
            handleSingleQuestionError(error)
            return
        }
        
        guard let result = result else { return }
        
        let recognizedText = result.bestTranscription.formattedString.lowercased()
        
        // Reset compteurs d'erreur en cas de succès
        if !recognizedText.isEmpty {
            currentRetryCount = 0
            lastErrorTime = nil
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.lastRecognizedText = recognizedText
            
            if result.isFinal {
                self?.processQuestion(text: recognizedText, isFinal: true)
            } else {
                // Résultat partiel - programmer timeout de finalisation
                self?.lastPartialUpdate = Date()
                self?.lastPartialResult = recognizedText
                self?.schedulePartialResultTimeout()
            }
        }
    }
    
    /// Programme un timeout pour finaliser les résultats partiels
    private func schedulePartialResultTimeout() {
        partialResultTimer?.invalidate()
        
        partialResultTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            
            if let lastUpdate = self.lastPartialUpdate,
               Date().timeIntervalSince(lastUpdate) >= 1.5,
               !self.lastPartialResult.isEmpty {
                
                self.processQuestion(text: self.lastPartialResult, isFinal: true)
            }
        }
    }
    
    /// Gère les erreurs lors d'une question ponctuelle
    /// @param error Erreur de reconnaissance
    private func handleSingleQuestionError(_ error: Error) {
        if !lastPartialResult.isEmpty {
            return // Ignorer l'erreur si on a déjà un résultat partiel
        }
        
        stopListening()
        isWaitingForQuestion = false
        
        // Message selon le type d'erreur
        if error.localizedDescription.contains("No speech detected") {
            voiceSynthesisManager?.speak("Je n'ai rien entendu")
        } else {
            voiceSynthesisManager?.speak("Erreur de reconnaissance vocale")
        }
        
        // Reprendre synthèse normale après erreur
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.voiceSynthesisManager?.resumeAfterInteraction()
        }
        
        lastRecognizedText = "Erreur - appui long pour réessayer"
    }
    
    /// Gère le timeout d'urgence (30s)
    private func handleEmergencyTimeout() {
        voiceSynthesisManager?.speak("Timeout d'urgence")
        finishSingleQuestion()
    }
    
    /// Gère les erreurs de reconnaissance et retry automatique
    /// @param error Erreur de reconnaissance
    private func handleSpeechError(_ error: Error) {
        lastErrorTime = Date()
        currentRetryCount += 1
        
        stopListening()
        
        // Arrêt temporaire si trop d'erreurs
        if currentRetryCount >= maxRetryAttempts {
            isRecovering = true
            
            recoveryTimer = Timer.scheduledTimer(withTimeInterval: retryDelay * 3, repeats: false) { [weak self] _ in
                self?.attemptRecovery()
            }
        } else {
            scheduleRetry()
        }
    }
    
    /// Programme une nouvelle tentative après délai
    private func scheduleRetry() {
        DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) { [weak self] in
            if self?.interactionEnabled == true && self?.isRecovering != true {
                self?.startListening()
            }
        }
    }
    
    /// Tente de récupérer le service vocal après erreurs multiples
    private func attemptRecovery() {
        isRecovering = false
        currentRetryCount = 0
        lastErrorTime = nil
        
        checkSpeechAvailability()
        
        if interactionEnabled && speechAvailable {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                // Service récupéré, prêt pour nouvelle question
                self?.lastRecognizedText = "Service récupéré - appui long pour parler"
            }
        }
    }
    
    /// Joue le son d'activation avec routage audio intelligent
    private func playBeep() {
        let audioSession = AVAudioSession.sharedInstance()
        let hasAirPods = audioSession.currentRoute.outputs.contains {
            $0.portType == .bluetoothA2DP || $0.portType == .bluetoothHFP
        }
        
        do {
            if hasAirPods {
                try audioSession.overrideOutputAudioPort(.none) // AirPods
            } else {
                try audioSession.overrideOutputAudioPort(.speaker) // Haut-parleurs
            }
        } catch {
            print("❌ Erreur route audio beep: \(error)")
        }
        
        beepPlayer?.stop()
        beepPlayer?.currentTime = 0
        beepPlayer?.play()
    }
    
    // MARK: - Système de Collection d'Objets sur 3 Secondes
    
    /// Démarre une collection différée après libération de l'audio
    /// @param question Question qui nécessite la collection (traversée uniquement)
    private func startDelayedCollection(for question: ParsedQuestion) {
        print("🔄 DÉBUT COLLECTION DIFFÉRÉE - Question: \(question.type), Objet: \(question.targetObject ?? "aucun")")
        
        // S'assurer que l'audio est complètement libéré
        guard !isListening && !isWaitingForQuestion else {
            print("❌ Audio pas encore libéré, report de la collection")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.startDelayedCollection(for: question)
            }
            return
        }
        
        print("   Objets actuels avant collection: \(currentImportantObjects.count)")
        
        isCollectingObjects = true
        pendingQuestion = question
        collectionStartTime = Date()
        collectedObjects.removeAll()
        
        // GELER les annonces pendant la collection
        voiceSynthesisManager?.interruptForInteraction(reason: "Collection en cours")
        
        // Message de collection puis démarrage immédiat du timer
        voiceSynthesisManager?.speak("Balayez la scène...")
        
        // Démarrer le timer de collection immédiatement (pas d'attente)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.collectionTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
                print("⏰ TIMER COLLECTION DIFFÉRÉE - 3 secondes écoulées, finalisation...")
                self?.completeCollection()
            }
            
            print("⏱️ Timer de collection différée démarré pour 3 secondes")
        }
    }
    
    /// Vérifie si on peut répondre immédiatement (signalisation + danger)
    /// @return true si conditions remplies pour réponse immédiate
    private func canRespondImmediately() -> Bool {
        let allObjects = collectedObjects + currentImportantObjects.map { (object: $0.object, score: $0.score, timestamp: Date()) }
        
        var hasSignalization = false
        var hasDanger = false
        
        for item in allObjects {
            let label = item.object.label
            
            // Signalisation détectée
            if ["traffic_light", "crosswalk", "traffic_sign"].contains(label) {
                hasSignalization = true
            }
            
            // Danger détecté
            if ["car", "truck", "bus", "motorcycle"].contains(label) {
                hasDanger = true
            }
        }
        
        return hasSignalization && hasDanger
    }
    
    /// Termine la collection anticipée et répond immédiatement
    /// @param question Question en attente
    private func completeCollectionEarly(for question: ParsedQuestion) {
        print("⚡ COMPLETE COLLECTION EARLY - Finalisation anticipée")
        
        collectionTimer?.invalidate()
        collectionTimer = nil
        
        let response = generateResponseFromCollection(for: question)
        print("💬 RÉPONSE ANTICIPÉE: '\(response)'")
        voiceSynthesisManager?.speak(response)
        
        resetCollection()
        
        print("✅ Collection anticipée terminée")
    }
    
    /// Termine la collection après 3 secondes et génère la réponse
    private func completeCollection() {
        guard let question = pendingQuestion else {
            print("❌ COMPLETE COLLECTION - Pas de question en attente")
            return
        }
        
        print("🏁 COMPLETE COLLECTION - Finalisation normale après 3 secondes")
        print("   Question type: \(question.type)")
        print("   Objet cible: \(question.targetObject ?? "aucun")")
        print("   Objets collectés: \(collectedObjects.count)")
        print("   Objets actuels: \(currentImportantObjects.count)")
        
        let response = generateResponseFromCollection(for: question)
        print("💬 RÉPONSE GÉNÉRÉE: '\(response)'")
        voiceSynthesisManager?.speak(response)
        
        resetCollection()
        
        // Finaliser la session après la réponse
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            print("🔚 Finalisation de la session question")
            self?.finishSingleQuestion()
        }
    }
    
    /// Génère une réponse basée sur tous les objets collectés
    /// @param question Question à traiter
    /// @return Réponse basée sur la collection complète
    private func generateResponseFromCollection(for question: ParsedQuestion) -> String {
        print("🔀 GÉNÉRATION RÉPONSE COLLECTION")
        print("   Objets collectés: \(collectedObjects.count)")
        print("   Objets actuels: \(currentImportantObjects.count)")
        
        // Fusionner objets collectés + objets actuels
        let allObjectsWithScore = collectedObjects.map { (object: $0.object, score: $0.score) } + currentImportantObjects
        print("   Total fusionné: \(allObjectsWithScore.count) objets")
        
        // Log des objets fusionnés
        for (index, item) in allObjectsWithScore.enumerated() {
            print("     [\(index)] \(item.object.label) (score: \(item.score))")
        }
        
        // Créer une analyse temporaire avec tous les objets
        let tempImportantObjects = currentImportantObjects
        self.currentImportantObjects = allObjectsWithScore
        
        let response: String
        switch question.type {
        case .crossing:
            print("   → Traitement CROSSING avec collection")
            response = handleCrossingQuestion(analysis: analyzeCurrentScene())
        default:
            print("   → Traitement DEFAULT avec collection")
            response = generateResponse(for: question)
        }
        
        // Restaurer objets originaux
        self.currentImportantObjects = tempImportantObjects
        print("   Objets restaurés: \(self.currentImportantObjects.count)")
        
        return response
    }
    
    /// Remet à zéro le système de collection
    private func resetCollection() {
        print("🧹 RESET COLLECTION")
        print("   Collection active: \(isCollectingObjects)")
        print("   Objets collectés avant reset: \(collectedObjects.count)")
        print("   Timer actif: \(collectionTimer != nil)")
        
        isCollectingObjects = false
        pendingQuestion = nil
        collectionStartTime = nil
        collectedObjects.removeAll()
        collectionTimer?.invalidate()
        collectionTimer = nil
        
        print("   ✅ Collection resetée")
    }
    
    // MARK: - Analyse et Traitement des Questions
    
    /// Traite une question finalisée et génère la réponse
    /// @param text Texte de la question
    /// @param isFinal true si finalisation confirmée
    private func processQuestion(text: String, isFinal: Bool) {
        partialResultTimer?.invalidate()
        partialResultTimer = nil
        questionTimer?.invalidate()
        questionTimer = nil
        
        print("🎤 PROCESSING QUESTION: '\(text)'")
        
        let parsedQuestion = parseQuestion(text)
        
        print("📝 QUESTION PARSÉE:")
        print("   Type final: \(parsedQuestion.type)")
        print("   Objet cible: \(parsedQuestion.targetObject ?? "aucun")")
        print("   Confiance: \(parsedQuestion.confidence)")
        print("   Objets disponibles: \(currentImportantObjects.count)")
        
        // Vérifier si c'est une question de traversée qui nécessite collection
        if parsedQuestion.type == .crossing {
            print("🔄 Question de traversée détectée - Collection nécessaire")
            print("   → PAS de réponse immédiate, collection directe")
            
            // Toujours finaliser la session de reconnaissance en premier
            finishSingleQuestion()
            
            // Démarrer la collection différée APRÈS avoir libéré l'audio
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                print("🔄 Démarrage collection pour traversée...")
                self?.startDelayedCollection(for: parsedQuestion)
            }
            return
        }
        
        // Pour toutes les autres questions (y compris localisation), réponse immédiate normale
        let immediateResponse: String
        if currentImportantObjects.isEmpty {
            immediateResponse = "Je ne détecte aucun objet actuellement"
        } else {
            immediateResponse = generateResponse(for: parsedQuestion)
        }
        
        print("💬 Réponse immédiate pour type \(parsedQuestion.type): '\(immediateResponse)'")
        voiceSynthesisManager?.speak(immediateResponse)
        
        // Finaliser la session
        finishSingleQuestion()
    }
    
    /// Finalise une session de question
    private func finishSingleQuestion() {
        print("🏁 FINISH SINGLE QUESTION")
        print("   Collection en cours: \(isCollectingObjects)")
        print("   Listening: \(isListening)")
        
        questionTimer?.invalidate()
        questionTimer = nil
        isWaitingForQuestion = false
        
        // Si une collection est en cours, ne pas finaliser maintenant
        if isCollectingObjects {
            print("   ⏳ Collection en cours, ne pas finaliser maintenant")
            return
        }
        
        print("   🔇 Arrêt de l'écoute")
        stopListening()
        
        // Reprendre synthèse normale
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            print("   🔊 Reprise synthèse normale")
            self?.voiceSynthesisManager?.resumeAfterInteraction()
        }
        
        lastRecognizedText = "Question traitée - appui long pour une nouvelle question"
        print("   ✅ Session terminée")
    }
    
    
    /// Arrête complètement l'écoute et nettoie les ressources
    private func stopListening() {
        partialResultTimer?.invalidate()
        partialResultTimer = nil
        
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
        
        questionTimer?.invalidate()
        questionTimer = nil
        
        // Désactivation propre de la session audio
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // Ignorer les erreurs de désactivation
        }
    }
    
    // MARK: - Analyse Sémantique des Questions
    
    /// Parse une question en français et identifie son type et cible
    /// @param text Texte de la question
    /// @return ParsedQuestion avec type, objet cible et confiance
    private func parseQuestion(_ text: String) -> ParsedQuestion {
        let normalizedText = text.lowercased()
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: ".", with: "")
        
        print("🔍 DEBUG PARSING - Texte original: '\(text)'")
        print("🔍 DEBUG PARSING - Texte normalisé: '\(normalizedText)'")
        
        var questionType: QuestionType = .unknown
        var confidence: Float = 0.0
        var detectedKeyword = ""
        
        // Test prioritaire des mots-clés CROSSING (sécurité)
        let crossingKeywords = getCrossingKeywords()
        print("🔍 DEBUG PARSING - Test CROSSING avec mots-clés: \(crossingKeywords)")
        for keyword in crossingKeywords {
            if normalizedText.contains(keyword) {
                questionType = .crossing
                confidence = 0.9
                detectedKeyword = keyword
                print("✅ DEBUG PARSING - CROSSING détecté avec '\(keyword)'")
                break
            }
        }
        
        // Test des mots-clés LOCATION (très spécifique)
        if questionType == .unknown {
            let locationKeywords = getLocationKeywords()
            print("🔍 DEBUG PARSING - Test LOCATION avec mots-clés: \(locationKeywords)")
            for keyword in locationKeywords {
                if normalizedText.contains(keyword) {
                    questionType = .location
                    confidence = 0.9
                    detectedKeyword = keyword
                    print("✅ DEBUG PARSING - LOCATION détecté avec '\(keyword)'")
                    break
                }
            }
        }
        
        // Test des mots-clés COUNT (plus spécifique)
        if questionType == .unknown {
            let countKeywords = getCountKeywords()
            print("🔍 DEBUG PARSING - Test COUNT avec mots-clés: \(countKeywords)")
            for keyword in countKeywords {
                if normalizedText.contains(keyword) {
                    questionType = .count
                    confidence = 0.8
                    detectedKeyword = keyword
                    print("✅ DEBUG PARSING - COUNT détecté avec '\(keyword)'")
                    break
                }
            }
        }
        
        // Test des autres types de questions
        if questionType == .unknown {
            let questionKeywords = getQuestionKeywords()
            print("🔍 DEBUG PARSING - Test autres types de questions")
            for (type, keywords) in questionKeywords {
                if type == .crossing || type == .count || type == .location { continue }
                print("🔍 DEBUG PARSING - Test \(type) avec mots-clés: \(keywords)")
                for keyword in keywords {
                    if normalizedText.contains(keyword) {
                        questionType = type
                        confidence = 0.8
                        detectedKeyword = keyword
                        print("✅ DEBUG PARSING - \(type) détecté avec '\(keyword)'")
                        break
                    }
                }
                if confidence > 0 { break }
            }
        }
        
        var targetObject: String?
        
        // Reconnaissance d'objet avec dictionnaire complet
        print("🔍 DEBUG PARSING - Recherche d'objet cible dans le dictionnaire...")
        for (englishObject, frenchVariants) in objectTranslations {
            for variant in frenchVariants {
                if normalizedText.contains(variant) {
                    targetObject = englishObject
                    confidence = max(confidence, 0.7)
                    print("✅ DEBUG PARSING - Objet trouvé: '\(variant)' -> '\(englishObject)'")
                    break
                }
            }
            if targetObject != nil { break }
        }
        
        // Cas spéciaux pour améliorer la détection
        if normalizedText.contains("scène") || normalizedText.contains("situation") {
            questionType = .sceneOverview
            confidence = 0.9
            detectedKeyword = "scène/situation"
            print("✅ DEBUG PARSING - SCENE_OVERVIEW détecté avec mot spécial")
        }
        
        if normalizedText.contains("devant") {
            questionType = .description
            confidence = max(confidence, 0.8)
            detectedKeyword = "devant"
            print("✅ DEBUG PARSING - DESCRIPTION détecté avec 'devant'")
        }
        
        // AJOUT: Détection spéciale pour "position" sans mot-clé "où"
        if normalizedText.contains("position") && questionType == .unknown {
            questionType = .location
            confidence = 0.8
            detectedKeyword = "position"
            print("✅ DEBUG PARSING - LOCATION détecté avec 'position' (cas spécial)")
        }
        
        let result = ParsedQuestion(
            type: questionType,
            targetObject: targetObject,
            confidence: confidence,
            originalText: text
        )
        
        print("🎯 DEBUG PARSING - RÉSULTAT:")
        print("   Type: \(questionType)")
        print("   Objet cible: \(targetObject ?? "aucun")")
        print("   Confiance: \(confidence)")
        print("   Mot-clé détecté: '\(detectedKeyword)'")
        print("───────────────────────────────")
        
        return result
    }
    
    // MARK: - Génération des Réponses Contextuelles
    
    /// Génère une réponse adaptée au type de question et au contexte
    /// @param question Question parsée avec type et cible
    /// @return String de réponse à vocaliser
    private func generateResponse(for question: ParsedQuestion) -> String {
        let analysis = analyzeCurrentScene()
        
        print("🎯 GÉNÉRATION RÉPONSE pour type: \(question.type)")
        print("   Objets analysés: \(analysis.totalObjects)")
        print("   Objet cible demandé: \(question.targetObject ?? "aucun")")
        
        switch question.type {
        case .presence:
            print("   → Appel handlePresenceQuestion")
            return handlePresenceQuestion(question, analysis: analysis)
        case .count:
            print("   → Appel handleCountQuestion")
            return handleCountQuestion(question, analysis: analysis)
        case .location:
            print("   → Appel handleLocationQuestion")
            return handleLocationQuestion(question, analysis: analysis)
        case .description:
            print("   → Appel handleDescriptionQuestion")
            return handleDescriptionQuestion(analysis: analysis)
        case .sceneOverview:
            print("   → Appel handleSceneOverviewQuestion")
            return handleSceneOverviewQuestion(analysis: analysis)
        case .crossing:
            print("   → Appel handleCrossingQuestion")
            return handleCrossingQuestion(analysis: analysis)
        case .specific:
            print("   → Appel handleSpecificQuestion")
            return handleSpecificQuestion(question, analysis: analysis)
        case .unknown:
            print("   → Appel handleUnknownQuestion")
            return handleUnknownQuestion(question, analysis: analysis)
        }
    }
    
    /// Analyse la scène actuelle et structure les informations
    /// @return SceneAnalysis avec objets organisés par type/zone/distance
    private func analyzeCurrentScene() -> SceneAnalysis {
        var objectsByType: [String: Int] = [:]
        var objectsByZone: [String: [String]] = [
            "devant": [], "gauche": [], "droite": []
        ]
        var distances: [String: Float] = [:]
        var criticalObjects: [String] = []
        var navigationObjects: [String] = []
        
        for (_, item) in currentImportantObjects.enumerated() {
            let object = item.object
            let frenchLabel = translateToFrench(object.label)
            
            // Comptage par type
            objectsByType[frenchLabel, default: 0] += 1
            
            // Analyse de position spatiale
            let zone = getZoneFromBoundingBox(object.lastRect)
            objectsByZone[zone, default: []].append(frenchLabel)
            
            // Stockage des distances
            if let distance = object.distance {
                let key = "\(frenchLabel)_\(object.trackingNumber)"
                distances[key] = distance
            }
            
            // Classification en objets critiques
            if item.score > 0.7 {
                criticalObjects.append(frenchLabel)
            }
            
            // Classification en objets de navigation
            if ["traffic_light", "traffic_sign", "crosswalk", "street_light", "traffic_cone"].contains(object.label) {
                navigationObjects.append(frenchLabel)
            }
        }
        
        return SceneAnalysis(
            totalObjects: currentImportantObjects.count,
            objectsByType: objectsByType,
            objectsByZone: objectsByZone,
            distances: distances,
            criticalObjects: criticalObjects,
            navigationObjects: navigationObjects
        )
    }
    
    /// Traite les questions de présence ("Y a-t-il une voiture ?")
    /// @param question Question parsée
    /// @param analysis Analyse de scène
    /// @return Réponse textuelle
    private func handlePresenceQuestion(_ question: ParsedQuestion, analysis: SceneAnalysis) -> String {
        guard let targetObject = question.targetObject else {
            if analysis.totalObjects == 0 {
                return "Non, aucun objet détecté actuellement"
            }
            
            let objectsList = analysis.objectsByType.map { type, count in
                if count == 1 {
                    return "une \(type)"
                } else {
                    return "\(count) \(type)s"
                }
            }
            
            if objectsList.count == 1 {
                return "Oui, je vois \(objectsList[0])"
            } else if objectsList.count == 2 {
                return "Oui, je vois \(objectsList[0]) et \(objectsList[1])"
            } else {
                let allButLast = objectsList.dropLast().joined(separator: ", ")
                return "Oui, je vois \(allButLast) et \(objectsList.last!)"
            }
        }
        
        let frenchLabel = translateToFrench(targetObject)
        let count = analysis.objectsByType[frenchLabel] ?? 0
        
        if count > 0 {
            return count == 1 ?
                "Oui je vois une \(frenchLabel)" :
                "Oui je vois \(count) \(frenchLabel)s"
        } else {
            return "Non je n'en vois pas"
        }
    }
    
    /// Traite les questions de comptage ("Combien de voitures ?")
    /// @param question Question parsée
    /// @param analysis Analyse de scène
    /// @return Réponse textuelle
    private func handleCountQuestion(_ question: ParsedQuestion, analysis: SceneAnalysis) -> String {
        guard let targetObject = question.targetObject else {
            let total = analysis.totalObjects
            if total == 0 {
                return "Je ne détecte aucun objet actuellement"
            } else if total == 1 {
                return "Je détecte un objet"
            } else {
                let summaryParts = analysis.objectsByType.map { type, count in
                    "\(count) \(type)\(count > 1 ? "s" : "")"
                }
                let summary = summaryParts.joined(separator: ", ")
                return "Je détecte \(total) objets au total : \(summary)"
            }
        }
        
        let frenchLabel = translateToFrench(targetObject)
        let count = analysis.objectsByType[frenchLabel] ?? 0
        
        switch count {
        case 0:
            return "Aucune \(frenchLabel) détectée"
        case 1:
            return "Une \(frenchLabel)"
        default:
            return "\(count) \(frenchLabel)s"
        }
    }
    
    /// Traite les questions de localisation ("Où est la voiture ?")
    /// @param question Question parsée
    /// @param analysis Analyse de scène
    /// @return Réponse textuelle
    private func handleLocationQuestion(_ question: ParsedQuestion, analysis: SceneAnalysis) -> String {
        print("📍 HANDLE LOCATION QUESTION")
        print("   Objet cible: \(question.targetObject ?? "aucun")")
        print("   Objets analysés: \(analysis.totalObjects)")
        print("   Types d'objets: \(analysis.objectsByType)")
        
        guard let targetObject = question.targetObject else {
            print("   → Pas d'objet cible, réponse générale")
            return generateGeneralLocationResponse(analysis: analysis)
        }
        
        let frenchLabel = translateToFrench(targetObject)
        let count = analysis.objectsByType[frenchLabel] ?? 0
        
        print("   Label français: '\(frenchLabel)'")
        print("   Nombre trouvé: \(count)")
        
        if count == 0 {
            return "Je ne vois pas de \(frenchLabel) actuellement"
        }
        
        let location = findObjectLocation(targetObject, in: analysis)
        let distance = findObjectDistance(targetObject, in: analysis)
        
        var response = "La \(frenchLabel) est \(location.isEmpty ? "visible" : location)"
        if !distance.isEmpty {
            response += " \(distance)"
        }
        
        if count > 1 {
            response = "Je vois \(count) \(frenchLabel)s. " + response.replacingOccurrences(of: "La \(frenchLabel)", with: "L'une d'elles")
        }
        
        print("   Réponse générée: '\(response)'")
        return response
    }
    
    /// Traite les questions de description ("Qu'est-ce qui est devant moi ?")
    /// @param analysis Analyse de scène
    /// @return Réponse textuelle
    private func handleDescriptionQuestion(analysis: SceneAnalysis) -> String {
        if analysis.totalObjects == 0 {
            return "Je ne vois rien de particulier devant vous"
        }
        
        let frontObjects = analysis.objectsByZone["devant"] ?? []
        
        if frontObjects.isEmpty {
            return "Rien directement devant vous, mais je détecte des objets sur les côtés"
        }
        
        let objectGroups = Dictionary(grouping: frontObjects) { $0 }
        let objectList = objectGroups.map { obj, occurrences in
            let count = occurrences.count
            return count > 1 ? "\(count) \(obj)s" : "une \(obj)"
        }.joined(separator: ", ")
        
        return "Devant vous, je vois : \(objectList)"
    }
    
    /// Traite les questions de vue d'ensemble ("Décris la scène")
    /// @param analysis Analyse de scène
    /// @return Réponse textuelle structurée par plans
    private func handleSceneOverviewQuestion(analysis: SceneAnalysis) -> String {
        if analysis.totalObjects == 0 {
            return "Aucun objet détecté"
        }
        
        let plansAnalysis = analyzeSceneByPlans()
        var description: [String] = []
        
        // Description par plans de profondeur avec formulation naturelle
        if !plansAnalysis.firstPlan.isEmpty {
            let firstPlanDesc = createGroupedDescription(plansAnalysis.firstPlan)
            description.append("Au premier plan, je vois \(firstPlanDesc)")
        }
        
        if !plansAnalysis.secondPlan.isEmpty {
            let secondPlanDesc = createGroupedDescription(plansAnalysis.secondPlan)
            description.append("Plus loin, \(secondPlanDesc)")
        }
        
        if !plansAnalysis.thirdPlan.isEmpty {
            let thirdPlanDesc = createGroupedDescription(plansAnalysis.thirdPlan)
            description.append("Au fond, \(thirdPlanDesc)")
        }
        
        // Information d'ambiance
        let ambiance = determineAmbiance(analysis)
        if !ambiance.isEmpty {
            description.append(ambiance)
        }
        
        let result = description.isEmpty ?
            "\(analysis.totalObjects) objet\(analysis.totalObjects > 1 ? "s" : "") détecté\(analysis.totalObjects > 1 ? "s" : "")" :
            description.joined(separator: ". ")
        
        return result
    }
    
    // MARK: - Analyse Spécialisée Aide à la Traversée
    
    /// Traite les questions de traversée ("Puis-je traverser ?")
    /// @param analysis Analyse de scène
    /// @return Conseil de sécurité adaptatif
    private func handleCrossingQuestion(analysis: SceneAnalysis) -> String {
        // Analyse signalisation de traversée
        let crossingSignalization = analyzeCrossingSignalization(analysis)
        
        // Analyse situation circulation
        let trafficAnalysis = analyzeTrafficSituation(analysis)
        
        // Génération conseil sécurité
        return generateCrossingAdvice(signalization: crossingSignalization, traffic: trafficAnalysis)
    }
    
    private struct CrossingSignalization {
        let hasTrafficLight: Bool
        let hasCrosswalk: Bool
        let hasTrafficSigns: Bool
        let hasStreetLight: Bool
        let signalizationScore: Int
    }
    
    private struct TrafficSituation {
        let vehicleCount: Int
        let closeVehicles: Int
        let movingVehicles: Int
        let safetyScore: Int
    }
    
    /// Analyse la signalisation disponible pour la traversée
    /// @param analysis Analyse de scène générale
    /// @return CrossingSignalization avec éléments détectés
    private func analyzeCrossingSignalization(_ analysis: SceneAnalysis) -> CrossingSignalization {
        var hasTrafficLight = false
        var hasCrosswalk = false
        var hasTrafficSigns = false
        var hasStreetLight = false
        
        for (object, _) in currentImportantObjects {
            switch object.label {
            case "traffic_light":
                hasTrafficLight = true
            case "crosswalk":
                hasCrosswalk = true
            case "traffic_sign":
                hasTrafficSigns = true
            case "street_light":
                hasStreetLight = true
            default:
                break
            }
        }
        
        // Score de signalisation (0-4)
        var score = 0
        if hasTrafficLight { score += 2 }
        if hasCrosswalk { score += 2 }
        if hasTrafficSigns { score += 1 }
        if hasStreetLight { score += 1 }
        
        return CrossingSignalization(
            hasTrafficLight: hasTrafficLight,
            hasCrosswalk: hasCrosswalk,
            hasTrafficSigns: hasTrafficSigns,
            hasStreetLight: hasStreetLight,
            signalizationScore: score
        )
    }
    
    /// Analyse la situation de circulation
    /// @param analysis Analyse de scène générale
    /// @return TrafficSituation avec métrics de sécurité
    private func analyzeTrafficSituation(_ analysis: SceneAnalysis) -> TrafficSituation {
        let vehicleTypes = ["voiture", "camion", "bus", "moto", "vélo"]
        var vehicleCount = 0
        var closeVehicles = 0
        var movingVehicles = 0
        
        for (object, score) in currentImportantObjects {
            let frenchLabel = translateToFrench(object.label)
            
            if vehicleTypes.contains(frenchLabel) {
                vehicleCount += 1
                
                // Véhicules proches (< 5m)
                if let distance = object.distance, distance < 5.0 {
                    closeVehicles += 1
                }
                
                // Véhicules en mouvement (score élevé)
                if score > 0.8 {
                    movingVehicles += 1
                }
            }
        }
        
        // Score de sécurité (0-10)
        var safetyScore = 10
        safetyScore -= closeVehicles * 3
        safetyScore -= movingVehicles * 2
        safetyScore -= max(0, vehicleCount - 2)
        safetyScore = max(0, safetyScore)
        
        return TrafficSituation(
            vehicleCount: vehicleCount,
            closeVehicles: closeVehicles,
            movingVehicles: movingVehicles,
            safetyScore: safetyScore
        )
    }
    
    /// Génère un conseil de traversée adaptatif
    /// @param signalization Analyse signalisation
    /// @param traffic Analyse circulation
    /// @return Conseil personnalisé
    private func generateCrossingAdvice(signalization: CrossingSignalization, traffic: TrafficSituation) -> String {
        // Signalisation complète (feu + passage piéton)
        if signalization.hasTrafficLight && signalization.hasCrosswalk {
            if traffic.safetyScore >= 7 {
                return "Oui, signalisation complète présente. Traversez au feu vert avec prudence"
            } else if traffic.closeVehicles > 0 {
                return "Signalisation présente mais circulation dense. Attendez que les véhicules passent"
            } else {
                return "Signalisation présente. Vérifiez le feu et traversez prudemment"
            }
        }
        
        // Passage piéton sans feu
        if signalization.hasCrosswalk && !signalization.hasTrafficLight {
            if traffic.safetyScore >= 8 {
                return "Passage piéton détecté, circulation calme. Vous pouvez traverser prudemment"
            } else if traffic.closeVehicles > 2 {
                return "Passage piéton présent mais circulation dense. Attendez une accalmie"
            } else {
                return "Passage piéton présent. Vérifiez bien la circulation avant de traverser"
            }
        }
        
        // Feu sans passage piéton visible
        if signalization.hasTrafficLight && !signalization.hasCrosswalk {
            return "Feu de circulation détecté. Cherchez le passage piéton à proximité"
        }
        
        // Signalisation minimale ou absente
        if signalization.signalizationScore <= 1 {
            if traffic.vehicleCount == 0 {
                return "Aucune signalisation et aucun véhicule"
            } else if traffic.safetyScore >= 8 {
                return "Pas de signalisation officielle. Circulation calme mais restez très prudent"
            } else {
                return "Pas de signalisation sécurisée et circulation présente. Cherchez un passage aménagé"
            }
        }
        
        // Signalisation partielle
        if traffic.safetyScore >= 6 {
            return "Signalisation partielle, circulation modérée. Traversée possible avec grande prudence"
        } else {
            return "Signalisation insuffisante et circulation dense. Trouvez un passage plus sûr"
        }
    }
    
    /// Traite les questions spécifiques (délégué vers localisation)
    /// @param question Question parsée
    /// @param analysis Analyse de scène
    /// @return Réponse textuelle
    private func handleSpecificQuestion(_ question: ParsedQuestion, analysis: SceneAnalysis) -> String {
        return handleLocationQuestion(question, analysis: analysis)
    }
    
    /// Traite les questions non reconnues avec aide contextuelle
    /// @param question Question parsée
    /// @param analysis Analyse de scène
    /// @return Réponse avec aide et contexte
    private func handleUnknownQuestion(_ question: ParsedQuestion, analysis: SceneAnalysis) -> String {
        print("❓ QUESTION UNKNOWN - Analyse:")
        print("   Texte original: '\(question.originalText)'")
        print("   Type détecté: \(question.type)")
        print("   Objet cible: \(question.targetObject ?? "aucun")")
        print("   Confiance: \(question.confidence)")
        
        let text = question.originalText.lowercased()
        
        if text.contains("aide") || text.contains("help") {
            return "Vous pouvez me demander s'il y a des objets, combien il y en a, où ils sont, si vous pouvez traverser, ou me demander de décrire la scène"
        }
        
        if analysis.totalObjects == 0 {
            return "Je ne détecte aucun objet actuellement. Reformulez votre question si besoin"
        }
        
        let mainObjectsList = Array(analysis.objectsByType.prefix(3))
        let mainObjects = mainObjectsList.map { type, count in
            "\(count) \(type)\(count > 1 ? "s" : "")"
        }.joined(separator: ", ")
        
        return "Je ne suis pas sûr de comprendre. Actuellement je vois : \(mainObjects)"
    }
    
    // MARK: - Analyse par Plans de Profondeur
    
    private struct PlansAnalysis {
        let firstPlan: [ObjectDescription]      // < 3m (distance critique)
        let secondPlan: [ObjectDescription]     // 3-6m
        let thirdPlan: [ObjectDescription]      // > 6m
    }
    
    private struct ObjectDescription {
        let frenchName: String
        let distance: Float?
        let zone: String
        let count: Int
        let isCritical: Bool
        let isNavigation: Bool
    }
    
    /// Analyse la scène par plans de profondeur
    /// @return PlansAnalysis structurée par distance
    private func analyzeSceneByPlans() -> PlansAnalysis {
        var firstPlan: [ObjectDescription] = []
        var secondPlan: [ObjectDescription] = []
        var thirdPlan: [ObjectDescription] = []
        
        // Groupement par type d'objet
        let objectGroups = Dictionary(grouping: currentImportantObjects) {
            translateToFrench($0.object.label)
        }
        
        for (frenchName, objects) in objectGroups {
            let distances = objects.compactMap { $0.object.distance }
            let avgDistance = distances.isEmpty ? nil : distances.reduce(0, +) / Float(distances.count)
            let minDistance = distances.min()
            
            // Zone principale
            let zones = objects.map { getZoneFromBoundingBox($0.object.lastRect) }
            let zoneCounts = Dictionary(grouping: zones, by: { $0 }).mapValues { $0.count }
            let mainZone = zoneCounts.max(by: { $0.value < $1.value })?.key ?? "devant"
            
            // Classification criticité et navigation
            let isCritical = objects.contains { $0.score > 0.7 }
            let isNavigation = objects.contains {
                ["traffic_light", "traffic_sign", "crosswalk", "street_light", "traffic_cone"].contains($0.object.label)
            }
            
            let objectDesc = ObjectDescription(
                frenchName: frenchName,
                distance: avgDistance,
                zone: mainZone,
                count: objects.count,
                isCritical: isCritical,
                isNavigation: isNavigation
            )
            
            // Classification par plan selon distance
            if let minDist = minDistance {
                if minDist < 3.0 {
                    firstPlan.append(objectDesc)
                } else if minDist < 6.0 {
                    secondPlan.append(objectDesc)
                } else {
                    thirdPlan.append(objectDesc)
                }
            } else {
                // Sans distance, classer par priorité
                if isCritical {
                    firstPlan.append(objectDesc)
                } else {
                    secondPlan.append(objectDesc)
                }
            }
        }
        
        return PlansAnalysis(
            firstPlan: firstPlan.sorted { $0.distance ?? 0 < $1.distance ?? 0 },
            secondPlan: secondPlan.sorted { $0.distance ?? 5 < $1.distance ?? 5 },
            thirdPlan: thirdPlan.sorted { $0.distance ?? 10 < $1.distance ?? 10 }
        )
    }
    
    /// Crée une description groupée pour un plan de profondeur
    /// @param objects Liste d'objets du plan
    /// @return Description textuelle naturelle et groupée
    private func createGroupedDescription(_ objects: [ObjectDescription]) -> String {
        if objects.isEmpty { return "" }
        
        var descriptions: [String] = []
        
        for obj in objects {
            let objectName = getGroupedObjectName(obj)
            let locationInfo = getLocationInfo(obj)
            
            let fullDescription = locationInfo.isEmpty ? objectName : "\(objectName)\(locationInfo)"
            descriptions.append(fullDescription)
        }
        
        return joinDescriptions(descriptions)
    }
    
    /// Obtient le nom d'un objet avec quantité pour description groupée
    /// @param obj Description d'objet
    /// @return Nom avec quantité appropriée
    private func getGroupedObjectName(_ obj: ObjectDescription) -> String {
        if obj.count == 1 {
            return getDirectName(obj)
        } else {
            return "\(obj.count) \(obj.frenchName)s"
        }
    }
    
    /// Obtient l'information de localisation simplifiée
    /// @param obj Description d'objet
    /// @return Information de localisation
    private func getLocationInfo(_ obj: ObjectDescription) -> String {
        var location = ""
        
        // Position spatiale uniquement
        switch obj.zone {
        case "gauche":
            location = " à gauche"
        case "droite":
            location = " à droite"
        case "devant":
            location = ""  // Pas besoin de préciser "devant" dans une description narrative
        default:
            location = ""
        }
        
        return location
    }
    
    /// Obtient le nom direct d'un objet en français naturel
    /// @param obj Description d'objet
    /// @return Nom avec article approprié
    private func getDirectName(_ obj: ObjectDescription) -> String {
        let directNames: [String: String] = [
            "voiture": "une voiture",
            "personne": "une personne",
            "arbre": "un arbre",
            "bâtiment": "un bâtiment",
            "poteau": "un poteau",
            "feu de circulation": "un feu",
            "panneau de signalisation": "un panneau",
            "trottoir": "le trottoir",
            "route": "la route",
            "passage piéton": "un passage piéton",
            "lampadaire": "un lampadaire",
            "banc": "un banc",
            "végétation": "de la végétation",
            "mur": "un mur",
            "eau": "de l'eau"
        ]
        
        return directNames[obj.frenchName] ?? "une \(obj.frenchName)"
    }
    
    /// Joint les descriptions avec conjonctions appropriées
    /// @param descriptions Liste de descriptions
    /// @return Texte joint naturellement
    private func joinDescriptions(_ descriptions: [String]) -> String {
        if descriptions.isEmpty { return "" }
        if descriptions.count == 1 { return descriptions[0] }
        if descriptions.count == 2 { return "\(descriptions[0]) et \(descriptions[1])" }
        
        let allButLast = descriptions.dropLast().joined(separator: ", ")
        return "\(allButLast) et \(descriptions.last!)"
    }
    
    /// Détermine l'ambiance générale de la scène
    /// @param analysis Analyse de scène
    /// @return Description d'ambiance
    private func determineAmbiance(_ analysis: SceneAnalysis) -> String {
        if analysis.criticalObjects.count > 2 {
            return "Attention, plusieurs objets proches"
        }
        
        if analysis.navigationObjects.count > 0 {
            return "Signalisation présente"
        }
        
        let vehicleCount = analysis.objectsByType.filter {
            ["voiture", "camion", "bus", "moto"].contains($0.key)
        }.values.reduce(0, +)
        
        if vehicleCount > 3 {
            return "Circulation dense"
        }
        
        if analysis.totalObjects < 3 {
            return "Environnement calme"
        }
        
        return ""
    }
    
    // MARK: - Méthodes Utilitaires
    
    /// Traduit un label anglais vers français
    /// @param englishLabel Label anglais du modèle
    /// @return Équivalent français
    private func translateToFrench(_ englishLabel: String) -> String {
        for (english, frenchVariants) in objectTranslations {
            if english == englishLabel {
                return frenchVariants.first ?? englishLabel
            }
        }
        return englishLabel
    }
    
    /// Détermine la zone spatiale d'une bounding box
    /// @param rect Rectangle de détection
    /// @return Zone spatiale ("gauche", "droite", "devant")
    private func getZoneFromBoundingBox(_ rect: CGRect) -> String {
        let centerX = rect.midX
        
        if centerX < 0.3 {
            return "gauche"
        } else if centerX > 0.7 {
            return "droite"
        } else {
            return "devant"
        }
    }
    
    /// Trouve la localisation d'un objet dans l'analyse
    /// @param objectType Type d'objet recherché
    /// @param analysis Analyse de scène
    /// @return Description de localisation
    private func findObjectLocation(_ objectType: String, in analysis: SceneAnalysis) -> String {
        let frenchLabel = translateToFrench(objectType)
        
        for (zone, objects) in analysis.objectsByZone {
            if objects.contains(frenchLabel) {
                return "à \(zone == "devant" ? "votre avant" : zone)"
            }
        }
        return ""
    }
    
    /// Trouve la distance d'un objet dans l'analyse
    /// @param objectType Type d'objet recherché
    /// @param analysis Analyse de scène
    /// @return Description de distance
    private func findObjectDistance(_ objectType: String, in analysis: SceneAnalysis) -> String {
        let frenchLabel = translateToFrench(objectType)
        var closestDistance: Float?
        
        for (key, distance) in analysis.distances {
            if key.contains(frenchLabel) {
                if closestDistance == nil || distance < closestDistance! {
                    closestDistance = distance
                }
            }
        }
        
        guard let distance = closestDistance else { return "" }
        
        if distance < 1.0 {
            return "à \(Int(distance * 100)) centimètres"
        } else if distance < 10.0 {
            return "à \(String(format: "%.1f", distance)) mètres"
        } else {
            return "à \(Int(distance)) mètres"
        }
    }
    
    /// Génère une réponse de localisation générale
    /// @param analysis Analyse de scène
    /// @return Description générale des localisations
    private func generateGeneralLocationResponse(analysis: SceneAnalysis) -> String {
        if analysis.totalObjects == 0 {
            return "Aucun objet détecté pour localiser"
        }
        
        var locations: [String] = []
        
        for (zone, objects) in analysis.objectsByZone {
            if !objects.isEmpty {
                let count = objects.count
                let zoneDescription = zone == "devant" ? "devant vous" : "à \(zone)"
                locations.append("\(count) objet\(count > 1 ? "s" : "") \(zoneDescription)")
            }
        }
        
        return locations.isEmpty ? "Objets détectés sans position précise" : locations.joined(separator: ", ")
    }
    
    // MARK: - Interface Publique pour Statistiques
    
    /// Retourne les statistiques complètes du gestionnaire
    /// @return String formaté avec toutes les informations
    func getStats() -> String {
        let statusText: String
        
        if isRecovering {
            statusText = "🔄 Récupération en cours"
        } else if isListening {
            statusText = isWaitingForQuestion ? "🎤 Écoute d'une question" : "👂 Écoute active"
        } else if interactionEnabled {
            statusText = "✅ Prêt (touchez le micro pour parler)"
        } else {
            statusText = "❌ Non disponible"
        }
        
        let errorInfo = currentRetryCount > 0 ? "\n⚠️ Erreurs récentes: \(currentRetryCount)/\(maxRetryAttempts)" : ""
        
        var privacyInfo = "🔒 Mode: LOCAL uniquement (100% privé)"
        if #available(iOS 13.0, *) {
            if let speechRecognizer = speechRecognizer {
                if !speechRecognizer.supportsOnDeviceRecognition {
                    privacyInfo = "❌ Mode local non supporté (interaction désactivée)"
                }
            }
        } else {
            privacyInfo = "❌ iOS 13+ requis pour mode local"
        }
        
        var soundInfo = "🎵 Son d'activation: "
        if let soundURL = beepPlayer?.url {
            if soundURL.lastPathComponent.contains("custom") ||
               soundURL.lastPathComponent.contains("ecoute") ||
               soundURL.lastPathComponent.contains("activation") {
                soundInfo += "Personnalisé (\(soundURL.lastPathComponent))"
            } else {
                soundInfo += "Bip généré"
            }
        } else {
            soundInfo += "Non chargé"
        }
        
        return """
        🎤 Interaction Vocale - AIDE À LA TRAVERSÉE + DICTIONNAIRE COMPLET:
           - État: \(statusText)
           - Service: \(speechAvailable ? "✅ Disponible" : "❌ Indisponible")
           - \(privacyInfo)
           - \(soundInfo)
           - Dernière activité: "\(lastRecognizedText)"
           - Objets analysés: \(currentImportantObjects.count)
           - Dictionnaire d'objets: \(objectTranslations.count) types supportés\(errorInfo)

        🚦 ANALYSE INTELLIGENTE DE TRAVERSÉE:
           • Évaluation automatique de la signalisation
           • Score de sécurité basé sur la circulation
           • Conseils adaptatifs selon la situation

        🎨 DESCRIPTION PAR PLANS:
           • Premier plan (< 3m distance critique), Plus loin (3-6m), Au fond (> 6m)
           • Description naturelle et groupée
           • Informations spatiales précises

        💡 Mode d'emploi:
           1. Appui long sur l'écran (0.8s)
           2. Attendez le son d'activation 🎵
           3. Posez votre question clairement
           4. Apple gère automatiquement la finalisation

        🔒 Confidentialité garantie:
           - Aucune donnée audio envoyée sur internet
           - Traitement 100% local sur votre appareil
           - Pas d'écoute continue (économie batterie)
        """
    }
    
    /// Indique si le service est prêt pour une question
    /// @return true si prêt à traiter une question
    func isReadyForQuestion() -> Bool {
        return interactionEnabled && speechAvailable && !isListening && !isRecovering
    }
}
