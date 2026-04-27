//
//  HistoryView.swift
//  AgenticHealthCoach
//

import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \Recommendation.timestamp, order: .reverse) private var recommendations: [Recommendation]

    var body: some View {
        NavigationStack {
            List {
                if recommendations.isEmpty {
                    ContentUnavailableView(
                        "No history yet",
                        systemImage: "clock",
                        description: Text("Past nudges will appear here once the agent decides to send one.")
                    )
                } else {
                    ForEach(recommendations) { rec in
                        NavigationLink {
                            RecommendationDetail(rec: rec)
                        } label: {
                            RecommendationRow(rec: rec)
                        }
                    }
                }
            }
            .navigationTitle("History")
        }
    }
}

private struct RecommendationDetail: View {
    let rec: Recommendation

    var body: some View {
        Form {
            Section("Nudge") {
                Text(rec.message).font(.title3.bold())
                Text(rec.goal.displayName).foregroundStyle(.secondary)
            }
            Section("Why you got this") {
                Text(rec.explanation.isEmpty ? "No explanation recorded." : rec.explanation)
            }
            Section("Status") {
                LabeledContent("Sent", value: rec.timestamp.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Acted on", value: rec.actedOn ? "Yes" : "No")
                LabeledContent("Dismissed", value: rec.dismissed ? "Yes" : "No")
            }
        }
        .navigationTitle("Detail")
        .navigationBarTitleDisplayMode(.inline)
    }
}
