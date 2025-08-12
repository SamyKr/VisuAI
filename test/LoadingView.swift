//
//  LoadingView.swift
//  VizAI Vision
//
//  RÔLE DANS L'ARCHITECTURE:
//  - Écran de chargement initial avec animation sophistiquée du logo
//  - Gestion de la transition vers questionnaire (première utilisation) ou app principale
//  - Vérification automatique du statut de configuration utilisateur
//  - Animation avec match move pour transition fluide vers ContentView
//
//  FONCTIONNALITÉS:
//  - Animation logo en 8 phases (6 secondes) avec effets visuels avancés
//  - Particules flottantes et effets de glow
//  - Clignement périodique de l'œil du logo
//  - Détection automatique profil utilisateur complet/incomplet
//  - Transition intelligente selon le statut utilisateur

import SwiftUI

// MARK: - Extension Color pour couleurs hexadécimales
extension Color {
    /// Initialise une couleur à partir d'une chaîne hexadécimale
    /// - Parameter hex: Code couleur hex (3, 6 ou 8 caractères)
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Vue de Chargement Principale
struct LoadingView: View {
    let logoNamespace: Namespace.ID // Namespace pour animation match move vers ContentView
    
    // États d'animation du logo et des effets
    @State private var eyeOpacity: Double = 0
    @State private var eyeScale: CGFloat = 0.3
    @State private var logoScale: CGFloat = 0.5
    @State private var rotationAngle: Double = 0
    @State private var showTitle: Bool = false
    @State private var pulseAnimation: Bool = false
    @State private var glowIntensity: Double = 0
    @State private var particlesOpacity: Double = 0
    @State private var backgroundPulse: Bool = false
    @State private var eyeGlow: Bool = false
    @State private var showSubtitle: Bool = false
    @State private var eyeBlink: Bool = false
    
    var body: some View {
        ZStack {
            // Fond dégradé animé avec pulsation
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(hex: "0a1f0a").opacity(0.98),
                    Color(hex: "56c228").opacity(backgroundPulse ? 0.15 : 0.08),
                    Color(hex: "5ee852").opacity(backgroundPulse ? 0.12 : 0.06),
                    Color(hex: "0a1f0a").opacity(0.95)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: backgroundPulse)
            
            // Particules flottantes décoratives
            ForEach(0..<15, id: \.self) { index in
                let particleColors = [Color(hex: "5ee852"), Color(hex: "56c228"), Color.white]
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [particleColors[index % particleColors.count].opacity(0.4), Color.clear]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: CGFloat.random(in: 2...6))
                    .position(
                        x: CGFloat.random(in: 0...UIScreen.main.bounds.width),
                        y: CGFloat.random(in: 0...UIScreen.main.bounds.height)
                    )
                    .opacity(particlesOpacity)
                    .animation(
                        .easeInOut(duration: Double.random(in: 2...4))
                        .repeatForever(autoreverses: true)
                        .delay(Double.random(in: 0...2)),
                        value: particlesOpacity
                    )
            }
            
            VStack(spacing: 40) {
                Spacer()
                
                // Logo animé avec effets complexes
                logoAnimationView
                
                // Titre et sous-titre avec apparition progressive
                titleSection
                
                Spacer()
                
                // Indicateur de chargement
                loadingIndicator
            }
        }
    }
    
    // MARK: - Logo avec Animation Complexe
    private var logoAnimationView: some View {
        ZStack {
            // Cercle de lueur extérieure
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color(hex: "5ee852").opacity(glowIntensity * 0.4),
                            Color(hex: "56c228").opacity(glowIntensity * 0.3),
                            Color.white.opacity(glowIntensity * 0.2),
                            Color.clear
                        ]),
                        center: .center,
                        startRadius: 10,
                        endRadius: 100
                    )
                )
                .frame(width: 200, height: 200)
                .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                .opacity(glowIntensity)
            
            // Logo base sans l'œil
            Image("logosansoeil")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 150, height: 150)
                .scaleEffect(logoScale)
                .rotationEffect(.degrees(rotationAngle))
                .shadow(color: Color(hex: "5ee852").opacity(0.6), radius: 15, x: 0, y: 8)
                .matchedGeometryEffect(id: "logoBase", in: logoNamespace)
            
            // Œil avec effets visuels
            eyeAnimationView
        }
        .onAppear {
            startLoadingAnimation()
        }
    }
    
    // MARK: - Animation de l'Œil
    private var eyeAnimationView: some View {
        ZStack {
            // Halo autour de l'œil
            if eyeGlow {
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [
                                Color(hex: "5ee852").opacity(0.7),
                                Color(hex: "56c228").opacity(0.5),
                                Color.white.opacity(0.3),
                                Color.clear
                            ]),
                            center: .center,
                            startRadius: 5,
                            endRadius: 40
                        )
                    )
                    .frame(width: 80, height: 80)
                    .scaleEffect(pulseAnimation ? 1.3 : 1.0)
                    .opacity(eyeOpacity)
            }
            
            // Œil principal avec clignement
            Image("eye")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 42, height: 42)
                .rotationEffect(.degrees(11)) // Alignement avec le logo
                .offset(x: -3, y: 0)
                .opacity(eyeBlink ? 0.1 : eyeOpacity)
                .scaleEffect(eyeBlink ? CGSize(width: 1.0, height: 0.1) : CGSize(width: eyeScale, height: eyeScale))
                .shadow(color: Color(hex: "5ee852").opacity(0.8), radius: 10, x: 0, y: 0)
                .scaleEffect(pulseAnimation ? 1.1 : 1.0)
                .matchedGeometryEffect(id: "logoEye", in: logoNamespace)
        }
    }
    
    // MARK: - Section Titre et Sous-titre
    private var titleSection: some View {
        VStack(spacing: 16) {
            if showTitle {
                Text("VizAI")
                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                    .foregroundColor(Color(hex: "f0fff0"))
                    .shadow(color: Color(hex: "5ee852").opacity(0.5), radius: 10, x: 0, y: 5)
                    .scaleEffect(showTitle ? 1 : 0.8)
                    .opacity(showTitle ? 1 : 0)
                    .offset(y: showTitle ? 0 : 30)
                
                if showSubtitle {
                    Text("Vision Beyond Eyes")
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundColor(Color(hex: "f0fff0").opacity(0.9))
                        .shadow(color: Color(hex: "56c228").opacity(0.3), radius: 5, x: 0, y: 2)
                        .scaleEffect(showSubtitle ? 1 : 0.8)
                        .opacity(showSubtitle ? 1 : 0)
                        .offset(y: showSubtitle ? 0 : 20)
                }
            }
        }
    }
    
    // MARK: - Indicateur de Chargement
    private var loadingIndicator: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(Color(hex: "56c228").opacity(0.3), lineWidth: 3)
                    .frame(width: 40, height: 40)
                
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [Color(hex: "5ee852"), Color(hex: "56c228")]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: 40, height: 40)
                    .rotationEffect(.degrees(rotationAngle))
            }
            
            Text("Initialisation de l'IA...")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(Color(hex: "f0fff0").opacity(0.8))
                .opacity(showTitle ? 1 : 0)
        }
        .padding(.bottom, 60)
    }
    
    // MARK: - Séquence d'Animation Complète (8 phases)
    /// Lance la séquence d'animation du logo en 8 phases sur 6 secondes
    private func startLoadingAnimation() {
        // Phase 1: Pulsation du fond
        withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
            backgroundPulse = true
        }
        
        // Phase 2: Apparition du logo (0-1.2s)
        withAnimation(.spring(response: 1.2, dampingFraction: 0.6, blendDuration: 0)) {
            logoScale = 1.0
        }
        
        withAnimation(.easeOut(duration: 0.8).delay(0.3)) {
            glowIntensity = 0.8
        }
        
        // Phase 3: Rotation du logo (0.8-2.5s)
        withAnimation(.easeInOut(duration: 1.7).delay(0.8)) {
            rotationAngle = 720 // Double rotation
        }
        
        // Phase 4: Particules (1.0s)
        withAnimation(.easeOut(duration: 1.0).delay(1.0)) {
            particlesOpacity = 1.0
        }
        
        // Phase 5: Apparition de l'œil (1.8-3.2s)
        withAnimation(.spring(response: 1.0, dampingFraction: 0.5, blendDuration: 0).delay(1.8)) {
            eyeOpacity = 1.0
            eyeScale = 1.0
            eyeGlow = true
        }
        
        // Phase 6: Intensification glow (2.5s)
        withAnimation(.easeOut(duration: 0.8).delay(2.5)) {
            glowIntensity = 1.0
        }
        
        // Phase 7: Titre principal (3.0s)
        withAnimation(.spring(response: 0.8, dampingFraction: 0.7, blendDuration: 0).delay(3.0)) {
            showTitle = true
        }
        
        // Phase 8: Sous-titre (3.5s)
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8, blendDuration: 0).delay(3.5)) {
            showSubtitle = true
        }
        
        // Animation continue (4.0s+)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulseAnimation = true
            }
        }
        
        // Clignement périodique (5.0s+)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            blinkEyePeriodically()
        }
    }
    
    // MARK: - Clignement Périodique
    /// Lance le clignement périodique de l'œil toutes les 2-5 secondes
    private func blinkEyePeriodically() {
        withAnimation(.easeInOut(duration: 0.1)) {
            eyeBlink = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeInOut(duration: 0.1)) {
                eyeBlink = false
            }
        }
        
        // Clignement suivant aléatoire
        let nextBlinkDelay = Double.random(in: 2.0...5.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + nextBlinkDelay) {
            blinkEyePeriodically()
        }
    }
}

// MARK: - Vue Principale avec Gestion de Flux
struct MainAppView: View {
    @StateObject private var questionnaireManager = QuestionnaireManager()
    @State private var isLoading = true
    @State private var showQuestionnaire = false
    @Namespace private var logoAnimation // Namespace pour match move
    
    var body: some View {
        ZStack {
            if isLoading {
                LoadingView(logoNamespace: logoAnimation)
                    .onAppear {
                        // Durée d'animation complète: 6 secondes
                        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
                            withAnimation(.easeInOut(duration: 1.0)) {
                                isLoading = false
                                checkQuestionnaireStatus()
                            }
                        }
                    }
            } else if showQuestionnaire {
                QuestionnaireView() // Première utilisation
            } else {
                ContentView() // App principale
            }
        }
    }
    
    // MARK: - Vérification Statut Questionnaire
    /// Vérifie si l'utilisateur a complété le questionnaire initial (3 questions)
    /// Redirige vers questionnaire si profil incomplet, sinon vers app principale
    private func checkQuestionnaireStatus() {
        let hasCompleteProfile = questionnaireManager.responses.count > 2
        
        if hasCompleteProfile {
            showQuestionnaire = false // → App principale
        } else {
            showQuestionnaire = true // → Questionnaire
        }
    }
}

// MARK: - Preview
struct LoadingView_Previews: PreviewProvider {
    static var previews: some View {
        MainAppView()
            .preferredColorScheme(.dark)
    }
}
