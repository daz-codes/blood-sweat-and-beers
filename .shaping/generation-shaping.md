---
shaping: true
---

# Workout Generation Rework — Shaping

## Source

> What if workouts were tagged instead, so some could be tagged as running, deka and hyrox or functional, weights, strength. People would add the tags that they want to work on (one or more), then we would pull the top rated 25 workouts with the same tags, post them to haiku with a suitable prompt to create a new workout based on those given.

> top rated by number of likes (users can like a workout), there should also be a weighting of sessions the user has already done and even higher on those in their library (because they saved them). The current structure needs changing. I think it needs to be exercise, time, distance, weight (not all these fields need filling in), we would have to seed some workouts to start with.

> Tags should be a normalised table in the db using a polymorphic taggable model. Don't worry about the weighting for now, just use number of likes to choose them, but use a method that can be changed when needed. Send the sessions as json and ask the llm to use the same format. Send a schema as well — use Claude tool use to force structured JSON output.

> Could the llm figure out the time based on the time of other workouts it was given? Yes, include duration_mins in the output schema so the LLM declares its estimate. Send duration in the prompt too.

---

## Problem

The current Ruby `WorkoutGenerator` uses hard-coded rules, lookup tables, and difficulty multipliers to produce workouts. It has no awareness of what actually works well in practice — it invents structure from scratch every time. The workout `structure` jsonb is too rigid (flat run/station array) to represent real training sessions. There's no community signal, no learning from good workouts, and no way to express AMRAP, rounds, or free-form sections.

## Outcome

Workout generation uses real community data as context. The top-liked workouts matching a user's chosen tags are sent to Claude Haiku (via tool use), which produces a new workout inspired by them, calibrated to the requested duration. The workout structure is flexible enough to represent any real training session. Tags are a first-class concept on workouts. The system is seeded with enough quality workouts to work on day one.

---

## Requirements (R)

| ID | Requirement | Status |
|----|-------------|--------|
| **R0** | **Workout structure** | Core goal |
| R0.1 | Workout `structure` jsonb supports sections (warm-up, main set, etc.) each with a format (amrap/rounds/straight/notes) and exercises | Core goal |
| R0.2 | Each exercise has a name and flexible metrics: reps, distance_m, weight_kg, duration_s — not all required | Core goal |
| R0.3 | Sections can have rest_secs, rounds count, duration_mins (for AMRAP), and free-text notes | Core goal |
| R0.4 | A `duration_mins` field at the top level of structure carries the LLM's estimated total workout time | Core goal |
| **R1** | **Tags** | Core goal |
| R1.1 | Tags are a normalised `tags` table (id, name, slug) | Core goal |
| R1.2 | Workouts are tagged via a polymorphic `taggings` join table (taggable_type/taggable_id) | Core goal |
| R1.3 | Taggings model is polymorphic so other models can be tagged later without schema changes | Core goal |
| **R2** | **Workout likes** | Core goal |
| R2.1 | Workouts (not just workout_logs) can be liked by users | Core goal |
| R2.2 | Like count on workouts drives generation ranking | Core goal |
| R2.3 | Like selection logic is encapsulated in a single method so weighting can be changed without touching the generator | Core goal |
| **R3** | **LLM generation** | Core goal |
| R3.1 | Generator selects up to 25 workouts matching user's chosen tags, ranked by like count | Core goal |
| R3.2 | Selected workouts are serialised as JSON and sent to Claude Haiku as context | Core goal |
| R3.3 | Claude tool use enforces the output schema — response is guaranteed to match the workout structure | Core goal |
| R3.4 | Prompt includes: requested duration, tag context, and instruction to match the style of the provided workouts | Core goal |
| R3.5 | LLM infers appropriate workout density/length from examples and calibrates to the requested duration | Core goal |
| **R4** | **Fallback** | Core goal |
| R4.1 | If fewer than 5 workouts match the tags, broaden to all liked workouts regardless of tag | Core goal |
| R4.2 | If the LLM call fails, surface a clear error rather than silently falling back to the Ruby generator | Core goal |
| **R5** | **Generation form** | Core goal |
| R5.1 | User selects one or more tags (from existing tags on seeded workouts) | Core goal |
| R5.2 | User sets target duration (slider, as before) | Core goal |
| R5.3 | Difficulty remains as a prompt parameter | Core goal |
| **R6** | **Seeding** | Core goal |
| R6.1 | Database is seeded with enough quality tagged workouts to produce good generation results on day one | Core goal |
| R6.2 | Seeded workouts are owned by a system user and use the new structure format | Core goal |
| R6.3 | Seeded workouts have likes from the system user so they appear in ranking | Core goal |

---

## Open Questions

| # | Question | Resolution |
|---|----------|------------|
| OQ1 | What happens to the current Ruby WorkoutGenerator? | ✅ **Retire entirely** — no fallback; LLM is the only path |
| OQ2 | Are tags free-text (user-created) or curated from a fixed list? | ✅ **Free text, anyone can create** — `Tag.find_or_create_by(slug:, name:)` on save |
| OQ3 | Does the existing `exercises` table remain? It's used for exercise_log FK and PR tracking | ✅ **Deferred** — exercises table, exercise_logs, and PR tracking are out of scope for this rework |
| OQ4 | Running preference (none/low/medium/high) — how does this translate to the LLM prompt? | ✅ **Removed** — running expressed via tag selection (e.g. `hyrox` or `running` tag implies runs) |
| OQ5 | What tags will the seeded workouts have? | ✅ **User-provided** — user will seed workouts manually; deka examples from conversation used if needed |

---

## Shape A: Tagged workouts + LLM generation via tool use

| Part | Mechanism | Flag |
|------|-----------|:----:|
| **A1** | **New workout structure** | |
| A1.1 | `workouts.structure` jsonb schema: `{ sections: [{ name, format, rounds, duration_mins, rest_secs, notes, exercises: [{ name, reps, distance_m, weight_kg, duration_s, notes }] }], duration_mins, goal }` | |
| A1.2 | Migration: existing `structure` column stays, new schema applied to all new records; old seeded data replaced | |
| **A2** | **Tags + Taggings** | |
| A2.1 | `tags` table: id, name, slug (unique, auto-generated from name) | |
| A2.2 | `taggings` table: id, tag_id, taggable_type, taggable_id, created_at — polymorphic index on (taggable_type, taggable_id) | |
| A2.3 | `Workout has_many :taggings, as: :taggable; has_many :tags, through: :taggings` | |
| A2.4 | 🟡 `Tag.find_or_create_by(slug: name.parameterize, name:)` — tags created on save if they don't exist; no admin curation needed | |
| A2.5 | 🟡 `Tag.used_on_workouts` scope: returns tags appearing on at least one workout, for populating the generator form | |
| **A3** | **Workout likes** | |
| A3.1 | `workout_likes` table: id, user_id, workout_id, created_at — unique index on (user_id, workout_id) | |
| A3.2 | `Workout.most_liked_with_tags(tag_ids, limit:)` — encapsulated query: JOIN workout_likes, COUNT, filter by tags, ORDER BY likes DESC, LIMIT — single place to swap in weighted ranking later | |
| **A4** | **LLM generation service** | |
| A4.1 | `WorkoutLLMGenerator.call(user:, tag_ids:, duration_mins:, difficulty:)` — replaces `WorkoutGenerator` as primary path | |
| A4.2 | Calls `Workout.most_liked_with_tags(tag_ids, limit: 25)` to select context workouts | |
| A4.3 | Serialises context workouts as JSON array (id, name, tags, structure) | |
| A4.4 | Builds prompt: target duration, difficulty, tag names, + context workouts JSON | |
| A4.5 | Calls Anthropic API (claude-haiku-4-5) with `tool_use` — tool definition encodes the structure JSON schema | |
| A4.6 | Parses tool call response → creates `Workout` record with structure, duration_mins, tags inherited from context | |
| A4.7 | On API failure: raises `WorkoutGenerationError` with message surfaced to user via turbo_stream | |
| **A5** | **Generator form** | |
| A5.1 | 🟡 Tag selector: pill toggles from `Tag.used_on_workouts`; free-text input to type a new tag; at least one required | |
| A5.2 | Duration slider: unchanged (5–120 min) | |
| A5.3 | Difficulty selector: unchanged (beginner/intermediate/advanced) | |
| **A6** | **Seeding** | |
| A6.1 | 🟡 `seeds.rb`: create system user (`system@bloodsweatbeers.app`); workout content is user-provided (pasted into seeds.rb using new structure schema) | |
| A6.2 | 🟡 System user likes each seeded workout so they have like_count > 0 and appear in ranking | |

---

## Fit Check: R × A

| Req | Requirement | Status | A |
|-----|-------------|--------|---|
| R0.1 | Workout structure supports sections with format and exercises | Core goal | ✅ |
| R0.2 | Each exercise has flexible metrics (reps, distance_m, weight_kg, duration_s) | Core goal | ✅ |
| R0.3 | Sections support rest_secs, rounds, duration_mins, free-text notes | Core goal | ✅ |
| R0.4 | Top-level duration_mins in structure carries LLM's estimated total time | Core goal | ✅ |
| R1.1 | Normalised tags table | Core goal | ✅ |
| R1.2 | Workouts tagged via polymorphic taggings join | Core goal | ✅ |
| R1.3 | Polymorphic taggings so other models can be tagged later | Core goal | ✅ |
| R2.1 | Workouts can be liked by users | Core goal | ✅ |
| R2.2 | Like count drives generation ranking | Core goal | ✅ |
| R2.3 | Like selection logic encapsulated in single method | Core goal | ✅ |
| R3.1 | Up to 25 workouts matching tags, ranked by likes | Core goal | ✅ |
| R3.2 | Context workouts serialised as JSON and sent to Haiku | Core goal | ✅ |
| R3.3 | Tool use enforces output schema | Core goal | ✅ |
| R3.4 | Prompt includes duration, tags, style instruction | Core goal | ✅ |
| R3.5 | LLM calibrates to requested duration from examples | Core goal | ✅ |
| R4.1 | Fewer than 5 tag matches → broaden to all liked workouts | Core goal | ✅ |
| R4.2 | LLM failure raises error surfaced to user | Core goal | ✅ |
| R5.1 | Tag selector on form | Core goal | ✅ |
| R5.2 | Duration slider unchanged | Core goal | ✅ |
| R5.3 | Difficulty as prompt parameter | Core goal | ✅ |
| R6.1 | Seeded quality tagged workouts | Core goal | ✅ |
| R6.2 | Seeded workouts owned by system user, new structure | Core goal | ✅ |
| R6.3 | System user likes seeded workouts for ranking | Core goal | ✅ |

**Notes:**
- All OQs resolved: Ruby generator retired (OQ1), tags are free-text user-created (OQ2), exercises/PRs deferred (OQ3), running preference removed (OQ4), seeded content user-provided (OQ5)
- A2.4/A2.5 cover R1.1–R1.3: tags created on save via find_or_create_by; used_on_workouts scope populates the form
- A5.1 updated: pill toggles from existing tags + free-text input for new tags; running preference (previously A5.4) removed entirely
- A6 restructured: workout content is user-provided; system user and likes mechanism still needed for cold-start ranking
- R6, R7, R8 (benchmarks, challenges, device integration) are not in scope for this rework
