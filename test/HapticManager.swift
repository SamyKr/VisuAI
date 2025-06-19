//
//  HapticManager.swift
//  test
//
//  Created by Samy 📍 on 19/06/2025.
//

import UIKit
import CoreHaptics
import AVFoundation

class HapticManager {
    
    // MARK: - Properties
    private var hapticEngine: CHHapticEngine?
    private var isHapticsEnabled = true
    private var proximityAlertsEnabled = true
    
    // Configuration de proximité
    private var dangerDistance: Float = 1.0  // Distance dangereuse en mètres
    private var warningDistance: Float = 2.0 // Distance d'avertissement en mètres
    
    // Configuration d'intensité graduée
    private var minIntensity: Float = 0.3    // Intensité minimale (à la distance max)
    private var maxIntensity: Float = 1.0    // Intensité maximale (très proche)
    private var graduatedVibrations = true   // Activer les vibrations graduées
    
    // Configuration de fréquence graduée (nouveau)
    private var graduatedFrequency = true    // Activer la fréquence graduée
    private var maxCooldown: TimeInterval = 0.8  // Cooldown maximal (loin)
    private var minCooldown: TimeInterval = 0.1  // Cooldown minimal (très proche)
    
    // Debouncing pour éviter les vibrations en continu
    private var lastProximityAlert: Date = Date.distantPast
    private var alertCooldown: TimeInterval = 0.8  // Secondes entre les alertes (utilisé si fréquence graduée OFF)
    
    // Statistiques
    private var totalProximityAlerts = 0
    private var dangerAlerts = 0
    private var warningAlerts = 0
    
    // MARK: - Initialization
    init() {
        setupHapticEngine()
    }
    
    private func setupHapticEngine() {
        // Vérifier la disponibilité des haptiques
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            print("❌ Haptiques non supportées sur cet appareil")
            return
        }
        
        do {
            hapticEngine = try CHHapticEngine()
            try hapticEngine?.start()
            
            // Gérer les interruptions (appels, etc.)
            hapticEngine?.stoppedHandler = { reason in
                print("🔄 Moteur haptique arrêté: \(reason)")
                self.restartEngine()
            }
            
            hapticEngine?.resetHandler = {
                print("🔄 Reset du moteur haptique")
                self.restartEngine()
            }
            
            print("✅ Moteur haptique initialisé")
            
        } catch {
            print("❌ Erreur d'initialisation du moteur haptique: \(error)")
        }
    }
    
    private func restartEngine() {
        do {
            try hapticEngine?.start()
        } catch {
            print("❌ Impossible de redémarrer le moteur haptique: \(error)")
        }
    }
    
    // MARK: - Public Methods
    
    func enableProximityAlerts(_ enabled: Bool) {
        proximityAlertsEnabled = enabled
        print("📳 Alertes de proximité: \(enabled ? "activées" : "désactivées")")
    }
    
    func setDangerDistance(_ distance: Float) {
        dangerDistance = max(0.1, min(distance, 5.0)) // Entre 10cm et 5m
        print("⚠️ Distance de danger définie à: \(dangerDistance)m")
    }
    
    func setWarningDistance(_ distance: Float) {
        warningDistance = max(dangerDistance, min(distance, 10.0)) // Au moins la distance de danger
        print("🚨 Distance d'avertissement définie à: \(warningDistance)m")
    }
    
    func setIntensityRange(min: Float, max: Float) {
        minIntensity = Swift.max(0.1, Swift.min(min, 1.0))
        maxIntensity = Swift.max(minIntensity, Swift.min(max, 1.0))
        print("📳 Intensité définie: \(minIntensity) - \(maxIntensity)")
    }
    
    func enableGraduatedVibrations(_ enabled: Bool) {
        graduatedVibrations = enabled
        print("📈 Vibrations graduées: \(enabled ? "activées" : "désactivées")")
    }
    
    func enableGraduatedFrequency(_ enabled: Bool) {
        graduatedFrequency = enabled
        print("⚡ Fréquence graduée: \(enabled ? "activée" : "désactivée")")
    }
    
    func setFrequencyRange(minCooldown: TimeInterval, maxCooldown: TimeInterval) {
        self.minCooldown = Swift.max(0.05, Swift.min(minCooldown, 1.0)) // Entre 50ms et 1s
        self.maxCooldown = Swift.max(self.minCooldown, Swift.min(maxCooldown, 3.0)) // Entre minCooldown et 3s
        print("⚡ Fréquence définie: \(String(format: "%.2f", self.minCooldown))s - \(String(format: "%.2f", self.maxCooldown))s")
    }
    
    // MARK: - Proximity Detection
    
    func checkProximityAndAlert(detections: [(rect: CGRect, label: String, confidence: Float, distance: Float?)]) {
        guard proximityAlertsEnabled && isHapticsEnabled else { return }
        
        // Trouver l'objet le plus proche avec une distance valide
        let closestDistance = detections.compactMap { $0.distance }.min()
        
        guard let distance = closestDistance else { return }
        
        // Calculer le cooldown dynamique basé sur la distance
        let dynamicCooldown = calculateDynamicCooldown(for: distance)
        
        // Vérifier le cooldown dynamique
        let now = Date()
        guard now.timeIntervalSince(lastProximityAlert) >= dynamicCooldown else { return }
        
        // Déterminer le type d'alerte
        if distance <= dangerDistance {
            triggerDangerAlert(distance: distance, dynamicCooldown: dynamicCooldown)
            dangerAlerts += 1
        } else if distance <= warningDistance {
            triggerWarningAlert(distance: distance, dynamicCooldown: dynamicCooldown)
            warningAlerts += 1
        }
    }
    
    // MARK: - Dynamic Cooldown Calculation
    
    private func calculateDynamicCooldown(for distance: Float) -> TimeInterval {
        guard graduatedFrequency else {
            return alertCooldown // Utiliser le cooldown fixe si fréquence graduée désactivée
        }
        
        let referenceDistance = warningDistance // Utiliser la distance d'avertissement comme référence
        let minDistance: Float = 0.1 // Distance minimale pour fréquence max
        
        // Calcul de la fréquence inversement proportionnelle à la distance
        // Plus proche = cooldown plus petit = plus fréquent
        let normalizedDistance = Swift.max(minDistance, Swift.min(distance, referenceDistance))
        let distanceRatio = Double((normalizedDistance - minDistance) / (referenceDistance - minDistance))
        
        let calculatedCooldown = minCooldown + (maxCooldown - minCooldown) * distanceRatio
        
        return Swift.max(minCooldown, Swift.min(calculatedCooldown, maxCooldown))
    }
    
    // MARK: - Haptic Patterns
    
    private func triggerDangerAlert(distance: Float, dynamicCooldown: TimeInterval) {
        totalProximityAlerts += 1
        lastProximityAlert = Date()
        
        let intensity = calculateIntensity(for: distance, in: .danger)
        
        print("🚨 ALERTE DANGER: Objet détecté à \(String(format: "%.1f", distance))m")
        print("   - Intensité: \(String(format: "%.1f", intensity))")
        print("   - Fréquence: vibration toutes les \(String(format: "%.2f", dynamicCooldown))s")
        
        // Vibration avec intensité graduée pour danger immédiat
        if let engine = hapticEngine {
            playCustomDangerPattern(intensity: intensity)
        } else {
            // Fallback vers vibrations système
            playSystemDangerVibration(intensity: intensity)
        }
    }
    
    private func triggerWarningAlert(distance: Float, dynamicCooldown: TimeInterval) {
        totalProximityAlerts += 1
        lastProximityAlert = Date()
        
        let intensity = calculateIntensity(for: distance, in: .warning)
        
        print("⚠️ Avertissement: Objet proche à \(String(format: "%.1f", distance))m")
        print("   - Intensité: \(String(format: "%.1f", intensity))")
        print("   - Fréquence: vibration toutes les \(String(format: "%.2f", dynamicCooldown))s")
        
        // Vibration avec intensité graduée pour avertissement
        if let engine = hapticEngine {
            playCustomWarningPattern(intensity: intensity)
        } else {
            // Fallback vers vibrations système
            playSystemWarningVibration(intensity: intensity)
        }
    }
    
    // MARK: - Intensity Calculation
    
    private enum AlertType {
        case danger, warning
    }
    
    private func calculateIntensity(for distance: Float, in alertType: AlertType) -> Float {
        guard graduatedVibrations else {
            return alertType == .danger ? 1.0 : 0.7 // Intensité fixe si graduations désactivées
        }
        
        let referenceDistance = alertType == .danger ? dangerDistance : warningDistance
        let minDistance: Float = 0.1 // Distance minimale pour intensité max
        
        // Calcul de l'intensité inversement proportionnelle à la distance
        // Plus proche = plus fort
        let normalizedDistance = Swift.max(minDistance, Swift.min(distance, referenceDistance))
        let distanceRatio = (referenceDistance - normalizedDistance) / (referenceDistance - minDistance)
        
        let calculatedIntensity = minIntensity + (maxIntensity - minIntensity) * distanceRatio
        
        return Swift.max(minIntensity, Swift.min(calculatedIntensity, maxIntensity))
    }
    
    // MARK: - Custom Haptic Patterns
    
    private func playCustomDangerPattern(intensity: Float) {
        guard let engine = hapticEngine else { return }
        
        do {
            // Pattern de danger: 3 impulsions avec intensité graduée
            let events = [
                CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: intensity)
                ], relativeTime: 0),
                
                CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: intensity)
                ], relativeTime: 0.08),
                
                CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: intensity)
                ], relativeTime: 0.16)
            ]
            
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
            
        } catch {
            print("❌ Erreur pattern de danger: \(error)")
            playSystemDangerVibration(intensity: intensity)
        }
    }
    
    private func playCustomWarningPattern(intensity: Float) {
        guard let engine = hapticEngine else { return }
        
        do {
            // Pattern d'avertissement: 2 impulsions avec intensité graduée
            let adjustedIntensity = intensity * 0.8 // Légèrement moins fort que le danger
            
            let events = [
                CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: adjustedIntensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: adjustedIntensity)
                ], relativeTime: 0),
                
                CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: adjustedIntensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: adjustedIntensity)
                ], relativeTime: 0.12)
            ]
            
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
            
        } catch {
            print("❌ Erreur pattern d'avertissement: \(error)")
            playSystemWarningVibration(intensity: intensity)
        }
    }
    
    // MARK: - System Vibrations (Fallback)
    
    private func playSystemDangerVibration(intensity: Float) {
        // Intensité graduée avec UIImpactFeedbackGenerator
        let feedbackStyle: UIImpactFeedbackGenerator.FeedbackStyle
        
        if intensity >= 0.8 {
            feedbackStyle = .heavy
        } else if intensity >= 0.5 {
            feedbackStyle = .medium
        } else {
            feedbackStyle = .light
        }
        
        let impactFeedback = UIImpactFeedbackGenerator(style: feedbackStyle)
        impactFeedback.prepare()
        
        // Triple vibration avec timing adapté à l'intensité
        let timing = intensity >= 0.7 ? 0.08 : 0.12
        
        impactFeedback.impactOccurred(intensity: CGFloat(intensity))
        
        DispatchQueue.main.asyncAfter(deadline: .now() + timing) {
            impactFeedback.impactOccurred(intensity: CGFloat(intensity))
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + timing * 2) {
            impactFeedback.impactOccurred(intensity: CGFloat(intensity))
        }
    }
    
    private func playSystemWarningVibration(intensity: Float) {
        // Intensité graduée plus douce pour les avertissements
        let adjustedIntensity = intensity * 0.7
        let feedbackStyle: UIImpactFeedbackGenerator.FeedbackStyle
        
        if adjustedIntensity >= 0.6 {
            feedbackStyle = .medium
        } else {
            feedbackStyle = .light
        }
        
        let impactFeedback = UIImpactFeedbackGenerator(style: feedbackStyle)
        impactFeedback.prepare()
        
        // Double vibration
        impactFeedback.impactOccurred(intensity: CGFloat(adjustedIntensity))
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            impactFeedback.impactOccurred(intensity: CGFloat(adjustedIntensity))
        }
    }
    
    // MARK: - Manual Haptics (for UI interactions)
    
    func playSelectionFeedback() {
        let selectionFeedback = UISelectionFeedbackGenerator()
        selectionFeedback.selectionChanged()
    }
    
    func playSuccessFeedback() {
        let notificationFeedback = UINotificationFeedbackGenerator()
        notificationFeedback.notificationOccurred(.success)
    }
    
    func playErrorFeedback() {
        let notificationFeedback = UINotificationFeedbackGenerator()
        notificationFeedback.notificationOccurred(.error)
    }
    
    // MARK: - Test Methods (pour les paramètres)
    
    func testDangerVibration(customIntensity: Float? = nil) {
        let testIntensity = customIntensity ?? (graduatedVibrations ? maxIntensity : 1.0)
        
        if let engine = hapticEngine {
            playCustomDangerPattern(intensity: testIntensity)
        } else {
            playSystemDangerVibration(intensity: testIntensity)
        }
        
        print("🧪 Test vibration danger - Intensité: \(String(format: "%.1f", testIntensity))")
    }
    
    func testWarningVibration(customIntensity: Float? = nil) {
        let testIntensity = customIntensity ?? (graduatedVibrations ? minIntensity : 0.7)
        
        if let engine = hapticEngine {
            playCustomWarningPattern(intensity: testIntensity)
        } else {
            playSystemWarningVibration(intensity: testIntensity)
        }
        
        print("🧪 Test vibration avertissement - Intensité: \(String(format: "%.1f", testIntensity))")
    }
    
    // MARK: - Statistics
    
    func getHapticStats() -> String {
        var stats = "📳 Statistiques des vibrations:\n"
        stats += "   - Haptiques supportées: \(CHHapticEngine.capabilitiesForHardware().supportsHaptics ? "✅" : "❌")\n"
        stats += "   - Alertes de proximité: \(proximityAlertsEnabled ? "✅" : "❌")\n"
        stats += "   - Vibrations graduées: \(graduatedVibrations ? "✅" : "❌")\n"
        stats += "   - Fréquence graduée: \(graduatedFrequency ? "✅" : "❌")\n"
        stats += "   - Distance de danger: \(dangerDistance)m\n"
        stats += "   - Distance d'avertissement: \(warningDistance)m\n"
        stats += "   - Intensité: \(String(format: "%.1f", minIntensity)) - \(String(format: "%.1f", maxIntensity))\n"
        
        if graduatedFrequency {
            stats += "   - Fréquence: \(String(format: "%.2f", minCooldown))s - \(String(format: "%.2f", maxCooldown))s\n"
            stats += "   - Très proche (\(String(format: "%.1f", dangerDistance/2))m): vibration toutes les \(String(format: "%.2f", minCooldown))s\n"
            stats += "   - Loin (\(String(format: "%.1f", warningDistance))m): vibration toutes les \(String(format: "%.2f", maxCooldown))s\n"
        } else {
            stats += "   - Cooldown fixe: \(alertCooldown)s\n"
        }
        
        stats += "   - Total alertes: \(totalProximityAlerts)\n"
        stats += "   - Alertes danger: \(dangerAlerts)\n"
        stats += "   - Alertes avertissement: \(warningAlerts)"
        
        return stats
    }
    
    func resetStats() {
        totalProximityAlerts = 0
        dangerAlerts = 0
        warningAlerts = 0
        lastProximityAlert = Date.distantPast
        print("📳 Statistiques haptiques réinitialisées")
    }
    
    // MARK: - Settings
    
    func getDangerDistance() -> Float {
        return dangerDistance
    }
    
    func getWarningDistance() -> Float {
        return warningDistance
    }
    
    func getIntensityRange() -> (min: Float, max: Float) {
        return (min: minIntensity, max: maxIntensity)
    }
    
    func isGraduatedVibrationsEnabled() -> Bool {
        return graduatedVibrations
    }
    
    func isGraduatedFrequencyEnabled() -> Bool {
        return graduatedFrequency
    }
    
    func getFrequencyRange() -> (minCooldown: TimeInterval, maxCooldown: TimeInterval) {
        return (minCooldown: minCooldown, maxCooldown: maxCooldown)
    }
    
    func isProximityAlertsEnabled() -> Bool {
        return proximityAlertsEnabled
    }
    
    func setCooldown(_ seconds: TimeInterval) {
        alertCooldown = max(0.1, min(seconds, 3.0)) // Entre 0.1s et 3s
        print("⏱️ Cooldown des alertes défini à: \(alertCooldown)s")
    }
}
