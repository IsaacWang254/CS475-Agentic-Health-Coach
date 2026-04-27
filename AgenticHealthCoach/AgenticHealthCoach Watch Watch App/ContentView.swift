//
//  ContentView.swift
//  AgenticHealthCoach Watch Watch App
//

import SwiftUI

struct ContentView: View {
    @State private var service = WatchConnectivityService.shared

    var body: some View {
        NavigationStack {
            Group {
                if let payload = service.latest {
                    NudgeGlance(payload: payload)
                } else {
                    EmptyState()
                }
            }
            .navigationTitle("Coach")
        }
    }
}

private struct NudgeGlance: View {
    let payload: WatchPayload

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(payload.goalDisplayName)
                    .font(.caption2)
                    .foregroundStyle(.tint)
                Text(payload.message)
                    .font(.headline)
                Text(payload.timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                NavigationLink {
                    WhyView(payload: payload)
                } label: {
                    Label("Why did I get this?", systemImage: "questionmark.circle")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .padding(.top, 4)
            }
            .padding(.horizontal, 4)
        }
    }
}

private struct WhyView: View {
    let payload: WatchPayload

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(payload.explanation.isEmpty ? "No explanation provided." : payload.explanation)
                    .font(.body)

                Divider().padding(.vertical, 4)

                Text("Signals").font(.caption.bold())
                if let steps = payload.stepsToday {
                    signal("Steps", "\(steps)")
                }
                if let sleep = payload.sleepHoursLastNight {
                    signal("Sleep", String(format: "%.1f h", sleep))
                }
                if let mins = payload.minutesUntilNextEvent {
                    signal("Next event", "\(mins) min")
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Why")
    }

    @ViewBuilder
    private func signal(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.caption)
    }
}

private struct EmptyState: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("No nudges yet")
                .font(.headline)
            Text("Open the iPhone app to get started.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
