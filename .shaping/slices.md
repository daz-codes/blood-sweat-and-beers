---
shaping: true
---

# Blood Sweat Beers — Slices

Vertical implementation slices derived from the breadboard. Each slice ends in demo-able UI. Build in order — later slices depend on earlier ones.

---

## Slice Summary

| # | Slice | Shape Parts | Demo | Status |
|---|-------|-------------|------|--------|
| V1 | Workout Generation (Ruby POC) | A1, A2, A3 | "Select Hyrox, 45 mins → see structured workout plan" | ✅ Built — superseded by GR1–GR3 |
| V2 | Workout Logging | A5.1, A5.2 | "Log sets/reps + sweat rating → WorkoutLog saved" | ✅ Built |
| V3 | Own Feed | A7.1–A7.4 (own only) | "My logged workouts appear in feed with cards" | ✅ Built |
| GR1 | Tags + new workout structure | gen-A1, A2 | "View a workout — see its tags and sections-based structure" | ⬜ Next |
| GR2 | Workout likes | gen-A3 | "Like a workout — count updates live; ranking method ready" | ⬜ |
| GR3 | LLM generator + form + seeding | gen-A4, A5, A6 | "Pick 'deka' + 30 mins → LLM generates a new sections-based workout" | ⬜ |
| V4 | Follow Graph + Private Profiles | A7.1–A7.3, R0.3 | "Request to follow → accept → see each other's workouts" | ⬜ |
| V5 | Likes + Comments | A8.1, A8.2 | "Like post → count updates live; comment → appends" | ⬜ |
| V6 | Library + Custom Workout + Chooser | A2.4, A3.4, A6.1–A6.5, A8.3 | "Save a workout to library → browse by category → start it; create custom workout" | ⬜ |
| V7 | PR Detection + Progress Charts | A5.3, A5.4, A6.4 | "Log heavier lift → PR badge fires; view exercise chart" | ⬜ |
| V8 | Daily WOD | A9.1–A9.5 | "WOD on home screen; log result; leaderboard updates live" | ⬜ — N100 must use WorkoutLLMGenerator after GR3 |
| V9 | Calendar History | A6.2 | "Heatmap of all workouts; tap day → see what you did" | ⬜ |

> GR1–GR3 detail: see `generation-slices.md`

---

## V1: Workout Generation

**Shape parts:** A1 (exercise library), A2 (workout model + jsonb), A3 (Ruby generator)

**Affordances in this slice:**

| # | Component | Affordance | Control | Wires Out | Returns To |
|---|-----------|------------|---------|-----------|------------|
| U21 | generator-form | Workout type selector (Deka / Hyrox) | select | — | — |
| U22 | generator-form | Duration input (minutes) | type | — | — |
| U23 | generator-form | Difficulty selector | select | — | — |
| U24 | generator-form | Equipment checkboxes | toggle | — | — |
| U25 | generator-form | "Generate" button | click | → N20 | — |
| U26 | workout-preview | Generated workout (Turbo Frame) | render | — | — |
| U27 | workout-preview | Loading spinner | render | — | — |
| U28 | workout-preview | "Start Logging" button | click | → P3 | — |
| U29 | workout-preview | "Save as Template" button | click | → N22 | — |
| U30 | workout-preview | "Regenerate" button | click | → N20 | — |
| N20 | WorkoutsController#create | POST /workouts; calls WorkoutGenerator | call | → N21 | → U26/U27 |
| N21 | WorkoutGenerator.call | Selects from exercises table, builds jsonb structure | call | → S1, S10 | → N20 |
| N22 | WorkoutsController#save_template | PATCH status=template | call | → S1 | → flash |
| S1 | workouts | user_id, type, duration_mins, difficulty, status, structure (jsonb) | — | — | — |
| S10 | exercises | name, type, equipment, format_tags (seeded) | — | — | — |

**What to build:**
- Seed `exercises` table with Deka and Hyrox station sets (A1.1–A1.3)
- `WorkoutGenerator` service with Hyrox sim mode (fixed station order + run segments) and standard Deka mode
- `Workouts` model with jsonb `structure` column (PostgreSQL)
- `WorkoutsController#create` — calls generator, responds with Turbo Frame preview
- Generator form page (P2) with Turbo Frame target for preview

**Demo:** Open Generate page → select Hyrox, 45 mins, intermediate → click Generate → see structured workout with 8 stations and run segments.

---

## V2: Workout Logging

**Shape parts:** A5.1 (workout_logs), A5.2 (exercise_logs with sets_data jsonb)

**Affordances in this slice:**

| # | Component | Affordance | Control | Wires Out | Returns To |
|---|-----------|------------|---------|-----------|------------|
| U31 | workout-header | Workout type, duration, source | render | — | — |
| U32 | exercise-list | Exercise name + target sets/reps/rest | render | — | — |
| U33 | set-logger | Set row: reps + weight (or time / distance) inputs | type | → N30 | — |
| U34 | set-logger | "Add set" button | click | → U33 | — |
| U35 | set-logger | "Exercise done" checkmark | click | — | — |
| U36 | progress-bar | Exercises done / total | render | — | — |
| U37 | completion-form | "Complete Workout" button | click | → U38 | — |
| U38 | completion-form | Sweat rating selector (1–5 drops) | select | — | — |
| U39 | completion-form | Notes field (ActionText) | type | — | — |
| U40 | completion-form | Location input (optional) | type | — | — |
| U41 | completion-form | Visibility toggle (public / private) | toggle | — | — |
| U42 | completion-form | "Post to Feed" button | click | → N35 | — |
| N30 | ExerciseLogsController#create | Creates ExerciseLog with sets_data jsonb | call | → S3 | — |
| N35 | WorkoutLogsController#create | Creates WorkoutLog; redirects to post detail | call | → S2, N36 | → P4 |
| N36 | PRDetectionService.call | Stub for now — wired but no-op until V7 | call | — | — |
| S2 | workout_logs | user_id, workout_id, completed_at, sweat_rating, notes, location, visibility | — | — | — |
| S3 | exercise_logs | workout_log_id, exercise_id, sets_data (jsonb) | — | — | — |

**What to build:**
- `WorkoutLogs` and `ExerciseLogs` models + migrations
- Log Workout page (P3): renders workout.structure as loggable set rows
- Stimulus controller for dynamic set rows (add/remove)
- Completion form with sweat rating (star/drop selector)
- `WorkoutLogsController#create` — saves log, calls (stubbed) PR detection, redirects to post detail (P4, basic view for now)
- ActionText for notes field

**Demo:** Click "Start Logging" on a generated Hyrox workout → log 3 sets of sled push → complete → enter sweat rating 4 → Post → redirected to workout post.

---

## V3: Own Feed

**Shape parts:** A7.2 (feed query — own only), A7.4 (Turbo Frames pagination)

**Affordances in this slice:**

| # | Component | Affordance | Control | Wires Out | Returns To |
|---|-----------|------------|---------|-----------|------------|
| U1 | nav-bar | Navigation (Feed / Generate / Library / Profile) | render | → P1/P2/P5/P6 | — |
| U2 | feed | Workout post card list | render | — | — |
| U3 | feed | "Generate Workout" FAB | click | → P2 | — |
| U14 | post-card | User avatar, name, type badge, date, sweat rating | render | — | — |
| U15 | post-card | Exercise summary (first 3) | render | — | — |
| U19 | post-card | Tap card → post detail | click | → P4 | — |
| U20 | feed | Infinite scroll sentinel | scroll | → N19 | — |
| U44 | post-header (P4) | User avatar, name, date, location, type badge | render | — | — |
| U45 | post-detail (P4) | Full exercise list with logged values | render | — | — |
| U46 | post-detail (P4) | Sweat rating display | render | — | — |
| U47 | post-detail (P4) | Notes display | render | — | — |
| N1 | FeedController#index | WorkoutLogs WHERE user_id = current; ordered DESC | call | → S2 | → U2, U14 |
| N19 | FeedController#index (page N) | Next page via Turbo Frame | call | → S2 | → U2 (append) |

**What to build:**
- `FeedController#index` — queries own WorkoutLogs, paginates (Pagy or kaminari)
- Feed layout (P1) with post cards partial
- Post card: type badge, sweat rating drops display, exercise summary
- Turbo Frame infinite scroll (page sentinel + frame lazy load)
- Full post detail view (P4) — exercises with logged sets, sweat rating, notes
- Nav bar with links to Feed / Generate / Library / Profile
- Home screen defaults to Feed after login

**Demo:** Log two workouts → go to Feed → see both as cards in reverse chronological order → scroll down if more → tap a card → see full detail.

---

## V4: Follow Graph + Private Profiles

**Shape parts:** A7.1 (follows table), A7.2 (feed updated to include followed users), A7.3 (follow request flow), R0.3 (private by default)

**Affordances in this slice:**

| # | Component | Affordance | Control | Wires Out | Returns To |
|---|-----------|------------|---------|-----------|------------|
| U4 | follow-badge | Follow requests notification badge | click | → P7 | — |
| U67 | profile-header | Avatar, name, bio | render | — | — |
| U68 | profile-stats | Workout count, PR count, followers, following | render | — | — |
| U69 | follow-actions | "Request to Follow" button | click | → N80 | — |
| U70 | follow-actions | "Requested" (pending, tap to cancel) | click | → N82 | — |
| U71 | follow-actions | "Following" / "Unfollow" | click | → N82 | — |
| U72 | workout-list | User's workouts (accepted followers only) | render | — | — |
| U73 | requests | Pending inbound requests list | render | — | — |
| U74 | requests | Accept button | click | → N91 | — |
| U75 | requests | Decline button | click | → N92 | — |
| N1 | FeedController#index | Updated: WHERE user_id = current OR user_id IN accepted_follower_ids | call | → S2, S5 | → U2 |
| N3 | FollowsController#pending_count | Inbound pending count for badge | call | → S5 | → U4 |
| N80 | FollowsController#create | Creates Follow (status=pending) | call | → S5 | → U70 (Turbo Frame) |
| N82 | FollowsController#destroy | Destroys Follow | call | → S5 | → U69 (Turbo Frame) |
| N90 | FollowsController#index | Pending inbound follows | call | → S5 | → U73 |
| N91 | FollowsController#update | Accept: status=accepted | call | → S5 | → U73 (Turbo Stream remove) |
| N92 | FollowsController#update | Decline: destroy record | call | → S5 | → U73 (Turbo Stream remove) |
| S5 | follows | follower_id, following_id, status (pending/accepted), requested_at, accepted_at | — | — | — |

**What to build:**
- `Follows` model + migration
- User Profile page (P6): stats, follow button states, workout list gated on accepted follow
- Follow Requests page/panel (P7): list with accept/decline (Turbo Stream)
- Follow requests notification badge (Turbo Stream count update on accept/decline)
- Update `FeedController#index` to include accepted followers' workouts
- Ensure private profile: `/users/:id` workout list hidden until follow accepted

**Demo:** User A requests to follow User B → User B sees badge → accepts → User A's feed now shows User B's workouts.

---

## V5: Likes + Comments

**Shape parts:** A8.1 (likes), A8.2 (comments)

**Affordances in this slice:**

| # | Component | Affordance | Control | Wires Out | Returns To |
|---|-----------|------------|---------|-----------|------------|
| U16 | post-card | Like button + count (Turbo Frame) | click | → N15 | — |
| U49 | post-actions | Like button + count in post detail (Turbo Stream) | click | → N50 | — |
| U51 | comments | Flat comments list | render | — | — |
| U52 | comments | Comment form (textarea + submit) | type/click | → N54 | — |
| U17 | post-card | Comment count link → post detail | click | → P4 | — |
| N15 | LikesController#toggle | Creates/destroys Like; Turbo Stream updates feed card like button | call | → S6 | → U16 |
| N50 | LikesController#toggle | Same — in post detail context | call | → S6 | → U49 |
| N54 | CommentsController#create | Creates Comment; Turbo Stream appends to comment list | call | → S7 | → U51 |
| S6 | likes | user_id, workout_log_id, created_at | — | — | — |
| S7 | comments | user_id, workout_log_id, body, created_at | — | — | — |

**What to build:**
- `Likes` model + migration; toggle endpoint (create if not exists, destroy if exists)
- Turbo Stream response for like toggle: updates like button + count in-place
- Like button on both feed cards (P1) and post detail (P4)
- `Comments` model + migration
- Comment form + flat comment list on post detail (P4)
- Turbo Stream appends new comment to list on create (no page reload)

**Demo:** On a friend's workout post → tap like → count increments instantly without reload → type comment → submit → comment appears below instantly.

---

## V6: Library + Custom Workout + New Workout Chooser

**Shape parts:** A2.4 (custom workout), A3.4 (chooser screen), A6.1–A6.5 (library categories + CRUD), A8.3 (save to library)

**Affordances in this slice:**

| # | Component | Affordance | Control | Wires Out | Returns To |
|---|-----------|------------|---------|-----------|------------|
| U18 | post-card | "Save to Library" button (feed) | click | → N17 | — |
| U50 | post-actions | "Save to Library" button (post detail) | click | → N17 | — |
| U51 | post-generate | "Save to Library" button (preview) | click | → N17 | — |
| U52 | save-picker | Category picker (inline dropdown) | select | → N17 | — |
| U53 | new-workout-chooser | Three options: Generate / Enter Own / From Library | click | → P2/P2b/P5 | — |
| U54 | library-page | Category sections with saved workout cards | render | — | — |
| U55 | library-card | Workout name, type, duration | render | — | — |
| U56 | library-card | "Start" button | click | → P3 | — |
| U57 | library-card | "Remove from library" action | click | → N61 | — |
| U58 | library-categories | "New Category" button | click | → N62 | — |
| U59 | library-categories | Category rename (inline edit) | type | → N63 | — |
| U60 | library-categories | Category delete | click | → N64 | — |
| U64 | custom-workout-form | Name input | type | — | — |
| U65 | custom-workout-form | Description / notes textarea | type | — | — |
| U66 | custom-workout-form | Category picker | select | — | — |
| U67 | custom-workout-form | "Save to Library" / "Start Now" buttons | click | → N65/P3 | — |
| N17 | LibraryWorkoutsController#create | Creates library_workouts record; Turbo Stream updates button state | call | → S_lib | → U18/U50/U51 |
| N60 | LibraryController#index | Loads library_categories + library_workouts for current user | call | → S_lib | → U54 |
| N61 | LibraryWorkoutsController#destroy | Removes library_workouts record | call | → S_lib | — |
| N62 | LibraryCategoriesController#create | Creates new category | call | → S_cat | → U54 |
| N63 | LibraryCategoriesController#update | Renames category | call | → S_cat | — |
| N64 | LibraryCategoriesController#destroy | Deletes category (with contents check) | call | → S_cat | — |
| N65 | WorkoutsController#create_custom | Creates Workout(type=custom, name, description, structure=[]); optionally saves to library | call | → S1 | → P3/S_lib |
| S_lib | library_workouts | user_id, workout_id, library_category_id, saved_at | — | — | — |
| S_cat | library_categories | user_id, name, position | — | — | — |

**What to build:**
- `library_categories` table + model; default "Workouts" category seeded on user creation
- `library_workouts` table + model; unique index on (user_id, workout_id)
- `LibraryController#index`: shows categories as sections, each with saved workout cards
- `LibraryCategoriesController`: create, update (rename), destroy
- `LibraryWorkoutsController`: create (save), destroy (remove); Turbo Stream updates the save button in-place
- "Save to Library" button + category picker on feed cards, post detail, and post-generate preview
- New Workout chooser screen (replaces current generator-as-root): three option cards
- Custom workout form (name + description + category) → creates Workout(type=custom) → option to start immediately or save first
- `From Library` path: library picker → select workout → go to Log page

**Demo:** Generate a Hyrox workout → save to library under "Hyrox" category → go to Library → see it under Hyrox → tap Start → log it. Also: see a friend's workout in feed → Save to Library → it appears in library under chosen category.

---

## V7: PR Detection + Progress Charts

**Shape parts:** A5.3 (PR detection), A5.4 (personal_records table), A6.4 (Chartkick progress charts)

**Affordances in this slice:**

| # | Component | Affordance | Control | Wires Out | Returns To |
|---|-----------|------------|---------|-----------|------------|
| U43 | pr-notification | PR badge (Turbo Stream, post-completion) | render | — | — |
| U48 | post-detail | PR badges on post (if PRs set) | render | — | — |
| U61 | progress | Exercise selector dropdown | select | → N72 | — |
| U62 | progress | Chartkick line chart | render | — | — |
| U63 | progress | PR milestone markers | render | — | — |
| N36 | PRDetectionService.call | Fully implemented: compares each set vs PersonalRecords; writes new record if best | call | → S4 | → N37 |
| N37 | Turbo Stream broadcast | Broadcasts PR badge to current user after WorkoutLog create | broadcast | — | → U43 |
| N72 | ExerciseLogsController#history | Sets data for selected exercise over time | call | → S3, S4 | → U62, U63 |
| S4 | personal_records | user_id, exercise_id, metric, value, achieved_at, workout_log_id | — | — | — |

**What to build:**
- `PersonalRecords` model + migration
- `PRDetectionService`: after WorkoutLog created, iterate ExerciseLogs, compare each metric (weight/time/reps/distance) against best PersonalRecord for that exercise + metric combination; write new record if better
- Turbo Stream notification broadcasting PR badge to user's session after WorkoutLog create
- PR badges on WorkoutLog post detail view (U48)
- Progress Charts tab in Library (P5.2): exercise dropdown → Chartkick line chart from ExerciseLogs data; overlay PR milestones from personal_records
- Add `chartkick` and `groupdate` to Gemfile

**Demo:** Log a heavier deadlift than before → PR badge fires on screen → open Library → Progress → select Deadlift → see weight over time chart with PR milestone marked.

---

## V8: Daily WOD

**Shape parts:** A9.1–A9.5 (wods, wod_entries, leaderboard, GenerateDailyWodJob)

**Affordances in this slice:**

| # | Component | Affordance | Control | Wires Out | Returns To |
|---|-----------|------------|---------|-----------|------------|
| U5 | wod-widget | WOD title, description, scoring type | render | — | — |
| U6 | wod-widget | WOD exercise list | render | — | — |
| U7 | wod-widget | "Log my result" button | click | → U8 | — |
| U8 | wod-log-form | Score input (seconds/reps/kg) | type | — | — |
| U9 | wod-log-form | Rx checkbox | toggle | — | — |
| U10 | wod-log-form | Notes field | type | — | — |
| U11 | wod-log-form | Submit button | click | → N10 | — |
| U12 | wod-widget | Leaderboard (Turbo Frame, top 10) | render | — | — |
| U13 | wod-widget | "My result" (post-submit) | render | — | — |
| N2 | WodsController#today | Loads today's Wod + top WodEntries | call | → S8, S9 | → U5, U6, U12 |
| N10 | WodEntriesController#create | Creates WodEntry; Turbo Stream refreshes leaderboard | call | → S9, N11 | → U12, U13 |
| N11 | Turbo Stream broadcast | Broadcasts updated leaderboard to wod channel | broadcast | — | → U12 |
| N100 | GenerateDailyWodJob | Solid Queue recurring job; balances type rotation; creates next-day Wod | job | → N21, S1, S8 | — |
| S8 | wods | date (unique), title, description, workout_id, scoring_type | — | — | — |
| S9 | wod_entries | user_id, wod_id, score, rx, notes, logged_at | — | — | — |

**What to build:**
- `Wods` and `WodEntries` models + migrations
- `GenerateDailyWodJob`: Solid Queue recurring job; looks at last 7 wod types, picks least-used; calls `WorkoutGenerator.call`; creates Wod record for tomorrow with auto-generated title + scoring_type
- Configure Solid Queue recurring schedule in `config/recurring.yml`
- WOD widget on home screen (P1.1): today's WOD, inline log form, leaderboard Turbo Frame
- Leaderboard ordered correctly per scoring_type (ASC for time, DESC for reps/weight/rounds)
- Turbo Stream broadcast on WodEntry create to refresh all subscribers' leaderboards
- Handle: user can only log one result per WOD per day

**Demo:** Home screen shows today's WOD (Hyrox sim, For Time) → log 38:42 Rx → leaderboard updates live showing rank → another user's tab also updates.

---

## V9: Calendar History

**Shape parts:** A6.2 (calendar view with Groupdate)

**Affordances in this slice:**

| # | Component | Affordance | Control | Wires Out | Returns To |
|---|-----------|------------|---------|-----------|------------|
| U58 | calendar | Monthly heatmap (cells shaded by workout count) | render | — | — |
| U59 | calendar | Day cell tap | click | → N70 | — |
| U60 | day-detail | Workouts on selected date | render | — | — |
| N70 | WorkoutLogsController#by_date | Loads WorkoutLogs for selected date (Turbo Frame) | call | → S2 | → U60 |
| N71 | WorkoutLogsController#calendar | Count grouped by date using Groupdate | call | → S2 | → U58 |

**What to build:**
- Calendar tab in Library (P5.1)
- `WorkoutLogsController#calendar`: uses Groupdate to group workout_log count by day for the current month; renders heatmap (CSS grid or simple table with shading based on count)
- Day cell tap: Turbo Frame loads mini workout list for that date inline below calendar
- Month navigation (prev/next) reloads calendar frame
- Add `groupdate` gem to Gemfile (also needed for V7 charts)

**Demo:** Open Library → Calendar tab → see a grid of the past month, days with workouts are darker → tap a day → mini list of that day's workouts appears.

---

## Setup Required Before V1

Before any slice can be built, the project needs to move from SQLite to PostgreSQL (OQ1 resolved).

**Steps:**
1. Remove `gem "sqlite3"` from Gemfile, add `gem "pg"`
2. Update `config/database.yml` for PostgreSQL (local dev: createdb blood_sweat_beers_development)
3. Run `bundle install`
4. `rails db:create && rails db:migrate`

Also add to Gemfile for later slices:
- `gem "chartkick"` (V7)
- `gem "groupdate"` (V7, V9)
- `gem "pagy"` (or keep kaminari — for feed pagination V3)
- `gem "image_processing"` is already present (avatar uploads via ActiveStorage)
