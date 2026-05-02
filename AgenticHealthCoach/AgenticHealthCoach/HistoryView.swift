//
//  HistoryView.swift
//  AgenticHealthCoach
//

import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \Recommendation.timestamp, order: .reverse) private var recommendations: [Recommendation]

    @State private var blockFilter: String = "all"
    @State private var customBlockFilter: String = ""
    @State private var variantFilter: String = "all"

    private var filtered: [Recommendation] {
        recommendations.filter { rec in
            matchesBlockFilter(rec.blockTag) &&
            (variantFilter == "all" || rec.variantLabel == variantFilter)
        }
    }

    private func matchesBlockFilter(_ tag: String?) -> Bool {
        switch blockFilter {
        case "all":
            true
        case "custom":
            tag == customBlockFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        default:
            tag == blockFilter
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Block", selection: $blockFilter) {
                        Text("All blocks").tag("all")
                        Text("1").tag("1")
                        Text("2").tag("2")
                        Text("3").tag("3")
                        Text("Custom").tag("custom")
                    }
                    if blockFilter == "custom" {
                        NoAssistantTextField(placeholder: "Custom block tag", text: $customBlockFilter)
                            .frame(minHeight: 36)
                    }
                    Picker("Variant", selection: $variantFilter) {
                        Text("All variants").tag("all")
                        Text("A").tag("A")
                        Text("B").tag("B")
                        Text("Custom").tag("custom")
                    }
                }

                if filtered.isEmpty {
                    ContentUnavailableView(
                        "No history yet",
                        systemImage: "clock",
                        description: Text("Past nudges will appear here once the agent decides to send one.")
                    )
                } else {
                    ForEach(filtered) { rec in
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
                if let v = rec.variantLabel { LabeledContent("Variant", value: v) }
                if let b = rec.blockTag { LabeledContent("Block", value: b) }
            }
        }
        .navigationTitle("Detail")
        .navigationBarTitleDisplayMode(.inline)
    }
}
