//
//  GeminiClient.swift
//  AgenticHealthCoach
//

import Foundation
import FirebaseAI

struct AgentDecision: Decodable {
    enum Action: String, Decodable {
        case nudge
        case stayQuiet = "stay_quiet"
    }

    let action: Action
    let goal: String?
    let message: String?
    let explanation: String?
    let reason: String?
}

enum GeminiError: Error {
    case emptyContent
    case malformedJSON(String)
}

struct GeminiClient {
    var modelName: String = "gemini-3.1-flash-lite-preview"

    func decide(prompt: String) async throws -> AgentDecision {
        let schema = Schema.object(
            properties: [
                "action": .enumeration(values: ["nudge", "stay_quiet"]),
                "goal": .string(),
                "message": .string(),
                "explanation": .string(),
                "reason": .string(),
            ],
            optionalProperties: ["goal", "message", "explanation", "reason"]
        )

        let config = GenerationConfig(
            temperature: 0.7,
            responseMIMEType: "application/json",
            responseSchema: schema
        )

        let model = FirebaseAI.firebaseAI(backend: .googleAI())
            .generativeModel(modelName: modelName, generationConfig: config)

        let response = try await model.generateContent(prompt)

        guard let text = response.text, let json = text.data(using: .utf8) else {
            throw GeminiError.emptyContent
        }
        do {
            return try JSONDecoder().decode(AgentDecision.self, from: json)
        } catch {
            throw GeminiError.malformedJSON(text)
        }
    }
}
