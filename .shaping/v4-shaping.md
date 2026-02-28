---
shaping: true
---

# Blood Sweat Beers — V4 Follow Graph Shaping

## Context

What's built going into V4:

- `User` model with `display` helper
- `Workout` + `WorkoutLog` + `ExerciseLog` + `WorkoutLike` + `Tag` models
- `FeedController#index` currently shows only the current user's own workout logs
- `ProfilesController`: only `edit`/`update` for the logged-in user's own profile
- No `follows` table, no `UsersController`, no concept of follow state anywhere

The feed is scoped to the current user's own logs. V4 makes the feed social — own posts plus accepted followers' posts — while keeping the feed private (no global discovery).

---

## Requirements (R)

| ID | Requirement | Status |
|----|-------------|--------|
| **R1** | **Follow mechanics** | Must-have |
| R1.1 | A user can request to follow another user | Must-have |
| R1.2 | The followee must explicitly accept before the requester can see their posts | Must-have |
| R1.3 | Following is one-way (directed graph); mutual follow = two separate accepted records | Must-have |
| R1.4 | A user can unfollow someone they already follow | Must-have |
| R1.5 | A user can cancel a pending outbound request | Must-have |
| **R2** | **Feed filtering** | Must-have |
| R2.1 | Feed shows: own posts + public posts from accepted-following users | Must-have |
| R2.2 | A user with zero accepted follows sees only their own posts (no empty feed) | Must-have |
| R2.3 | No global feed — unknown users' posts are never shown | Must-have |
| **R3** | **User discovery** | Must-have |
| R3.1 | Users can find other users by searching username/display name | Must-have |
| R3.2 | Clicking a user's name anywhere navigates to their public profile | Must-have |
| **R4** | **Profile page** | Must-have |
| R4.1 | Public profile at `/users/:id`: display name, username, workout count, follower/following counts | Must-have |
| R4.2 | Follow button on profile reflects current state: Request / Requested (cancel) / Following (unfollow) | Must-have |
| R4.3 | Workout list on another user's profile is only visible to accepted followers | Must-have |
| **R5** | **Follow requests inbox** | Must-have |
| R5.1 | Nav badge shows count of pending inbound follow requests | Must-have |
| R5.2 | Requests view lists pending inbound requests with Accept / Decline per row | Must-have |
| R5.3 | Accepting/declining updates the UI via Turbo Stream without a full reload | Must-have |
| **R6** | **New user experience** | Must-have |
| R6.1 | A new user with an empty feed sees a useful prompt to find people / generate a workout | Must-have |

---

## Shapes

### Shape A — Profile page only, no search

Follow button only on `/users/:id` profile page. Discovery is purely viral — clicking names already visible in the feed.

| Part | Mechanism |
|------|-----------|
| A1 | `follows` table (follower_id, following_id, status, timestamps) |
| A2 | Feed query expands to include accepted-following user IDs |
| A3 | `UsersController#show` — profile page with follow button (Turbo Frame) |
| A4 | `FollowsController` — create, destroy, index (inbox), update (accept/decline) |
| A5 | Nav badge (lazy Turbo Frame) for pending request count |
| A6 | Username links on feed cards → profile page |

**Problem:** A new user has zero feed cards → zero names to click → can never find anyone. The follow graph can't bootstrap.

---

### Shape B — Profile page + inline follow button on cards + user search ✅ Selected

Same as A, plus: follow button inline on feed cards for users you don't yet follow, and a user search at `/users?q=`.

| Part | Mechanism |
|------|-----------|
| B1 | `follows` table (follower_id, following_id, status, requested_at, accepted_at) |
| B2 | Feed query: own posts + accepted-following users' public posts |
| B3 | `UsersController#show` — profile page + `UsersController#index` — search by username/display_name |
| B4 | `FollowsController` — create (request), destroy (cancel/unfollow), index (inbox), update (accept/decline) |
| B5 | `follow_button` partial — shared Turbo Frame component, 3 states: Request / Requested+Cancel / Following+Unfollow |
| B6 | `follow_button` embedded in feed cards for non-followed users |
| B6 | Nav badge (lazy Turbo Frame) for pending request count |
| B7 | Nav "Find people" link → `/users` |
| B8 | Username links on feed cards → profile page |

---

### Shape C — All of B + followers/following lists + mutual-follow indicator

Adds browsable follower/following lists on profiles and a "Mutual" badge. Four extra views, mutual-follow scopes.

**Problem:** Followers/following lists only have value when users have dozens of connections. Premature at launch scale.

---

## Fit Check

| Req | Requirement | Status | A | B | C |
|-----|-------------|--------|---|---|---|
| R1.1 | User can request to follow | Must-have | ✅ | ✅ | ✅ |
| R1.2 | Followee must accept before posts visible | Must-have | ✅ | ✅ | ✅ |
| R1.3 | One-way directed graph | Must-have | ✅ | ✅ | ✅ |
| R1.4 | Unfollow | Must-have | ✅ | ✅ | ✅ |
| R1.5 | Cancel pending outbound request | Must-have | ✅ | ✅ | ✅ |
| R2.1 | Feed = own + accepted-following posts | Must-have | ✅ | ✅ | ✅ |
| R2.2 | Zero-follows → own posts only | Must-have | ✅ | ✅ | ✅ |
| R2.3 | No global feed | Must-have | ✅ | ✅ | ✅ |
| R3.1 | Discovery via search | Must-have | ❌ | ✅ | ✅ |
| R3.2 | Clicking name → profile | Must-have | ✅ | ✅ | ✅ |
| R4.1 | Profile: name + stats | Must-have | ✅ | ✅ | ✅ |
| R4.2 | Follow button with all states | Must-have | ✅ | ✅ | ✅ |
| R4.3 | Workout list gated on accepted follow | Must-have | ✅ | ✅ | ✅ |
| R5.1 | Nav badge for pending requests | Must-have | ✅ | ✅ | ✅ |
| R5.2 | Requests view with accept/decline | Must-have | ✅ | ✅ | ✅ |
| R5.3 | Turbo Stream updates on accept/decline | Must-have | ✅ | ✅ | ✅ |
| R6.1 | New user sees useful empty state | Must-have | ❌ | ✅ | ✅ |

**Notes:**
- A fails R3.1: no search means cold-start is impossible for new users with empty feeds
- A fails R6.1: new user has zero feed cards → no names to click → stuck
- C passes all but adds 4 extra views and mutual-follow logic with no value at current scale

**Selected: Shape B**

---

## Shape B — Implementation Parts

### B1: Data layer

| Part | Mechanism |
|------|-----------|
| B1.1 | Migration: `follows` table — `follower_id` FK, `following_id` FK, `status` string (default `"pending"`), `requested_at` datetime, `accepted_at` datetime nullable |
| B1.2 | Unique index on `[follower_id, following_id]` |
| B1.3 | Index on `[following_id, status]` (inbound pending lookup) |
| B1.4 | Index on `[follower_id, status]` (feed query subquery) |
| B1.5 | `Follow` model: `belongs_to :follower`, `belongs_to :following` (both User); scopes `pending`, `accepted`; validates follower ≠ following |
| B1.6 | `User` additions: `has_many :follows_as_follower`, `has_many :follows_as_following`; `accepted_following_ids` scope for feed query; `pending_inbound_count` for badge |

### B2: Feed update

| Part | Mechanism |
|------|-----------|
| B2.1 | `FeedController#index`: query `WorkoutLog.where(user_id: [Current.user.id] + accepted_following_ids)` |
| B2.2 | Scope: own posts (any visibility) + followed users' public posts only |
| B2.3 | Empty state: "Find people to follow →" link to `/users` + Generate Workout modal trigger |

### B3: UsersController

| Part | Mechanism |
|------|-----------|
| B3.1 | `GET /users?q=` — `ILIKE` on `username` and `display_name`, limit 20, exclude self |
| B3.2 | `GET /users/:id` — profile page: stats, follow button (Turbo Frame), gated workout list |
| B3.3 | Viewing own profile redirects to `edit_profile_path` |

### B4: FollowsController

| Part | Mechanism |
|------|-----------|
| B4.1 | `POST /follows` — create Follow (status: pending); Turbo Frame response → "Requested" button state |
| B4.2 | `DELETE /follows/:id` — destroy (unfollow or cancel); Turbo Frame → "Request to Follow" state |
| B4.3 | `PATCH /follows/:id` — accept: set status=accepted, accepted_at=now; Turbo Stream removes row, decrements badge |
| B4.4 | `DELETE /follows/:id` from inbox — decline: destroy; Turbo Stream removes row, decrements badge |
| B4.5 | `GET /follows` — inbound pending requests list |

### B5: follow_button partial (shared)

| Part | Mechanism |
|------|-----------|
| B5.1 | Turbo Frame `id="follow_button_#{user.id}"` |
| B5.2 | State: `none` → "Request to Follow" (POST); `pending` → "Requested · Cancel" (DELETE); `accepted` → "Following · Unfollow" (DELETE); `self` → nothing |
| B5.3 | Used in: feed card header, profile page, search results |

### B6: Nav badge

| Part | Mechanism |
|------|-----------|
| B6.1 | Turbo Frame `id="follow_requests_badge"` in nav, `src: follows_pending_path` (lazy) |
| B6.2 | Renders count badge when `pending_inbound_count > 0`, empty when zero |
| B6.3 | Broadcast Turbo Stream replace to badge after accept/decline in FollowsController |

### B7: User search

| Part | Mechanism |
|------|-----------|
| B7.1 | `GET /users?q=` with sanitised `ILIKE` query |
| B7.2 | Results list: display name, username, workout count, `follow_button` partial per result |
| B7.3 | Nav "Find people" icon/link → `/users` |

### B8: Feed card updates

| Part | Mechanism |
|------|-----------|
| B8.1 | Wrap username in `link_to user_path(workout_log.user)` |
| B8.2 | Show `follow_button` partial in card header for non-self, non-followed users |

---

## Demo Scenario

1. New user registers → sees empty feed with "Find people to follow" prompt
2. Clicks "Find people" in nav → `/users` search → types name → sees result → clicks "Request to Follow" → button → "Requested"
3. Target user sees badge (count: 1) → clicks → requests inbox → clicks "Accept" → Turbo Stream removes row, badge → 0
4. Requester reloads feed → sees target's public workout posts
5. Clicks target's name on a card → profile page → "Following" button state + workout list visible
6. Clicks "Unfollow" → button resets → posts disappear from next feed load
