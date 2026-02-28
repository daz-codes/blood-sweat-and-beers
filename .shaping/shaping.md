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

---

## Problem

Athletes training in Deka/Hyrox-style functional fitness have no tailored social platform. Generic apps don't understand the format. Strava is GPS-only. There's no community layer purpose-built for this kind of training — no way to share, discover, be challenged daily, or track meaningful improvement over time.

## Outcome

A focused social fitness app where users generate structured Deka/Hyrox-style workouts, log their performance, track PRs, compete on daily WODs, and share within a trusted community of accepted followers. Progress is visible, measurable, and social.

---

## Requirements (R)

| ID | Requirement | Status |
|----|-------------|--------|
| **R0** | **Auth & Profile** | Core goal |
| R0.1 | Authenticated users can access the app (auth already built) | Core goal |
| R0.2 | User profile stores name, avatar, fitness preferences | Core goal |
| R0.3 | Profiles are private by default; follow requests must be accepted | Core goal |
| **R1** | **Workout Types & Formats** | Core goal |
| R1.1 | 🟡 Workouts are tagged with user-created free-text tags (polymorphic taggable); Deka/Hyrox expressed as tags | 🟡 Core goal |
| R1.2 | 🟡 Tags are selected at workout creation and generation time | 🟡 Core goal |
| R1.3 | 🟡 Format is expandable (custom workouts now first-class; Deka/Hyrox are tags/formats) | 🟡 Core goal |
| **R2** | **Workout Generation & Creation** | Core goal |
| R2.1 | 🟡 "New Workout" entry point is a chooser: Generate / Enter Own / From Library | Core goal |
| R2.2 | 🟡 Generator produces structured workout: sections (AMRAP/rounds/straight) with exercises having optional metrics (reps, distance_m, weight_kg, duration_s) | 🟡 Core goal |
| R2.3 | Hyrox simulation mode: mimics actual race format (1km run × 8 + 8 stations in order) | Core goal |
| R2.4 | Generated workouts can be saved to personal library | Core goal |
| R2.5 | 🟡 LLM (Haiku) via tool use is primary and only generation path; Ruby generator retired | 🟡 Core goal |
| R2.6 | 🟡 Users can create a custom workout: name + description/notes, free-form (no structured steps) | 🟡 Core goal |
| R2.7 | 🟡 Workouts have a separate like count (workout_likes) used to rank generation context selection | 🟡 Core goal |
| **R3** | **Workout Logging** | Core goal |
| R3.1 | Log per-exercise: sets/reps/weight OR time/distance | Core goal |
| R3.2 | Post-workout: sweat rating (1–5) + optional notes | Core goal |
| R3.3 | Auto-detect and surface per-exercise PR achievements after each log | Core goal |
| R3.4 | Optional location tagging on a workout post | Nice-to-have |
| **R4** | **Personal Library, History & Progress** | Core goal |
| R4.1 | Calendar view of workout history | Core goal |
| R4.2 | 🟡 Personal library: saved workout templates (own + others'), organised into user-created categories | 🟡 Core goal |
| R4.3 | 🟡 Saving another user's workout to library stores a reference link (not a copy); original user retains ownership | 🟡 Core goal |
| R4.4 | Progress charts per exercise: weight/time/reps over time to visualise improvement | Core goal |
| R4.5 | 🟡 Library categories are user-created and editable (rename, add, delete); default "Workouts" category created on signup | 🟡 Core goal |
| **R5** | **Social Feed & Interactions** | Core goal |
| R5.1 | Feed shows only own workouts + workouts from accepted followers (no public discovery) | Core goal |
| R5.2 | Follow requests must be accepted before the requester sees your workouts | Core goal |
| R5.3 | Public/private visibility per individual workout post | Core goal |
| R5.4 | Like workout posts | Core goal |
| R5.5 | Flat comments on workout posts | Core goal |
| R5.6 | 🟡 Save a workout from the feed into personal library (reference link; user picks target category) | Core goal |
| R5.7 | Daily WOD: a community workout posted each day; users post scores and a leaderboard ranks them | Core goal |
| **R6** | **Fitness Benchmarks** | Nice-to-have |
| R6.1 | Predefined benchmark tests (1-mile run, max push-ups, 1RM squat, 2km row, etc.) | Nice-to-have |
| R6.2 | Log results over time with progress charts | Nice-to-have |
| R6.3 | Compare scores against age/gender norms | Nice-to-have |
| R6.4 | Periodic reminders to retest benchmarks | Nice-to-have |
| **R7** | **Community Challenges** | Nice-to-have |
| R7.1 | Weekly challenges (most workouts, heaviest lift, fastest time, etc.) | Nice-to-have |
| R7.2 | Challenge leaderboards | Nice-to-have |
| **R8** | **Device Integration** | Nice-to-have |
| R8.1 | Garmin watch integration | Nice-to-have |
| R8.2 | Apple Watch / Apple Fitness integration | Nice-to-have |
| R8.3 | Import workout data from connected devices | Nice-to-have |

---

## Open Questions

| # | Question | Resolution |
|---|----------|------------|
| OQ1 | SQLite vs PostgreSQL? | ✅ **PostgreSQL** — switch needed before schema design; sqlite3 gem → pg; database.yml update |
| OQ2 | Sweat rating vs computed suffer score — same or different? | ✅ **Sweat rating only** (1–5, user-given). No computed score. App is Blood, Sweat and Beers — the sweat rating is the thing |
| OQ3 | PRs: per-exercise or per-workout-format? | ✅ **Per-exercise PRs** (best weight, best time, best distance, best reps per exercise). Also: daily WOD leaderboard, and time-series tracking for all logged values to chart improvement |
| OQ4 | Comments: flat or threaded? | ✅ **Flat** — simpler for v1 |
| OQ5 | User profiles: public by default? | ✅ **Private by default** — follow requests require acceptance. New users see only their own workouts. |
| OQ6 | What does "enter your own" workout look like? | ✅ **Free-form** — name + description/notes, no structured steps. No exercise library lookup. Can be logged (log form shows just the completion section, no per-step inputs). |
| OQ7 | How do categories relate to workout type (Hyrox/Deka)? | ✅ **Separate concepts** — categories are user-created library folders for organising saved workout templates. Hyrox/Deka remain as workout types on the workout record (used at creation time). Default "Workouts" category created on signup; user can add/rename/delete their own. |
| OQ8 | When saving another user's workout, copy or reference? | ✅ **Reference link** — `library_workouts` join record points to original workout. No copy is made. Original user retains ownership. |

---

## Shape A: Ruby POC → LLM upgrade path

**Direction confirmed.** Two key architectural decisions baked in: PostgreSQL (jsonb for flexible workout structures), and a generator abstraction that lets the Ruby service and the future LLM job share the same output interface.

| Part | Mechanism | Flag |
|------|-----------|:----:|
| **A1** | **Exercise library** | |
| A1.1 | `exercises` table: name, type, movement_pattern, equipment, format_tags (deka/hyrox) | |
| A1.2 | Hyrox station set: 8 ordered stations + run format rules seeded as constants | |
| A1.3 | Deka station set: 10 stations + format rules seeded as constants | |
| **A2** | **Workout model + Tags** | |
| A2.1 | 🟡 `workouts` table: user_id, workout_type (deka/hyrox/custom/etc.), name (for custom; nullable for generated), duration_mins, difficulty, structure (jsonb) | |
| A2.2 | 🟡 jsonb structure: `{ sections: [{ name, format, rounds, duration_mins, rest_secs, notes, exercises: [{ name, reps, distance_m, weight_kg, duration_s, notes }] }], duration_mins, goal }` — empty sections `[]` for custom free-form workouts | |
| A2.3 | Workout owned by the user who created it; `source_workout_id` tracks origin (nil for original, set when derived) | |
| A2.4 | 🟡 Custom workout creation: name + description fields; workout_type = "custom"; structure = []; can be saved to library and logged (log form shows completion section only, no per-step inputs) | |
| A2.5 | 🟡 `tags` table: id, name, slug (unique); `taggings` table: id, tag_id, taggable_type, taggable_id — polymorphic index; `Tag.find_or_create_by(slug:, name:)` on save | |
| A2.6 | 🟡 `Workout has_many :taggings, as: :taggable; has_many :tags, through: :taggings`; `Tag.used_on_workouts` scope populates generator form | |
| **A3** | **New Workout entry point** | |
| A3.1 | 🟡 `WorkoutGenerator` (Ruby POC) retired entirely — LLM generator is the only path | |
| A3.2 | Hyrox sim mode: deferred — running expressed via tag selection | |
| A3.3 | 🟡 Output interface: `Workout` record with populated jsonb structure (new sections schema) — created by LLM generator | |
| A3.4 | 🟡 "New Workout" chooser screen: three paths — Generate (→ generator form), Enter Own (→ custom workout form), From Library (→ library picker) | |
| **A4** | **LLM generator (primary)** | |
| A4.1 | 🟡 `WorkoutLLMGenerator.call(user:, tag_ids:, duration_mins:, difficulty:)` — synchronous; replaces WorkoutGenerator entirely | |
| A4.2 | 🟡 Selects up to 25 workouts via `Workout.most_liked_with_tags(tag_ids, limit: 25)`; broadens to all liked workouts if fewer than 5 match | |
| A4.3 | 🟡 Calls Anthropic API (claude-haiku-4-5) with tool use — tool definition encodes the sections jsonb schema; no fallback on failure, raises `WorkoutGenerationError` surfaced to user | |
| **A5** | **Workout logging** | |
| A5.1 | `workout_logs` table: user_id, workout_id, completed_at, sweat_rating (1–5), notes (ActionText), location | |
| A5.2 | `exercise_logs` table: workout_log_id, exercise_id, sets_data (jsonb: [{reps, weight, time, distance}]) | |
| A5.3 | PR detection: after save, compare each exercise_log value against historical bests; write `personal_records` if new best found | |
| A5.4 | `personal_records` table: user_id, exercise_id, metric (weight/time/reps/distance), value, achieved_at, workout_log_id | |
| **A6** | **Personal library & history** | |
| A6.1 | 🟡 `library_categories` table: id, user_id, name, position; default "Workouts" category created on signup | |
| A6.2 | 🟡 `library_workouts` table: id, user_id, workout_id, library_category_id, saved_at; unique per user+workout (save once, moveable between categories) | |
| A6.3 | 🟡 Library page: shows categories as sections; each section lists saved workouts with name/type/duration; "Start" → Log page; "Remove from library" action | |
| A6.4 | 🟡 Category management: create new category, rename existing, delete (prompts to move contents or remove entries first) | |
| A6.5 | 🟡 From Library path in New Workout chooser: browse categories → tap workout → go directly to Log page | |
| A6.6 | Calendar view: WorkoutLogs grouped by completed_at date (Groupdate) | |
| A6.7 | Progress charts: exercise_logs for a given exercise_id over time → Chartkick line chart per metric | |
| **A7** | **Follow graph & feed** | |
| A7.1 | `follows` table: follower_id, following_id, status (pending/accepted), requested_at, accepted_at | |
| A7.2 | Follow request flow: request → notification → accept/decline; only accepted follows unlock feed access | |
| A7.3 | Feed query: WorkoutLogs WHERE (user_id = current_user OR user_id IN accepted_follower_ids) AND visibility != 'private'; ordered by completed_at DESC | |
| A7.4 | Turbo Frames for feed pagination; Turbo Streams for new post insertion without reload | |
| **A8** | **Social interactions** | |
| A8.1 | 🟡 `likes` table: user_id, workout_log_id (social feed likes, toggled via Turbo Stream); separate `workout_likes` table: user_id, workout_id (generation ranking signal, unique per user+workout) | |
| A8.2 | `comments` table: user_id, workout_log_id, body, created_at (flat, not threaded) | |
| A8.3 | 🟡 Save to Library action: creates `library_workouts` record (reference, no copy); user picks target category via inline picker; available from feed cards, post detail, and post-generate preview | |
| **A9** | **Daily WOD** | |
| A9.1 | 🟡 `wods` table: date (unique), title, description, workout_id (FK to workouts), scoring_type (time/reps/weight/rounds) — no created_by; system-owned | |
| A9.2 | `wod_entries` table: user_id, wod_id, score (numeric: seconds/reps/kg), rx (boolean: as-prescribed), notes, logged_at | |
| A9.3 | Leaderboard: wod_entries for today's WOD ordered by score (asc for time, desc for reps/weight/rounds) | |
| A9.4 | WOD shown on home screen each day; users can log a result inline; leaderboard updates via Turbo Stream | |
| A9.5 | 🟡 `GenerateDailyWodJob`: Solid Queue recurring job, runs at midnight, calls `WorkoutGenerator` with rotating type/difficulty, creates `Wod` + associated `Workout` for next day | |
| **A10** | **Benchmarks, challenges, device integration** | ⚠️ |
| A10.1 | Fitness benchmarks (R6): deferred to v2 | ⚠️ |
| A10.2 | Weekly challenges (R7): deferred to v2 | ⚠️ |
| A10.3 | Garmin / Apple Watch (R8): deferred to v3 | ⚠️ |

---

## Fit Check: R × A

| Req | Requirement | Status | A |
|-----|-------------|--------|---|
| R0.1 | Authenticated access | Core goal | ✅ |
| R0.2 | User profile (name, avatar, preferences) | Core goal | ✅ |
| R0.3 | Private profiles, follow requests require acceptance | Core goal | ✅ |
| R1.1 | 🟡 Workouts tagged with user-created free-text tags; Deka/Hyrox expressed as tags | Core goal | ✅ |
| R1.2 | 🟡 Tags selected at workout creation and generation time | Core goal | ✅ |
| R1.3 | Format is expandable; custom workouts are first-class | Core goal | ✅ |
| R2.1 | "New Workout" is a chooser: Generate / Enter Own / From Library | Core goal | ✅ |
| R2.2 | 🟡 Structured workout: sections (AMRAP/rounds/straight) with exercises having optional metrics | Core goal | ✅ |
| R2.3 | Hyrox simulation mode | Core goal | ✅ |
| R2.4 | Generated workouts can be saved to personal library | Core goal | ✅ |
| R2.5 | 🟡 LLM (Haiku) via tool use is primary and only generation path; Ruby generator retired | Core goal | ✅ |
| R2.6 | Users can create a custom workout (name + description, free-form) | Core goal | ✅ |
| R2.7 | 🟡 Workouts have workout_likes for generation ranking (separate from feed likes) | Core goal | ✅ |
| R3.1 | Log per-exercise: sets/reps/weight or time/distance | Core goal | ✅ |
| R3.2 | Sweat rating (1–5) + notes | Core goal | ✅ |
| R3.3 | Auto-detect per-exercise PRs | Core goal | ✅ |
| R3.4 | Optional location tagging | Nice-to-have | ✅ |
| R4.1 | Calendar view of workout history | Core goal | ✅ |
| R4.2 | Library: saved workout templates (own + others'), organised by user-created categories | Core goal | ✅ |
| R4.3 | Saving another user's workout stores a reference link, not a copy | Core goal | ✅ |
| R4.4 | Progress charts per exercise over time | Core goal | ✅ |
| R4.5 | Library categories are user-created and editable; default "Workouts" on signup | Core goal | ✅ |
| R5.1 | Feed: own + accepted followers only (no public discovery) | Core goal | ✅ |
| R5.2 | Follow requests require acceptance | Core goal | ✅ |
| R5.3 | Public/private per workout post | Core goal | ✅ |
| R5.4 | Like workout posts | Core goal | ✅ |
| R5.5 | Flat comments on workout posts | Core goal | ✅ |
| R5.6 | Save workout from feed to personal library (reference, user picks category) | Core goal | ✅ |
| R5.7 | Daily WOD with leaderboard | Core goal | ✅ |
| R6.1 | Predefined benchmark tests | Nice-to-have | ❌ |
| R6.2 | Benchmark progress charts | Nice-to-have | ❌ |
| R6.3 | Age/gender norm comparison | Nice-to-have | ❌ |
| R6.4 | Retest reminders | Nice-to-have | ❌ |
| R7.1 | Weekly challenges | Nice-to-have | ❌ |
| R7.2 | Challenge leaderboards | Nice-to-have | ❌ |
| R8.1 | Garmin integration | Nice-to-have | ❌ |
| R8.2 | Apple Watch integration | Nice-to-have | ❌ |
| R8.3 | Device data import | Nice-to-have | ❌ |

**Notes:**
- All Core goal requirements pass ✅
- R2.5 passes via A4: Ruby generator retired; `WorkoutLLMGenerator` (Haiku, tool use) is the only generation path; no fallback
- R1.1/R1.2 pass via A2.5/A2.6: polymorphic tags + taggings; free-text, created on save
- R2.7 passes via A8.1: `workout_likes` table separate from social `likes` on workout_logs
- R4.3 passes via A6.2 (`library_workouts` reference table) — no copy is made; reference semantics are sufficient for v1
- R6, R7, R8 are intentionally ❌ — deferred to v2/v3
- See `generation-shaping.md` for full detail on the generation rework
