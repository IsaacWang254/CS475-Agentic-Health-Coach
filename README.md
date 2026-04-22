# CS475-Agentic-Health-Coach

The proposed Agentic Health Coach is a proactive wellness assistant that combines Apple Watch data, smartphone context, and calendar information to deliver timely, low-friction health recommendations through the watch and phone. Rather than requiring users to manually inspect dashboards or initiate conversations, the system continuously interprets wearable and contextual signals in relation to user-defined goals such as improving sleep, increasing activity, managing stress, or maintaining workout consistency. When the agent detects an appropriate intervention opportunity, it generates a concise, context-aware recommendation, explains why it appeared, and delivers it through a glanceable Apple Watch interaction with optional follow-up on the phone. The system also gives users control over tone, notification behavior, and data access, allowing the experience to remain personalized, understandable, and privacy-aware rather than intrusive.

# To do
---

## 1. Project Initialization & Permissions
- [ ] Initialize Xcode project with both **iOS** and **watchOS** companion targets.
- [ ] Configure **HealthKit** entitlements and request read permissions (Sleep, Active Energy, Workouts, Heart Rate, HRV).
- [ ] Configure **EventKit** entitlements to read calendar data for contextual awareness.
- [ ] Request **Push Notification** and **Background Modes** (Background Fetch, Processing) permissions.

## 2. Core Data Ingestion & Context Layer
- [ ] Build a HealthKit manager to continuously query and aggregate Apple Watch data.
- [ ] Build an EventKit manager to fetch upcoming calendar events (to determine "free time" vs. "busy/stressed" contexts).
- [ ] Implement background processing tasks to periodically sync and cache context data without draining the battery.
- [ ] Create a local storage layer (CoreData or SwiftData) to store user preferences, generated recommendations, and historical signals.

## 3. The Agentic Logic (Intelligence Layer)
- [ ] Define data models for the four primary user goals: Sleep, Activity, Stress Management, and Workout Consistency.
- [ ] Develop the trigger logic: Define thresholds that prompt an intervention (e.g., low sleep + free calendar slot = "take a nap" recommendation).
- [ ] Integrate an LLM or on-device natural language generator to craft the context-aware recommendation text.
- [ ] Implement the "Explanation Engine" (ensuring the agent can articulate *why* a specific recommendation was generated based on recent data).

## 4. iOS App (The Control Center)
- [ ] **Onboarding Flow:** Screen to define primary health goals and grant permissions.
- [ ] **Settings UI:** Toggles for notification frequency, strictness, and system access.
- [ ] **Persona/Tone Controls:** UI to select the agent's tone (e.g., Empathetic, Direct, Analytical).
- [ ] **History Dashboard:** A log of past recommendations and the data signals that triggered them.

## 5. watchOS App (The Delivery Mechanism)
- [ ] Build a glanceable main interface using SwiftUI for Apple Watch.
- [ ] Implement actionable, rich notifications (e.g., "Start 10-min walk", "Dismiss", "Snooze").
- [ ] Create a lightweight detailed view to show the "Why did I get this?" explanation directly on the wrist.
- [ ] Ensure seamless state synchronization across the Watch and iPhone via `WatchConnectivity`.

## 6. Testing & Refinement
- [ ] Test background execution limits and ensure HealthKit queries succeed when the device is locked.
- [ ] Simulate edge cases (e.g., back-to-back calendar meetings with elevated heart rate).
- [ ] Refine the notification delivery logic to ensure it feels low-friction and strictly non-intrusive.
