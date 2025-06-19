//
//  CameraManager.swift
//  test
//
//  Created by Samy 📍 on 18/06/2025.
//

import AVFoundation
import Vision
import SwiftUI

// --- PROTOCOLE MIS À JOUR POUR LIDAR ---
protocol CameraManagerDelegate {
    func didDetectObjects(_ detections: [(rect: CGRect, label: String, confidence: Float, distance: Float?)])
}
// -----------------------------

class CameraManager: NSObject, ObservableObject {
    @Published var isRunning = false
    @Published var hasPermission = false
    @Published var currentFPS: Double = 0.0  // Pour afficher les performances
    @Published var isLiDARAvailable = false
    @Published var isLiDAREnabled = false
    
    // Le 'weak' est toujours important ici pour éviter les cycles de rétention
    // même si le délégué peut être une struct (car la struct n'a pas de cycle de rétention directe avec le manager)
    var delegate: CameraManagerDelegate?
    
    private let captureSession = AVCaptureSession()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let depthDataOutput = AVCaptureDepthDataOutput()  // Pour LiDAR
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    private let objectDetectionManager = ObjectDetectionManager()
    
    // Configuration des skip frames
    private var skipFrameCount = 5  // Par défaut, traite 1 frame sur 6
    private var frameCounter = 0
    
    // Données de profondeur pour LiDAR
    private var latestDepthData: CVPixelBuffer?
    private var currentDetectionsWithDistance: [(rect: CGRect, label: String, confidence: Float, distance: Float?)] = []
    
    override init() {
        super.init()
        checkLiDARAvailability()
        setupCaptureSession()
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
    
    // Fonction pour obtenir les statistiques de performance
    func getPerformanceStats() -> String {
        return objectDetectionManager.getPerformanceStats()
    }
    
    // Fonction pour réinitialiser les statistiques
    func resetPerformanceStats() {
        objectDetectionManager.resetStats()
    }
    
    // MARK: - Configuration Skip Frames
    func setSkipFrames(_ count: Int) {
        skipFrameCount = max(0, count)
        print("⚙️ Skip frames défini à: \(skipFrameCount)")
    }
    
    func getSkipFrames() -> Int {
        return skipFrameCount
    }
    
    // MARK: - Configuration des classes actives
    func setActiveClasses(_ classes: [String]) {
        objectDetectionManager.setActiveClasses(classes)
    }
    
    func getActiveClasses() -> [String] {
        return objectDetectionManager.getActiveClasses()
    }
    
    // MARK: - LiDAR Configuration
    
    private func checkLiDARAvailability() {
        isLiDARAvailable = objectDetectionManager.isLiDARSupported()
        if isLiDARAvailable {
            isLiDAREnabled = true  // Activé par défaut si disponible
            objectDetectionManager.setLiDAREnabled(true)
            print("📡 LiDAR détecté et activé")
        } else {
            print("📡 LiDAR non disponible sur cet appareil")
        }
    }
    
    func setLiDAREnabled(_ enabled: Bool) {
        guard isLiDARAvailable else { return }
        isLiDAREnabled = enabled
        objectDetectionManager.setLiDAREnabled(enabled)
        
        // Reconfigurer la session caméra si nécessaire
        if isRunning {
            sessionQueue.async {
                self.setupCaptureSession()
            }
        }
    }
    
    private func setupCaptureSession() {
        sessionQueue.async {
            self.captureSession.beginConfiguration()
            
            // Nettoyer les anciennes configurations
            for input in self.captureSession.inputs {
                self.captureSession.removeInput(input)
            }
            for output in self.captureSession.outputs {
                self.captureSession.removeOutput(output)
            }
            
            // Choisir la caméra appropriée (avec LiDAR si disponible et activé)
            var videoDevice: AVCaptureDevice?
            
            if self.isLiDAREnabled && self.isLiDARAvailable {
                // Caméra avec LiDAR
                videoDevice = AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back)
                print("📡 Configuration caméra avec LiDAR")
            }
            
            // Fallback vers la caméra classique
            if videoDevice == nil {
                videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                print("📷 Configuration caméra standard")
            }
            
            guard let device = videoDevice,
                  let videoDeviceInput = try? AVCaptureDeviceInput(device: device),
                  self.captureSession.canAddInput(videoDeviceInput) else {
                print("❌ Impossible de configurer l'entrée vidéo")
                self.captureSession.commitConfiguration()
                return
            }
            
            self.captureSession.addInput(videoDeviceInput)
            
            // Configurer la sortie vidéo
            if self.captureSession.canAddOutput(self.videoDataOutput) {
                self.captureSession.addOutput(self.videoDataOutput)
                
                self.videoDataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "video.processing.queue"))
                self.videoDataOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
            }
            
            // Configurer la sortie depth si LiDAR est activé
            if self.isLiDAREnabled && self.isLiDARAvailable {
                if self.captureSession.canAddOutput(self.depthDataOutput) {
                    self.captureSession.addOutput(self.depthDataOutput)
                    self.depthDataOutput.setDelegate(self, callbackQueue: DispatchQueue(label: "depth.processing.queue"))
                    
                    // Synchroniser les données vidéo et depth
                    if let connection = self.depthDataOutput.connection(with: .depthData) {
                        connection.isEnabled = true
                    }
                    
                    print("📡 Sortie depth configurée")
                }
            }
            
            self.captureSession.commitConfiguration()
        }
    }
    
    // Stocker les détections avec distance pour l'accès depuis l'interface
    private func storeDetectionsWithDistance(_ detections: [(rect: CGRect, label: String, confidence: Float, distance: Float?)]) {
        currentDetectionsWithDistance = detections
    }
    
    // Obtenir les détections avec distance
    func getDetectionsWithDistance() -> [(rect: CGRect, label: String, confidence: Float, distance: Float?)] {
        return currentDetectionsWithDistance
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        // Système de skip frames configurable
        frameCounter += 1
        guard frameCounter % (skipFrameCount + 1) == 0 else { return }
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // Passer les données de profondeur si disponibles
        objectDetectionManager.detectObjects(in: pixelBuffer, depthData: latestDepthData) { [weak self] detections, inferenceTime in
            DispatchQueue.main.async {
                // Mettre à jour le FPS pour l'affichage
                self?.currentFPS = 1000.0 / inferenceTime
                
                // Transmettre directement les détections avec distance au delegate
                self?.delegate?.didDetectObjects(detections)
                
                // Stocker les distances pour l'affichage si nécessaire
                self?.storeDetectionsWithDistance(detections)
            }
        }
    }
}

// MARK: - AVCaptureDepthDataOutputDelegate
extension CameraManager: AVCaptureDepthDataOutputDelegate {
    func depthDataOutput(_ output: AVCaptureDepthDataOutput, didOutput depthData: AVDepthData, timestamp: CMTime, connection: AVCaptureConnection) {
        
        // Convertir les données de profondeur en CVPixelBuffer
        let depthPixelBuffer = depthData.depthDataMap
        
        // Stocker les dernières données de profondeur
        latestDepthData = depthPixelBuffer
        
        // Debug : Vérifier que les données arrivent
        let depthWidth = CVPixelBufferGetWidth(depthPixelBuffer)
        let depthHeight = CVPixelBufferGetHeight(depthPixelBuffer)
        print("📡 CameraManager: Données LiDAR reçues: \(depthWidth)x\(depthHeight)")
    }
}
