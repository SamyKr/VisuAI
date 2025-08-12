//
//  ContentView.swift
//  VizAI Vision
//
//  RÔLE DANS L'ARCHITECTURE:
//  ContentView est l'ÉCRAN D'ACCUEIL PRINCIPAL de l'application - point d'entrée utilisateur
//
//  🏠 INTERFACE PRINCIPALE:
//  - Écran d'accueil avec logo animé (continuation de LoadingView via match move)
//  - Bouton principal vers DetectionView (cœur de l'application)
//  - Présentation visuelle des fonctionnalités disponibles selon l'appareil
//
//  🔍 VÉRIFICATION CAPACITÉS:
//  - Détection automatique disponibilité LiDAR (iPhone Pro/iPad Pro)
//  - Adaptation interface selon les capacités matérielles
//  - Information utilisateur sur fonctionnalités actives/limitées
//
//  🎨 EXPÉRIENCE UTILISATEUR:
//  - Design cohérent avec charte graphique verte VizAI
//  - Animation logo avec œil clignotant (respiration + clignement périodique)
//  - Interface accessible et informative pour utilisateurs malvoyants
//
//  📱 NAVIGATION:
//  - Point central vers DetectionView (session de détection temps réel)
//  - Informations contextuelles sur matériel et fonctionnalités
//  - Transition fluide vers l'expérience de détection
//
//  FLUX UTILISATEUR:
//  LoadingView → ContentView → DetectionView (session active)

import SwiftUI
import CoreML
import Vision

// MARK: - Vue Principale d'Accueil
struct ContentView: View {
    
    // MARK: - États Animation Logo
    @State private var eyeBlink: Bool = false // Contrôle clignement œil
    @State private var eyeBreath: Bool = false // Contrôle respiration œil
    
    var body: some View {
        NavigationView {
            ZStack {
                // Fond dégradé avec charte graphique VizAI
                backgroundGradient
                
                ScrollView {
                    VStack(spacing: 40) {
                        // Logo animé (même que LoadingView mais plus petit)
                        animatedLogoSection
                        
                        // Bouton principal vers détection temps réel
                        mainDetectionButton
                        
                        // Informations fonctionnalités selon appareil
                        FeaturesInfoView()
                            .padding(.bottom, 20)
                    }
                    .padding()
                }
            }
            .navigationTitle("VizAI Vision")
            .navigationBarHidden(true)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    // MARK: - Fond Dégradé
    private var backgroundGradient: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color(hex: "0a1f0a"), // Vert très sombre
                Color(hex: "56c228").opacity(0.08), // Vert foncé logo
                Color(hex: "5ee852").opacity(0.06), // Vert clair logo
                Color(hex: "0a1f0a") // Vert très sombre
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
    
    // MARK: - Section Logo Animé
    private var animatedLogoSection: some View {
        ZStack {
            // Logo base sans l'œil
            Image("logosansoeil")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 120, height: 120)
                .shadow(color: Color(hex: "5ee852").opacity(0.3), radius: 10, x: 0, y: 5)
            
            // Œil avec animations respiration + clignement
            Image("eye")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 34, height: 34)
                .rotationEffect(.degrees(11)) // Alignement avec logo
                .offset(x: -2, y: 0) // Positionnement précis
                .opacity(eyeBlink ? 0.1 : 1.0) // Effet clignement
                .scaleEffect(
                    eyeBlink ?
                    CGSize(width: 1.0, height: 0.1) : // Clignement vertical
                    CGSize(width: eyeBreath ? 1.05 : 1.0, height: eyeBreath ? 1.05 : 1.0) // Respiration
                )
                .shadow(color: Color(hex: "5ee852").opacity(0.6), radius: 8, x: 0, y: 0)
        }
        .onAppear {
            startEyeAnimations()
        }
        .padding(.top, 40)
    }
    
    // MARK: - Bouton Principal Détection
    private var mainDetectionButton: some View {
        NavigationLink(destination: DetectionView()) {
            VStack(spacing: 20) {
                // Icônes et indicateurs fonctionnalités
                featureIndicators
                
                // Titre principal
                Text("Détecter en temps réel")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(Color(hex: "5ee852"))
                
                // Liste fonctionnalités disponibles
                featuresList
            }
            .frame(maxWidth: .infinity)
            .padding(40)
            .background(buttonGradientBackground)
            .cornerRadius(20)
            .overlay(buttonBorder)
            .shadow(color: Color(hex: "5ee852").opacity(0.2), radius: 10, x: 0, y: 5)
        }
        .padding(.horizontal)
    }
    
    // MARK: - Indicateurs Fonctionnalités
    private var featureIndicators: some View {
        HStack(spacing: 15) {
            Image(systemName: "camera.fill")
                .font(.system(size: 50))
                .foregroundColor(Color(hex: "5ee852"))
            
            VStack(spacing: 8) {
                // Indicateur LiDAR
                HStack(spacing: 8) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 20))
                        .foregroundColor(Color(hex: "56c228"))
                    Text("LiDAR")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(Color(hex: "56c228"))
                }
                
                // Indicateur tracking
                HStack(spacing: 8) {
                    Image(systemName: "target")
                        .font(.system(size: 20))
                        .foregroundColor(Color(hex: "5ee852"))
                    Text("Tracking")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(Color(hex: "5ee852"))
                }
                
                // Indicateur interaction vocale
                HStack(spacing: 8) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 20))
                        .foregroundColor(Color(hex: "f0fff0"))
                    Text("Voice AI")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(Color(hex: "f0fff0"))
                }
            }
        }
    }
    
    // MARK: - Liste Fonctionnalités
    private var featuresList: some View {
        VStack(spacing: 8) {
            Text("+ Distances LiDAR")
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(Color(hex: "56c228"))
            
            Text("+ Tracking coloré persistant")
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(Color(hex: "5ee852"))
            
            Text("+ Interaction vocale intelligente")
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(Color(hex: "f0fff0"))
        }
    }
    
    // MARK: - Style Bouton Principal
    private var buttonGradientBackground: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color(hex: "5ee852").opacity(0.15),
                Color(hex: "56c228").opacity(0.1),
                Color(hex: "f0fff0").opacity(0.05),
                Color(hex: "0a1f0a").opacity(0.1)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private var buttonBorder: some View {
        RoundedRectangle(cornerRadius: 20)
            .stroke(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(hex: "5ee852").opacity(0.5),
                        Color(hex: "56c228").opacity(0.3),
                        Color(hex: "f0fff0").opacity(0.2)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 2
            )
    }
    
    // MARK: - Animations Logo
    
    /// Lance les animations de l'œil (respiration continue + clignement périodique)
    private func startEyeAnimations() {
        // Animation respiration continue (2 secondes cycle)
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
            eyeBreath = true
        }
        
        // Clignement périodique (démarre après 1 seconde)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            blinkEyePeriodically()
        }
    }
    
    /// Gère le clignement périodique de l'œil (toutes les 7 secondes)
    private func blinkEyePeriodically() {
        // Animation clignement rapide (0.1s fermeture + 0.1s ouverture)
        withAnimation(.easeInOut(duration: 0.1)) {
            eyeBlink = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeInOut(duration: 0.1)) {
                eyeBlink = false
            }
        }
        
        // Programmer le prochain clignement dans 7 secondes
        DispatchQueue.main.asyncAfter(deadline: .now() + 7.0) {
            blinkEyePeriodically()
        }
    }
}

// MARK: - Vue Informations Fonctionnalités
struct FeaturesInfoView: View {
    
    // MARK: - États Vue
    @State private var lidarAvailable = false // Disponibilité LiDAR sur appareil
    @State private var isExpanded = false // État section collapsible
    
    var body: some View {
        VStack(spacing: 12) {
            // En-tête cliquable pour expansion/contraction
            expandableHeader
            
            // Liste fonctionnalités (collapsible)
            if isExpanded {
                featuresListView
            }
        }
        .padding(16)
        .background(Color(hex: "56c228").opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(hex: "5ee852").opacity(0.3), lineWidth: 1)
        )
        .onAppear {
            checkLiDARAvailability()
        }
    }
    
    // MARK: - En-tête Collapsible
    private var expandableHeader: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.3)) {
                isExpanded.toggle()
            }
        }) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(Color(hex: "5ee852"))
                    .font(.title3)
                
                Text("Fonctionnalités disponibles")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(Color(hex: "f0fff0"))
                
                Spacer()
                
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .foregroundColor(Color(hex: "5ee852"))
                    .font(.title3)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .animation(.easeInOut(duration: 0.3), value: isExpanded)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Liste Fonctionnalités Détaillée
    private var featuresListView: some View {
        VStack(spacing: 8) {
            FeatureRowView(
                icon: "camera.fill",
                iconColor: Color(hex: "5ee852"),
                title: "Détection YOLOv11",
                description: "Reconnaissance d'objets en temps réel",
                available: true
            )
            
            FeatureRowView(
                icon: "target",
                iconColor: Color(hex: "56c228"),
                title: "Tracking coloré",
                description: "Suivi persistant des objets avec couleurs uniques",
                available: true
            )
            
            FeatureRowView(
                icon: "location.fill",
                iconColor: Color(hex: "5ee852"),
                title: "LiDAR",
                description: lidarAvailable ? "Mesure de distances en temps réel" : "Non disponible sur cet appareil",
                available: lidarAvailable
            )
            
            FeatureRowView(
                icon: "iphone.radiowaves.left.and.right",
                iconColor: Color(hex: "56c228"),
                title: "Alertes proximité",
                description: lidarAvailable ? "Vibrations selon la distance des objets" : "Nécessite LiDAR",
                available: lidarAvailable
            )
            
            FeatureRowView(
                icon: "speaker.wave.2.fill",
                iconColor: Color(hex: "5ee852"),
                title: "Synthèse vocale",
                description: "Annonces automatiques des objets importants",
                available: true
            )
            
            FeatureRowView(
                icon: "mic.fill",
                iconColor: Color(hex: "56c228"),
                title: "Interaction vocale",
                description: "Posez vos questions : 'Y a-t-il une voiture ?'",
                available: true
            )
        }
        .transition(.asymmetric(
            insertion: .scale(scale: 0.95).combined(with: .opacity).combined(with: .move(edge: .top)),
            removal: .scale(scale: 0.95).combined(with: .opacity).combined(with: .move(edge: .top))
        ))
    }
    
    // MARK: - Vérification Capacités Appareil
    
    /// Vérifie la disponibilité du LiDAR sur l'appareil actuel
    private func checkLiDARAvailability() {
        let lidarManager = LiDARManager()
        lidarAvailable = lidarManager.isAvailable()
    }
}

// MARK: - Vue Ligne Fonctionnalité
struct FeatureRowView: View {
    
    // MARK: - Paramètres Ligne
    let icon: String // Nom icône SF Symbols
    let iconColor: Color // Couleur icône
    let title: String // Titre fonctionnalité
    let description: String // Description détaillée
    let available: Bool // Disponibilité sur appareil
    
    var body: some View {
        HStack(spacing: 12) {
            // Icône avec indicateur disponibilité
            Image(systemName: available ? icon : "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundColor(available ? iconColor : .orange)
                .frame(width: 24, height: 24)
            
            // Informations fonctionnalité
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(available ? Color(hex: "f0fff0") : Color(hex: "f0fff0").opacity(0.6))
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(Color(hex: "f0fff0").opacity(0.7))
                    .multilineTextAlignment(.leading)
            }
            
            Spacer()
            
            // Indicateur statut
            Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(available ? Color(hex: "5ee852") : .red)
                .font(.caption)
        }
        .opacity(available ? 1.0 : 0.7) // Réduction opacité si non disponible
    }
}
