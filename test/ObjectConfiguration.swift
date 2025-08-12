//
//  ObjectConfiguration.swift
//  VizAI Vision
//
//  Configuration uniforme des objets détectables avec propriétés statiques/dynamiques
//

import Foundation

// MARK: - Structure pour la configuration d'un objet

struct ObjectConfig {
    let type: String
    let displayName: String
    var isStatiqueByDefault: Bool  // MODIFIÉ: Maintenant modifiable par l'utilisateur
    var isDangerous: Bool        // Modifiable par l'utilisateur
    
    init(type: String, displayName: String, isStatiqueByDefault: Bool, isDangerous: Bool = false) {
        self.type = type.lowercased()
        self.displayName = displayName
        self.isStatiqueByDefault = isStatiqueByDefault
        self.isDangerous = isDangerous
    }
}

// MARK: - Gestionnaire unifié des objets

class ObjectConfigurationManager: ObservableObject {
    @Published var objectConfigs: [String: ObjectConfig] = [:]
    
    private weak var cameraManager: CameraManager?
    private let userDefaults = UserDefaults.standard
    private let dangerousObjectsKey = "dangerous_objects_configuration"
    private let objectTypesKey = "object_types_configuration"  // NOUVEAU: Pour sauvegarder les types modifiés
    
    // Configuration par défaut de tous les objets avec leur nature statique/dynamique
    private let defaultConfigurations: [ObjectConfig] = [
        // === OBJETS MOBILES/DYNAMIQUES ===
        // Personnes
        ObjectConfig(type: "person", displayName: "Personne", isStatiqueByDefault: false, isDangerous: true),
        ObjectConfig(type: "cyclist", displayName: "Cycliste", isStatiqueByDefault: false, isDangerous: true),
        ObjectConfig(type: "motorcyclist", displayName: "Motocycliste", isStatiqueByDefault: false, isDangerous: true),
        
        // Véhicules
        ObjectConfig(type: "car", displayName: "Voiture", isStatiqueByDefault: false, isDangerous: true),
        ObjectConfig(type: "truck", displayName: "Camion", isStatiqueByDefault: false, isDangerous: true),
        ObjectConfig(type: "bus", displayName: "Bus", isStatiqueByDefault: false, isDangerous: true),
        ObjectConfig(type: "motorcycle", displayName: "Moto", isStatiqueByDefault: false, isDangerous: true),
        ObjectConfig(type: "bicycle", displayName: "Vélo", isStatiqueByDefault: false, isDangerous: true),
        ObjectConfig(type: "slow_vehicle", displayName: "Véhicule lent", isStatiqueByDefault: false, isDangerous: true),
        ObjectConfig(type: "vehicle_group", displayName: "Groupe de véhicules", isStatiqueByDefault: false, isDangerous: true),
        ObjectConfig(type: "rail_vehicle", displayName: "Véhicule ferroviaire", isStatiqueByDefault: false, isDangerous: true),
        ObjectConfig(type: "boat", displayName: "Bateau", isStatiqueByDefault: false, isDangerous: false),
        
        // Animaux
        ObjectConfig(type: "animals", displayName: "Animaux", isStatiqueByDefault: false, isDangerous: false),
        
        // === OBJETS STATIQUES ===
        // Infrastructure routière
        ObjectConfig(type: "sidewalk", displayName: "Trottoir", isStatiqueByDefault: true, isDangerous: false),
        ObjectConfig(type: "road", displayName: "Route", isStatiqueByDefault: true, isDangerous: false),
        ObjectConfig(type: "crosswalk", displayName: "Passage piéton", isStatiqueByDefault: true, isDangerous: false),
        ObjectConfig(type: "driveway", displayName: "Allée", isStatiqueByDefault: true, isDangerous: false),
        ObjectConfig(type: "bike_lane", displayName: "Piste cyclable", isStatiqueByDefault: true, isDangerous: false),
        ObjectConfig(type: "parking_area", displayName: "Zone de stationnement", isStatiqueByDefault: true, isDangerous: false),
        ObjectConfig(type: "rail_track", displayName: "Voie ferrée", isStatiqueByDefault: true, isDangerous: false),
        ObjectConfig(type: "service_lane", displayName: "Voie de service", isStatiqueByDefault: true, isDangerous: false),
        ObjectConfig(type: "curb", displayName: "Bordure", isStatiqueByDefault: true, isDangerous: false),
        
        // Barrières et obstacles
        ObjectConfig(type: "wall", displayName: "Mur", isStatiqueByDefault: true, isDangerous: false),
        ObjectConfig(type: "fence", displayName: "Clôture", isStatiqueByDefault: true, isDangerous: false),
        ObjectConfig(type: "guard_rail", displayName: "Glissière de sécurité", isStatiqueByDefault: true, isDangerous: false),
        ObjectConfig(type: "barrier", displayName: "Barrière", isStatiqueByDefault: true, isDangerous: true),
        ObjectConfig(type: "temporary_barrier", displayName: "Barrière temporaire", isStatiqueByDefault: false, isDangerous: true), // Temporaire = peut bouger
        ObjectConfig(type: "barrier_other", displayName: "Autre barrière", isStatiqueByDefault: true, isDangerous: true),
        
        // Mobilier urbain et équipements
        ObjectConfig(type: "pole", displayName: "Poteau", isStatiqueByDefault: true, isDangerous: true),
        ObjectConfig(type: "traffic_light", displayName: "Feu de circulation", isStatiqueByDefault: true, isDangerous: false),
        ObjectConfig(type: "traffic_sign", displayName: "Panneau de signalisation", isStatiqueByDefault: true, isDangerous: false),
        ObjectConfig(type: "street_light", displayName: "Lampadaire", isStatiqueByDefault: true, isDangerous: false),
        ObjectConfig(type: "traffic_cone", displayName: "Cône de signalisation", isStatiqueByDefault: false, isDangerous: true), // Peut être déplacé
        ObjectConfig(type: "bench", displayName: "Banc", isStatiqueByDefault: true, isDangerous: false),
        ObjectConfig(type: "trash_can", displayName: "Poubelle", isStatiqueByDefault: false, isDangerous: false), // Peut être déplacée
        ObjectConfig(type: "fire_hydrant", displayName: "Bouche d'incendie", isStatiqueByDefault: true, isDangerous: false),
        ObjectConfig(type: "mailbox", displayName: "Boîte aux lettres", isStatiqueByDefault: true, isDangerous: false),
        ObjectConfig(type: "parking_meter", displayName: "Parcmètre", isStatiqueByDefault: true, isDangerous: false),
        ObjectConfig(type: "bike_rack", displayName: "Support à vélos", isStatiqueByDefault: true, isDangerous: false),
        ObjectConfig(type: "phone_booth", displayName: "Cabine téléphonique", isStatiqueByDefault: true, isDangerous: false),
        
        // Infrastructure souterraine/de surface
        ObjectConfig(type: "pothole", displayName: "Nid-de-poule", isStatiqueByDefault: true, isDangerous: false),
        ObjectConfig(type: "manhole", displayName: "Plaque d'égout", isStatiqueByDefault: true, isDangerous: false),
        ObjectConfig(type: "catch_basin", displayName: "Regard d'égout", isStatiqueByDefault: true, isDangerous: false),
        ObjectConfig(type: "water_valve", displayName: "Vanne d'eau", isStatiqueByDefault: true, isDangerous: false),
        ObjectConfig(type: "junction_box", displayName: "Boîtier de jonction", isStatiqueByDefault: true, isDangerous: false),
        
        // Bâtiments et structures
        ObjectConfig(type: "building", displayName: "Bâtiment", isStatiqueByDefault: true, isDangerous: false),
        ObjectConfig(type: "bridge", displayName: "Pont", isStatiqueByDefault: true, isDangerous: false),
        ObjectConfig(type: "tunnel", displayName: "Tunnel", isStatiqueByDefault: true, isDangerous: false),
        ObjectConfig(type: "garage", displayName: "Garage", isStatiqueByDefault: true, isDangerous: false),
        
        // Éléments naturels
        ObjectConfig(type: "vegetation", displayName: "Végétation", isStatiqueByDefault: true, isDangerous: false),
        ObjectConfig(type: "water", displayName: "Eau", isStatiqueByDefault: true, isDangerous: false),
        ObjectConfig(type: "terrain", displayName: "Terrain", isStatiqueByDefault: true, isDangerous: false)
    ]
    
    init(cameraManager: CameraManager) {
        self.cameraManager = cameraManager
        initializeConfigurations()
        loadSavedConfigurations()
    }
    
    private func initializeConfigurations() {
        // Initialiser avec les configurations par défaut
        for config in defaultConfigurations {
            objectConfigs[config.type] = config
        }
    }
    
    private func loadSavedConfigurations() {
        // Charger les préférences de danger
        if let savedData = userDefaults.data(forKey: dangerousObjectsKey),
           let savedConfigs = try? JSONDecoder().decode([String: Bool].self, from: savedData) {
            
            for (objectType, isDangerous) in savedConfigs {
                if var config = objectConfigs[objectType] {
                    config.isDangerous = isDangerous
                    objectConfigs[objectType] = config
                }
            }
        }
        
        // NOUVEAU: Charger les types statique/mobile modifiés
        if let savedTypesData = userDefaults.data(forKey: objectTypesKey),
           let savedTypes = try? JSONDecoder().decode([String: Bool].self, from: savedTypesData) {
            
            for (objectType, isStatique) in savedTypes {
                if var config = objectConfigs[objectType] {
                    config.isStatiqueByDefault = isStatique
                    objectConfigs[objectType] = config
                }
            }
        }
        
        synchronizeWithVoiceManager()
    }
    
    private func saveConfigurations() {
        // Sauvegarder les objets dangereux
        let dangerousSettings = objectConfigs.mapValues { $0.isDangerous }
        if let encoded = try? JSONEncoder().encode(dangerousSettings) {
            userDefaults.set(encoded, forKey: dangerousObjectsKey)
        }
        
        // NOUVEAU: Sauvegarder les types statique/mobile modifiés
        let typeSettings = objectConfigs.mapValues { $0.isStatiqueByDefault }
        if let encodedTypes = try? JSONEncoder().encode(typeSettings) {
            userDefaults.set(encodedTypes, forKey: objectTypesKey)
        }
    }
    
    func toggleDangerous(for objectType: String) {
        guard var config = objectConfigs[objectType] else { return }
        
        config.isDangerous.toggle()
        objectConfigs[objectType] = config
        
        saveConfigurations()
        synchronizeWithVoiceManager()
    }
    
    // NOUVEAU: Basculer le type statique/mobile
    func toggleStatiqueType(for objectType: String) {
        guard var config = objectConfigs[objectType] else { return }
        
        config.isStatiqueByDefault.toggle()
        objectConfigs[objectType] = config
        
        saveConfigurations()
        synchronizeWithVoiceManager()
    }
    
    // NOUVEAU: Définir explicitement le type statique/mobile
    func setStatiqueType(for objectType: String, isStatique: Bool) {
        guard var config = objectConfigs[objectType] else { return }
        
        config.isStatiqueByDefault = isStatique
        objectConfigs[objectType] = config
        
        saveConfigurations()
        synchronizeWithVoiceManager()
    }
    
    func isDangerous(_ objectType: String) -> Bool {
        return objectConfigs[objectType.lowercased()]?.isDangerous ?? false
    }
    
    func isStatique(_ objectType: String) -> Bool {
        return objectConfigs[objectType.lowercased()]?.isStatiqueByDefault ?? true
    }
    
    func getDangerousObjects() -> Set<String> {
        let dangerous = objectConfigs.values.filter { $0.isDangerous }.map { $0.type }
        return Set(dangerous)
    }
    
    func getAllConfigurations() -> [ObjectConfig] {
        return objectConfigs.values.sorted { $0.displayName < $1.displayName }
    }
    
    func getDynamicDangerousObjects() -> Set<String> {
        let dynamicDangerous = objectConfigs.values.filter {
            $0.isDangerous && !$0.isStatiqueByDefault
        }.map { $0.type }
        return Set(dynamicDangerous)
    }
    
    func getStatiquesDangerousObjects() -> Set<String> {
        let statiquesDangerous = objectConfigs.values.filter {
            $0.isDangerous && $0.isStatiqueByDefault
        }.map { $0.type }
        return Set(statiquesDangerous)
    }
    
    private func synchronizeWithVoiceManager() {
        let dangerousObjects = getDangerousObjects()
        let dynamicDangerousObjects = getDynamicDangerousObjects()
        
        // Mettre à jour le CameraManager avec les nouveaux paramètres
        cameraManager?.updateDangerousObjects(dangerousObjects)
        cameraManager?.updateDynamicDangerousObjects(dynamicDangerousObjects)
    }
    
    func resetToDefaults() {
        // Remettre tous les objets à leur configuration par défaut
        for defaultConfig in defaultConfigurations {
            objectConfigs[defaultConfig.type] = defaultConfig
        }
        
        saveConfigurations()
        synchronizeWithVoiceManager()
    }
    
    // Statistiques
    func getStats() -> (total: Int, dangerous: Int, statiques: Int, dynamic: Int) {
        let all = objectConfigs.values
        let dangerous = all.filter { $0.isDangerous }
        let statiquesDangerous = dangerous.filter { $0.isStatiqueByDefault }
        let dynamicDangerous = dangerous.filter { !$0.isStatiqueByDefault }
        
        return (
            total: all.count,
            dangerous: dangerous.count,
            statiques: statiquesDangerous.count,
            dynamic: dynamicDangerous.count
        )
    }
}

// MARK: - Extensions pour compatibilité

extension ObjectConfigurationManager {
    // Pour compatibilité avec l'ancien système
    func getAvailableClasses() -> [String] {
        return objectConfigs.keys.sorted()
    }
    
    // Pour obtenir le nom d'affichage
    func getDisplayName(for objectType: String) -> String {
        return objectConfigs[objectType.lowercased()]?.displayName ?? objectType.capitalized
    }
}
