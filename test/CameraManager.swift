//
//  CameraManager.swift
//  VizAI Vision
//
//  RÔLE CENTRAL DANS L'ARCHITECTURE:
//  CameraManager est le CŒUR du système de détection - il orchestre tous les composants:
//
//  📱 CAPTURE VIDÉO:
//  - Gestion complète AVCaptureSession (caméra + LiDAR si disponible)
//  - Configuration optimisée pour détection IA (HD 1920x1080, 60fps)
//  - Synchronisation flux vidéo/profondeur pour mesures de distance précises
//
//  🤖 INTELLIGENCE ARTIFICIELLE:
//  - Interface principale avec ObjectDetectionManager (YOLOv11)
//  - Orchestration détection + tracking + scoring d'importance
//  - Gestion liste objets actifs/ignorés et classes dangereuses
//
//  🗣️ SYSTÈME VOCAL ET HAPTIQUE:
//  - Connection directe avec VoiceSynthesisManager pour alertes critiques
//  - Contrôle HapticManager pour vibrations de proximité
//  - Transmission distance critique et objets dangereux
//
//  📏 LiDAR ET DISTANCES:
//  - Activation/désactivation capteur profondeur
//  - Intégration LiDARManager pour mesures précises
//  - Calculs de proximité pour alertes sécurité
//
//  🎯 INTERFACE UTILISATEUR:
//  - Delegate pattern pour communication avec DetectionView
//  - Méthodes publiques pour tous les contrôles UI
//  - Gestion permissions et états de session
//
//  FLUX DE DONNÉES:
//  Caméra → CameraManager → ObjectDetection → Tracking → VoiceSynthesis/Haptic → UI

import AVFoundation
import Vision
import SwiftUI

// MARK: - Protocol de Communication avec UI
protocol CameraManagerDelegate {
    /// Transmet les détections enrichies avec tracking et distance à l'interface
    /// - Parameter detections: Array des objets détectés avec infos complètes
    func didDetectObjects(_ detections: [(rect: CGRect, label: String, confidence: Float, distance: Float?, trackingInfo: (id: Int, color: UIColor, opacity: Double))])
}

// MARK: - Gestionnaire Principal Caméra et Détection
class CameraManager: NSObject, ObservableObject {
    
    // MARK: - États Publics Observables
    @Published var isRunning = false
    @Published var hasPermission = false
    @Published var currentFPS: Double = 0.0
    @Published var isLiDAREnabled = false
    @Published var lidarAvailable = false
    
    var delegate: CameraManagerDelegate?
    
    // MARK: - Composants Système Caméra
    private let captureSession = AVCaptureSession()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let depthDataOutput = AVCaptureDepthDataOutput()
    private var outputSynchronizer: AVCaptureDataOutputSynchronizer?
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    // MARK: - Gestionnaires Spécialisés
    private let objectDetectionManager = ObjectDetectionManager()
    private let lidarManager = LiDARManager()
    private let hapticManager = HapticManager()
    private var voiceSynthesisManager: VoiceSynthesisManager?
    
    // MARK: - Configuration Performance
    private var skipFrameCount = 1 // Nombre de frames à ignorer (performance)
    private var frameCounter = 0   // Compteur pour skip frames
    
    // MARK: - Variables de Synchronisation
    private var lastImageBuffer: CVPixelBuffer?
    private var lastDepthData: AVDepthData?
    private var imageSize: CGSize = .zero
    
    // MARK: - Initialisation
    override init() {
        super.init()
        
        lidarAvailable = lidarManager.isAvailable()
        setupCaptureSession()
    }
    
    // MARK: - Gestion Permissions
    
    /// Demande l'autorisation d'accès à la caméra
    func requestPermission() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                self.hasPermission = granted
            }
        }
    }
    
    // MARK: - Contrôle Session Caméra
    
    /// Démarre la session de capture vidéo
    func startSession() {
        guard hasPermission else {
            requestPermission()
            return
        }
        
        sessionQueue.async {
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
                DispatchQueue.main.async {
                    self.isRunning = true
                }
            }
        }
    }
    
    /// Arrête la session de capture vidéo
    func stopSession() {
        sessionQueue.async {
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
                DispatchQueue.main.async {
                    self.isRunning = false
                }
            }
        }
    }
    
    /// Fournit la couche de prévisualisation pour l'affichage UI
    /// - Returns: AVCaptureVideoPreviewLayer configurée
    func getPreviewLayer() -> AVCaptureVideoPreviewLayer {
        if previewLayer == nil {
            previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            previewLayer?.videoGravity = .resizeAspectFill
        }
        return previewLayer!
    }
    
    // MARK: - Interface VoiceSynthesisManager
    
    /// Connecte le gestionnaire de synthèse vocale pour les alertes
    /// - Parameter manager: Instance VoiceSynthesisManager
    func setVoiceSynthesisManager(_ manager: VoiceSynthesisManager) {
        self.voiceSynthesisManager = manager
    }
    
    /// Met à jour la distance critique pour les alertes vocales
    /// - Parameter distance: Distance en mètres (0.5-10m)
    func updateCriticalDistance(_ distance: Float) {
        voiceSynthesisManager?.updateCriticalDistance(distance)
    }
    
    /// Met à jour la liste des objets considérés comme dangereux
    /// - Parameter dangerousObjects: Set des types d'objets dangereux
    func updateDangerousObjects(_ dangerousObjects: Set<String>) {
        voiceSynthesisManager?.updateDangerousObjects(dangerousObjects)
    }
    
    // MARK: - Contrôles Tracking
    
    /// Réinitialise le système de tracking des objets
    func resetTracking() {
        objectDetectionManager.resetTracking()
    }
    
    /// Obtient les statistiques détaillées du tracking
    /// - Returns: String formaté avec les stats
    func getTrackingStats() -> String {
        return objectDetectionManager.getTrackingStats()
    }
    
    // MARK: - Contrôles Vibrations Haptiques
    
    /// Active/désactive les alertes de proximité par vibration
    /// - Parameter enabled: État des alertes
    func enableProximityAlerts(_ enabled: Bool) {
        hapticManager.enableProximityAlerts(enabled)
    }
    
    func isProximityAlertsEnabled() -> Bool {
        return hapticManager.isProximityAlertsEnabled()
    }
    
    /// Configure la distance de danger pour vibrations
    /// - Parameter distance: Distance en mètres
    func setDangerDistance(_ distance: Float) {
        hapticManager.setDangerDistance(distance)
    }
    
    func getDangerDistance() -> Float {
        return hapticManager.getDangerDistance()
    }
    
    /// Configure la distance d'avertissement pour vibrations
    /// - Parameter distance: Distance en mètres
    func setWarningDistance(_ distance: Float) {
        hapticManager.setWarningDistance(distance)
    }
    
    func getWarningDistance() -> Float {
        return hapticManager.getWarningDistance()
    }
    
    /// Définit la plage d'intensité des vibrations
    /// - Parameters:
    ///   - min: Intensité minimale (0.0-1.0)
    ///   - max: Intensité maximale (0.0-1.0)
    func setIntensityRange(min: Float, max: Float) {
        hapticManager.setIntensityRange(min: min, max: max)
    }
    
    func getIntensityRange() -> (min: Float, max: Float) {
        return hapticManager.getIntensityRange()
    }
    
    /// Active/désactive les vibrations graduées selon la distance
    /// - Parameter enabled: État des vibrations graduées
    func enableGraduatedVibrations(_ enabled: Bool) {
        hapticManager.enableGraduatedVibrations(enabled)
    }
    
    func isGraduatedVibrationsEnabled() -> Bool {
        return hapticManager.isGraduatedVibrationsEnabled()
    }
    
    /// Active/désactive la fréquence graduée des vibrations
    /// - Parameter enabled: État de la fréquence graduée
    func enableGraduatedFrequency(_ enabled: Bool) {
        hapticManager.enableGraduatedFrequency(enabled)
    }
    
    func isGraduatedFrequencyEnabled() -> Bool {
        return hapticManager.isGraduatedFrequencyEnabled()
    }
    
    /// Configure la plage de fréquence des vibrations
    /// - Parameters:
    ///   - minCooldown: Délai minimum entre vibrations (proche)
    ///   - maxCooldown: Délai maximum entre vibrations (loin)
    func setFrequencyRange(minCooldown: TimeInterval, maxCooldown: TimeInterval) {
        hapticManager.setFrequencyRange(minCooldown: minCooldown, maxCooldown: maxCooldown)
    }
    
    func getFrequencyRange() -> (minCooldown: TimeInterval, maxCooldown: TimeInterval) {
        return hapticManager.getFrequencyRange()
    }
    
    // MARK: - Feedback Haptique Manuel
    
    /// Joue un feedback de succès
    func playSuccessFeedback() {
        hapticManager.playSuccessFeedback()
    }
    
    /// Joue un feedback de sélection
    func playSelectionFeedback() {
        hapticManager.playSelectionFeedback()
    }
    
    /// Test vibration de danger avec intensité personnalisée
    /// - Parameter intensity: Intensité (0.0-1.0), défaut 1.0
    func testDangerVibration(intensity: Float = 1.0) {
        hapticManager.testDangerVibration(customIntensity: intensity)
    }
    
    /// Test vibration d'avertissement avec intensité personnalisée
    /// - Parameter intensity: Intensité (0.0-1.0), défaut 0.7
    func testWarningVibration(intensity: Float = 0.7) {
        hapticManager.testWarningVibration(customIntensity: intensity)
    }
    
    // MARK: - Contrôles LiDAR
    
    /// Active le capteur LiDAR si disponible
    /// - Returns: true si activation réussie
    func enableLiDAR() -> Bool {
        guard lidarAvailable else { return false }
        
        let success = lidarManager.enableDepthCapture()
        if success {
            DispatchQueue.main.async {
                self.isLiDAREnabled = true
            }
        }
        return success
    }
    
    /// Désactive le capteur LiDAR
    func disableLiDAR() {
        lidarManager.disableDepthCapture()
        DispatchQueue.main.async {
            self.isLiDAREnabled = false
        }
    }
    
    /// Bascule l'état du LiDAR
    /// - Returns: Nouvel état (true = activé)
    func toggleLiDAR() -> Bool {
        if isLiDAREnabled {
            disableLiDAR()
            return false
        } else {
            return enableLiDAR()
        }
    }
    
    // MARK: - Objets Importants et Statistiques
    
    /// Obtient les objets les plus importants selon leur score
    /// - Parameter maxCount: Nombre maximum d'objets à retourner
    /// - Returns: Array des objets avec leurs scores
    func getTopImportantObjects(maxCount: Int = 5) -> [(object: TrackedObject, score: Float)] {
        return objectDetectionManager.getTopImportantObjects(maxCount: maxCount)
    }
    
   
    
    /// Remet à zéro toutes les statistiques
    func resetPerformanceStats() {
        objectDetectionManager.resetStats()
        lidarManager.resetStats()
        hapticManager.resetStats()
    }
    
    // MARK: - Configuration Performance
    
    /// Configure le nombre de frames à ignorer pour optimiser les performances
    /// - Parameter count: Nombre de frames à skip (0 = aucun skip)
    func setSkipFrames(_ count: Int) {
        skipFrameCount = max(0, count)
    }
    
    func getSkipFrames() -> Int {
        return skipFrameCount
    }
    
    // MARK: - Gestion Classes d'Objets
    
    /// Définit les classes d'objets à détecter (autres seront ignorées)
    /// - Parameter classes: Set des noms de classes à activer
    func setEnabledClasses(_ classes: Set<String>) {
        objectDetectionManager.setEnabledClasses(classes)
    }
    
    /// Ajoute une classe à la liste des objets ignorés
    /// - Parameter className: Nom de la classe à ignorer
    func addIgnoredClass(_ className: String) {
        objectDetectionManager.addIgnoredClass(className)
    }
    
    /// Retire une classe de la liste des objets ignorés
    /// - Parameter className: Nom de la classe à réactiver
    func removeIgnoredClass(_ className: String) {
        objectDetectionManager.removeIgnoredClass(className)
    }
    
    /// Obtient la liste des classes actuellement ignorées
    /// - Returns: Array des noms de classes ignorées
    func getIgnoredClasses() -> [String] {
        return objectDetectionManager.getIgnoredClasses()
    }
    
    /// Vide la liste des classes ignorées (réactive tout)
    func clearIgnoredClasses() {
        objectDetectionManager.clearIgnoredClasses()
    }
    
    /// Obtient toutes les classes disponibles dans le modèle
    /// - Returns: Array des 49 classes supportées
    func getAvailableClasses() -> [String] {
        return objectDetectionManager.getAvailableClasses()
    }
    
    /// Accès statique aux classes du modèle YOLOv11
    /// - Returns: Array des 49 classes du modèle
    static func getAllModelClasses() -> [String] {
        return ObjectDetectionManager.getAllModelClasses()
    }
    
    // MARK: - Configuration Session Caméra
    
    /// Configure la session de capture avec support LiDAR optimal
    private func setupCaptureSession() {
        sessionQueue.async {
            self.captureSession.beginConfiguration()
            
            // Configuration haute résolution pour meilleure détection IA
            if self.captureSession.canSetSessionPreset(.hd1920x1080) {
                self.captureSession.sessionPreset = .hd1920x1080
            }
            
            // Configuration entrée vidéo avec support LiDAR
            guard let videoDevice = self.getBestCameraDevice(),
                  let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice),
                  self.captureSession.canAddInput(videoDeviceInput) else {
                return
            }
            
            self.captureSession.addInput(videoDeviceInput)
            
            // Stockage taille image pour calculs de distance
            let dimensions = CMVideoFormatDescriptionGetDimensions(videoDevice.activeFormat.formatDescription)
            self.imageSize = CGSize(width: Int(dimensions.width), height: Int(dimensions.height))
            
            // Configuration sortie vidéo optimisée
            if self.captureSession.canAddOutput(self.videoDataOutput) {
                self.captureSession.addOutput(self.videoDataOutput)
                
                self.videoDataOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
                
                self.videoDataOutput.alwaysDiscardsLateVideoFrames = true
            }
            
            // Configuration sortie profondeur LiDAR si disponible
            if self.lidarAvailable && self.captureSession.canAddOutput(self.depthDataOutput) {
                self.captureSession.addOutput(self.depthDataOutput)
                
                if let connection = self.depthDataOutput.connection(with: .depthData) {
                    connection.isEnabled = true
                }
                
                // Configuration format profondeur optimal
                if let depthFormat = self.getBestDepthFormat(for: videoDevice) {
                    try? videoDevice.lockForConfiguration()
                    videoDevice.activeDepthDataFormat = depthFormat
                    videoDevice.unlockForConfiguration()
                }
            }
            
            // Configuration synchronizer pour coordination vidéo/profondeur
            self.configureSynchronizer()
            
            self.captureSession.commitConfiguration()
        }
    }
    
    /// Sélectionne la meilleure caméra disponible (LiDAR en priorité)
    /// - Returns: AVCaptureDevice optimal pour détection
    private func getBestCameraDevice() -> AVCaptureDevice? {
        // Priorité à la caméra avec LiDAR si disponible
        if lidarAvailable {
            if let lidarDevice = AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back) {
                return lidarDevice
            }
        }
        
        // Sinon caméra standard arrière
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    }
    
    /// Sélectionne le meilleur format de profondeur pour performances optimales
    /// - Parameter device: Device caméra
    /// - Returns: Format de profondeur optimal (640x480 prioritaire)
    private func getBestDepthFormat(for device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        let depthFormats = device.activeFormat.supportedDepthDataFormats
        
        // Recherche format 640x480 pour équilibre qualité/performance
        let preferredDepthFormat = depthFormats.first { format in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return dimensions.width == 640 && dimensions.height == 480
        }
        
        return preferredDepthFormat ?? depthFormats.first
    }
    
    /// Configure le synchronizer pour coordination vidéo/profondeur
    private func configureSynchronizer() {
        if lidarAvailable {
            // Mode LiDAR: synchronisation vidéo + profondeur
            outputSynchronizer = AVCaptureDataOutputSynchronizer(dataOutputs: [videoDataOutput, depthDataOutput])
            outputSynchronizer?.setDelegate(self, queue: DispatchQueue(label: "sync.processing.queue"))
        } else {
            // Mode standard: vidéo seule
            videoDataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "video.processing.queue"))
        }
    }
}

// MARK: - Delegate Synchronization (Mode LiDAR)
extension CameraManager: AVCaptureDataOutputSynchronizerDelegate {
    
    /// Traite les données synchronisées vidéo + profondeur LiDAR
    /// - Parameters:
    ///   - synchronizer: Synchronizer source
    ///   - synchronizedDataCollection: Données coordonnées vidéo/profondeur
    func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer,
                               didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection) {
        
        // Système skip frames pour optimisation performance
        frameCounter += 1
        guard frameCounter % (skipFrameCount + 1) == 0 else { return }
        
        // Extraction données vidéo
        guard let syncedVideoData = synchronizedDataCollection.synchronizedData(for: videoDataOutput) as? AVCaptureSynchronizedSampleBufferData,
              !syncedVideoData.sampleBufferWasDropped,
              let pixelBuffer = CMSampleBufferGetImageBuffer(syncedVideoData.sampleBuffer) else {
            return
        }
        
        // Extraction données profondeur si LiDAR actif
        var depthData: AVDepthData?
        if lidarAvailable && isLiDAREnabled,
           let syncedDepthData = synchronizedDataCollection.synchronizedData(for: depthDataOutput) as? AVCaptureSynchronizedDepthData,
           !syncedDepthData.depthDataWasDropped {
            depthData = syncedDepthData.depthData
            lidarManager.processDepthData(syncedDepthData.depthData)
        }
        
        // Stockage pour calculs de distance
        lastImageBuffer = pixelBuffer
        lastDepthData = depthData
        
        // Lancement détection IA avec données LiDAR et tracking
        objectDetectionManager.detectObjectsWithLiDAR(
            in: pixelBuffer,
            depthData: depthData,
            lidarManager: lidarManager,
            imageSize: imageSize
        ) { [weak self] detections, inferenceTime in
            DispatchQueue.main.async {
                self?.currentFPS = 1000.0 / inferenceTime
                
                // Vérification proximité pour vibrations
                let proximityDetections = detections.map {
                    (rect: $0.rect, label: $0.label, confidence: $0.confidence, distance: $0.distance)
                }
                self?.hapticManager.checkProximityAndAlert(detections: proximityDetections)
                
                // Transmission à l'interface utilisateur
                self?.delegate?.didDetectObjects(detections)
            }
        }
    }
}

// MARK: - Delegate Video (Mode Standard)
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    /// Traite les données vidéo seules (sans LiDAR)
    /// - Parameters:
    ///   - output: Source de sortie
    ///   - sampleBuffer: Buffer vidéo
    ///   - connection: Connection source
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        // Ne traiter que si pas de synchronizer (mode sans LiDAR)
        guard outputSynchronizer == nil else { return }
        
        // Système skip frames
        frameCounter += 1
        guard frameCounter % (skipFrameCount + 1) == 0 else { return }
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // Détection IA sans LiDAR mais avec tracking
        objectDetectionManager.detectObjects(in: pixelBuffer) { [weak self] detections, inferenceTime in
            DispatchQueue.main.async {
                self?.currentFPS = 1000.0 / inferenceTime
                self?.delegate?.didDetectObjects(detections)
            }
        }
    }
}
