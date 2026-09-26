# Forge — project brief for agents

Forge is a personal fitness + nutrition tracker: a single static `index.html`
(HTML/CSS/vanilla JS, no build step, no framework) backed by Supabase
(Postgres + Auth). It's a one-user app in practice — built and used by the
repo owner, ramakrishnavaitla@gmail.com.

## Where things live

- **Repo**: `forgeitstrength/forgeit` on GitHub, default branch `main`.
- **Hosting**: GitHub Pages, serving `main` directly. Live at
  `https://forgeitstrength.github.io/forgeit/`. No build step — Pages just
  serves the raw `index.html`.
- **Backend**: Supabase project **"Forge IT!"**, ref `pbttrknzevqmcqvcfcak`,
  region `us-east-1`, Postgres 17. Project URL:
  `https://pbttrknzevqmcqvcfcak.supabase.co`.
- **Client auth to Supabase**: the anon/publishable key is hardcoded in
  `index.html` (`CONFIG.SUPABASE_ANON_KEY`) — this is intentional, it's the
  public client key and RLS does the real access control. Don't duplicate
  the raw key value in other files/docs (avoid tripping credential-leak
  scanners on a second copy) — read it straight from `index.html` when
  needed. Supabase has also issued a newer-style `sb_publishable_...` key
  for this project, but the client still uses the legacy anon JWT.
- **Schema changes / admin DB access**: requires the Supabase MCP connector
  (or dashboard login) authenticated to this project — the anon key alone
  cannot alter schema or bypass RLS. Whoever picks this up needs that
  connector attached, or the Supabase project owner's dashboard access.
- **The one real user**: `ramakrishnavaitla@gmail.com`,
  `auth.users.id = 9eaf01b8-5b98-4fe8-90d7-ebeb067ecdc6`. A second dormant
  account (`sneha.nlvr@gmail.com`) exists with no real data.

## App structure (all in `index.html`)

- `CONFIG` / `LIVE` — Supabase client setup. `LIVE` is false only if the key
  looks like a placeholder; in practice always true.
- Auth: email/password only (`signInWithPassword`/`signUp`), no OAuth, no
  magic links, no password reset flow in the app.
- **Workout tab**: `loadProgram()` fetches `workout_days` + `exercises` for
  a day/cycle and renders `WORKOUT`; `renderWorkout()` draws it;
  `finishBtn` handler upserts into `sessions` + `session_exercise_logs`.
- **Nutrition tab**: `loadNutritionForDate()`, `logFoodBtn` handler. Macro
  estimation for free-typed food text is entirely local (no third-party
  API) via `estimateMacrosFromIngredients()` against `nutrition_ingredients`
  / `nutrition_units`, with a fuzzy-match layer (`findFuzzyFoodMatch`)
  against the user's own `food_items` history to reuse known macros.
- **Plan tab**: `loadPlan()`/`renderPlan()` — read-only preview of each
  active day's next cycle.
- **Progress tab**: best lifts (est. 1RM), volume by muscle group,
  nutrition adherence, TDEE estimate — all derived client-side from
  `sessions`/`session_exercise_logs`/`daily_nutrition_totals`.
- Onboarding / "add a workout day" flow builds `workout_days` + `exercises`
  rows directly from the UI.

## Database schema (public schema)

All user-owned tables have RLS `own rows` policies (`auth.uid() = user_id`,
or via parent FK for `exercises`/`session_exercise_logs`). Reference tables
(`nutrition_ingredients`, `nutrition_units`, `foods`, `food_servings`,
`food_aliases`, `food_library_runs`) are readable by anyone authenticated.

- **workout_days** — `id, user_id, code (A/B/C/D/E/F/G/H/P...), name,
  sequence_order, active, created_at`. `active=false` days (currently `F`
  "Zone 2", `C` "5K Speed") are excluded from the auto-rotation but still
  shown, greyed out, in the day picker.
- **exercises** — `id, workout_day_id, section (WARM-UP/MAIN/FINISHER),
  name, order_index, cycles (jsonb), muscle_group, video_url, notes,
  equipment`.
  - `cycles` is `[{ "cycle": 1, "prescription": "45 x 12, 45 x 10" }, ...]`.
    Cycle numbers loop (`((n-1) % maxCycle) + 1`) — cycle_number stored on
    `sessions` keeps incrementing forever, but only maps onto a fixed set
    of prescription slots per exercise.
  - `notes` holds the actual instructions for WARM-UP/FINISHER rows
    (rendered as a prominent callout, not collapsed) and is otherwise
    unused for MAIN rows today.
  - `equipment` is a short "what to use in the gym" string, shown behind a
    collapsed "Details" toggle along with `video_url`.
  - `video_url` is either a specific `youtube.com/watch?v=...` link (kept
    only where independently corroborated — see Known gaps) or a safe
    `youtube.com/results?search_query=...` fallback that always resolves.
  - **Gotcha**: exercise *names* get edited by the user directly in
    Supabase or via future onboarding edits, independent of this repo —
    they have changed before (e.g. "Belt Squat" → "Hack Squat") without
    any corresponding code change. Anything matched by exercise **name**
    (video/equipment/notes authoring, research agent prompts) can silently
    go stale. Always re-pull the live exercise list before trusting a
    cached name list.
- **sessions** — one row per `(user_id, workout_day_id, cycle_number,
  date)`, unique constraint on that tuple (upserted on save).
  `sets_completed`, `sets_total`, `general_note` (free journal text),
  `issue_note` (flags a one-off/bad day — see auto-progression below).
  There's also an older unused `notes` column from the initial schema;
  `general_note`/`issue_note` are the ones the app actually uses.
- **session_exercise_logs** — per-exercise actual performance for a
  session: `session_id, exercise_id, actual (text, "45 x 12, 45 x 10"),
  completed (bool — every set in that exercise was checked off),
  progressed_at` (set by the nightly auto-progression job, see below).
- **profiles**, **daily_targets** (macro/weight targets, one row per
  `effective_date`, most recent wins), **body_metrics**, **water_log**,
  **supplement_log** — straightforward per-user logs.
- **nutrition_log** — one row per logged food. `kcal` is a **generated
  column** (`protein*4 + carbs*4 + fat*9 + alcohol*7`), never set by the
  client. `covers` is a text[] of tags (`Protein`/`Carbs`/`Fat`).
- **food_items** — the user's personal "known foods" cache, keyed by
  free-typed name, reused by the fuzzy/exact matcher when logging food
  again. `use_count`/`last_used_at` drive matching priority.
- **nutrition_ingredients** / **nutrition_units** — the reference data the
  local macro estimator matches against (ingredient name+aliases+macros
  per 100g; unit→grams conversions per category). ~877 ingredients, ~200
  unit rows as of writing.
- **foods** / **food_servings** / **food_aliases** — a **separate**, larger
  food reference set (582/1753/1902 rows) with cuisine tagging
  (indian/american/common) and per-serving gram weights. **Not currently
  read by the live client code** (grep `index.html` for `from("foods")` —
  there's none). This looks like it's populated/used by an external
  process (see `food_library_runs` below) and may be a planned-but-not-
  wired-up upgrade path, or a leftover. Worth clarifying intent before
  building on it.
- **food_library_runs** — a log of automated "food library research" runs
  (`run_date, status, foods_added, foods_verified, ...`). Combined with
  `food_items` entries tagged like `[ref nightly-research-2026-09-02]`,
  this shows **there is already a separate recurring agent/job populating
  nutrition reference data in this project**, outside of this repo's code
  or this conversation. A new agent should check `food_library_runs` and
  recent migrations (named `nightly_research_*`) before assuming it's
  starting from a clean slate on the nutrition side.
- **api_usage** — per-user daily counter, `count` — purpose/writer unclear
  from the current client code (no `from("api_usage")` write found either);
  likely also written by the external research process above.

### Views

- **daily_nutrition_totals** — per `(user_id, date)` sums of
  protein/carbs/fat/alcohol/kcal + `entries`/`empty_entries` counts. Used
  by the Progress tab's adherence chart and TDEE estimate.
- **nutrition_suspect_entries** — flags `nutrition_log` rows that look
  wrong: implausible kcal (>2000 for one entry), any macro >200-300g,
  zero protein on an obviously protein-named food, or high fat on a
  usually-lean item. **Useful starting point for any agent asked to audit
  nutrition data quality** — this view already encodes the same kind of
  bug I found and fixed manually earlier (see Known gaps).

### Functions / scheduled jobs

- **`progress_set_str(text) → text`** — bumps one "45 x 12"-style set
  string: +5 to the numeric weight if there is one, else +1 rep if the
  weight side is non-numeric (e.g. "BW"). Used only by `progress_workouts`.
- **`progress_workouts() → void`** — the nightly auto-progression job.
  For every `session_exercise_logs` row with `completed=true`,
  `progressed_at is null`, processed oldest-session-first: if the parent
  session's `issue_note` is set, skip (mark processed, don't touch
  prescriptions — a flagged day is a one-off, not a new baseline).
  Otherwise, recompute that exercise's prescription for **that same cycle
  slot** from `actual` (via `progress_set_str` per set) and write it back
  into `exercises.cycles`. This is what makes "I did weighted pull-ups
  today" actually show up as the prescription next time that cycle comes
  around, instead of resetting to the original seed value.
  - Scheduled via **pg_cron**, job name `progress-workouts-nightly`,
    `0 9 * * *` (09:00 UTC daily), command `select
    public.progress_workouts();`. Check with
    `select * from cron.job;` / `cron.job_run_details` for run history.
  - Idempotent by design (`progressed_at` gate) — safe to call manually.
  - **Known past bug (fixed)**: an early version re-read `exercises.cycles`
    once per whole run instead of per-row, so only the last-touched cycle
    slot per exercise actually stuck; and a `trim(trailing '.0' from ...)`
    used to strip trailing zero *characters* rather than a literal ".0"
    suffix, turning e.g. 20 into "2". Both are fixed in the current
    function bodies, but if prescriptions ever look randomly wrong again,
    suspect this function first and diff it against what's described here.

### Edge Functions

- **`nutrition-lookup`** — deliberately decommissioned stub (returns 410).
  Nutrition estimation is 100% local now (see `nutrition_ingredients`
  above); this function exists only because there's no "delete edge
  function" call in the tooling used so far. Safe to actually delete via
  the Supabase dashboard if anyone gets there first.

## Known gaps / things worth a follow-up agent's attention

1. **Video links are a mix of confidence levels.** Every exercise has
   *some* `video_url`. Some are specific YouTube videos I found and
   cross-verified against independent searches; a couple of candidates
   that repeatedly failed independent verification were deliberately left
   as the safe `youtube.com/results?search_query=...` fallback instead
   (currently: `Hack Squat`, `Barbell Hip Thrust`, and anything not
   explicitly re-verified). None are fabricated, but "verified by two
   AI-run web searches" is not the same as "confirmed by a human watching
   the video" — a periodic human spot-check would be worthwhile, and any
   time exercise names change, the video/equipment mapping needs re-doing
   (matched by exact name, so renamed exercises silently keep no data
   until someone re-runs the authoring pass).
2. **`foods`/`food_servings`/`food_aliases` vs.
   `nutrition_ingredients`/`nutrition_units`** — two parallel food
   reference systems exist; only the second is wired into the live app.
   Worth figuring out whether the first is meant to replace the second
   eventually (better structure: cuisine tags, per-serving weights) and
   migrating, or whether it's dead weight from an earlier design.
3. **There's an existing external automation** touching this database
   (nutrition research, `food_library_runs`, migrations named
   `nightly_research_*`, `food_items` rows tagged
   `[ref nightly-research-YYYY-MM-DD]`). A new agent should look at
   `food_library_runs` (status/notes columns) and recent migration names
   before duplicating that work.
4. **`nutrition_suspect_entries`** already flags likely-bad nutrition log
   rows — run `select * from nutrition_suspect_entries;` before assuming
   the log is clean. I found and fixed three corrupted entries this way
   manually (a fuzzy-match bug — since fixed in `index.html`'s
   `findFuzzyFoodMatch` — let a one-ingredient preset like "1.5 cups rice"
   silently swallow an entirely different, more complex meal's macros).
5. **`workout_days.code = 'H'`'s WARM-UP row has `section = 'MAIN'`**
   (data entry quirk, harmless since the client matches by `name =
   'WARM-UP'`, not `section`, for the celebration/warm-up rendering path
   — but worth normalizing if anyone touches that row).
6. **No automated tests, no CI, no build step.** Validate changes by
   opening `index.html` (or the Pages URL) and exercising the flow by
   hand; check JS syntax with `node --check` after extracting the
   `<script>` block if editing without a browser.
7. `sessions.notes` (the original schema column) is dead — the app writes
   `general_note`/`issue_note` instead. Fine to ignore or drop later.

## Conventions for anyone continuing this

- All app changes are single commits to `index.html` on `main` (no PR
  step is currently used per the repo owner's preference — ask if that's
  still wanted before assuming it).
- Prefer additive, backward-compatible schema migrations
  (`apply_migration`) over destructive ones; this is a real user's live
  data.
- Before trusting any AI-sourced factual claim that will be written to the
  DB or shown to the user as fact (a specific video, a specific number),
  verify independently rather than trusting a subagent's own
  self-reported confidence — see the video-link saga above for why.
