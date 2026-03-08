---
shaping: true
---

# Blood Sweat Beers — Shaping

## Source

> I'm looking to develop an application that is like strava but for gym workouts, initially focussing on deka and hyrox style workouts. I would like users to be able to login (auth is already set up) and see a feed where they can post a workout. The app will generate a workout based on the time the user enters. They then complete the workout and give a sweat rating out of 5 of how hard it was. This is then posted to there feed with dates and details of the workout (and maybe location), users can follow other users and will see the workouts in their feed, they can like the workout and also choose to do it themselves.
>
> Ruby POC → LLM upgrade path confirmed. Sweat rating only (no separate suffer score). Per-exercise PRs, plus daily WOD challenges with leaderboard and full time-tracking for improvement charts. Flat comments. Private profiles — follow requests require acceptance. New users see only their own workouts.
>
> Generation rework: Ruby WorkoutGenerator retired entirely. LLM (Haiku) via tool use is the primary and only generation path. Workouts are tagged with user-created free-text tags (polymorphic taggable model). Top 25 liked workouts matching selected tags sent as JSON context; Haiku produces new workout via tool use (schema enforced). Workout structure changed from flat run/station array to flexible sections (AMRAP/rounds/straight) with exercises having optional metrics. Separate workout_likes table drives generation ranking (distinct from social likes on workout_log posts). Ruby generator retired — no fallback.
>
> Monetisation: Free tier (5 AI generations/week) + Pro tier (unlimited, Sonnet model, training plans, coaching insights). Ultimate goal is iPhone and Android native apps — PWA is the stepping stone. Device integration (heart rate, workout stats from Apple Watch / Garmin) is a native app feature via HealthKit and Google Fit — not dependent on Strava.

---

## Problem

Athletes training in functional fitness (Deka, Hyrox, CrossFit, HIIT etc.) have no tailored social platform. Generic apps don't understand the format. Strava is GPS-only and cardio-biased. There's no community layer purpose-built for this kind of training — no way to generate structured workouts, share them, discover community sessions, be challenged daily, follow progressive training plans, or track meaningful improvement over time.

## Outcome

A focused social fitness platform where users generate structured workouts, log performance, track PRs, compete on daily challenges, follow progressive training plans, and share within a trusted community. Progress is visible, measurable, and social. Pro users get AI-powered coaching, unlimited generation, and — via native apps — real-time device data. The long-term platform is iOS + Android native with full HealthKit / Google Fit integration.

---

## Requirements (R)

| ID | Requirement | Tier | Status |
|----|-------------|------|--------|
| **R0** | **Auth & Profile** | | |
| R0.1 | Authenticated users can access the app | Free | ✅ Built |
| R0.2 | User profile stores name, avatar, age, weight, equipment, PBs | Free | ✅ Built |
| R0.3 | Private profiles by default; follow requests must be accepted | Free | ✅ Built |
| R0.4 | New users redirected to profile setup on first login | Free | ✅ Built |
| R0.5 | Find people via search or device contacts (Contact Picker API) | Free | ✅ Built |
| **R1** | **Workout Types & Formats** | | |
| R1.1 | Workouts tagged with free-text tags (polymorphic taggable) | Free | ✅ Built |
| R1.2 | Tags selected at creation and generation time | Free | ✅ Built |
| R1.3 | Format is expandable (custom workouts first-class; Deka/Hyrox/etc. as tags) | Free | ✅ Built |
| R1.4 | 10 curated session-type pills shown on generate form for new users | Free | ✅ Built |
| R1.5 | Returning users see their last 3 used types first, then curated list | Free | ✅ Built |
| **R2** | **Workout Generation & Creation** | | |
| R2.1 | Generate modal opens from persistent nav button (mobile + desktop) | Free | ✅ Built |
| R2.2 | Generator produces structured workout: sections with exercises, metrics, formats | Free | ✅ Built |
| R2.3 | Race simulation mode: exact competition reps/distances/weights in race order | Free | ✅ Built |
| R2.4 | Generated workouts can be saved to personal library | Free | ✅ Built |
| R2.5 | LLM (Haiku) via tool use is the only generation path | Free | ✅ Built |
| R2.6 | Session Notes field: injuries, equipment, intensity, focus — free text | Free | ✅ Built |
| R2.7 | Workouts have separate workout_likes (generation ranking signal) | Free | ✅ Built |
| R2.8 | Remix a workout: same feel, different session | Free | ✅ Built |
| R2.9 | Weights prescribed against athlete's 1RM — pre-computed, never exceed 1RM | Free | ✅ Built |
| R2.10 | Free users limited to 5 AI generations per week | Free | Planned — V11 |
| R2.11 | Pro users get unlimited generations with Sonnet model | Pro | Planned — V11 |
| R2.12 | Pro users can request a structured multi-week training plan | Pro | Planned — V13 |
| **R3** | **Workout Logging** | | |
| R3.1 | Log per-exercise: sets/reps/weight or time/distance | Free | ✅ Built |
| R3.2 | Sweat rating (1–5) + optional notes | Free | ✅ Built |
| R3.3 | Auto-detect per-exercise PR achievements after each log | Free | Planned — V7 |
| R3.4 | Optional location tagging | Free | ✅ Built |
| **R4** | **Personal Library, History & Progress** | | |
| R4.1 | Calendar view of workout history | Free | Planned — V9 |
| R4.2 | Personal library of saved workouts | Free | ✅ Built |
| R4.3 | Saving another user's workout stores a reference link (not a copy) | Free | ✅ Built |
| R4.4 | Progress charts per exercise over time | Free | Planned — V7 |
| R4.5 | Workout streak tracking (consecutive active weeks) | Free | Planned — V12 |
| **R5** | **Social Feed & Interactions** | | |
| R5.1 | Feed: own + accepted followers' workouts only | Free | ✅ Built |
| R5.2 | Follow requests require acceptance | Free | ✅ Built |
| R5.3 | Like and comment on workout posts | Free | ✅ Built |
| R5.4 | Save workout from feed to personal library | Free | ✅ Built |
| R5.5 | Daily challenge posted each day; users log results; leaderboard | Free | Planned — V8 |
| R5.6 | Additional daily challenges for Pro users | Pro | Planned — V8 |
| R5.7 | Share a workout as an image (for Instagram, WhatsApp, etc.) | Free | Planned — V14 |
| R5.8 | Tag a friend on a workout as a challenge | Free | Planned — V19 |
| **R6** | **AI Coaching (Pro)** | | |
| R6.1 | On-demand Coach's Notes on any workout (Sonnet, cached, free) | Free | Planned — V15a |
| R6.2 | Weekly AI coaching digest: trends, volume, load insights (Sonnet, async, Pro) | Pro | Planned — V15b |
| R6.3 | Load management: flags overtraining vs rolling average | Pro | Planned — V15b |
| R6.3 | Training plan awareness: future plans build on previous completed plans | Pro | Planned — V13 |
| **R7** | **Training Plans (Pro)** | | |
| R7.1 | Request a multi-week plan toward a goal (e.g. 6-week Hyrox prep) | Pro | Planned — V13 |
| R7.2 | Plan generates N sessions/week; each subsequent week remixes with progressive overload (+5–7% load) | Pro | Planned — V13 |
| R7.3 | Week 5: deload. Final week: benchmark/test | Pro | Planned — V13 |
| R7.4 | Completed plans stored; future plans build on them | Pro | Planned — V13 |
| R7.5 | Plan progress visible on profile and feed | Pro | Planned — V13 |
| **R8** | **Monetisation** | | |
| R8.1 | Free tier: 5 AI generations per week, all social features | Free | Planned — V11 |
| R8.2 | Pro tier: unlimited generations, Sonnet model, training plans, coaching insights | Pro | Planned — V11 |
| R8.3 | Stripe Checkout for subscription management | — | Planned — V11 |
| R8.4 | Stripe webhook flips user.plan on payment success / cancellation | — | Planned — V11 |
| **R9** | **Platform — PWA** | | |
| R9.1 | App installable on iOS and Android home screen (PWA manifest + service worker) | All | Planned — V16 |
| R9.2 | Push notifications for follows, challenges, plan sessions | All | Planned — V16 |
| R9.3 | Basic offline support: cached feed, offline log entry queued for sync | All | Planned — V16 |
| **R10** | **Platform — Native Apps** | | |
| R10.1 | Native iOS app (Swift / SwiftUI) sharing Rails API backend | All | Planned — V17 |
| R10.2 | Native Android app sharing same Rails API | All | Planned — V17 |
| R10.3 | API-first Rails backend: JSON endpoints for all app data | — | Planned — V17 |
| **R11** | **Device Integration (native app required)** | | |
| R11.1 | iOS: HealthKit integration — read heart rate, active calories, workout duration from Apple Watch | Pro | Planned — V18 |
| R11.2 | Android: Google Fit / Health Connect integration | Pro | Planned — V18 |
| R11.3 | Workout log displays device stats: avg HR, max HR, HR zones, calories | Pro | Planned — V18 |
| R11.4 | Device data stored on workout_logs and shown on feed cards | Pro | Planned — V18 |
| R11.5 | Garmin direct integration (via Garmin Health API) as optional extra | Pro | Planned — V18 |

---

## Open Questions

| # | Question | Resolution |
|---|----------|------------|
| OQ1 | SQLite vs PostgreSQL? | ✅ **PostgreSQL** |
| OQ2 | Sweat rating vs computed suffer score? | ✅ **Sweat rating only** (1–5, user-given) |
| OQ3 | PRs: per-exercise or per-workout-format? | ✅ **Per-exercise PRs** (best weight, time, distance, reps) |
| OQ4 | Comments: flat or threaded? | ✅ **Flat** |
| OQ5 | Profiles: public by default? | ✅ **Private by default** — follow requests required |
| OQ6 | Custom workout format? | ✅ **Free-form** — name + notes, no structured steps |
| OQ7 | Library categories vs workout types? | ✅ **Separate** — categories are folders; types are tags |
| OQ8 | Saving another user's workout: copy or reference? | ✅ **Reference link** |
| OQ9 | Device integration via Strava or direct? | ✅ **Direct via HealthKit / Google Fit** on native apps. No Strava dependency — we are competing with them. Web app has no access to device data until native apps are shipped. |
| OQ10 | Free / Pro generation limits? | ✅ **5/week free, unlimited Pro**. Sonnet model for Pro. |
| OQ11 | Training plan generation: synchronous or async? | **Async** — each week generated as a background job, not one big LLM call. User sees plan skeleton immediately, weeks fill in as jobs complete. |
| OQ12 | PWA before or after native apps? | **PWA first** — service worker + manifest + push notifications. Then native apps use the same API. PWA gives iOS/Android installs without app store. |
| OQ13 | Native app tech stack? | **TBD** — options: React Native (single codebase, web knowledge reuse), Swift/Kotlin native (best device integration, more work), Flutter. Decision deferred to V17 planning. HealthKit requires Swift on iOS regardless; could be a thin native shell around React Native. |

---

## Shape A: Core Platform (V1–V9) — largely built

See `slices.md` for implementation detail. All generation rework (GR1–GR4) complete. V1–V6 built.

---

## Shape B: Pro Tier + Monetisation (V11)

| Part | Mechanism |
|------|-----------|
| B1 | `plan` enum on users: `free` / `pro` |
| B2 | `generation_uses` table: user_id, created_at — count this week's generations |
| B3 | `WorkoutsController#create` gate: free users blocked after 5/week with upgrade prompt |
| B4 | Stripe Checkout session created server-side; user redirected to Stripe |
| B5 | Stripe webhook: `customer.subscription.created/deleted` → update user.plan |
| B6 | Pro users routed to `claude-sonnet-4-6`; free users stay on `claude-haiku-4-5` |
| B7 | Profile page shows plan status + upgrade CTA |

---

## Shape C: Training Plans (V13)

| Part | Mechanism |
|------|-----------|
| C1 | `training_plans`: user_id, name, goal, main_tag_id, duration_weeks, sessions_per_week, status (draft/active/completed) |
| C2 | `training_plan_weeks`: plan_id, week_number, theme (Build/Accumulate/Peak/Deload/Test), overload_pct |
| C3 | `training_plan_sessions`: week_id, day_of_week, workout_id, completed_at |
| C4 | `TrainingPlanGeneratorJob`: generates Week 1 workouts; subsequent weeks remix with load modifier |
| C5 | Overload schedule: W1 baseline → W2 +5% → W3 +7% → W4 +5% → W5 deload −20% → W6 test/benchmark |
| C6 | Plan history: completed plans summarised in prompt context for future plans ("athlete ran 6-week Hyrox prep, finishing loads: ...") |
| C7 | Plan dashboard: week grid, session cards, completion tracking |

---

## Shape D: PWA (V16)

| Part | Mechanism |
|------|-----------|
| D1 | Web App Manifest: name, icons, theme_color, display: standalone, start_url |
| D2 | Service Worker: cache shell assets; serve feed from cache when offline |
| D3 | Push notifications via Web Push (vapid keys): follow requests, challenge results, plan session reminders |
| D4 | Install prompt: shown after 3rd session if not installed |
| D5 | Offline log entry: IndexedDB queue; synced when back online |

---

## Shape E: Native Apps (V17)

| Part | Mechanism |
|------|-----------|
| E1 | Rails API mode endpoints (JSON) for all app data: workouts, logs, feed, profile, plans |
| E2 | Auth via API tokens (not session cookies); token refresh flow |
| E3 | iOS app: Swift/SwiftUI (or React Native shell for HealthKit bridge) |
| E4 | Android app: Kotlin / Jetpack Compose (or React Native) |
| E5 | Push notifications via APNs (iOS) and FCM (Android) replacing Web Push |

---

## Shape F: Device Integration (V18, native app required)

| Part | Mechanism |
|------|-----------|
| F1 | iOS: HealthKit `HKWorkoutSession` reads HR, calories, duration during workout |
| F2 | Android: Google Health Connect reads equivalent metrics |
| F3 | Post-workout: device stats (avg_hr, max_hr, hr_zones[], active_calories) stored as jsonb on workout_logs |
| F4 | Feed card shows device stats badge when present |
| F5 | Garmin Health API (optional): OAuth2, activity webhook → same stats jsonb |
| F6 | Stats used in AI coaching insights (R6.1): "Your avg HR in zone 3 increased this week" |

---

## Fit Check: R × Shape

| Req | Requirement | Shape | Slice | Status |
|-----|-------------|-------|-------|--------|
| R0.1 | Auth | A | — | ✅ Built |
| R0.2 | Profile (name, age, weight, equipment, PBs) | A | — | ✅ Built |
| R0.3 | Private profiles + follow requests | A7 | V4 | ✅ Built |
| R0.4 | New users → profile setup on first login | A | — | ✅ Built |
| R0.5 | Find people / Contact Picker | A | — | ✅ Built |
| R1.1–1.3 | Polymorphic tags, formats | A2 | GR1 | ✅ Built |
| R1.4–1.5 | Curated session pills + recency ordering | A | — | ✅ Built |
| R2.1 | Generate modal in nav | A | — | ✅ Built |
| R2.2 | Structured sections workout | A4 | GR3 | ✅ Built |
| R2.3 | Race simulation mode | A4 | GR4 | ✅ Built |
| R2.4 | Save to library | A6 | V6 | ✅ Built |
| R2.5 | LLM (Haiku) only path | A4 | GR3 | ✅ Built |
| R2.6 | Session Notes field | A | — | ✅ Built |
| R2.7 | workout_likes ranking | A8 | GR2 | ✅ Built |
| R2.8 | Remix | A4 | — | ✅ Built |
| R2.9 | Weights vs 1RM pre-computed | A4 | — | ✅ Built |
| R2.10 | Free tier: 5 gen/week gate | B1–B3 | V11 | ⬜ Planned |
| R2.11 | Pro: unlimited + Sonnet | B1, B6 | V11 | ⬜ Planned |
| R2.12 | Pro: training plans | C1–C7 | V13 | ⬜ Planned |
| R3.1 | Log per-exercise sets/reps/weight | A5 | V2 | ✅ Built |
| R3.2 | Sweat rating + notes | A5 | V2 | ✅ Built |
| R3.3 | PR detection | A5.3–5.4 | V7 | ⬜ Planned |
| R3.4 | Location tagging | A5 | V2 | ✅ Built |
| R4.1 | Calendar history | A6.2 | V9 | ⬜ Planned |
| R4.2–4.3 | Library + reference save | A6 | V6 | ✅ Built |
| R4.4 | Progress charts | A6.4 | V7 | ⬜ Planned |
| R4.5 | Workout streaks | — | V12 | ⬜ Planned |
| R5.1–5.4 | Feed, follows, likes, comments, save | A7–A8 | V3–V6 | ✅ Built |
| R5.5 | Daily challenge + leaderboard | A9 | V8 | ⬜ Planned |
| R5.6 | Extra daily challenges for Pro | A9 | V8 | ⬜ Planned |
| R5.7 | Share workout as image | — | V14 | ⬜ Planned |
| R5.8 | Tag friend as challenge | — | V19 | ⬜ Planned |
| R6.1 | Coach's Notes on any workout (on-demand, Sonnet, free) | — | V15a | ⬜ Planned |
| R6.2 | Weekly AI coaching digest (Sonnet, async, Pro) | — | V15b | ⬜ Planned |
| R6.3 | Load management / fatigue warning | — | V15b | ⬜ Planned |
| R6.4 | Plan-aware future generations | C6 | V13 | ⬜ Planned |
| R7.1–7.5 | Training plans (Pro) | C1–C7 | V13 | ⬜ Planned |
| R8.1–8.4 | Stripe, free/pro gating | B1–B7 | V11 | ⬜ Planned |
| R9.1–9.3 | PWA: install, push, offline | D1–D5 | V16 | ⬜ Planned |
| R10.1–10.3 | Native iOS + Android | E1–E5 | V17 | ⬜ Planned |
| R11.1–11.5 | HealthKit / Google Fit / Garmin | F1–F6 | V18 | ⬜ Planned — native app required |

**Gaps / Notes:**
- R11 (device integration) is fully blocked on V17 (native apps). No web workaround for HealthKit. Garmin has a REST API usable from the web app if needed as an interim step.
- R5.7 (share card) can be done as server-side image render (Grover/Puppeteer or HTML canvas) before native apps — no native dependency.
- R9 (PWA) should ship before V17 to give users a home screen install experience and validate engagement before committing to native app build.
- Training plan week-by-week async generation (OQ11) means users need a plan status page that updates as weeks complete — Turbo Stream or polling.
