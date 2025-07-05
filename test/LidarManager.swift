//
//  LidarManager.swift
//  test
//
//  Created by Samy 📍 on 19/06/2025.
//

import AVFoundation
import CoreVideo
import simd

class LiDARManager: NSObject {
    
    // MARK: - Properties
    private var isLiDARAvailable = false
    private var isDepthEnabled = false
    private var lastDepthData: AVDepthData?
    private var lastDepthPixelBuffer: CVPixelBuffer?
    
    // Statistiques LiDAR
    private var depthDataCount = 0
    private var averageDepthRange: (min: Float, max: Float) = (0, 0)
    
    // MARK: - Initialization
    override init() {
        super.init()
        checkLiDARAvailability()
    }
    
    // MARK: - LiDAR Availability Check
    func checkLiDARAvailability() {
        // Vérification de la disponibilité du LiDAR
        if let device = AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back) {
            isLiDARAvailable = true
            
            
            // Vérifier les formats supportés
            let supportedFormats = device.activeFormat.supportedDepthDataFormats
          
            
            for format in supportedFormats {
                let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                // print("   - Format: \(dimensions.width)x\(dimensions.height)")
            }
            
        } else {
            isLiDARAvailable = false
            print("❌ LiDAR non disponible sur cet appareil")
        }
    }
    
    // MARK: - Public Methods
    func isAvailable() -> Bool {
        return isLiDARAvailable
    }
    
    func isEnabled() -> Bool {
        return isDepthEnabled && isLiDARAvailable
    }
    
    func enableDepthCapture() -> Bool {
        guard isLiDARAvailable else {
            print("❌ Impossible d'activer le LiDAR - non disponible")
            return false
        }
        
        isDepthEnabled = true
        print("✅ Capture de profondeur LiDAR activée")
        return true
    }
    
    func disableDepthCapture() {
        isDepthEnabled = false
        lastDepthData = nil
        lastDepthPixelBuffer = nil
        print("⏹️ Capture de profondeur LiDAR désactivée")
    }
    
    // MARK: - Depth Data Processing
    func processDepthData(_ depthData: AVDepthData) {
        guard isDepthEnabled else { return }
        
        // Convertir en format float32 si nécessaire
        let convertedDepthData = depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        
        lastDepthData = convertedDepthData
        lastDepthPixelBuffer = convertedDepthData.depthDataMap
        
        depthDataCount += 1
        
        // Calculer les statistiques de profondeur
        updateDepthStatistics(convertedDepthData)
        
        // Debug occasionnel
        if depthDataCount % 30 == 0 {
            print("📏 LiDAR: \(depthDataCount) frames de profondeur traités")
            print("   - Plage de profondeur: \(averageDepthRange.min)m - \(averageDepthRange.max)m")
        }
    }
    
    // MARK: - Distance Calculation
    func getDistanceAtPoint(_ point: CGPoint, imageSize: CGSize) -> Float? {
        guard let depthPixelBuffer = lastDepthPixelBuffer else {
            return nil
        }
        
        // Convertir les coordonnées de l'image vers les coordonnées du depth buffer
        let depthSize = CGSize(
            width: CVPixelBufferGetWidth(depthPixelBuffer),
            height: CVPixelBufferGetHeight(depthPixelBuffer)
        )
        
        let normalizedX = point.x / imageSize.width
        let normalizedY = point.y / imageSize.height
        
        let depthX = Int(normalizedX * depthSize.width)
        let depthY = Int(normalizedY * depthSize.height)
        
        // Vérifier les limites
        guard depthX >= 0 && depthX < Int(depthSize.width) &&
              depthY >= 0 && depthY < Int(depthSize.height) else {
            return nil
        }
        
        return getDepthValue(at: CGPoint(x: depthX, y: depthY), from: depthPixelBuffer)
    }
    
    func getDistanceForBoundingBox(_ boundingBox: CGRect, imageSize: CGSize) -> Float? {
        guard let depthPixelBuffer = lastDepthPixelBuffer else {
            return nil
        }
        
        // Prendre plusieurs points dans la bounding box pour une mesure plus précise
        let centerPoint = CGPoint(
            x: boundingBox.midX * imageSize.width,
            y: boundingBox.midY * imageSize.height
        )
        
        // Points de sampling dans la bounding box
        let samplePoints = [
            centerPoint, // Centre
            CGPoint(x: boundingBox.midX * imageSize.width,
                   y: (boundingBox.minY + boundingBox.height * 0.3) * imageSize.height), // Haut
            CGPoint(x: boundingBox.midX * imageSize.width,
                   y: (boundingBox.maxY - boundingBox.height * 0.3) * imageSize.height), // Bas
        ]
        
        var validDistances: [Float] = []
        
        for point in samplePoints {
            if let distance = getDistanceAtPoint(point, imageSize: imageSize) {
                // Filtrer les valeurs aberrantes (trop proches ou trop loin)
                if distance > 0.1 && distance < 50.0 {
                    validDistances.append(distance)
                }
            }
        }
        
        // Retourner la médiane pour plus de robustesse
        guard !validDistances.isEmpty else { return nil }
        
        validDistances.sort()
        let middleIndex = validDistances.count / 2
        
        if validDistances.count % 2 == 0 {
            return (validDistances[middleIndex - 1] + validDistances[middleIndex]) / 2.0
        } else {
            return validDistances[middleIndex]
        }
    }
    
    // MARK: - Private Methods
    private func getDepthValue(at point: CGPoint, from pixelBuffer: CVPixelBuffer) -> Float? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }
        
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let floatBuffer = baseAddress.assumingMemoryBound(to: Float32.self)
        
        let x = Int(point.x)
        let y = Int(point.y)
        
        let index = y * (bytesPerRow / MemoryLayout<Float32>.size) + x
        let depthValue = floatBuffer[index]
        
        // Vérifier si la valeur est valide
        guard depthValue.isFinite && depthValue > 0 else {
            return nil
        }
        
        return depthValue
    }
    
    private func updateDepthStatistics(_ depthData: AVDepthData) {
        let pixelBuffer = depthData.depthDataMap
        
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let floatBuffer = baseAddress.assumingMemoryBound(to: Float32.self)
        
        var minDepth: Float = Float.greatestFiniteMagnitude
        var maxDepth: Float = 0
        var validPixels = 0
        
        // Échantillonner une grille pour les performances
        let sampleStep = max(width / 50, 1)
        
        for y in stride(from: 0, to: height, by: sampleStep) {
            for x in stride(from: 0, to: width, by: sampleStep) {
                let index = y * (bytesPerRow / MemoryLayout<Float32>.size) + x
                let depth = floatBuffer[index]
                
                if depth.isFinite && depth > 0 && depth < 100 {
                    minDepth = min(minDepth, depth)
                    maxDepth = max(maxDepth, depth)
                    validPixels += 1
                }
            }
        }
        
        if validPixels > 0 {
            averageDepthRange = (min: minDepth, max: maxDepth)
        }
    }
    
    // MARK: - Statistics
    func getLiDARStats() -> String {
        var stats = "📏 Statistiques LiDAR:\n"
        stats += "   - Disponible: \(isLiDARAvailable ? "✅" : "❌")\n"
        stats += "   - Activé: \(isDepthEnabled ? "✅" : "❌")\n"
        stats += "   - Frames traitées: \(depthDataCount)\n"
        
        if isEnabled() && averageDepthRange.max > 0 {
            stats += "   - Plage détectée: \(String(format: "%.1f", averageDepthRange.min))m - \(String(format: "%.1f", averageDepthRange.max))m\n"
            stats += "   - Dernière capture: \(lastDepthData != nil ? "✅" : "❌")"
        }
        
        return stats
    }
    
    func resetStats() {
        depthDataCount = 0
        averageDepthRange = (0, 0)
        print("📏 Statistiques LiDAR réinitialisées")
    }
    
    // MARK: - Utility
    func formatDistance(_ distance: Float) -> String {
        if distance < 1.0 {
            return "\(Int(distance * 100))cm"
        } else if distance < 10.0 {
            return "\(String(format: "%.1f", distance))m"
        } else {
            return "\(Int(distance))m"
        }
    }
}
