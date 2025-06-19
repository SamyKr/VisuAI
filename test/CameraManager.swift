//
//  CameraManager.swift
//  test
//
//  Created by Samy 📍 on 18/06/2025.
//

import AVFoundation
import Vision
import SwiftUI

// --- LA CORRECTION EST ICI ---
// On supprime ': AnyObject' pour permettre aux structs de se conformer à ce protocole.
protocol CameraManagerDelegate {
    func didDetectObjects(_ detections: [(rect: CGRect, label: String, confidence: Float)])
}
// -----------------------------

class CameraManager: NSObject, ObservableObject {
    @Published var isRunning = false
    @Published var hasPermission = false
    @Published var currentFPS: Double = 0.0  // Pour afficher les performances
    
    // Le 'weak' est toujours important ici pour éviter les cycles de rétention
    // même si le délégué peut être une struct (car la struct n'a pas de cycle de rétention directe avec le manager)
    var delegate: CameraManagerDelegate?
    
    private let captureSession = AVCaptureSession()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    private let objectDetectionManager = ObjectDetectionManager()
    
    // Configuration des skip frames
    private var skipFrameCount = 5  // Par défaut, traite 1 frame sur 6
    private var frameCounter = 0
    
    override init() {
        super.init()
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
    
    private func setupCaptureSession() {
        sessionQueue.async {
            self.captureSession.beginConfiguration()
            
            // Ajouter l'entrée vidéo
            guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice),
                  self.captureSession.canAddInput(videoDeviceInput) else {
                print("❌ Impossible de configurer l'entrée vidéo")
                return
            }
            
            self.captureSession.addInput(videoDeviceInput)
            
            // Configurer la sortie vidéo pour la détection
            if self.captureSession.canAddOutput(self.videoDataOutput) {
                self.captureSession.addOutput(self.videoDataOutput)
                
                self.videoDataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "video.processing.queue"))
                self.videoDataOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
            }
            
            self.captureSession.commitConfiguration()
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        // Système de skip frames configurable
        frameCounter += 1
        guard frameCounter % (skipFrameCount + 1) == 0 else { return }
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // CORRECTION : Ajout du deuxième paramètre inferenceTime dans la closure
        objectDetectionManager.detectObjects(in: pixelBuffer) { [weak self] detections, inferenceTime in
            DispatchQueue.main.async {
                // Mettre à jour le FPS pour l'affichage
                self?.currentFPS = 1000.0 / inferenceTime
                
                // Notifier le délégué des détections
                self?.delegate?.didDetectObjects(detections)
            }
        }
    }
}
