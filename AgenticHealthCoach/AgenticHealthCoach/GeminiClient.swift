//
//  GeminiClient.swift
//  AgenticHealthCoach
//

import Foundation

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
    case invalidURL
    case badResponse(Int, String)
    case emptyContent
    case malformedJSON(String)
}

struct GeminiClient {
    var apiKey: String = Secrets.geminiAPIKey
    var model: String = Secrets.geminiModel
    var session: URLSession = .shared

    func decide(prompt: String) async throws -> AgentDecision {
        let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"
        guard var components = URLComponents(string: endpoint) else { throw GeminiError.invalidURL }
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components.url else { throw GeminiError.invalidURL }

        let body: [String: Any] = [
            "contents": [[
                "role": "user",
                "parts": [["text": prompt]],
            ]],
            "generationConfig": [
                "temperature": 0.7,
                "responseMimeType": "application/json",
                "responseSchema": [
                    "type": "object",
                    "properties": [
                        "action": ["type": "string", "enum": ["nudge", "stay_quiet"]],
                        "goal": ["type": "string"],
                        "message": ["type": "string"],
                        "explanation": ["type": "string"],
                        "reason": ["type": "string"],
                    ],
                    "required": ["action"],
                ],
            ],
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let snippet = String(data: data, encoding: .utf8) ?? ""
            throw GeminiError.badResponse(http.statusCode, snippet)
        }

        guard
            let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let candidates = envelope["candidates"] as? [[String: Any]],
            let content = candidates.first?["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]],
            let text = parts.first?["text"] as? String
        else {
            throw GeminiError.emptyContent
        }

        guard let json = text.data(using: .utf8) else {
            throw GeminiError.malformedJSON(text)
        }
        do {
            return try JSONDecoder().decode(AgentDecision.self, from: json)
        } catch {
            throw GeminiError.malformedJSON(text)
        }
    }
}
