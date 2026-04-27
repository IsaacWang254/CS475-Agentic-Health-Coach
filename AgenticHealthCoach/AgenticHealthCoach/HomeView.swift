//
//  HomeView.swift
//  AgenticHealthCoach
//

import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Recommendation.timestamp, order: .reverse) private var recommendations: [Recommendation]
    @Query(sort: \ContextSnapshot.timestamp, order: .reverse) private var snapshots: [ContextSnapshot]

    @State private var refreshing = false

    var body: some View {
        NavigationStack {
            List {
                if let latest = recommendations.first {
                    Section("Latest nudge") {
                        RecommendationRow(rec: latest, expanded: true)
                        HStack {
                            Button("Acted on it") {
                                latest.actedOn = true
                                try? modelContext.save()
                            }
                            .disabled(latest.actedOn)
                            Spacer()
                            Button("Dismiss") {
                                latest.dismissed = true
                                try? modelContext.save()
                            }
                            .disabled(latest.dismissed)
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    Section {
                        ContentUnavailableView(
                            "No nudges yet",
                            systemImage: "sparkles",
                            description: Text("Pull to refresh once you've granted permissions.")
                        )
                    }
                }

                if let snap = snapshots.first {
                    Section("Current signals") {
                        SignalsList(snapshot: snap)
                    }
                }
            }
            .navigationTitle("Coach")
            .refreshable { await refresh() }
            .toolbar {
                ToolbarItem {
                    Button { Task { await refresh() } } label: {
                        Image(systemName: refreshing ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.clockwise")
                    }
                    .disabled(refreshing)
                }
            }
        }
    }

    private func refresh() async {
        refreshing = true
        defer { refreshing = false }
        await ContextSyncService.syncNow(container: modelContext.container)
    }
}

struct RecommendationRow: View {
    let rec: Recommendation
    var expanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(rec.goal.displayName)
                    .font(.caption)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(.tint.opacity(0.15), in: .capsule)
                Spacer()
                Text(rec.timestamp, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(rec.message).font(.body.bold())
            if expanded || !rec.explanation.isEmpty {
                Text(rec.explanation).font(.callout).foregroundStyle(.secondary)
            }
            if rec.actedOn || rec.dismissed {
                Text(rec.actedOn ? "Acted on" : "Dismissed")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct SignalsList: View {
    let snapshot: ContextSnapshot

    var body: some View {
        Group {
            row("Steps today", snapshot.stepsToday.map { "\($0)" })
            row("Sleep last night", snapshot.sleepHoursLastNight.map { String(format: "%.1f h", $0) })
            row("Active energy", snapshot.activeEnergyKcalToday.map { "\(Int($0)) kcal" })
            row("Heart rate", snapshot.latestHeartRateBPM.map { "\(Int($0)) bpm" })
            row("HRV", snapshot.latestHRVms.map { "\(Int($0)) ms" })
            row("Workouts (7d)", "\(snapshot.workoutsLast7Days)")
            row("Next event", snapshot.minutesUntilNextEvent.map { "in \($0) min" })
        }
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String?) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value ?? "—").monospacedDigit()
        }
    }
}
