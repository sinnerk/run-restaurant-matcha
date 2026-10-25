# Repo status — read this before editing the README

Last verified: 2026-10-25.

## What is actually in this repo

```
RunRestaurant_Matcha.lua  ← v3.0, 22 KB — added 2026-10-25 from the Downloads copy
README.md                 ← design doc for that v3.0
docs/MATCHA-API.md        ← verified Matcha API surface
.githooks/                ← pre-commit guard against secrets / personal paths
tools/                    ← guard setup + history scanner
```

The script is the **v3.0** build (`RunRestaurant_Matcha_6.lua` on disk, byte-identical,
SHA-256 `2C625E3C…F082D`). It parses as Lua 5.1 and contains no secrets or personal
paths, but see the next section before running it.

## The README describes a build that cannot run

The README is written against `UI.AddTab`, `UI.GetValue` and `remote:FireServer(...)`.
None of those exist in Matcha (see `docs/MATCHA-API.md`). That exact architecture was
already tried and diagnosed in the sibling repo `roblox-matcha-autofarm`, whose README
records the failure:

> v3 called `UI.AddTab("Restaurant", ...)` at line 472 and `UI.GetValue(...)` everywhere
> else. There is no `UI` library in the Matcha API. That call threw immediately, so the
> entire menu block died, and the main loop's `UI.GetValue("farmSpeed")` then killed the
> farm thread before it ran one tick.

So the menu section, the toggle reads, the remote scanner and every `fire0/1/2` call in
the README's design are non-functional by construction. Rebuilding it as written
reproduces a known-dead script.

## What does work — and where it lives

`projects/roblox-matcha-autofarm` (separate repo, `sinnerk/roblox-matcha-autofarm`)
holds **v4.2.0**, the rewrite that was tested against the real VM:

- GUI drawn with `Drawing` (no `Instance.new`, no `UI.*`)
- targets `ProximityPrompt`s and drives them with `keypress`/`mousemoveabs`
- focus gate via `isrbxactive()` so injected input never hits the desktop
- capability probe, prompt inventory, telemetry JSON dumps, build + lint scripts
- `dist/RunRestaurant.lua` — 144 KB, single file

That build is the real starting point. This repo currently has a README for a version that
predates it.

## Game data captured so far

`[121042]  === REMOTE SCANNER ===.txt` — 6.7 MB, 64,056 lines of instance paths from the
live place (sits in the user's Downloads folder, outside the repo). It is deliberately
**not** committed (public repo, size). Relevant findings:

- **Exactly one `RemoteEvent` in the entire workspace**: `Workspace.__THINGS.__REMOTES.__INTRO`.
  That confirms remote firing is a dead end here — there is nothing to fire for cooking,
  serving or cashing out.
- Interactions are `ProximityPrompt`s, e.g.
  `Restaurant_68.Entities.Cash Register_<guid>.Interact.ProximityPrompt`,
  `Restaurant_68.Entities.Rusty Fridge_<guid>.Root.ProximityPrompt`,
  `Restaurant_58.Entities.Piano_<guid>.Root.InteractAttachment.ProximityPrompt`.
- Restaurant instances are numbered (`Restaurant_42`, `_58`, `_68`, `_69` …) with
  `Entities` children, so "my restaurant" has to be identified before any job acts.

## Open decisions

1. Make this repo the home of the v4.2.0 lineage, or keep `roblox-matcha-autofarm` as the
   code repo and use this one only for notes? Two repos holding the same project will
   drift.
2. If the code moves here, the README gets rewritten against `docs/MATCHA-API.md`.
3. The scanner dump should be summarised into a small committed file (prompt names,
   restaurant layout) rather than committed raw.
