---
shaping: true
---

# Blood Sweat Beers — Slices

Vertical implementation slices derived from the breadboard. Each slice ends in demo-able UI. Build in order — later slices depend on earlier ones.

---

## Slice Summary

| # | Slice | Shape | Demo | Status |
|---|-------|-------|------|--------|
| V1 | Workout Generation (Ruby POC) | A1–A3 | "Select Hyrox, 45 mins → see structured workout plan" | ✅ Built — superseded by GR1–GR4 |
| V2 | Workout Logging | A5.1–5.2 | "Log sets/reps + sweat rating → WorkoutLog saved" | ✅ Built |
| V3 | Own Feed | A7 (own only) | "My logged workouts appear in feed with cards" | ✅ Built |
| GR1 | Tags + new workout structure | gen-A1–A2 | "View workout — see tags and sections-based structure" | ✅ Built |
| GR2 | Workout likes | gen-A3 | "Like a workout — count updates live; ranking ready" | ✅ Built |
| GR3 | LLM generator + form + seeding | gen-A4–A6 | "Pick 'deka' + 30 mins → LLM generates sections workout" | ✅ Built |
| GR4 | Generation rework — gym-first | gen-A7 | "HIIT/CrossFit/Functional tags; competition reps; race sim" | ✅ Built |
| V4 | Follow Graph + Private Profiles | A7.1–7.3 | "Request follow → accept → see each other's workouts" | ✅ Built |
| V5 | Likes + Comments | A8.1–8.2 | "Like post live; comment appends without reload" | ✅ Built |
| V6 | Library + Save + Remix | A6, A8.3 | "Save to library; remix a workout; preview before logging" | ✅ Built |
| V7 | PR Detection + Progress Charts | A5.3–5.4 | "Log heavier lift → PR badge; view exercise chart" | ⬜ Next |
| V8 | Daily Challenges | A9 | "Challenge on home screen; log result; leaderboard live" | ⬜ |
| V9 | Calendar History | A6.2 | "Heatmap of all workouts; tap day → see sessions" | ⬜ |
| V10 | Exercise Guides | — | "Tap exercise → modal shows cues + video link" | ⬜ |
| V11 | Pro Tier + Stripe | B1–B7 | "Free user hits limit → upgrade prompt → Stripe → Pro unlocked" | ⬜ |
| V12 | Workout Streaks | — | "Profile shows current streak; badge on feed card" | ⬜ |
| V13 | Training Plans (Pro) | C1–C7 | "Request 6-week Hyrox plan → week grid → sessions auto-generated with progressive overload" | ⬜ |
| V14 | Share Card | — | "Tap share → styled PNG of workout generated → share sheet" | ⬜ |
| V15 | AI Coaching Insights (Pro) | — | "Coach's Notes on any workout (on-demand); weekly digest: volume trends, load warning, PR highlights" | ⬜ |
| V16 | PWA — Install + Push + Offline | D1–D5 | "Install prompt appears → app on home screen → push notification for challenge" | ⬜ |
| V17 | Native Apps (iOS + Android) | E1–E5 | "App store install → full feature parity with web" | ⬜ |
| V18 | Device Integration (native required) | F1–F6 | "Post workout → HR + calories from Apple Watch on feed card" | ⬜ |
| V19 | Community Challenges + Friend Challenges | — | "Weekly leaderboard; tag friend on a workout as a challenge" | ⬜ |

---

## V7: PR Detection + Progress Charts

**Shape parts:** A5.3 (PR detection), A5.4 (personal_records), A6.4 (progress charts)

| # | Component | Affordance | Control | Wires Out | Returns To |
|---|-----------|------------|---------|-----------|------------|
| U43 | pr-notification | PR badge fires post-completion (Turbo Stream) | render | — | — |
| U48 | post-detail | PR badges on post if PRs set | render | — | — |
| U61 | progress | Exercise selector | select | → N72 | — |
| U62 | progress | Chartkick line chart (weight/reps/time over time) | render | — | — |
| U63 | progress | PR milestone markers on chart | render | — | — |
| N36 | PRDetectionService.call | Compare each set vs PersonalRecords; write if new best | call | → S4 | → N37 |
| N37 | Turbo Stream | Broadcast PR badge to current user | broadcast | — | → U43 |
| N72 | ExerciseLogsController#history | Sets data for exercise over time | call | → S3, S4 | → U62 |
| S4 | personal_records | user_id, exercise_name, metric, value, achieved_at, workout_log_id | — | — | — |

**What to build:**
- `personal_records` table + model (keyed by exercise name string, not exercise_id — no exercise library table)
- `PRDetectionService`: after WorkoutLog created, iterate logged exercises, compare each metric vs best; write new record if better
- Turbo Stream broadcast of PR badge after WorkoutLog#create
- PR badges on workout log post detail
- Progress tab in profile/library: exercise name search → Chartkick line chart + PR overlays
- Add `chartkick` + `groupdate` gems

**Demo:** Log a heavier deadlift → PR badge appears on screen → open Progress → select Deadlift → see weight over time with PR marked.

---

## V8: Daily Challenges

**Shape parts:** A9.1–A9.5 (wods, wod_entries, leaderboard, GenerateDailyWodJob)

**Notes:** Free users see 1 challenge/day. Pro users see up to 3 (short/medium/long or different intensities). Everyone on the same challenge = community feel + leaderboard.

| # | Component | Affordance | Control | Wires Out | Returns To |
|---|-----------|------------|---------|-----------|------------|
| U5 | challenge-widget | Challenge title, format, scoring type | render | — | — |
| U6 | challenge-widget | Exercise list | render | — | — |
| U7 | challenge-widget | "Log my result" button | click | → U8 | — |
| U8 | challenge-log-form | Score input (time/reps/weight) | type | — | — |
| U9 | challenge-log-form | Rx checkbox | toggle | — | — |
| U10 | challenge-log-form | Submit | click | → N10 | — |
| U11 | challenge-widget | Leaderboard (Turbo Frame, top 10) | render | — | — |
| U12 | challenge-widget | "My result" post-submit | render | — | — |
| U13 | pro-challenges | 2 additional challenges (Pro badge gated) | render | — | — |
| N2 | ChallengesController#today | Load today's challenge(s) + top entries | call | → S8, S9 | → U5, U11 |
| N10 | ChallengeEntriesController#create | Create entry; Turbo Stream refresh leaderboard | call | → S9 | → U11 |
| N100 | GenerateDailyChallengeJob | Solid Queue recurring (midnight); generates 3 challenges; creates records for next day | job | → S8 | — |
| S8 | daily_challenges | date, title, workout_id, scoring_type (time/reps/weight/rounds), tier (all/pro) | — | — | — |
| S9 | challenge_entries | user_id, challenge_id, score, rx, notes, logged_at | — | — | — |

**What to build:**
- `daily_challenges` + `challenge_entries` tables + models
- `GenerateDailyChallengeJob`: generates 3 challenges (1 free-tier, 2 pro-tier) per day; balances workout type rotation across the week
- Challenge widget on home/feed: today's challenge inline, log form, live leaderboard
- Leaderboard ordering per scoring_type (ASC for time, DESC for everything else)
- Turbo Stream broadcast on entry create — all subscribers' leaderboards update
- One entry per user per challenge per day enforced
- Pro gate on the 2 additional challenges (check user.plan)

**Demo:** Home shows today's challenge → log 38:42 Rx → leaderboard updates live → another user's tab also updates.

---

## V9: Calendar History

**Shape parts:** A6.2 (calendar + Groupdate)

| # | Component | Affordance | Control | Wires Out | Returns To |
|---|-----------|------------|---------|-----------|------------|
| U58 | calendar | Monthly heatmap (shaded by workout count) | render | — | — |
| U59 | calendar | Day cell tap | click | → N70 | — |
| U60 | day-detail | Workouts on selected date (Turbo Frame) | render | — | — |
| U61 | calendar | Prev/next month nav | click | → N71 | — |
| N70 | WorkoutLogsController#by_date | WorkoutLogs for selected date | call | → S2 | → U60 |
| N71 | WorkoutLogsController#calendar | Count grouped by date (Groupdate) | call | → S2 | → U58 |

**What to build:**
- `WorkoutLogsController#calendar`: Groupdate group by day for current month; CSS grid heatmap (darker = more workouts)
- Day tap: Turbo Frame loads mini workout list inline below grid
- Month navigation reloads calendar Turbo Frame
- Add `groupdate` gem (also needed for V7)
- Link from profile page

**Demo:** Profile → Calendar → see grid; days with workouts darker → tap day → mini list appears.

---

## V10: Exercise Guides

**Shape parts:** None (standalone)

| # | Component | Affordance | Control | Wires Out | Returns To |
|---|-----------|------------|---------|-----------|------------|
| U80 | exercise-row | Exercise name tappable | click | → N80 | — |
| U81 | exercise-guide-modal | Coaching cues, common faults, video link | render | — | — |
| N80 | ExerciseGuidesController#show | Load or generate guide for exercise name | call | → S_guides | → U81 |
| S_guides | exercise_guides | exercise_name (unique), cues (text), faults (text), video_url, generated_at | — | — | — |

**What to build:**
- `exercise_guides` table: keyed by exercise name string; cached forever once generated
- `ExerciseGuidesController#show`: if cached, serve it; else call LLM to generate cues + faults + video search term; cache result
- Modal on exercise name tap in workout preview and workout log
- LLM prompt: "Give 3 coaching cues and 2 common faults for [exercise name] in 2 sentences each"

**Demo:** Tap "Sandbag Lunge" in a workout → modal shows setup cues, common faults, YouTube search link.

---

## V11: Pro Tier + Stripe

**Shape parts:** B1–B7

| # | Component | Affordance | Control | Wires Out | Returns To |
|---|-----------|------------|---------|-----------|------------|
| U90 | generate-modal | Usage counter "3 of 5 this week" | render | — | — |
| U91 | generate-modal | Upgrade CTA when limit hit | render | → N90 | — |
| U92 | profile | Plan badge (Free / Pro) | render | — | — |
| U93 | profile | "Upgrade to Pro" button | click | → N90 | — |
| U94 | profile | "Manage subscription" link (Pro users) | click | → Stripe portal | — |
| N90 | SubscriptionsController#create | Create Stripe Checkout session; redirect to Stripe | call | → Stripe | → Stripe hosted page |
| N91 | SubscriptionsController#webhook | Handle Stripe events: subscription created/cancelled → update user.plan | webhook | → S_users | — |
| N92 | WorkoutsController#create | Check generation limit before calling LLM | gate | → S_uses | — |
| S_uses | generation_uses | user_id, created_at | — | — | — |

**What to build:**
- `plan` enum on users: `free` (default) / `pro`
- `generation_uses` table: insert one row per generation; count WHERE created_at > start_of_week
- Gate in `WorkoutsController#create`: free users blocked after 5; render upgrade prompt
- `SubscriptionsController`: create Stripe Checkout session (server-side); webhook endpoint (verify Stripe signature)
- Stripe webhook: `customer.subscription.created` → `user.update!(plan: :pro)`; `customer.subscription.deleted` → `user.update!(plan: :free)`
- Profile page: plan badge, upgrade button (free) or manage link (pro → Stripe billing portal)
- `WorkoutLLMGenerator`: route Pro users to `claude-sonnet-4-6`, free users stay on `claude-haiku-4-5`
- Add `stripe` gem

**Demo:** Free user generates 5 workouts → 6th attempt shows "You've used your 5 free generations this week — upgrade to Pro for unlimited" → click Upgrade → Stripe → return → Pro badge on profile → unlimited generations with Sonnet.

---

## V12: Workout Streaks

**Shape parts:** None (standalone, simple)

| # | Component | Affordance | Control | Wires Out | Returns To |
|---|-----------|------------|---------|-----------|------------|
| U100 | profile | Streak flame + count "🔥 12 weeks" | render | — | — |
| U101 | feed-card | Streak badge on own posts if ≥ 4 weeks | render | — | — |
| U102 | profile | "Longest streak: 24 weeks" | render | — | — |
| N100 | User#current_streak | Count consecutive ISO weeks with ≥ 1 workout_log | call | → S2 | — |

**What to build:**
- `User#current_streak`: query workout_logs grouped by ISO week; count consecutive weeks ending this week (cached in a computed column or low-TTL cache)
- `User#longest_streak`: same, find the longest run historically
- Streak display on profile page (current + longest)
- Streak badge on feed cards when streak ≥ 4 weeks (subtle, not spammy)

**Demo:** Log a workout each week for 6 weeks → profile shows "🔥 6 weeks" → feed posts show flame badge.

---

## V13: Training Plans (Pro)

**Shape parts:** C1–C7

| # | Component | Affordance | Control | Wires Out | Returns To |
|---|-----------|------------|---------|-----------|------------|
| U110 | plans-page | "Start a new plan" button (Pro only) | click | → U111 | — |
| U111 | plan-form | Goal input, session type, duration (4–12 weeks), sessions/week | type/select | → N110 | — |
| U112 | plan-dashboard | Week grid — sessions as cards, greyed if future | render | — | — |
| U113 | plan-session-card | Workout name + "Do this" / "View" | click | → log/preview | — |
| U114 | plan-dashboard | Week theme label (Build / Accumulate / Peak / Deload / Test) | render | — | — |
| U115 | plan-dashboard | Completion ring per week | render | — | — |
| U116 | plan-history | Completed plans list with summary stats | render | — | — |
| N110 | TrainingPlansController#create | Create plan record; enqueue TrainingPlanGeneratorJob for week 1 | call | → S_plans | → U112 |
| N111 | TrainingPlanGeneratorJob | Generate week N workouts using LLM; if N > 1, remix previous week's workouts with overload prompt modifier; enqueue next week | job | → S_sessions | — |
| N112 | TrainingPlansController#show | Load plan + weeks + sessions + completion status | call | → S_plans | → U112 |
| S_plans | training_plans | user_id, name, goal, main_tag_id, duration_weeks, sessions_per_week, status | — | — | — |
| S_weeks | training_plan_weeks | plan_id, week_number, theme, overload_pct, generated_at | — | — | — |
| S_sessions | training_plan_sessions | week_id, day_of_week, workout_id, completed_at | — | — | — |

**What to build:**
- `training_plans`, `training_plan_weeks`, `training_plan_sessions` tables + models
- Plan creation form (goal, type, duration, sessions/week) — Pro-gated
- `TrainingPlanGeneratorJob`:
  - Week 1: call `WorkoutLLMGenerator` N times for the chosen session type
  - Week 2+: remix each week-1 workout with prompt suffix: "Increase all working loads by {overload_pct}%, add 1 set to the main working block"
  - Overload schedule: W1=0%, W2=+5%, W3=+7%, W4=+5%, W5=−20% (deload), W6=test/benchmark
  - Enqueue next week's job on completion; Turbo Stream notifies plan dashboard as each week lands
- Plan dashboard: week grid, session cards, completion rings, week themes
- Completed plan summary stored in user profile; passed as context to future plan generations ("Previous plan: 6-week Hyrox prep. Final week loads: sandbag lunge 25kg, wall balls 9kg. Build from these baselines.")
- Plan history page showing all completed plans

**Demo (Pro):** Tap "New Plan" → "6-week Hyrox prep, 3 sessions/week, intermediate" → plan dashboard appears with Week 1 generating → 3 sessions appear → complete them → Week 2 loads are heavier → Week 5 is labelled Deload → Week 6 is test week.

---

## V14: Share Card

**Shape parts:** None (standalone)

| # | Component | Affordance | Control | Wires Out | Returns To |
|---|-----------|------------|---------|-----------|------------|
| U120 | workout-log-detail | "Share" button | click | → N120 | — |
| U121 | share-sheet | Native OS share sheet with PNG attached | render | — | — |
| N120 | WorkoutLogsController#share_card | Render workout card as PNG; return as download/share | call | — | → U121 |

**What to build:**
- Server-side PNG generation: render a styled ERB template as HTML, convert to PNG via Grover (Puppeteer) or html2image gem
- Share card design: BSB branding, workout name, key stats (duration, sweat rating, exercise highlights), QR code linking to the post
- `WorkoutLogsController#share_card`: generate PNG, serve as `image/png` for download or Base64 for JS share API
- Use Web Share API (`navigator.share({ files: [png] })`) on mobile for native share sheet; fallback to download link on desktop

**Demo:** Tap Share on a workout post → native share sheet opens with a styled workout image → share to WhatsApp/Instagram Stories.

---

## V15: AI Coaching Insights (Pro)

**Shape parts:** None (standalone, Pro-only)

**Model strategy:** Workout generation uses Claude Haiku (fast, structured, follows rules well). Coaching features use Claude Sonnet (better reasoning and narrative quality; acceptable on on-demand or async requests where speed matters less).

### V15a: Coach's Notes (on-demand, any workout)

| # | Component | Affordance | Control | Wires Out | Returns To |
|---|-----------|------------|---------|-----------|------------|
| U128 | workout/show | "Coach's Notes" button (lazy Turbo Frame) | click | → N128 | U129 |
| U129 | coaching-notes | Coaching rationale: why these reps/loads, what to focus on, how it fits a training week | render | — | — |
| N128 | CoachingNotesController#show | Receives workout_id; builds prompt from workout structure + user context; calls Sonnet; caches result against workout_id forever | call | → S_notes | U129 |
| S_notes | coaching_notes | workout_id, narrative (text), generated_at | — | — | — |

**What to build:**
- `coaching_notes` table (cached forever per workout — generate once, serve many times)
- `CoachingNotesController`: lazy Turbo Frame; calls Sonnet with workout structure + user context; returns 3-4 sentences covering rationale, focus cues, and training context
- Button on workout show page inside a `<turbo-frame>` — only fires on tap, not on page load
- Available to all users (good showcase of AI depth; not gated behind Pro)

**Demo:** Tap "Coach's Notes" on a Hyrox workout → "This session targets your ski erg and sled push weak points identified in your last race. The 65% rep counts give you enough stimulus to build capacity without the CNS cost of a full simulation. Focus on hip extension at the top of each ski pull…"

### V15b: Weekly Coaching Digest (Pro, async)

| # | Component | Affordance | Control | Wires Out | Returns To |
|---|-----------|------------|---------|-----------|------------|
| U130 | profile/coaching | Weekly digest card | render | — | — |
| U131 | coaching | "This week" stats: sessions, volume, avg sweat | render | — | — |
| U132 | coaching | AI narrative: trends, flags, encouragement | render | — | — |
| N130 | GenerateCoachingInsightJob | Weekly job (Monday morning); queries last 4 weeks of logs; calls Sonnet for narrative; stores result | job | → S_insights | — |
| S_insights | coaching_insights | user_id, week_start, stats_json, narrative, generated_at | — | — | — |

**What to build:**
- `coaching_insights` table
- `GenerateCoachingInsightJob`: Solid Queue recurring, Pro users only; aggregates: session count, total volume (sets × reps × kg), workout types, avg sweat rating, PRs set, streak status vs 4-week rolling average; calls Sonnet for 3-sentence coaching narrative + 1 action recommendation
- Coaching tab on profile (Pro badge): this week's digest + last 4 weeks history
- Load management flag: if this week's volume > 130% of 4-week avg, include "Consider a lighter session this week" warning

**Demo (Pro):** Monday morning → open app → coaching tab shows "You trained 4 times last week, up from your 3-session average. Your deadlift volume hit a new high. This week: consider one lower-body recovery session."

---

## V16: PWA — Install, Push, Offline

**Shape parts:** D1–D5

| # | Component | Affordance | Control | Wires Out | Returns To |
|---|-----------|------------|---------|-----------|------------|
| U140 | install-prompt | "Add to home screen" banner (after 3rd session) | click | → browser install | — |
| U141 | push-settings | "Enable notifications" toggle on profile | toggle | → N140 | — |
| U142 | push-notification | Follow request / challenge result / plan session ready | receive | — | — |
| U143 | offline-banner | "You're offline — your log will sync when reconnected" | render | — | — |
| N140 | PushSubscriptionsController#create | Store Web Push subscription endpoint + keys | call | → S_push | — |
| N141 | NotificationJob | Send push via web-push gem for follows, challenges, plan sessions | job | → S_push | — |

**What to build:**
- `manifest.json`: name, icons (192 + 512px), theme_color, background_color, display: standalone, start_url: /feed
- Link manifest in layout `<head>`
- Service Worker (`service-worker.js`): cache shell (CSS, JS, fonts); serve cached feed page when offline; queue log submissions in IndexedDB; sync when reconnected
- VAPID key pair (generated once, stored in credentials)
- `push_subscriptions` table: user_id, endpoint, p256dh, auth
- `web-push` gem: send notifications on follow request, challenge leaderboard position, plan week ready
- Install prompt: Stimulus controller that catches `beforeinstallprompt` event; shows banner after 3 app loads
- Push permission request prompt on profile settings

**Demo:** Install app to home screen → enable notifications → receive push when a friend follows you → open offline → see cached feed → log a workout → it syncs when back online.

---

## V17: Native Apps (iOS + Android)

**Shape parts:** E1–E5

**Notes:** This is a large programme of work — plan as its own project once PWA is stable and user numbers justify the investment. The web app's Hotwire architecture can be wrapped in a native shell (Turbo Native) as the fastest path to App Store presence.

**Approach options (decide at V17 planning):**
- **Turbo Native** (fastest): thin Swift/Kotlin shell wrapping the Rails Hotwire web app. Full feature parity immediately. Push via APNs/FCM. HealthKit bridge via native code.
- **React Native**: single JS codebase for iOS + Android. More work upfront but better native feel. Requires Rails JSON API.
- **Swift/Kotlin native**: most native feel, best HealthKit/Google Fit integration, most work.

**What to build (regardless of approach):**
- Rails API endpoints (JSON) for all data: workouts, logs, feed, profile, plans, challenges
- Token-based auth (replace session cookies)
- APNs / FCM push replacing Web Push
- App Store / Google Play listings
- Turbo Native bridge or React Native app

**Demo:** Download from App Store → log in → full app with push notifications → Apple Watch HR data on workout post.

---

## V18: Device Integration (native app required)

**Shape parts:** F1–F6

**Dependency:** V17 must ship first. HealthKit requires a native iOS app. Google Health Connect requires native Android.

| # | Component | Affordance | Control | Wires Out | Returns To |
|---|-----------|------------|---------|-----------|------------|
| U150 | workout-log-form | "Import from Apple Watch" toggle (iOS only) | toggle | → native bridge | — |
| U151 | feed-card | Device stats badge: ❤️ 142 avg HR · 🔥 380 kcal | render | — | — |
| U152 | workout-log-detail | Full HR zone breakdown chart | render | — | — |
| N150 | Native bridge | Request HealthKit / Google Fit workout data for session timeframe | call | → device | — |
| N151 | WorkoutLogsController#update | Store device_stats jsonb: avg_hr, max_hr, hr_zones, calories, duration_s | call | → S2 | — |

**What to build:**
- Native bridge (Swift/Kotlin or React Native module): read HealthKit HKWorkoutSession or Google Health Connect session
- Request permissions on first log post-install
- Match device workout to BSB log by start time ± 5 minutes
- `device_stats` jsonb column on `workout_logs`: `{ avg_hr, max_hr, hr_zones: {z1..z5}, active_calories, source }`
- Feed card: compact stat badge when device_stats present
- Workout log detail: HR zone breakdown as simple bar chart (Chartkick or native chart)
- Garmin Health API as optional web-accessible data source (interim before native — REST API + OAuth2)

**Demo (native app):** Complete a workout wearing Apple Watch → post log → BSB automatically pulls HR + calories → feed card shows "❤️ 148 avg · 🔥 420 kcal" → tap for HR zone breakdown.

---

## V19: Community Challenges + Friend Challenges

**Shape parts:** None (extends V5 + V8)

| # | Component | Affordance | Control | Wires Out | Returns To |
|---|-----------|------------|---------|-----------|------------|
| U160 | feed-card | "Challenge a friend" button | click | → U161 | — |
| U161 | challenge-modal | Pick follower to challenge | select | → N160 | — |
| U162 | notification | "Alex challenged you to do [workout]" | receive | — | — |
| U163 | weekly-board | Weekly community leaderboard (most sessions, heaviest lift, etc.) | render | — | — |
| N160 | ChallengesController#create | Create friend challenge record; send push notification | call | → S_challenges | — |

**What to build:**
- Friend challenge: tap "Challenge" on a workout log → pick a follower → they get a push notification; if they log the same workout within 7 days, both get a notification comparing results
- Weekly community leaderboards: most workouts, highest sweat rating average, heaviest single lift — reset each Monday; shown on a Challenges tab
- `friend_challenges` table: challenger_id, challenged_id, workout_id, created_at, responded_at

**Demo:** Tap "Challenge" on your Hyrox workout → pick Sarah → Sarah gets push → Sarah logs it → both see side-by-side comparison.

---

## Dependency Map

```
V7 (PRs) → no hard deps but groupdate gem shared with V9
V8 (Challenges) → no hard deps
V9 (Calendar) → groupdate gem (also in V7)
V11 (Pro/Stripe) → should ship before V13, V15 (those are Pro features)
V12 (Streaks) → no hard deps
V13 (Plans) → V11 (Pro gate), uses V6 (remix logic)
V14 (Share Card) → V2 (workout logs)
V15 (Coaching) → V11 (Pro gate), V2 (logs for data)
V16 (PWA) → can ship any time; enables better mobile UX for V8 challenges
V17 (Native Apps) → V16 recommended first; big programme of work
V18 (Device) → V17 required
V19 (Community Challenges) → V5 (follows), V8 (challenge infra)
```

## Suggested Build Order (next 6 slices)

1. **V7** PR Detection + Progress Charts — high user value, self-contained
2. **V8** Daily Challenges — drives daily engagement, community feel
3. **V11** Pro Tier + Stripe — unlocks revenue before building Pro features
4. **V9** Calendar History — completes the core personal tracking loop
5. **V12** Workout Streaks — low effort, high retention impact
6. **V13** Training Plans — headline Pro feature, justifies subscription
