# Manual Mode, In-App Chat, and A/B Variants

**Date:** 2026-05-02
**Status:** Draft for review

## Goal

Add an experimenter-facing **Manual / Lab mode** and an in-app **Chat** surface to the existing Agentic Health Coach, plus **A/B variant** prompt configuration so the same recommendation can be generated under two distinct prompt regimes for study comparisons. The autonomous nudge loop stays intact.

## Motivation

The current app is purely autonomous: HealthKit/EventKit signals flow into a `RecommendationEngine` that decides whether to send a nudge. For class evaluation we need:

1. **Reproducible scenario triggering** — fire specific health/calendar contexts on demand for demos and study sessions, instead of waiting for real signals.
2. **User-initiated prompting** — let the user ask the coach things directly, not only receive proactive nudges.
3. **A/B variant generation** — produce two distinct versions of the same recommendation under different prompt configurations (Tone, Timing, Explanation), with the option to override prompts entirely for ad-hoc tests.

## Architecture overview

The autonomous loop (`ContextSyncService` → `RecommendationEngine.runOnce`) is preserved. Two new tabs are added to the iOS app:

- **Chat tab** — conversational interface backed by `GeminiClient`, grounded in the latest real `ContextSnapshot` and the active variant's prompt config.
- **Lab tab** — experimenter playground: scenario picker, snapshot field editor, variant selector (A / B / custom), prompt override fields, "Fire" button.

`RecommendationEngine.runOnce` is refactored so the autonomous and manual paths share a single code path, parameterized by snapshot, prompt config, simulated `now`, and a guard-bypass flag.

## Components

### `PromptConfig` (struct, value type)

```swift
enum Tone { case neutral, supportive }
enum Timing { case fixed, contextAware }
enum Explanation { case with, without }

struct PromptConfig {
    var tone: Tone
    var timing: Timing
    var explanation: Explanation
    var systemPromptOverride: String?       // if set, fully replaces built prompt
    var notificationPromptOverride: String? // if set, replaces nudge-message text generation
}
```

### `VariantPreset` (SwiftData model)

Persists named presets for the study. Two seeded on first launch:

- **A:** `tone: .neutral, timing: .fixed, explanation: .without`
- **B:** `tone: .supportive, timing: .contextAware, explanation: .with`

Both editable from the Lab tab.

### `ScenarioPreset` (enum, hardcoded)

Each case yields a synthetic `ContextSnapshot` and a fixed simulated `now`.

| ID | Name | Block(s) | Synthetic signals |
|----|------|----------|-------------------|
| S1 | Poor Sleep + Busy Morning | 1 & 2 | `sleepHoursLastNight = 4.53` (4h 32m, bedtime 2:30 AM); calendar: Tue 9 AM lecture, 11 AM tutoring, 1 PM quiz; `minutesUntilNextEvent = 30` (firing at 8:30 AM) |
| S2 | Prolonged Inactivity | 2 | `stepsToday ≈ 600` over 4 hours, `activeEnergyKcalToday ≈ 80`, `minutesUntilNextEvent = nil` (free time ahead) |
| S3 | Pre-Deadline Stress | 2 | simulated time 9:00 PM, `latestHeartRateBPM = 92`, `latestHRVms = 28` |
| S4 | Post-Workout Recovery | 1 (& 2A replication) | `workoutsLast7Days += 1`, `activeEnergyKcalToday ≈ 600`, `latestHeartRateBPM = 110` (post-run elevated), `minutesUntilNextEvent = 90` |

### `RecommendationEngine` (refactored)

```swift
func runOnce(
    snapshot: ContextSnapshot,
    config: PromptConfig,
    simulatedNow: Date?,        // nil = use Date.now
    bypassGuards: Bool,         // true skips quiet-hours / cadence checks
    variantLabel: String?,      // "A" / "B" / "custom" / nil
    blockTag: String?           // "1" / "2" / "2A" / nil
) async
```

`buildPrompt` is updated to consume `PromptConfig`:

- **Tone** swaps the tone line in the system prompt.
- **Timing** changes the cadence guidance (`fixed` = "send at the scheduled time regardless"; `contextAware` = current behavior, factor in calendar/quiet hours).
- **Explanation** toggles whether the JSON shape requires an `explanation` field.
- If `systemPromptOverride` is set, the entire prompt is replaced by the override (with the signals block appended). UI surfaces this state clearly.

### `ChatMessage` (SwiftData model)

```swift
@Model class ChatMessage {
    var timestamp: Date
    var role: String   // "user" | "assistant"
    var text: String
    var variantLabel: String?
}
```

### `Recommendation` (extended)

Add two optional fields: `variantLabel: String?`, `blockTag: String?`. Defaulting to `nil` keeps existing autonomous rows unchanged.

### UI

- **`ChatView`** — message thread, text input at bottom, send button. Each user turn assembles `[system prompt from active PromptConfig + latest real snapshot signals] + chat history + user message`, calls Gemini, appends assistant reply.
- **`LabView`** — sections:
  1. **Scenario picker** (S1–S4 + "Live signals" option).
  2. **Snapshot editor** — form fields pre-filled from the chosen scenario, all editable before firing.
  3. **Variant selector** — A / B / Custom. Custom reveals tone/timing/explanation toggles + raw override text fields.
  4. **Block tag** — picker (1 / 2 / 2A / none).
  5. **Fire** button — runs the engine with `bypassGuards: true`.
- **`HistoryView`** — gain a filter by `blockTag` and `variantLabel`.

## Data flow

**Autonomous (unchanged behavior):**
background task → `ContextSyncService` writes `ContextSnapshot` → `runOnce(snapshot: latest, config: autonomousDefault, simulatedNow: nil, bypassGuards: false, variantLabel: nil, blockTag: nil)` → Gemini → `Recommendation` saved → notification + watch sync.

**Manual scenario:**
Lab "Fire" → build synthetic `ContextSnapshot` from preset (with any edits) → `runOnce(snapshot: synthetic, config: chosenConfig, simulatedNow: preset.now, bypassGuards: true, variantLabel: "A"|"B"|"custom", blockTag: chosen)` → same downstream path; rec rows are tagged for filtering.

**Chat:**
user types → assemble prompt (override-aware) + signals from latest real snapshot + chat history + user message → Gemini → assistant reply appended. No `Recommendation` row; lives in `ChatMessage`.

## Error handling

- **Gemini failure (chat):** inline error bubble with a retry button; chat history preserved.
- **Gemini failure (lab):** toast notification, scenario + variant selection retained.
- **Gemini failure (autonomous):** silent (current behavior).
- **Override active:** `LabView` and `ChatView` show a visible "raw prompt override active" badge so the experimenter is never confused about what's being sent.

## Testing

- Smoke test: fire S1–S4 with both A and B; verify `Recommendation` rows persist with correct `variantLabel` and `blockTag`, that notifications fire, and that the watch payload is delivered.
- Verify autonomous path is byte-identical in behavior — the refactor must not change autonomous output for the same inputs.
- Verify chat round-trip: send a message, get a reply, confirm both rows persist and survive app restart.
- Verify override mode: set a custom system prompt in Lab, fire, confirm the raw prompt is what hit Gemini (log the outgoing prompt during dev).

## Out of scope

- Remote experiment configuration or server-side logging.
- Cross-user randomization or bucketing.
- Statistical analysis tooling for study results.
- Watch-side UI for manual/chat (watch keeps receiving nudges as today).
