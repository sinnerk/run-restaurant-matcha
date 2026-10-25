# Run a Restaurant! — Matcha toolkit

**v5.0.0** · Matcha LuaVM · place `121042`

A module-based automation toolkit for *Run a Restaurant!*, built only on APIs that Matcha
actually exposes. It is a foundation with real, working pieces and clearly-marked gaps —
not a finished bot that pretends to be one.

```
dist/RunRestaurant.lua   <- paste this into Matcha and execute
```

Press **INSERT** for the menu.

---

## Status in one table

| Area | State |
|---|---|
| Capability probe (what works in this build) | done |
| Focus-gated input | done |
| Movement: position write **and** walk-mode fallback | done |
| Sliced world scan (64k instances, no freeze) | done |
| Prompt / ClickDetector interaction | done |
| Job scheduler with weights and backoff | done |
| Drawing menu | done |
| Passive jobs: quests, spin, harvest, shops, fisherman, corn maze, gnome | done, names confirmed from the live place |
| Restaurant state machine (seat / cook / serve / clean / cash) | **blocked — see below** |
| Economy, fishing, pets, market | **blocked — see below** |

---

## Why the restaurant part is not written yet

The previous versions (v1–v3, kept in `legacy/`) were built on `UI.AddTab`, `UI.GetValue`
and `remote:FireServer(...)`. None of those exist in Matcha. v3 was a 22 KB file that threw
on line 472 and never executed a single farm tick.

This version starts from measurement instead. Scanning the live place turned up something
that changes the whole design:

> The entire workspace contains **20 ProximityPrompts**, and not one of them is a stove,
> pot, sink, table or customer. There is also exactly **one RemoteEvent** in the whole map
> (`__THINGS.__REMOTES.__INTRO`).

So cooking cannot be automated by firing a remote (they do not exist / are not emulated) and
cannot be driven by a station prompt that is visible at scan time (there is none). The
interaction almost certainly lives in the **Backpack** (tools) or **PlayerGui**, neither of
which the original scan touched.

`tools/Recon.lua` is a standalone script that closes that gap. Run it in-game for 90 seconds
while you play a normal round, then commit the output:

```powershell
# after Matcha writes recon.txt to its workspace folder
copy "<matcha workspace>\recon.txt" diagnostics\recon.txt
git add diagnostics/recon.txt
git commit -m "diagnostics: live recon capture"
git push
```

With that file, the restaurant modules get written against real names — the same way the
eight world jobs already are.

---

## What runs today

On load the toolkit:

1. **probes the environment** — executor, place id, missing globals, whether
   `HumanoidRootPart.Position` writes survive the server, whether prompts expose
   `KeyboardKeyCode` / `HoldDuration`, whether `ReplicatedStorage`, `Backpack` and
   `PlayerGui` are reachable
2. **scans the world** in 7 ms slices, indexing every prompt and click detector
3. **starts the job loop** — quests, spin wheel, harvest minigame, harvest shop, shop,
   fisherman, corn maze door, secret gnome

Movement picks itself: if position writes stick it teleports, otherwise it holds `W` and
steers the camera with right-mouse drag until `WorldToScreen` puts the target in the middle
of the screen. That fallback is why this should survive places that reject position writes.

Every key press and click is gated on `isrbxactive()`. If you alt-tab, the bot stops
pressing things instead of typing into Discord.

---

## Menu

```
Status          live world / movement / interaction / job counters
Job toggles     one switch per job
Movement        allow position writes vs walk only
System          focus gate, log to file
Actions         rescan, run probe, write report, save config, stop
```

`Write report file` produces `runrestaurant_report.txt` in the Matcha workspace: capability
report, movement and interaction stats, per-job results, every live prompt with coordinates,
and the log tail. That file is the fastest way to tell what is wrong.

---

## Repository layout

```
dist/RunRestaurant.lua        built single-file release (the thing you run)
src/                          the modules, concatenated in filename order
  00_boot.lua                 namespace, log, config, utilities
  10_caps.lua                 capability probe
  15_input.lua                keyboard/mouse, focus gate
  20_move.lua                 writes, walking, camera steering, unstuck
  25_world.lua                sliced world snapshot + name matching
  30_act.lua                  prompts, click detectors
  35_jobs.lua                 scheduler
  40_ui.lua                   Drawing menu
  50_jobs_world.lua           the eight confirmed jobs
  60_main.lua                 boot, loops, report
tools/Recon.lua               standalone recon capture (run this next)
docs/MATCHA-API.md            verified API surface — read before writing code
docs/GAME-MODEL.md            what the place contains, from the dump
docs/ARCHITECTURE.md          module contracts, roadmap, known weak points
legacy/                       v1-v3, kept for reference, does not run
diagnostics/                  recon output goes here
```

Build and check:

```powershell
powershell -ExecutionPolicy Bypass -File build.ps1     # src -> dist
powershell -ExecutionPolicy Bypass -File check.ps1     # parse every file
node tools\lint.js                                     # forbidden APIs + silent globals
```

`check.ps1` parses with a Lua 5.1 grammar and `tools/lint.js` fails the build on
`Instance.new`, `FireServer`, `WorldToViewportPoint`, `task.delay`, `task.defer`,
`CharacterAdded`, `gethwid`, and on any assignment to an undeclared global.

---

## Rules this codebase follows

1. **Verified API only.** If it is not in `docs/MATCHA-API.md`, it does not go in `src/`.
   The doc has a "things that do NOT exist" table for a reason.
2. **Probe, do not assume.** Anything build- or place-dependent is measured at startup.
3. **No silent failures.** A job returns `true` only when something changed; otherwise it
   returns a string that shows up in the menu and the report.
4. **Never block the render path.** Drawing and scanning run on `RenderStepped`; work that
   waits runs on a worker thread.
5. **This repo is public.** The pre-commit hook blocks secrets, personal paths, emails and
   files over 2 MB. Run `tools/scan-history.ps1` before making anything public elsewhere.

---

## Changelog

| Version | Notes |
|---|---|
| v5.0.0 | Module rewrite. Capability probe, dual-mode movement, sliced world scan, scheduler, Drawing menu, eight confirmed world jobs. Restaurant logic deliberately not faked. |
| v4.2.0 | Separate repo (`sinnerk/roblox-matcha-autofarm`). Prompt-first targeting, drawn GUI, capability probe, telemetry. Superseded by this repo. |
| v3.0 | `UI.AddTab` based, threw on load. Kept in `legacy/`. |
| v2.0 / v1.0 | Earlier attempts, same fatal assumptions. `legacy/`. |
