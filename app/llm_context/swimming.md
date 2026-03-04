# Swimming

## VOLUME BUDGET — READ FIRST, APPLY BEFORE PLANNING ANY SET
> **If the prompt specifies an exact target distance (e.g. "covering 2.5km"), use that as your total budget and ignore the table below.**


**Step 1: Determine the athlete's level using their PBs if available (from Athlete Context), otherwise use the requested difficulty:**
- Advanced: 100m Freestyle under 1:30, or 400m swim under 6:30
- Intermediate: 100m Freestyle 1:30–2:00, or 400m swim 6:30–9:00
- Beginner: 100m Freestyle over 2:00, no PB set, or new to structured swimming

**Step 2: Look up your total distance budget for the session:**

| Session duration | Beginner | Intermediate | Advanced |
|-----------------|----------|--------------|---------|
| 30 min | 500m | 750m | 1000m |
| 45 min | 750m | 1100m | 1400m |
| 60 min | 1000m | 1500m | 2000m |
| 90 min | 1500m | 2000m | 2500m |

**Step 3: Allocate the budget across sections:**
- Warm-up: 400m (standard). Use 200m for sessions ≤30 min. Never more than 600m.
- Cool-down: 100m (standard). Never more than 200m.
- Main set = Total budget − warm-up − cool-down.

Do not plan the main set without first calculating how many metres remain in the budget. These caps exist because 100m of swimming takes 2–4 minutes depending on level, plus rest time adds more.

---

## Pool Lengths
Always use the user's pool length from their profile.

- **25m (short course):** Most common for training. 1 length = 25m, 1 lap = 50m.
- **50m (long course):** Olympic pool. Far fewer turns, more sustained effort, significantly more demanding. 1 length = 50m, 1 lap = 100m.
- **33m:** Less common. Adjust set distances accordingly.
- **Open water:** No walls. Structure sets in minutes, not laps.

## Strokes
Use full names in exercise names — never abbreviations like FC, BK, BR, FLY.
- **Freestyle:** Front crawl. Used for the majority of training volume.
- **Backstroke:** On back, flutter kick, alternating arm pull.
- **Breaststroke:** Frog kick, sweeping arms. Slower, good for recovery sets.
- **Butterfly:** Dolphin kick, simultaneous arm pull. Most fatiguing — use sparingly.
- **IM (Individual Medley):** Butterfly → Backstroke → Breaststroke → Freestyle. Minimum distance 100m.

## Set Notation
Always be explicit. Every set should state distance, stroke, and rest interval.
- **4×100m Freestyle on 2:00** = 4 reps of 100m freestyle, sending off every 2 minutes
- **4×100m Freestyle / 20s rest** = 4 reps of 100m freestyle with 20 seconds rest after each
- **CSS** = Critical Swim Speed — threshold pace (roughly 400m TT pace + 3–5 secs per 100m)

## Common Set Types
- **CSS / Threshold** — sustained effort at threshold pace
- **Aerobic / Base** — comfortable, conversational effort; long continuous swims or moderate intervals
- **Speed / Sprint** — short reps, full recovery, maximum effort
- **Pull** — pull buoy only, builds upper body endurance
- **Kick** — board or streamline kick, builds leg power
- **Drill** — technical work, slow and deliberate
- **Descending** — each rep gets faster
- **Pyramid** — distance or intensity increases then decreases
- **Broken Swims** — rest within a longer swim to allow faster pace

## Rest Interval Guide
- **10–15s:** Short rest, aerobic / CSS sets
- **20–30s:** Standard rest, threshold and moderate sets
- **45s–1:00:** Long recovery, sprint or high-intensity sets
- **Full recovery (2:00+):** Maximum effort, very short reps

## Open Water Specific
- Structure by **time not distance**: e.g. "30 min steady aerobic" not "1200m"
- Include sighting technique cues (lift eyes every 6–8 strokes)
- Open water pace is typically 5–10% slower than pool pace for the same effort

## Important Rules

**HARD RULE — VALID SWIMMING DISTANCES:**
Every `distance_m` value MUST be one of: **25, 50, or a multiple of 100** (100, 200, 300, 400, 500 …).
- **Valid:** 25, 50, 100, 200, 300, 400, 500, 600, 800, 1000, 1500
- **INVALID — never use:** 75, 125, 150, 175, 225, 250, 350, 450 — these are not natural training distances
- 75m = 3 lengths and finishes at the wrong end. 125m, 150m, 175m are equally awkward.
- The only non-100 valid distances are 25 (one length sprint) and 50 (standard drill/sprint rep).
- **IM sets:** always in 100m units (25m Butterfly + 25m Backstroke + 25m Breaststroke + 25m Freestyle).
- **Ladder/mountain sections:** `start`, `end`, and `step` must only produce valid distances (25, 50, or multiples of 100). E.g. start:100 end:400 step:100 is valid; start:50 end:200 step:50 is valid; start:75 end:225 step:75 is NOT valid.

- Do NOT programme butterfly for long main sets — it is highly fatiguing
- Always specify both **distance AND stroke** for every rep
- Always include **rest periods explicitly** in every set
- Never leave the pool length ambiguous — it changes everything about the set structure
