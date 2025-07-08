//
//  CameraManager.swift (Version avec LiDAR + Tracking)
//  test
//
//  Created by Samy 📍 on 18/06/2025.
//  Updated with LiDAR integration - 19/06/2025
//  Updated with Object Tracking - 20/06/2025
//  Updated with new class management system - 08/07/2025
//

import AVFoundation
import Vision
import SwiftUI

// Protocole mis à jour pour le tracking coloré avec LiDAR
protocol CameraManagerDelegate {
    func didDetectObjects(_ detections: [(rect: CGRect, label: String, confidence: Float, distance: Float?, trackingInfo: (id: Int, color: UIColor, opacity: Double))])
}

class CameraManager: NSObject, ObservableObject {
    @Published var isRunning = false
    @Published var hasPermission = false
    @Published var currentFPS: Double = 0.0
    @Published var isLiDAREnabled = false
    @Published var lidarAvailable = false
    
    var delegate: CameraManagerDelegate?
    
    private let captureSession = AVCaptureSession()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let depthDataOutput = AVCaptureDepthDataOutput()
    private var outputSynchronizer: AVCaptureDataOutputSynchronizer?
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    private let objectDetectionManager = ObjectDetectionManager()
    private let lidarManager = LiDARManager()
    private let hapticManager = HapticManager()  // ← Manager pour les vibrations
    
    // Configuration des skip frames
    private var skipFrameCount = 1
    private var frameCounter = 0
    
    // Variables pour la synchronisation des données
    private var lastImageBuffer: CVPixelBuffer?
    private var lastDepthData: AVDepthData?
    private var imageSize: CGSize = .zero
    
    override init() {
        super.init()
        
        // Vérifier la disponibilité du LiDAR
        lidarAvailable = lidarManager.isAvailable()
        
        setupCaptureSession()
        
        print("🎥 CameraManager initialisé avec tracking")
        print("📏 LiDAR disponible: \(lidarAvailable ? "✅" : "❌")")
    }
    
    func requestPermission() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                self.hasPermission = granted
            }
        }
    }
    
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
    
    func getPreviewLayer() -> AVCaptureVideoPreviewLayer {
        if previewLayer == nil {
            previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            previewLayer?.videoGravity = .resizeAspectFill
        }
        return previewLayer!
    }
    
    // MARK: - Tracking Controls
    func resetTracking() {
        objectDetectionManager.resetTracking()
        print("🔄 Tracking réinitialisé")
    }
    
    func getTrackingStats() -> String {
        return objectDetectionManager.getTrackingStats()
    }
    
    // MARK: - Haptic Controls
    func enableProximityAlerts(_ enabled: Bool) {
        hapticManager.enableProximityAlerts(enabled)
    }
    
    func isProximityAlertsEnabled() -> Bool {
        return hapticManager.isProximityAlertsEnabled()
    }
    
    func setDangerDistance(_ distance: Float) {
        hapticManager.setDangerDistance(distance)
    }
    
    func getDangerDistance() -> Float {
        return hapticManager.getDangerDistance()
    }
    
    func setWarningDistance(_ distance: Float) {
        hapticManager.setWarningDistance(distance)
    }
    
    func getWarningDistance() -> Float {
        return hapticManager.getWarningDistance()
    }
    
    func setIntensityRange(min: Float, max: Float) {
        hapticManager.setIntensityRange(min: min, max: max)
    }
    
    func getIntensityRange() -> (min: Float, max: Float) {
        return hapticManager.getIntensityRange()
    }
    
    func enableGraduatedVibrations(_ enabled: Bool) {
        hapticManager.enableGraduatedVibrations(enabled)
    }
    
    func isGraduatedVibrationsEnabled() -> Bool {
        return hapticManager.isGraduatedVibrationsEnabled()
    }
    
    func enableGraduatedFrequency(_ enabled: Bool) {
        hapticManager.enableGraduatedFrequency(enabled)
    }
    
    func isGraduatedFrequencyEnabled() -> Bool {
        return hapticManager.isGraduatedFrequencyEnabled()
    }
    
    func setFrequencyRange(minCooldown: TimeInterval, maxCooldown: TimeInterval) {
        hapticManager.setFrequencyRange(minCooldown: minCooldown, maxCooldown: maxCooldown)
    }
    
    func getFrequencyRange() -> (minCooldown: TimeInterval, maxCooldown: TimeInterval) {
        return hapticManager.getFrequencyRange()
    }
    
    func playSuccessFeedback() {
        hapticManager.playSuccessFeedback()
    }
    
    func playSelectionFeedback() {
        hapticManager.playSelectionFeedback()
    }
    
    func testDangerVibration(intensity: Float = 1.0) {
        hapticManager.testDangerVibration(customIntensity: intensity)
    }
    
    func testWarningVibration(intensity: Float = 0.7) {
        hapticManager.testWarningVibration(customIntensity: intensity)
    }
    
    // MARK: - LiDAR Controls
    func enableLiDAR() -> Bool {
        guard lidarAvailable else {
            print("❌ LiDAR non disponible")
            return false
        }
        
        let success = lidarManager.enableDepthCapture()
        if success {
            DispatchQueue.main.async {
                self.isLiDAREnabled = true
            }
            print("✅ LiDAR activé")
        }
        return success
    }
    
    func disableLiDAR() {
        lidarManager.disableDepthCapture()
        DispatchQueue.main.async {
            self.isLiDAREnabled = false
        }
        print("⏹️ LiDAR désactivé")
    }
    
    func toggleLiDAR() -> Bool {
        if isLiDAREnabled {
            disableLiDAR()
            return false
        } else {
            return enableLiDAR()
        }
    }
    
    // MARK: - Important Objects Ranking
    func getTopImportantObjects(maxCount: Int = 5) -> [(object: TrackedObject, score: Float)] {
        return objectDetectionManager.getTopImportantObjects(maxCount: maxCount)
    }
    
    func getImportanceStats() -> String {
        return objectDetectionManager.getImportanceStats()
    }
    
    func getPerformanceStats() -> String {
        var stats = objectDetectionManager.getPerformanceStats()
        
        if lidarAvailable {
            stats += "\n\n" + lidarManager.getLiDARStats()
        }
        
        stats += "\n\n" + hapticManager.getHapticStats()
        
        return stats
    }
    
    func resetPerformanceStats() {
        objectDetectionManager.resetStats()
        lidarManager.resetStats()
        hapticManager.resetStats()
    }
    
    // MARK: - Configuration
    func setSkipFrames(_ count: Int) {
        skipFrameCount = max(0, count)
        print("⚙️ Skip frames défini à: \(skipFrameCount)")
    }
    
    func getSkipFrames() -> Int {
        return skipFrameCount
    }
    
    // MODIFIÉ: Nouveau système de gestion des classes
    func setEnabledClasses(_ classes: Set<String>) {
        objectDetectionManager.setEnabledClasses(classes)
        print("✅ Classes activées mises à jour: \(classes.count) classes")
    }
    
    func addIgnoredClass(_ className: String) {
        objectDetectionManager.addIgnoredClass(className)
    }
    
    func removeIgnoredClass(_ className: String) {
        objectDetectionManager.removeIgnoredClass(className)
    }
    
    func getIgnoredClasses() -> [String] {
        return objectDetectionManager.getIgnoredClasses()
    }
    
    func clearIgnoredClasses() {
        objectDetectionManager.clearIgnoredClasses()
    }
    
    // AJOUTÉ: Accès aux classes du modèle
    func getAvailableClasses() -> [String] {
        return objectDetectionManager.getAvailableClasses()
    }
    
    // AJOUTÉ: Accès statique aux classes du modèle
    static func getAllModelClasses() -> [String] {
        return ObjectDetectionManager.getAllModelClasses()
    }
    
    // MARK: - Setup
    private func setupCaptureSession() {
        sessionQueue.async {
            self.captureSession.beginConfiguration()
            
            // Configuration de la session pour de meilleures performances
            if self.captureSession.canSetSessionPreset(.hd1920x1080) {
                self.captureSession.sessionPreset = .hd1920x1080
            }
            
            // Ajouter l'entrée vidéo avec support LiDAR si disponible
            guard let videoDevice = self.getBestCameraDevice(),
                  let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice),
                  self.captureSession.canAddInput(videoDeviceInput) else {
                print("❌ Impossible de configurer l'entrée vidéo")
                return
            }
            
            self.captureSession.addInput(videoDeviceInput)
            
            // Stocker la taille de l'image pour les calculs de distance
            let dimensions = CMVideoFormatDescriptionGetDimensions(videoDevice.activeFormat.formatDescription)
            self.imageSize = CGSize(width: Int(dimensions.width), height: Int(dimensions.height))
            
            // Configurer la sortie vidéo
            if self.captureSession.canAddOutput(self.videoDataOutput) {
                self.captureSession.addOutput(self.videoDataOutput)
                
                self.videoDataOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
                
                // Configuration pour de meilleures performances
                self.videoDataOutput.alwaysDiscardsLateVideoFrames = true
            }
            
            // Configurer la sortie de profondeur si LiDAR disponible
            if self.lidarAvailable && self.captureSession.canAddOutput(self.depthDataOutput) {
                self.captureSession.addOutput(self.depthDataOutput)
                
                // Connecter la sortie de profondeur à l'entrée vidéo
                if let connection = self.depthDataOutput.connection(with: .depthData) {
                    connection.isEnabled = true
                }
                
                // Configuration du format de profondeur
                if let depthFormat = self.getBestDepthFormat(for: videoDevice) {
                    try? videoDevice.lockForConfiguration()
                    videoDevice.activeDepthDataFormat = depthFormat
                    videoDevice.unlockForConfiguration()
                    print("✅ Format de profondeur configuré: \(depthFormat)")
                }
                
                print("✅ Sortie de profondeur LiDAR configurée")
            }
            
            // Configurer le synchronizer pour coordonner les données
            self.configureSynchronizer()
            
            self.captureSession.commitConfiguration()
            print("✅ Session de capture configurée avec LiDAR: \(self.lidarAvailable)")
        }
    }
    
    private func getBestCameraDevice() -> AVCaptureDevice? {
        // Essayer d'abord la caméra avec LiDAR
        if lidarAvailable {
            if let lidarDevice = AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back) {
                print("✅ Utilisation de la caméra LiDAR")
                return lidarDevice
            }
        }
        
        // Sinon, utiliser la caméra standard
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    }
    
    private func getBestDepthFormat(for device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        let depthFormats = device.activeFormat.supportedDepthDataFormats
        
        // Chercher un format 640x480 pour de bonnes performances
        let preferredDepthFormat = depthFormats.first { format in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return dimensions.width == 640 && dimensions.height == 480
        }
        
        return preferredDepthFormat ?? depthFormats.first
    }
    
    private func configureSynchronizer() {
        // Créer le synchronizer APRÈS que les outputs soient ajoutés à la session
        if lidarAvailable {
            outputSynchronizer = AVCaptureDataOutputSynchronizer(dataOutputs: [videoDataOutput, depthDataOutput])
            outputSynchronizer?.setDelegate(self, queue: DispatchQueue(label: "sync.processing.queue"))
            print("✅ Synchronizer configuré avec LiDAR")
        } else {
            // Mode sans LiDAR - utiliser seulement le delegate vidéo
            videoDataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "video.processing.queue"))
            print("✅ Mode vidéo seule configuré (pas de LiDAR)")
        }
    }
}

// MARK: - AVCaptureDataOutputSynchronizerDelegate (avec LiDAR)
extension CameraManager: AVCaptureDataOutputSynchronizerDelegate {
    func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer,
                               didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection) {
        
        // Système de skip frames
        frameCounter += 1
        guard frameCounter % (skipFrameCount + 1) == 0 else { return }
        
        // Récupérer les données vidéo
        guard let syncedVideoData = synchronizedDataCollection.synchronizedData(for: videoDataOutput) as? AVCaptureSynchronizedSampleBufferData,
              !syncedVideoData.sampleBufferWasDropped,
              let pixelBuffer = CMSampleBufferGetImageBuffer(syncedVideoData.sampleBuffer) else {
            return
        }
        
        // Récupérer les données de profondeur si disponibles
        var depthData: AVDepthData?
        if lidarAvailable && isLiDAREnabled,
           let syncedDepthData = synchronizedDataCollection.synchronizedData(for: depthDataOutput) as? AVCaptureSynchronizedDepthData,
           !syncedDepthData.depthDataWasDropped {
            depthData = syncedDepthData.depthData
            
            // Traiter les données de profondeur
            lidarManager.processDepthData(syncedDepthData.depthData)
        }
        
        // Stocker pour utilisation dans les calculs de distance
        lastImageBuffer = pixelBuffer
        lastDepthData = depthData
        
        // Effectuer la détection d'objets avec données LiDAR et tracking
        objectDetectionManager.detectObjectsWithLiDAR(
            in: pixelBuffer,
            depthData: depthData,
            lidarManager: lidarManager,
            imageSize: imageSize
        ) { [weak self] detections, inferenceTime in
            DispatchQueue.main.async {
                self?.currentFPS = 1000.0 / inferenceTime
                
                // Vérifier la proximité et déclencher les vibrations si nécessaire
                // Convertir les détections au format attendu par hapticManager (sans tracking info)
                let proximityDetections = detections.map {
                    (rect: $0.rect, label: $0.label, confidence: $0.confidence, distance: $0.distance)
                }
                self?.hapticManager.checkProximityAndAlert(detections: proximityDetections)
                
                self?.delegate?.didDetectObjects(detections)
            }
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate (sans LiDAR)
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        // Ne traiter que si pas de synchronizer (mode sans LiDAR)
        guard outputSynchronizer == nil else { return }
        
        // Système de skip frames configurable
        frameCounter += 1
        guard frameCounter % (skipFrameCount + 1) == 0 else { return }
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // Effectuer la détection d'objets sans LiDAR mais avec tracking
        objectDetectionManager.detectObjects(in: pixelBuffer) { [weak self] detections, inferenceTime in
            DispatchQueue.main.async {
                // Mettre à jour le FPS pour l'affichage
                self?.currentFPS = 1000.0 / inferenceTime
                
                // Pas de vérification de proximité sans LiDAR (distances non disponibles)
                
                // Notifier le délégué des détections avec tracking
                // Note: detections ont déjà distance: nil car pas de LiDAR
                self?.delegate?.didDetectObjects(detections)
            }
        }
    }
}
