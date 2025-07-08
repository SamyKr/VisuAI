//
//  ProfileView.swift
//  test
//
//  Created by Samy 📍 on 07/07/2025.
//
import SwiftUI
import AVFoundation



// Structure pour les questions
struct Question {
    let id: Int
    let text: String
    let spokenText: String // Texte complet pour la synthèse vocale
}

// Gestionnaire de sauvegarde
class QuestionnaireManager: ObservableObject {
    @Published var responses: [Int: Bool] = [:]
    
    private let userDefaults = UserDefaults.standard
    private let responsesKey = "questionnaire_responses"
    
    init() {
        loadResponses()
    }
    
    func saveResponse(questionId: Int, response: Bool) {
        responses[questionId] = response
        saveResponses()
    }
    
    private func saveResponses() {
        let data = try? JSONEncoder().encode(responses)
        userDefaults.set(data, forKey: responsesKey)
    }
    
    private func loadResponses() {
        guard let data = userDefaults.data(forKey: responsesKey),
              let savedResponses = try? JSONDecoder().decode([Int: Bool].self, from: data) else {
            return
        }
        responses = savedResponses
    }
    
    func clearResponses() {
        responses.removeAll()
        userDefaults.removeObject(forKey: responsesKey)
    }
}

struct QuestionnaireView: View {
    @StateObject private var manager = QuestionnaireManager()
    @StateObject private var speechSynthesizer = SpeechSynthesizer()
    
    @State private var currentQuestionIndex = 0
    @State private var isComplete = false
    @State private var hasAnswered = false
    
    // Les 5 questions du questionnaire
    private let questions = [
        Question(
            id: 1,
            text: "Utilisez-vous régulièrement des applications de navigation ?",
            spokenText: "Question 1 sur 5. Utilisez-vous régulièrement des applications de navigation ? Appuyez à gauche de l'écran pour non, à droite pour oui."
        ),
        Question(
            id: 2,
            text: "Souhaitez-vous être averti des obstacles à distance ?",
            spokenText: "Question 2 sur 5. Souhaitez-vous être averti des obstacles à distance ? Appuyez à gauche de l'écran pour non, à droite pour oui."
        ),
        Question(
            id: 3,
            text: "Préférez-vous les alertes vocales aux vibrations ?",
            spokenText: "Question 3 sur 5. Préférez-vous les alertes vocales aux vibrations ? Appuyez à gauche de l'écran pour non, à droite pour oui."
        ),
        Question(
            id: 4,
            text: "Utilisez-vous fréquemment les transports en commun ?",
            spokenText: "Question 4 sur 5. Utilisez-vous fréquemment les transports en commun ? Appuyez à gauche de l'écran pour non, à droite pour oui."
        ),
        Question(
            id: 5,
            text: "Souhaitez-vous des descriptions détaillées de l'environnement ?",
            spokenText: "Question 5 sur 5. Souhaitez-vous des descriptions détaillées de l'environnement ? Appuyez à gauche de l'écran pour non, à droite pour oui."
        )
    ]
    
    var body: some View {
        ZStack {
            // Fond avec la même charte graphique
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
            
            if isComplete {
                // Vue de fin
                VStack(spacing: 40) {
                    Spacer()
                    
                    VStack(spacing: 20) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 80))
                            .foregroundColor(Color(hex: "5ee852"))
                        
                        Text("Questionnaire terminé !")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(Color(hex: "f0fff0"))
                            .multilineTextAlignment(.center)
                        
                        Text("Vos réponses ont été sauvegardées")
                            .font(.title2)
                            .foregroundColor(Color(hex: "f0fff0").opacity(0.8))
                            .multilineTextAlignment(.center)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        // Auto-redirect vers MainAppView qui détectera le profil complet
                        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                           let window = windowScene.windows.first {
                            window.rootViewController = UIHostingController(rootView: MainAppView())
                        }
                    }) {
                        Text("Commencer l'expérience")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(Color(hex: "0a1f0a"))
                            .frame(maxWidth: .infinity)
                            .padding(20)
                            .background(Color(hex: "5ee852"))
                            .cornerRadius(15)
                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 40)
                }
                .onAppear {
                    speechSynthesizer.speak("Questionnaire terminé ! Vos réponses ont été sauvegardées. Appuyez sur le bouton pour commencer l'expérience.")
                }
                
            } else {
                // Vue du questionnaire
                VStack(spacing: 0) {
                    // Zone de question en haut
                    VStack(spacing: 30) {
                        Text("Question \(currentQuestionIndex + 1)/\(questions.count)")
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundColor(Color(hex: "5ee852"))
                        
                        Text(questions[currentQuestionIndex].text)
                            .font(.title)
                            .fontWeight(.semibold)
                            .foregroundColor(Color(hex: "f0fff0"))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                            .accessibilityLabel(questions[currentQuestionIndex].spokenText)
                        
                        Text("Appuyez à gauche pour NON, à droite pour OUI")
                            .font(.headline)
                            .foregroundColor(Color(hex: "f0fff0").opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                    .padding(.bottom, 40)
                    
                    Spacer()
                    
                    // Zone des boutons (toute la largeur et hauteur disponible)
                    HStack(spacing: 0) {
                        // Bouton NON - Toute la partie gauche
                        Button(action: {
                            answerQuestion(response: false)
                        }) {
                            VStack(spacing: 20) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 80))
                                    .foregroundColor(.red)
                                
                                Text("NON")
                                    .font(.system(size: 48, weight: .bold))
                                    .foregroundColor(.red)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(
                                Color.red.opacity(0.15)
                            )
                            .overlay(
                                Rectangle()
                                    .stroke(Color.red.opacity(0.4), lineWidth: 3)
                            )
                        }
                        .accessibilityLabel("Non. Appuyez pour répondre non à la question.")
                        .accessibilityHint("Partie gauche de l'écran")
                        
                        // Bouton OUI - Toute la partie droite
                        Button(action: {
                            answerQuestion(response: true)
                        }) {
                            VStack(spacing: 20) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 80))
                                    .foregroundColor(Color(hex: "5ee852"))
                                
                                Text("OUI")
                                    .font(.system(size: 48, weight: .bold))
                                    .foregroundColor(Color(hex: "5ee852"))
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(
                                Color(hex: "5ee852").opacity(0.15)
                            )
                            .overlay(
                                Rectangle()
                                    .stroke(Color(hex: "5ee852").opacity(0.4), lineWidth: 3)
                            )
                        }
                        .accessibilityLabel("Oui. Appuyez pour répondre oui à la question.")
                        .accessibilityHint("Partie droite de l'écran")
                    }
                    .frame(maxHeight: .infinity) // Prend toute la hauteur disponible
                    
                    Spacer()
                    
                    // Slider de progression en bas
                    VStack(spacing: 15) {
                        Text("Progression: \(currentQuestionIndex + 1)/\(questions.count)")
                            .font(.caption)
                            .foregroundColor(Color(hex: "f0fff0").opacity(0.7))
                        
                        ProgressView(value: Double(currentQuestionIndex + 1), total: Double(questions.count))
                            .progressViewStyle(LinearProgressViewStyle(tint: Color(hex: "5ee852")))
                            .scaleEffect(x: 1, y: 2, anchor: .center)
                            .padding(.horizontal, 40)
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .onAppear {
            speakCurrentQuestion()
        }
        .navigationBarHidden(true)
    }
    
    private func speakCurrentQuestion() {
        speechSynthesizer.speak(questions[currentQuestionIndex].spokenText)
    }
    
    private func answerQuestion(response: Bool) {
        guard !hasAnswered else { return }
        hasAnswered = true
        
        // Sauvegarde de la réponse
        manager.saveResponse(questionId: questions[currentQuestionIndex].id, response: response)
        
        // Feedback vocal
        let responseText = response ? "Oui" : "Non"
        speechSynthesizer.speak(responseText)
        
        // Vibration légère pour confirmer
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        // Passage à la question suivante après un délai
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            nextQuestion()
        }
    }
    
    private func nextQuestion() {
        hasAnswered = false
        
        if currentQuestionIndex < questions.count - 1 {
            currentQuestionIndex += 1
            speakCurrentQuestion()
        } else {
            // Questionnaire terminé
            isComplete = true
        }
    }
}

// Gestionnaire de synthèse vocale
class SpeechSynthesizer: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    
    override init() {
        super.init()
        synthesizer.delegate = self
    }
    
    func speak(_ text: String) {
        // Arrêter toute synthèse en cours
        synthesizer.stopSpeaking(at: .immediate)
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "fr-FR")
        utterance.rate = 0.5 // Vitesse modérée
        utterance.volume = 1.0
        
        synthesizer.speak(utterance)
    }
    
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}

// Vue de prévisualisation
struct QuestionnaireView_Previews: PreviewProvider {
    static var previews: some View {
        QuestionnaireView()
    }
}
