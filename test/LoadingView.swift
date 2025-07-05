import SwiftUI

// Extension pour supporter les couleurs hexadécimales
extension Color {
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

struct LoadingView: View {
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
            // Fond animé avec pulsation
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(hex: "0a1f0a").opacity(0.98), // Vert très sombre
                    Color(hex: "56c228").opacity(backgroundPulse ? 0.15 : 0.08), // Vert foncé du logo
                    Color(hex: "5ee852").opacity(backgroundPulse ? 0.12 : 0.06), // Vert clair du logo
                    Color(hex: "0a1f0a").opacity(0.95) // Vert très sombre
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: backgroundPulse)
            
            // Particules flottantes
            ForEach(0..<15, id: \.self) { index in
                let particleColors = [Color(hex: "5ee852"), Color(hex: "56c228"), Color.white, Color(hex: "5ee852"), Color(hex: "56c228")]
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
                
                // Logo avec animation complexe
                ZStack {
                    // Cercle de lueur extérieure
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [
                                    Color(hex: "5ee852").opacity(glowIntensity * 0.4), // Vert clair principal
                                    Color(hex: "56c228").opacity(glowIntensity * 0.3), // Vert foncé
                                    Color.white.opacity(glowIntensity * 0.2), // Blanc
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
                    
                    // Logo sans l'œil (arrière-plan)
                    Image("logosansoeil")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 150, height: 150)
                        .scaleEffect(logoScale)
                        .rotationEffect(.degrees(rotationAngle))
                        .shadow(color: Color(hex: "5ee852").opacity(0.6), radius: 15, x: 0, y: 8)
                        .shadow(color: Color(hex: "56c228").opacity(0.4), radius: 25, x: 0, y: 12)
                        .shadow(color: .white.opacity(0.3), radius: 35, x: 0, y: 15)
                    
                    // Œil qui apparaît progressivement avec effet spectaculaire
                    ZStack {
                        // Halo autour de l'œil
                        if eyeGlow {
                            Circle()
                                .fill(
                                    RadialGradient(
                                        gradient: Gradient(colors: [
                                            Color(hex: "5ee852").opacity(0.7), // Vert clair
                                            Color(hex: "56c228").opacity(0.5), // Vert foncé
                                            Color.white.opacity(0.3), // Blanc
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
                        
                        // L'œil principal (ne tourne PAS avec le logo)
                        Image("eye")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .offset(x: -2, y: 0)
                            .frame(width: 42, height: 42) // Taille réduite
                            .rotationEffect(.degrees(11)) // Rotation de 11° pour alignement
                            .opacity(eyeBlink ? 0.1 : eyeOpacity) // Effet de clignement
                            .scaleEffect(eyeBlink ? CGSize(width: 1.0, height: 0.1) : CGSize(width: eyeScale, height: eyeScale)) // Clignement vertical
                            .shadow(color: Color(hex: "5ee852").opacity(0.8), radius: 10, x: 0, y: 0)
                            .shadow(color: Color(hex: "56c228").opacity(0.6), radius: 20, x: 0, y: 0)
                            .shadow(color: .white.opacity(0.4), radius: 30, x: 0, y: 0)
                            .scaleEffect(pulseAnimation ? 1.1 : 1.0)
                    }
                }
                .onAppear {
                    startLoadingAnimation()
                }
                
                // Titre avec animation élégante
                if showTitle {
                    VStack(spacing: 16) {
                        Text("VizAI")
                            .font(.system(size: 42, weight: .heavy, design: .rounded))
                            .foregroundColor(Color(hex: "f0fff0")) // Blanc très légèrement vert
                            .shadow(color: Color(hex: "5ee852").opacity(0.5), radius: 10, x: 0, y: 5)
                            .scaleEffect(showTitle ? 1 : 0.8)
                            .opacity(showTitle ? 1 : 0)
                            .offset(y: showTitle ? 0 : 30)
                        
                        if showSubtitle {
                            Text("Vision Beyond Eyes")
                                .font(.system(size: 18, weight: .medium, design: .rounded))
                                .foregroundColor(Color(hex: "f0fff0").opacity(0.9)) // Blanc très légèrement vert
                                .shadow(color: Color(hex: "56c228").opacity(0.3), radius: 5, x: 0, y: 2)
                                .scaleEffect(showSubtitle ? 1 : 0.8)
                                .opacity(showSubtitle ? 1 : 0)
                                .offset(y: showSubtitle ? 0 : 20)
                        }
                    }
                }
                
                Spacer()
                
                // Indicateur de chargement amélioré
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
                        .foregroundColor(Color(hex: "f0fff0").opacity(0.8)) // Blanc très légèrement vert
                        .opacity(showTitle ? 1 : 0)
                }
                .padding(.bottom, 60)
            }
        }
    }
    
    private func startLoadingAnimation() {
        // Démarrage immédiat des effets de fond
        withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
            backgroundPulse = true
        }
        
        // Phase 1: Apparition dramatique du logo (0-1.2s)
        withAnimation(.spring(response: 1.2, dampingFraction: 0.6, blendDuration: 0)) {
            logoScale = 1.0
        }
        
        withAnimation(.easeOut(duration: 0.8).delay(0.3)) {
            glowIntensity = 0.8
        }
        
        // Phase 2: Rotation élégante du logo (0.8-2.5s)
        withAnimation(.easeInOut(duration: 1.7).delay(0.8)) {
            rotationAngle = 720 // Double rotation pour plus d'effet
        }
        
        // Phase 3: Apparition des particules (1.0s)
        withAnimation(.easeOut(duration: 1.0).delay(1.0)) {
            particlesOpacity = 1.0
        }
        
        // Phase 4: Apparition spectaculaire de l'œil (1.8-3.2s)
        withAnimation(.spring(response: 1.0, dampingFraction: 0.5, blendDuration: 0).delay(1.8)) {
            eyeOpacity = 1.0
            eyeScale = 1.0
            eyeGlow = true
        }
        
        // Phase 5: Effet de glow plus intense sur l'œil (2.5s)
        withAnimation(.easeOut(duration: 0.8).delay(2.5)) {
            glowIntensity = 1.0
        }
        
        // Phase 6: Affichage du titre principal (3.0s)
        withAnimation(.spring(response: 0.8, dampingFraction: 0.7, blendDuration: 0).delay(3.0)) {
            showTitle = true
        }
        
        // Phase 7: Affichage du sous-titre (3.5s)
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8, blendDuration: 0).delay(3.5)) {
            showSubtitle = true
        }
        
        // Phase 8: Animations continues (4.0s+)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            // Pulsation continue de l'œil
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulseAnimation = true
            }
            
            // SUPPRIMÉ: Plus de rotation continue
            // withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
            //     rotationAngle += 360
            // }
        }
        
        // Effet supplémentaire: clignement de l'œil à intervalles (5.0s+)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            blinkEyePeriodically()
        }
    }
    
    private func blinkEyePeriodically() {
        // Animation de clignement rapide
        withAnimation(.easeInOut(duration: 0.1)) {
            eyeBlink = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeInOut(duration: 0.1)) {
                eyeBlink = false
            }
        }
        
        // Clignement aléatoire entre 2 et 5 secondes
        let nextBlinkDelay = Double.random(in: 2.0...5.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + nextBlinkDelay) {
            blinkEyePeriodically()
        }
    }
}

// Vue principale qui gère le chargement
struct MainAppView: View {
    @State private var isLoading = true
    
    var body: some View {
        Group {
            if isLoading {
                LoadingView()
                    .onAppear {
                        // Durée totale du chargement (6 secondes pour profiter de l'animation)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
                            withAnimation(.easeInOut(duration: 1.0)) {
                                isLoading = false
                            }
                        }
                    }
            } else {
                ContentView()
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.8).combined(with: .opacity).combined(with: .move(edge: .bottom)),
                        removal: .scale(scale: 1.2).combined(with: .opacity).combined(with: .move(edge: .top))
                    ))
            }
        }
    }
}

// Prévisualisation
struct LoadingView_Previews: PreviewProvider {
    static var previews: some View {
        MainAppView() // Affiche la vue complète avec gestion du chargement
            .preferredColorScheme(.dark) // Force le mode sombre pour mieux voir l'effet
    }
}
