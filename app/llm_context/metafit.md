# Metafit

## What Metafit Is
Metafit is a 30-minute, high-intensity, bodyweight-only interval training program. **No equipment is used whatsoever** — no dumbbells, no barbells, no kettlebells, no cardio machines. Every exercise uses bodyweight only. Sessions are typically exactly 30 minutes with minimal rest built into the interval structure.

## Signature Session Structures

### Matrix Workouts
The defining feature of Metafit. A matrix progressively builds combinations of exercises then strips them back:
- Round 1: A
- Round 2: A + B
- Round 3: A + B + C
- Round 4: B + C
- Round 5: C

Use 3, 4, or 5 exercises per matrix. The progression always builds up then strips back:
- 3 exercises (A,B,C): A → AB → ABC → BC → C
- 4 exercises (A,B,C,D): A → AB → ABC → ABCD → BCD → CD → D
- 5 exercises (A,B,C,D,E): A → AB → ABC → ABCD → ABCDE → BCDE → CDE → DE → E

All exercises in a matrix must use the same metric. Prefer duration_s: 30 for each exercise (30s per exercise per combination round) — this is the authentic Metafit style. Use reps only occasionally for variety. Rest 30–60s between each combination round (set rest_secs).

Example — timed: 30s Press-ups / 30s Press-ups + 30s Squats / 30s Press-ups + 30s Squats + 30s Tuck Jumps / 30s Squats + 30s Tuck Jumps / 30s Tuck Jumps
Example — reps: 10 Press-ups / 10 Press-ups + 10 Squats / 10 Press-ups + 10 Squats + 10 Tuck Jumps / 10 Squats + 10 Tuck Jumps / 10 Tuck Jumps

Use the `matrix` format for these sections.

### Tri-Block Pyramid
A full-session structure using 9 exercises split into 3 blocks of 3 (Block A, Block B, Block C). Build in three phases:

**Phase 1 — Introduction (30s work / 30s rest per exercise):**
Generate 3 separate sections, one per block. Each section: format `straight`, 3 exercises with `duration_s: 30`, notes: "30s rest after each exercise".

**Phase 2 — Extension (1 min work per exercise, 1 min rest after each block):**
Generate 3 more sections using the SAME exercises as Phase 1, same block grouping. Each section: format `straight`, 3 exercises with `duration_s: 60`, `rest_secs: 60`. Name them "Block A — Extended" etc.

**Phase 3 — Finale (all 9 back to back, no rest):**
One final section: format `for_time`, all 9 exercises with `duration_s: 30`, no rest_secs. Name it "Finale — All 9".

This structure IS the main set for a Metafit session — do not add other main sections alongside it.

### Interval Rounds
Multi-exercise sets repeated for a fixed number of rounds with short rest:
- 3–5 rounds of 3–5 exercises, 30–45s work per exercise, 10–15s transition
- Work-to-rest: high (typically 3:1 or 2:1)
- Use `rounds` format with short `rest_secs` (15–30s between rounds)

### AMRAP Circuits
Clock-driven bodyweight circuits. 8–15 minutes, 3–5 exercises, keep moving.

### Tabata Blasts
20s on / 10s off × 8 rounds on a single explosive movement (burpees, jump squats, mountain climbers).

## Movement Vocabulary
**Lower body:** Squats, Jump Squats, Tuck Jumps, Squat Jumps, Reverse Lunges, Jump Lunges, Broad Jumps, Skaters, Lateral Bounds
**Upper body:** Press-ups (standard, wide, diamond, decline), Pike Press-ups, Tricep Dips (floor), Shoulder Taps
**Full body / explosive:** Burpees, Burpee Broad Jumps, Mountain Climbers, Bear Crawls, Sprawls, Star Jumps
**Core:** Sit-ups, V-ups, Leg Raises, Hollow Hold, Plank, Side Plank, Flutter Kicks, Russian Twists
**Cardio:** High Knees, Butt Kicks, Jumping Jacks, Speed Skaters

## Coaching Style
- High energy, music-driven pacing
- Short sharp intervals — work periods rarely exceed 45 seconds
- Minimal rest — transitions are part of the challenge
- Clear start/stop cues — athletes follow the instructor's calls
- Modifications always available (e.g. step-back burpee instead of jump)

## Session Structure
Warm-up (5 min, dynamic bodyweight) → 1–2 matrix sections or interval blocks → optional tabata finisher → cool-down stretches.
