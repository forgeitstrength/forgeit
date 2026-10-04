# Forge — native iOS + watchOS app (v1)

A SwiftUI companion to `index.html`, talking to the same Supabase project
directly (same anon key, same tables, same RLS). See `../CLAUDE.md` for the
full backend brief.

## What's in this build

- **Auth** — email/password, same as the web app.
- **Workout** — today's session with the same day/cycle auto-rotation logic
  as the web app, day picker, check off sets, edit weight/reps, per-exercise
  equipment + "Watch form" video link, warm-up/finisher notes, general/issue
  notes, save (upserts `sessions` + `session_exercise_logs` exactly like
  `finishBtn` does on the web).
- **Nutrition** — macro rings, log food via the same local ingredient
  estimator (ported to Swift in `Shared/NutritionEstimator.swift`) with the
  same exact/fuzzy "reuse a saved food's macros" matching, water + supplement
  quick-log.
- **Watch app** — a trimmed version: view + check off today's sets and save,
  plus a Quick Log page for water/supplements. Full nutrition text entry
  stays on the phone (typing food descriptions on a watch is painful).

## Not in this build yet (use the web app for these)

Plan tab, Progress tab (best lifts / volume / adherence / TDEE), Profile
editing, body metrics, the onboarding "build your program" flow. All of
that logic exists in `index.html` if someone wants to port it next —
`Shared/WorkoutService.swift` and `Shared/NutritionService.swift` are the
pattern to follow (mirror the Supabase calls, keep the same table/column
names).

## Building this (you'll need a Mac + Xcode)

I can't compile or test Swift from the environment that wrote this — no
Xcode, no Mac. Expect some first-build fixups; this was written carefully
against the real Supabase schema but never run.

1. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen) (generates the
   `.xcodeproj` from `project.yml` — much more reliable than a hand-written
   project file):
   ```
   brew install xcodegen
   ```
2. From this `apple/` directory:
   ```
   xcodegen generate
   open Forge.xcodeproj
   ```
3. In Xcode, select the **Forge** target → *Signing & Capabilities* → pick
   your Apple ID as the team. Do the same for the **ForgeWatch** target. A
   free Apple ID works for installing to your own devices (re-sign every 7
   days); a paid Developer account ($99/yr) avoids that.
4. If Xcode complains the bundle ID is taken, change `bundleIdPrefix` in
   `project.yml` to something only you'd use (e.g. `com.<yourname>.forgeit`)
   and re-run `xcodegen generate`.
5. Plug in your iPhone (paired with your Watch), select the **Forge**
   scheme → your iPhone as the run destination → Run. First launch will ask
   you to trust the developer certificate: **Settings → General → VPN &
   Device Management** on the phone.
6. Switch the scheme to **ForgeWatch** → your paired Watch as the
   destination → Run, to install the watch app the same way.
7. Log in with your Forge account on the phone; the Watch app shares the
   same signed-in session once both are on the same Apple ID/Watch pairing
   (if it doesn't pick it up automatically, log in again on the Watch — it
   has its own login screen for that case).

## Architecture notes

- `Shared/SupabaseClient.swift` is a from-scratch REST client (no Supabase
  SDK dependency) — plain `URLSession` calls to PostgREST (`/rest/v1/...`)
  and GoTrue (`/auth/v1/...`), refresh token stored in the Keychain. Kept
  dependency-free on purpose so the first build doesn't also have to
  resolve a Swift Package.
- Every table with a server-generated `id` has a matching `New*` encode-only
  struct (`NewWorkoutSession`, `NewNutritionLogEntry`, etc.) — Swift's
  `Encodable` writes `nil` as JSON `null` rather than omitting the key, and
  an explicit `"id": null` on insert blocks Postgres's `gen_random_uuid()`
  default. Follow that pattern for any new insert you add.
- Match the DB's actual nullability when adding fields to a Codable struct
  used for *decoding* — `protein_g`/`carbs_g`/`fat_g`/`fiber_g` are nullable
  on `nutrition_log` and `food_items` in the live schema; declaring them as
  non-optional `Double` will crash the decode on a row that happens to have
  a null. Check `CLAUDE.md`'s schema section before assuming a column is
  required.
