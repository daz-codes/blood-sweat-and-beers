---
shaping: true
---

# Workout Generation Rework — Slices

Derived from `generation-shaping.md` Shape A. Three vertical slices, each demo-able. Build in order — GR3 depends on GR1 and GR2.

**Prerequisite:** `anthropic` gem added to Gemfile before GR3.

---

## Slice Summary

| # | Slice | Shape Parts | Demo |
|---|-------|-------------|------|
| GR1 | Tags + new workout structure | A1, A2 | "View a workout — see its tags and sections-based structure" |
| GR2 | Workout likes | A3 | "Like a workout — count updates live; ranking method ready" |
| GR3 | LLM generator + form + seeding | A4, A5, A6 | "Pick 'deka' + 30 mins → LLM generates a new sections-based workout" |

---

## GR1: Tags + new workout structure

**Shape parts:** A1 (new structure schema), A2 (tags + taggings)

**Affordances in this slice:**

| # | Component | Affordance | Control | Wires Out | Returns To |
|---|-----------|------------|---------|-----------|------------|
| U1 | workout-show | Tags list (pill badges) | render | — | — |
| U2 | workout-show | Sections display: section name + format badge, exercise rows | render | — | — |
| U3 | feed-card | Tags pill list (truncated) | render | — | — |
| N1 | WorkoutsController#show | Loads workout with tags | call | → S1, S2 | → U1, U2 |
| N2 | FeedController#index | Loads workout_logs with workout.tags | call | → S1, S2 | → U3 |
| S1 | workouts | structure jsonb — now sections-based; duration_mins at top level | — | — | — |
| S2 | tags / taggings | tags: id, name, slug; taggings: polymorphic join | — | — | — |

**What to build:**
- Migration: `create_tags` (id, name, slug unique) + `create_taggings` (tag_id, taggable_type, taggable_id, polymorphic index)
- `Tag` model: `has_many :taggings`; `find_or_create_by(name:)`; `used_on_workouts` scope
- `Tagging` model: `belongs_to :tag; belongs_to :taggable, polymorphic: true`
- `Workout`: `has_many :taggings, as: :taggable; has_many :tags, through: :taggings`
- Update workout show page to render new sections structure (warm-up / main set / sections with format label, exercises list)
- Update feed card `_workout_log_card.html.erb` to show tags and render sections structure (replacing current flat step display)
- Seed a handful of workouts using the new structure (deka examples from conversation), with tags applied — owned by system user created here

**Demo:** View a seeded workout → see tag badges ("deka", "carries") → workout body shows "Warm-up · 5 min" / "Main Set · AMRAP 20" with exercises listed underneath.

---

## GR2: Workout likes

**Shape parts:** A3 (workout_likes table, Workout.most_liked_with_tags)

**Affordances in this slice:**

| # | Component | Affordance | Control | Wires Out | Returns To |
|---|-----------|------------|---------|-----------|------------|
| U4 | workout-show | Like button (❤️ + count, Turbo Frame) | click | → N3 | → U4 |
| U5 | workout-show | Like count display | render | — | — |
| N3 | WorkoutLikesController#toggle | Creates WorkoutLike if not exists; destroys if exists; Turbo Stream updates button | call | → S3 | → U4 |
| N4 | Workout.most_liked_with_tags | `joins(:workout_likes).where(taggings: tag_ids).group(:id).order('COUNT(workout_likes.id) DESC').limit(n)` — single encapsulated method | call | → S3, S2 | → N5 (GR3) |
| S3 | workout_likes | user_id, workout_id — unique index | — | — | — |

**What to build:**
- Migration: `create_workout_likes` (id, user_id, workout_id, created_at — unique index on user_id + workout_id)
- `WorkoutLike` model: `belongs_to :user; belongs_to :workout`
- `Workout`: `has_many :workout_likes`; class method `most_liked_with_tags(tag_ids, limit: 25)` — encapsulated here so weighting logic lives in one place
- `WorkoutLikesController#toggle`: find_or_initialize → toggle → Turbo Stream response updating the like button frame
- Route: `post /workouts/:id/like` → `workout_likes#toggle`
- Like button on workout show page (Turbo Frame wrapping button + count)
- System user likes each seeded workout (in seeds.rb or a rake task) so they have like_count > 0 for GR3

**Demo:** Open a seeded workout → click ❤️ → count goes from 1 to 2 without page reload → click again → back to 1.

---

## GR3: LLM generator + updated form + seeding

**Shape parts:** A4 (WorkoutLLMGenerator), A5 (updated form), A6 (seeding)

**Affordances in this slice:**

| # | Component | Affordance | Control | Wires Out | Returns To |
|---|-----------|------------|---------|-----------|------------|
| U6 | generator-form | Tag selector: pill toggles from existing tags + free-text input for new tags | select/type | — | — |
| U7 | generator-form | Duration slider (unchanged) | drag | — | — |
| U8 | generator-form | Difficulty selector (unchanged) | select | — | — |
| U9 | generator-form | "Generate Workout" button | click | → N5 | — |
| U10 | workout-preview | Generated workout (Turbo Frame) — sections-based | render | — | — |
| U11 | workout-preview | Error message (if LLM fails) | render | — | — |
| N5 | WorkoutsController#create | Calls WorkoutLLMGenerator; Turbo Stream updates preview | call | → N6 | → U10/U11 |
| N6 | WorkoutLLMGenerator.call | Fetches context via most_liked_with_tags; builds prompt; calls Haiku via tool use; parses response; creates Workout | call | → N7, N8 | → S1 |
| N7 | Workout.most_liked_with_tags | Selects up to 25 by likes for given tags; broadens to all liked if < 5 match | call | → S1, S3 | → N6 |
| N8 | Anthropic API (claude-haiku-4-5) | Tool use call with structure schema as tool definition; returns structured JSON | call | — | → N6 |
| S1 | workouts | New workout created with sections structure + tags inherited from context | — | — | — |

**What to build:**
- Add `gem "anthropic"` to Gemfile (or use `Faraday`/`Net::HTTP` directly against `https://api.anthropic.com/v1/messages`)
- `WorkoutLLMGenerator` service:
  - `call(user:, tag_ids:, duration_mins:, difficulty:)`
  - Calls `Workout.most_liked_with_tags`; broadens if < 5 results
  - Serialises context workouts as JSON (id, tags, structure)
  - Builds prompt with duration, difficulty, tag names, context
  - Calls Anthropic API with tool use — tool name `create_workout`, input_schema = sections jsonb schema
  - Parses `tool_use` block from response → creates `Workout` record
  - Raises `WorkoutGenerationError` on API failure
- Delete `app/services/workout_generator.rb`
- Update `WorkoutsController#create` to call `WorkoutLLMGenerator` (remove `WorkoutGenerator` call)
- Update generator form (`workouts/new.html.erb`):
  - Replace workout type radio + running preference with tag pill selector
  - Tag pills from `Tag.used_on_workouts`; text input for new tags
  - Keep duration slider + difficulty selector
- Update `workouts/preview` partial to render new sections structure
- Update `db/seeds.rb`: create system user (`system@bloodsweatbeers.app`), seed initial tagged workouts using new structure, system user likes each one

**Demo:** Open Generate → select "deka" pill → set 30 mins, intermediate → Generate → LLM produces a new 30-minute deka session with warm-up / main set sections → preview renders correctly.

---

## Notes

- GR1 and GR2 are independent — either can be built first, but GR1 should come first since seeded workouts (needed for GR2 likes) use the new structure
- GR3 depends on both GR1 (tags on form) and GR2 (most_liked_with_tags query)
- V8 (Daily WOD) in slices.md calls `WorkoutGenerator.call` — this must be updated to use `WorkoutLLMGenerator` after GR3 is complete
- The `exercises` table and `exercise_logs` remain untouched for now (deferred, OQ3)
