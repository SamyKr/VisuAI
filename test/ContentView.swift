import SwiftUI
import CoreML
import Vision



struct ContentView: View {
    @State private var eyeBlink: Bool = false
    @State private var eyeBreath: Bool = false
    
    var body: some View {
        NavigationView {
            ZStack {
                // Fond avec la charte graphique verte
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(hex: "0a1f0a"),
                        Color(hex: "56c228").opacity(0.08),
                        Color(hex: "5ee852").opacity(0.06),
                        Color(hex: "0a1f0a")
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 40) {
                        // En-tête avec SEULEMENT le logo animé (pas de texte)
                        ZStack {
                            // Logo sans l'œil (arrière-plan)
                            Image("logosansoeil")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 120, height: 120)
                                .shadow(color: Color(hex: "5ee852").opacity(0.3), radius: 10, x: 0, y: 5)
                            
                            // Œil qui respire et cligne
                            Image("eye")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 34, height: 34)
                                .rotationEffect(.degrees(11))
                                .offset(x: -2, y: 0) // Décalage de 3 pixels vers la gauche
                                .opacity(eyeBlink ? 0.1 : 1.0)
                                .scaleEffect(
                                    eyeBlink ?
                                    CGSize(width: 1.0, height: 0.1) :
                                    CGSize(width: eyeBreath ? 1.05 : 1.0, height: eyeBreath ? 1.05 : 1.0)
                                )
                                .shadow(color: Color(hex: "5ee852").opacity(0.6), radius: 8, x: 0, y: 0)
                        }
                        .onAppear {
                            startEyeAnimations()
                        }
                        .padding(.top, 40)
                        
                        // Bouton principal de détection temps réel
                        NavigationLink(destination: DetectionView()) {
                            VStack(spacing: 20) {
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
                                
                                Text("Détecter en temps réel")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(Color(hex: "5ee852"))
                                
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
                            .frame(maxWidth: .infinity)
                            .padding(40)
                            .background(
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
                            )
                            .cornerRadius(20)
                            .overlay(
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
                            )
                            .shadow(color: Color(hex: "5ee852").opacity(0.2), radius: 10, x: 0, y: 5)
                        }
                        .padding(.horizontal)
                        
                        // Information sur les fonctionnalités
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
    
    private func startEyeAnimations() {
        // Animation de respiration continue
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
            eyeBreath = true
        }
        
        // Clignement périodique toutes les 7 secondes
        blinkEyePeriodically()
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
        
        // Clignement suivant dans 7 secondes
        DispatchQueue.main.asyncAfter(deadline: .now() + 7.0) {
            blinkEyePeriodically()
        }
    }
}

// Vue d'information sur les fonctionnalités disponibles
struct FeaturesInfoView: View {
    @State private var lidarAvailable = false
    @State private var isExpanded = false
    
    var body: some View {
        VStack(spacing: 12) {
            // En-tête cliquable
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
            
            // Liste des fonctionnalités (collapsible)
            if isExpanded {
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
    
    private func checkLiDARAvailability() {
        let lidarManager = LiDARManager()
        lidarAvailable = lidarManager.isAvailable()
    }
}

struct FeatureRowView: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let available: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: available ? icon : "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundColor(available ? iconColor : .orange)
                .frame(width: 24, height: 24)
            
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
            
            Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(available ? Color(hex: "5ee852") : .red)
                .font(.caption)
        }
        .opacity(available ? 1.0 : 0.7)
    }
}
