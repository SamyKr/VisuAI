import Foundation
import AVFoundation
import Speech
import UIKit

// MARK: - Enums et Structures
enum VoiceCommand: String, CaseIterable {
    case activate = "dis moi"
    case alternative1 = "dis-moi"
    case alternative2 = "écoute"
    case alternative3 = "hey"

    static let activationPhrases = VoiceCommand.allCases.map { $0.rawValue }
}

enum QuestionType {
    case presence      // "Y a-t-il une voiture ?"
    case count         // "Combien de voitures ?"
    case location      // "Où est la voiture ?"
    case description   // "Qu'est-ce qui est devant moi ?"
    case sceneOverview // "Décris la scène"
    case specific      // "Où est le feu ?"
    case unknown
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

// MARK: - VoiceInteractionManager avec confiance totale en Apple
class VoiceInteractionManager: NSObject, ObservableObject {

    // MARK: - Configuration
    private let listeningTimeout: TimeInterval = 5.0
    private let activationTimeout: TimeInterval = 2.0
    private let emergencyTimeoutDuration: TimeInterval = 30.0  // Timeout d'urgence seulement
    private let maxRetryAttempts = 3
    private let retryDelay: TimeInterval = 2.0

    // 🔒 RECONNAISSANCE LOCALE UNIQUEMENT - Aucune donnée envoyée sur internet

    // MARK: - État
    @Published var isListening = false
    @Published var isWaitingForQuestion = false
    @Published var lastRecognizedText = ""
    @Published var interactionEnabled = true

    // MARK: - Gestion d'erreurs
    private var currentRetryCount = 0
    private var lastErrorTime: Date?
    private var isRecovering = false
    private var speechAvailable = true

    // MARK: - Reconnaissance vocale
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "fr-FR"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    // MARK: - Audio
    private var beepPlayer: AVAudioPlayer?
    private var questionTimer: Timer?
    private var activationTimer: Timer?
    private var recoveryTimer: Timer?

    // MARK: - Résolution du problème isFinal
    private var lastPartialUpdate: Date?
    private var lastPartialResult: String = ""
    private var partialResultTimer: Timer?

    // MARK: - Références externes
    weak var voiceSynthesisManager: VoiceSynthesisManager?
    private var currentImportantObjects: [(object: TrackedObject, score: Float)] = []

    // MARK: - Dictionnaire de traduction inversée (étendu)
    private let objectTranslations: [String: [String]] = [
        "person": ["personne", "personnes", "gens", "piéton", "piétons", "homme", "femme", "enfant"],
        "car": ["voiture", "voitures", "auto", "autos", "véhicule", "véhicules", "bagnole", "caisse"],
        "truck": ["camion", "camions", "poids lourd", "poids lourds", "semi", "semi-remorque"],
        "bus": ["bus", "autobus", "car"],
        "motorcycle": ["moto", "motos", "motocyclette", "motocyclettes", "scooter", "scooters"],
        "bicycle": ["vélo", "vélos", "bicyclette", "bicyclettes", "bike"],
        "traffic light": ["feu", "feux", "feu de circulation", "feux de circulation", "feu tricolore", "signal"],
        "traffic sign": ["panneau", "panneaux", "panneau de signalisation", "signalisation", "stop"],
        "pedestrian crossing": ["passage piéton", "passage piétons", "passage clouté", "zebra"],
        "pole": ["poteau", "poteaux", "pilier", "piliers", "mât"],
        "curb": ["bordure", "bordures", "trottoir", "trottoirs"],
        "road": ["route", "routes", "rue", "rues", "chaussée", "voie"],
        "building": ["bâtiment", "bâtiments", "immeuble", "immeubles", "maison", "maisons"],
        "tree": ["arbre", "arbres"],
        "light": ["lumière", "lumières", "éclairage", "lampe", "lampes"]
    ]

    // MARK: - Mots-clés pour les questions
    private func getPresenceKeywords() -> [String] {
        return ["y a-t-il", "ya-t-il", "est-ce qu'il y a", "il y a", "vois-tu", "détectes-tu","tu vois"]
    }

    private func getCountKeywords() -> [String] {
        return ["combien", "nombre", "quantité"]
    }

    private func getLocationKeywords() -> [String] {
        return ["où", "ou", "position", "située", "situé", "place"]
    }

    private func getDescriptionKeywords() -> [String] {
        return ["qu'est-ce qui", "que vois-tu", "devant moi", "autour"]
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
            .sceneOverview: getSceneKeywords()
        ]
    }

    override init() {
        super.init()
        setupAudio()
        requestSpeechPermission()
        setupBeepSound()
        checkSpeechAvailability()
        print("🎤 VoiceInteractionManager initialisé - Fait confiance au système Apple")
    }

    deinit {
        cleanupResources()
    }

    // MARK: - Configuration et nettoyage

    private func setupAudio() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            // ✅ NOUVELLE CONFIGURATION : Support AirPods + Bluetooth
            try audioSession.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [
                    .duckOthers,
                    .allowBluetooth,           // ← NOUVEAU : Autoriser Bluetooth
                    .allowBluetoothA2DP,       // ← NOUVEAU : Autoriser AirPods/casques
                    .allowAirPlay              // ← NOUVEAU : Autoriser AirPlay
                    // ❌ SUPPRIMÉ : .defaultToSpeaker (forçait le haut-parleur)
                ]
            )
            
            try audioSession.setActive(false) // Commencer inactif
            
            // ✅ NOUVEAU : Forcer la route intelligente DÈS LE DÉBUT
            let hasAirPods = audioSession.currentRoute.outputs.contains {
                $0.portType == .bluetoothA2DP || $0.portType == .bluetoothHFP
            }
            
            if hasAirPods {
                try audioSession.overrideOutputAudioPort(.none) // AirPods
                print("✅ Route forcée vers AirPods dès l'init")
            } else {
                try audioSession.overrideOutputAudioPort(.speaker) // Haut-parleurs
                print("🔊 Route forcée vers haut-parleurs dès l'init")
            }
            
            print("✅ Configuration audio réussie - AirPods supportés")
            
            // 🔍 Debug : Afficher les routes audio disponibles
            printAvailableAudioRoutes()
            
        } catch {
            print("❌ Erreur configuration audio: \(error)")
        }
    }
    
    // ✅ NOUVELLE MÉTHODE : Debug des routes audio
    private func printAvailableAudioRoutes() {
        let audioSession = AVAudioSession.sharedInstance()
        
        print("📱 Routes audio disponibles :")
        for output in audioSession.availableInputs ?? [] {
            print("  - Entrée : \(output.portName) (\(output.portType.rawValue))")
        }
        
        print("🔊 Route de sortie actuelle :")
        for output in audioSession.currentRoute.outputs {
            print("  - Sortie : \(output.portName) (\(output.portType.rawValue))")
        }
        
        if audioSession.currentRoute.outputs.contains(where: { $0.portType == .bluetoothA2DP || $0.portType == .bluetoothHFP }) {
            print("✅ AirPods/Bluetooth détectés et actifs")
        } else {
            print("⚠️ Pas d'AirPods détectés - vérifiez la connexion")
        }
    }

    private func checkSpeechAvailability() {
        guard let speechRecognizer = speechRecognizer else {
            speechAvailable = false
            interactionEnabled = false
            print("❌ SFSpeechRecognizer non initialisé")
            return
        }

        speechAvailable = speechRecognizer.isAvailable

        if !speechAvailable {
            print("❌ Reconnaissance vocale non disponible")
            interactionEnabled = false
            return
        }

        // Vérifier le support de la reconnaissance locale OBLIGATOIRE
        if #available(iOS 13.0, *) {
            if speechRecognizer.supportsOnDeviceRecognition {
                print("✅ Reconnaissance vocale LOCALE prête (100% privé, hors ligne)")
                interactionEnabled = true
            } else {
                print("❌ Reconnaissance locale non supportée sur cet appareil")
                print("   L'interaction vocale sera désactivée pour préserver la vie privée")
                interactionEnabled = false
            }
        } else {
            print("❌ iOS < 13.0 - reconnaissance locale requise non disponible")
            print("   Mise à jour iOS recommandée pour l'interaction vocale")
            interactionEnabled = false
        }
    }

    private func cleanupResources() {
        stopListening()
        recoveryTimer?.invalidate()
        recoveryTimer = nil

        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            print("❌ Erreur désactivation session audio: \(error)")
        }
    }

    private func setupBeepSound() {
        let beepURL = createBeepSound()
        do {
            beepPlayer = try AVAudioPlayer(contentsOf: beepURL)
            beepPlayer?.prepareToPlay()
            beepPlayer?.volume = 0.8
        } catch {
            print("❌ Erreur création beep: \(error)")
        }
    }

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

    private func requestSpeechPermission() {
        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            DispatchQueue.main.async {
                switch authStatus {
                case .authorized:
                    print("✅ Permission reconnaissance vocale accordée")
                    self?.interactionEnabled = self?.speechAvailable ?? false
                case .denied, .restricted, .notDetermined:
                    print("❌ Permission reconnaissance vocale refusée")
                    self?.interactionEnabled = false
                @unknown default:
                    self?.interactionEnabled = false
                }
            }
        }
    }

    // MARK: - Interface publique

    func setVoiceSynthesisManager(_ manager: VoiceSynthesisManager) {
        self.voiceSynthesisManager = manager
    }

    func updateImportantObjects(_ objects: [(object: TrackedObject, score: Float)]) {
        self.currentImportantObjects = objects
        print("🔄 VoiceInteraction: Reçu \(objects.count) objets importants")
        for (index, item) in objects.enumerated() {
            print("   \(index + 1). #\(item.object.trackingNumber) \(item.object.label) (score: \(item.score))")
        }
    }

    /// Vérifie si la reconnaissance locale est supportée sur cet appareil
    func isLocalRecognitionSupported() -> Bool {
        if #available(iOS 13.0, *) {
            return speechRecognizer?.supportsOnDeviceRecognition ?? false
        }
        return false
    }

    /// Retourne la version iOS minimum requise pour l'interaction vocale
    func getMinimumIOSVersion() -> String {
        return "iOS 13.0+"
    }

    func startContinuousListening() {
        guard interactionEnabled && speechAvailable else {
            print("❌ Interaction vocale désactivée ou service indisponible")
            return
        }

        guard !isListening && !isRecovering else {
            print("⚠️ Écoute déjà active ou en récupération")
            return
        }

        print("🎤 Mode interaction vocale ACTIVÉ (appuyez sur le bouton mic pour parler)")
        // Note: On n'écoute PAS en continu, on attend l'activation manuelle
        currentRetryCount = 0
        lastRecognizedText = "Prêt - touchez le micro pour parler"
    }

    func stopContinuousListening() {
        stopListening()
        isRecovering = false
        recoveryTimer?.invalidate()
        recoveryTimer = nil
        lastRecognizedText = ""
        print("🎤 Mode interaction vocale DÉSACTIVÉ")
    }

    /// Démarre l'écoute pour UNE question (appelé par l'appui long)
    func startSingleQuestion() {
        guard interactionEnabled && speechAvailable else {
            voiceSynthesisManager?.speak("Interaction vocale non disponible")
            return
        }

        guard !isListening else {
            print("⚠️ Écoute déjà en cours")
            return
        }

        print("🎤 Démarrage écoute d'UNE question - Apple gère la finalisation")

        // 🛑 ARRÊT TOTAL DE TOUTE SYNTHÈSE VOCALE
        voiceSynthesisManager?.stopSpeaking()
        voiceSynthesisManager?.interruptForInteraction(reason: "Question utilisateur")

        // Attendre que l'audio se libère complètement
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            // Jouer le beep
            self?.playBeep()

            // Passer en mode question directement
            self?.isWaitingForQuestion = true

            // Démarrer l'écoute après le beep avec plus de délai
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.startListening(forActivation: false)

                // 🎯 TIMEOUT BEAUCOUP PLUS LONG - Juste sécurité contre les blocages
                self?.questionTimer = Timer.scheduledTimer(withTimeInterval: self?.emergencyTimeoutDuration ?? 30.0, repeats: false) { _ in
                    self?.handleEmergencyTimeout()
                }
            }
        }
    }

    func toggleListening() {
        if isListening {
            stopContinuousListening()
        } else {
            startContinuousListening()
        }
    }

    // MARK: - Méthodes publiques pour interaction directe

    func interruptForInteraction(reason: String = "Interaction utilisateur") {
        print("🛑 Interruption pour interaction: \(reason)")
        voiceSynthesisManager?.interruptForInteraction(reason: reason)
    }

    func speakInteraction(_ text: String, priority: Int = 15) {
        voiceSynthesisManager?.speakInteraction(text, priority: priority)
        print("🎤 Message d'interaction envoyé: '\(text)'")
    }

    func resumeAfterInteraction() {
        voiceSynthesisManager?.resumeAfterInteraction()
        print("▶️ Reprise après interaction")
    }

    // MARK: - Reconnaissance vocale avec confiance totale en Apple

    private func startListening(forActivation: Bool = false) {
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            print("❌ Reconnaissance vocale non disponible")
            handleSpeechError(NSError(domain: "SpeechRecognizer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Service non disponible"]))
            return
        }

        // Vérifier si on est en période de récupération
        if let lastError = lastErrorTime, Date().timeIntervalSince(lastError) < retryDelay {
            print("⏳ En attente avant nouvelle tentative...")
            scheduleRetry(forActivation: forActivation)
            return
        }

        stopListening() // Nettoyer toute session précédente

        // Activer la session audio
        do {
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("❌ Erreur activation session audio: \(error)")
            handleSpeechError(error)
            return
        }

        isListening = true

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            handleSpeechError(NSError(domain: "SpeechRecognizer", code: -2, userInfo: [NSLocalizedDescriptionKey: "Impossible de créer la requête"]))
            return
        }

        // 🔒 RECONNAISSANCE LOCALE UNIQUEMENT 🔒
        recognitionRequest.shouldReportPartialResults = true

        if #available(iOS 13.0, *) {
            // OBLIGATOIRE : Mode local seulement
            recognitionRequest.requiresOnDeviceRecognition = true
            print("✅ Mode LOCAL forcé (aucune donnée envoyée sur internet)")

            // Double vérification sécurité
            if !speechRecognizer.supportsOnDeviceRecognition {
                print("❌ ERREUR : Mode local requis mais non supporté")
                handleSpeechError(NSError(domain: "SpeechRecognizer", code: -3, userInfo: [NSLocalizedDescriptionKey: "Mode local requis non supporté"]))
                return
            }
        } else {
            print("❌ iOS 13+ requis pour reconnaissance locale sécurisée")
            handleSpeechError(NSError(domain: "SpeechRecognizer", code: -4, userInfo: [NSLocalizedDescriptionKey: "iOS 13+ requis"]))
            return
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Supprimer le tap existant s'il y en a un
        inputNode.removeTap(onBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }

        audioEngine.prepare()

        do {
            try audioEngine.start()
            print("✅ Moteur audio démarré - Apple gère la finalisation naturellement")
        } catch {
            print("❌ Erreur démarrage audio engine: \(error)")
            handleSpeechError(error)
            return
        }

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            self?.handleRecognitionResult(result: result, error: error, forActivation: forActivation)
        }

        // 🎯 PAS DE TIMER AGRESSIF - Laisser Apple gérer !
        // Seulement pour l'activation continue (si utilisé)
        if forActivation {
            DispatchQueue.main.asyncAfter(deadline: .now() + activationTimeout) { [weak self] in
                if self?.isListening == true && self?.isWaitingForQuestion != true && self?.isRecovering != true {
                    self?.restartListening(forActivation: true)
                }
            }
        }
    }

    private func handleRecognitionResult(result: SFSpeechRecognitionResult?, error: Error?, forActivation: Bool) {
        if let error = error {
            print("❌ Erreur reconnaissance: \(error)")

            // Pour une question ponctuelle, on gère différemment
            if !forActivation {
                handleSingleQuestionError(error)
            } else {
                handleSpeechError(error, forActivation: forActivation)
            }
            return
        }

        guard let result = result else { return }

        let recognizedText = result.bestTranscription.formattedString.lowercased()

        print("🍎 Apple dit: '\(recognizedText)' (final: \(result.isFinal))")

        // Reset des compteurs d'erreur en cas de succès
        if !recognizedText.isEmpty {
            currentRetryCount = 0
            lastErrorTime = nil
        }

        DispatchQueue.main.async { [weak self] in
            self?.lastRecognizedText = recognizedText

            if forActivation {
                self?.checkForActivation(text: recognizedText)
            } else {
                if result.isFinal {
                    // Cas normal - Apple a finalisé
                    self?.processQuestion(text: recognizedText, isFinal: true)
                } else {
                    // Résultat partiel - mettre à jour et démarrer un timer
                    self?.lastPartialUpdate = Date()
                    self?.lastPartialResult = recognizedText
                    self?.schedulePartialResultTimeout()
                }
            }
        }
    }

    private func schedulePartialResultTimeout() {
        // Annuler tout timer précédent
        partialResultTimer?.invalidate()

        // Démarrer un nouveau timer
        partialResultTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            guard let self = self else { return }

            // Vérifier si nous avons reçu des mises à jour depuis
            if let lastUpdate = self.lastPartialUpdate,
               Date().timeIntervalSince(lastUpdate) >= 1.5,
               !self.lastPartialResult.isEmpty {

                print("ℹ️ Détection de fin de phrase après timeout")
                self.processQuestion(text: self.lastPartialResult, isFinal: true)
            }
        }
    }

    private func handleSingleQuestionError(_ error: Error) {
        print("❌ Erreur lors de la question: \(error)")

        if !lastPartialResult.isEmpty {
                print("ℹ️ Ignorant l'erreur car nous avons déjà un résultat partiel: '\(lastPartialResult)'")
                return
            }
        // Pour les questions ponctuelles, on ne fait pas de retry
        stopListening()
        isWaitingForQuestion = false

        // Message selon le type d'erreur
        if error.localizedDescription.contains("No speech detected") {
            voiceSynthesisManager?.speak("Je n'ai rien entendu")
        } else {
            voiceSynthesisManager?.speak("Erreur de reconnaissance vocale")
        }

        // ▶️ REPRENDRE LA SYNTHÈSE VOCALE NORMALE APRÈS L'ERREUR
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.voiceSynthesisManager?.resumeAfterInteraction()
            print("▶️ Synthèse vocale normale reprise après erreur")
        }

        // Ne PAS relancer automatiquement
        lastRecognizedText = "Erreur - appui long pour réessayer"
    }

    // Timer d'urgence seulement (pas pour l'usage normal)
    private func handleEmergencyTimeout() {
        print("🚨 TIMEOUT D'URGENCE (30s) - Quelque chose ne va pas")
        voiceSynthesisManager?.speak("Timeout d'urgence")
        finishSingleQuestion()
    }

    private func handleSpeechError(_ error: Error, forActivation: Bool = false) {
        lastErrorTime = Date()
        currentRetryCount += 1

        print("❌ Erreur Speech (tentative \(currentRetryCount)/\(maxRetryAttempts)): \(error)")

        // Nettoyer les ressources
        stopListening()

        // Si on dépasse le nombre max de tentatives, arrêter temporairement
        if currentRetryCount >= maxRetryAttempts {
            print("🛑 Trop d'erreurs, arrêt temporaire du service vocal")
            isRecovering = true

            // Programmer une récupération après un délai plus long
            recoveryTimer = Timer.scheduledTimer(withTimeInterval: retryDelay * 3, repeats: false) { [weak self] _ in
                self?.attemptRecovery()
            }
        } else {
            // Tentative de relance après un court délai
            scheduleRetry(forActivation: forActivation)
        }
    }

    private func scheduleRetry(forActivation: Bool) {
        print("⏳ Programmation nouvelle tentative dans \(retryDelay)s...")
        DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) { [weak self] in
            if self?.interactionEnabled == true && self?.isRecovering != true {
                self?.startListening(forActivation: forActivation)
            }
        }
    }

    private func attemptRecovery() {
        print("🔄 Tentative de récupération du service vocal...")
        isRecovering = false
        currentRetryCount = 0
        lastErrorTime = nil

        // Vérifier la disponibilité
        checkSpeechAvailability()

        if interactionEnabled && speechAvailable {
            print("✅ Service vocal récupéré, redémarrage...")

            // Petit délai avant de redémarrer
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.startListening(forActivation: true)
            }
        } else {
            print("❌ Service vocal toujours indisponible")
        }
    }

    private func restartListening(forActivation: Bool) {
        print("🔄 Redémarrage écoute...")
        stopListening()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.startListening(forActivation: forActivation)
        }
    }

    private func checkForActivation(text: String) {
        for phrase in VoiceCommand.activationPhrases {
            if text.contains(phrase) {
                print("🎯 Phrase d'activation détectée: '\(phrase)'")
                handleActivation()
                return
            }
        }
    }

    private func handleActivation() {
        voiceSynthesisManager?.stopSpeaking()
        playBeep()
        isWaitingForQuestion = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.startListening(forActivation: false)

            self?.questionTimer = Timer.scheduledTimer(withTimeInterval: self?.listeningTimeout ?? 5.0, repeats: false) { _ in
                self?.timeoutQuestion()
            }
        }
    }

    private func playBeep() {
        // ✅ NOUVEAU : Logique audio intelligente (même que VoiceSynthesisManager)
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
        print("🔊 Beep d'activation joué")
    }

    // Version modifiée pour gérer le timeout des résultats partiels
    private func processQuestion(text: String, isFinal: Bool) {
        print("📝 processQuestion: '\(text)' (final: \(isFinal))")

        // Annuler le timer s'il existe
        partialResultTimer?.invalidate()
        partialResultTimer = nil

        // Annuler le timer d'urgence
        questionTimer?.invalidate()
        questionTimer = nil

        let parsedQuestion = parseQuestion(text)

        // Debug info
        let debugInfo = "Question analysée: Type \(parsedQuestion.type), Objet \(parsedQuestion.targetObject ?? "aucun"), \(currentImportantObjects.count) objets détectés"
        print("🐛 \(debugInfo)")

        if !currentImportantObjects.isEmpty {
            let response = generateResponse(for: parsedQuestion)
            voiceSynthesisManager?.speak(response)
        } else {
            voiceSynthesisManager?.speak("Je ne détecte aucun objet actuellement")
        }

        finishSingleQuestion()
    }

    private func finishSingleQuestion() {
        questionTimer?.invalidate()
        questionTimer = nil
        isWaitingForQuestion = false
        stopListening()

        // ▶️ REPRENDRE LA SYNTHÈSE VOCALE NORMALE APRÈS LA QUESTION
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.voiceSynthesisManager?.resumeAfterInteraction()
            print("▶️ Synthèse vocale normale reprise après question")
        }

        // Message d'état pour l'utilisateur
        lastRecognizedText = "Question traitée - appui long pour une nouvelle question"
        print("✅ Question traitée, synthèse normale va reprendre")
    }

    private func timeoutQuestion() {
        print("⏰ Timeout question - retour mode activation")
        voiceSynthesisManager?.speak("Je n'ai pas entendu de question")
        resetToActivationMode()
    }

    private func resetToActivationMode() {
        questionTimer?.invalidate()
        questionTimer = nil
        isWaitingForQuestion = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            if self?.interactionEnabled == true && self?.isRecovering != true {
                self?.startListening(forActivation: true)
            }
        }
    }

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
        activationTimer?.invalidate()
        activationTimer = nil

        // Désactiver la session audio proprement
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // Ignorer les erreurs de désactivation - c'est normal
        }
    }

    // MARK: - Analyse des questions

    private func parseQuestion(_ text: String) -> ParsedQuestion {
        let normalizedText = text.lowercased()
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: ".", with: "")

        print("🔍 PARSE: '\(text)' → '\(normalizedText)'")

        var questionType: QuestionType = .unknown
        var confidence: Float = 0.0

        // Test des mots-clés COUNT en premier (plus spécifique)
        let countKeywords = getCountKeywords()
        for keyword in countKeywords {
            if normalizedText.contains(keyword) {
                questionType = .count
                confidence = 0.8
                print("✅ PARSE: COUNT détecté avec '\(keyword)'")
                break
            }
        }

        // Si pas COUNT, tester les autres
        if questionType == .unknown {
            let questionKeywords = getQuestionKeywords()
            for (type, keywords) in questionKeywords {
                if type == .count { continue } // Déjà testé
                for keyword in keywords {
                    if normalizedText.contains(keyword) {
                        questionType = type
                        confidence = 0.8
                        print("✅ PARSE: \(type) détecté avec '\(keyword)'")
                        break
                    }
                }
                if confidence > 0 { break }
            }
        }

        var targetObject: String?

        // Test de reconnaissance d'objet
        for (englishObject, frenchVariants) in objectTranslations {
            for variant in frenchVariants {
                if normalizedText.contains(variant) {
                    targetObject = englishObject
                    confidence = max(confidence, 0.7)
                    print("✅ PARSE: Objet '\(variant)' → '\(englishObject)'")
                    break
                }
            }
            if targetObject != nil { break }
        }

        // Cas spéciaux
        if normalizedText.contains("scène") || normalizedText.contains("situation") {
            questionType = .sceneOverview
            confidence = 0.9
            print("✅ PARSE: scène/situation détecté")
        }

        if normalizedText.contains("devant") {
            questionType = .description
            confidence = max(confidence, 0.8)
            print("✅ PARSE: devant détecté")
        }

        let result = ParsedQuestion(
            type: questionType,
            targetObject: targetObject,
            confidence: confidence,
            originalText: text
        )

        print("📋 PARSE FINAL: Type=\(questionType), Objet=\(targetObject ?? "aucun"), Conf=\(confidence)")

        return result
    }

    // MARK: - Génération des réponses

    private func generateResponse(for question: ParsedQuestion) -> String {
        print("💬 Génération réponse pour: '\(question.originalText)'")
        print("   - Type: \(question.type), Objet: \(question.targetObject ?? "aucun")")

        let analysis = analyzeCurrentScene()

        let response: String
        switch question.type {
        case .presence:
            response = handlePresenceQuestion(question, analysis: analysis)
        case .count:
            response = handleCountQuestion(question, analysis: analysis)
        case .location:
            response = handleLocationQuestion(question, analysis: analysis)
        case .description:
            response = handleDescriptionQuestion(analysis: analysis)
        case .sceneOverview:
            response = handleSceneOverviewQuestion(analysis: analysis)
        case .specific:
            response = handleSpecificQuestion(question, analysis: analysis)
        case .unknown:
            response = handleUnknownQuestion(question, analysis: analysis)
        }

        print("💬 Réponse: '\(response)'")
        return response
    }

    private func analyzeCurrentScene() -> SceneAnalysis {
        print("📊 Analyse de scène avec \(currentImportantObjects.count) objets importants")

        var objectsByType: [String: Int] = [:]
        var objectsByZone: [String: [String]] = [
            "devant": [], "gauche": [], "droite": []
        ]
        var distances: [String: Float] = [:]
        var criticalObjects: [String] = []
        var navigationObjects: [String] = []

        for (index, item) in currentImportantObjects.enumerated() {
            let object = item.object
            let frenchLabel = translateToFrench(object.label)

            print("   \(index + 1). #\(object.trackingNumber) \(object.label) → \(frenchLabel) (score: \(item.score))")

            // Compter par type
            objectsByType[frenchLabel, default: 0] += 1

            // Analyser la position
            let zone = getZoneFromBoundingBox(object.lastRect)
            objectsByZone[zone, default: []].append(frenchLabel)

            // Distance
            if let distance = object.distance {
                let key = "\(frenchLabel)_\(object.trackingNumber)"
                distances[key] = distance
                print("     → Distance: \(distance)m")
            }

            // Objets critiques
            if item.score > 0.7 {
                criticalObjects.append(frenchLabel)
            }

            // Objets de navigation
            if ["traffic light", "traffic sign", "pedestrian crossing"].contains(object.label) {
                navigationObjects.append(frenchLabel)
            }
        }

        print("📊 Résumé par type:")
        for (type, count) in objectsByType {
            print("   - \(type): \(count)")
        }

        print("📊 Résumé par zone:")
        for (zone, objects) in objectsByZone {
            if !objects.isEmpty {
                print("   - \(zone): \(objects)")
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

    private func handlePresenceQuestion(_ question: ParsedQuestion, analysis: SceneAnalysis) -> String {
        print("❓ Traitement question PRESENCE:")

        guard let targetObject = question.targetObject else {
            print("   - Aucun objet spécifique → présence générale")
            
            if analysis.totalObjects == 0 {
                return "Non, aucun objet détecté actuellement"
            }
            
            // Créer une liste des objets détectés avec leurs quantités
            let objectsList = analysis.objectsByType.map { type, count in
                if count == 1 {
                    return "une \(type)"
                } else {
                    return "\(count) \(type)s"
                }
            }
            
            if objectsList.count == 1 {
                return "Oui, je détecte \(objectsList[0])"
            } else if objectsList.count == 2 {
                return "Oui, je détecte \(objectsList[0]) et \(objectsList[1])"
            } else {
                let allButLast = objectsList.dropLast().joined(separator: ", ")
                return "Oui, je détecte \(allButLast) et \(objectsList.last!)"
            }
        }

        let frenchLabel = translateToFrench(targetObject)
        let count = analysis.objectsByType[frenchLabel] ?? 0

        print("   - Objet recherché: '\(targetObject)' → '\(frenchLabel)'")
        print("   - Présence: \(count > 0 ? "OUI (\(count))" : "NON")")
        print("   - Objets disponibles: \(Array(analysis.objectsByType.keys))")

        if count > 0 {
            let location = findObjectLocation(targetObject, in: analysis)
            return count == 1 ?
                "Oui, je vois une \(frenchLabel)\(location.isEmpty ? "" : " \(location)")" :
                "Oui, je vois \(count) \(frenchLabel)s"
        } else {
            return "Non, je ne vois pas de \(frenchLabel) actuellement"
        }
    }

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

    private func handleLocationQuestion(_ question: ParsedQuestion, analysis: SceneAnalysis) -> String {
        guard let targetObject = question.targetObject else {
            return generateGeneralLocationResponse(analysis: analysis)
        }

        let frenchLabel = translateToFrench(targetObject)
        let count = analysis.objectsByType[frenchLabel] ?? 0

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

        return response
    }

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

    private func handleSceneOverviewQuestion(analysis: SceneAnalysis) -> String {
        if analysis.totalObjects == 0 {
            return "La scène est calme, aucun objet détecté actuellement"
        }

        var description: [String] = []

        if analysis.criticalObjects.count > 0 {
            description.append("Attention, objets proches détectés")
        }

        for (zone, objects) in analysis.objectsByZone {
            if !objects.isEmpty {
                let uniqueObjects = Dictionary(grouping: objects) { $0 }
                    .map { obj, list in list.count > 1 ? "\(list.count) \(obj)s" : "une \(obj)" }
                    .joined(separator: ", ")
                description.append("\(zone) : \(uniqueObjects)")
            }
        }

        if !analysis.navigationObjects.isEmpty {
            description.append("Signalisation présente")
        }

        let result = description.isEmpty ?
            "Environnement calme avec \(analysis.totalObjects) objet\(analysis.totalObjects > 1 ? "s" : "") détecté\(analysis.totalObjects > 1 ? "s" : "")" :
            description.joined(separator: ". ")

        return result
    }

    private func handleSpecificQuestion(_ question: ParsedQuestion, analysis: SceneAnalysis) -> String {
        return handleLocationQuestion(question, analysis: analysis)
    }

    private func handleUnknownQuestion(_ question: ParsedQuestion, analysis: SceneAnalysis) -> String {
        let text = question.originalText.lowercased()

        if text.contains("aide") || text.contains("help") {
            return "Vous pouvez me demander s'il y a des objets, combien il y en a, où ils sont, ou me demander de décrire la scène"
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

    // MARK: - Méthodes utilitaires

    private func translateToFrench(_ englishLabel: String) -> String {
        for (english, frenchVariants) in objectTranslations {
            if english == englishLabel {
                return frenchVariants.first ?? englishLabel
            }
        }
        return englishLabel
    }

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

    private func findObjectLocation(_ objectType: String, in analysis: SceneAnalysis) -> String {
        let frenchLabel = translateToFrench(objectType)

        for (zone, objects) in analysis.objectsByZone {
            if objects.contains(frenchLabel) {
                return "à \(zone == "devant" ? "votre avant" : zone)"
            }
        }
        return ""
    }

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

    // MARK: - Interface publique pour les stats

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

        // Mode de reconnaissance (toujours local)
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

        return """
        🎤 Interaction Vocale (confiance Apple):
           - État: \(statusText)
           - Service: \(speechAvailable ? "✅ Disponible" : "❌ Indisponible")
           - \(privacyInfo)
           - Dernière activité: "\(lastRecognizedText)"
           - Objets analysés: \(currentImportantObjects.count)\(errorInfo)

        💡 Mode d'emploi:
           1. Appui long sur l'écran (0.8s)
           2. Attendez le bip sonore
           3. Posez votre question clairement
           4. Apple gère automatiquement la finalisation

        ❓ Questions supportées:
           - "Y a-t-il des voitures ?"
           - "Combien d'objets ?"
           - "Où est le feu ?"
           - "Décris la scène"

        🔒 Confidentialité garantie:
           - Aucune donnée audio envoyée sur internet
           - Traitement 100% local sur votre appareil
           - Pas d'écoute continue (économie batterie)

        🍎 Système Apple:
           - Détection automatique des pauses
           - Finalisation intelligente des phrases
           - Timeout d'urgence: 30s (vs 8s avant)
        """
    }

    /// Indique si le service est prêt à traiter une question
    func isReadyForQuestion() -> Bool {
        return interactionEnabled && speechAvailable && !isListening && !isRecovering
    }
}
