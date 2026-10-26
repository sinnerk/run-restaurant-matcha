# Run a Restaurant! — Matcha toolkit

**v5.1.0** · Matcha LuaVM · place `121042`

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
| Prompt / ClickDetector / GUI-button interaction | done |
| Prompt activation observed (`ProximityPromptService`) | done, falls back to camera geometry |
| Correct `KeyCode` → VK translation | done (v5.0.0 pressed numpad keys) |
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

Two tools close that gap, in this order:

**1. `tools/DumpScripts.lua`** — decompiles the client's own scripts. `getscripts()` +
`decompile()` returns the LocalScripts and ModuleScripts that handle prompts, tools and
menus, which is exactly where "how do I cook" is answered. It writes
`scripts/findings.txt`: object names, remote names, key codes and class names, with no
source code in it, so that one file is safe to commit. The `.lua` files it also writes
stay on your machine — decompiled game code is not ours to publish.

**2. `tools/Recon.lua`** — behavioural fallback if script source is not available. Run it
in-game for 90 seconds while you play a normal round, then commit the output:

```powershell
# after Matcha writes recon.txt to its workspace folder
copy "<matcha workspace>\recon.txt" diagnostics\recon.txt
git add diagnostics/recon.txt
git commit -m "diagnostics: live recon capture"
git push
```

With either file, the restaurant modules get written against real names — the same way the
eight world jobs already are.

---

## What runs today

On load the toolkit:

1. **probes the environment** — executor, place id, missing globals, whether
   `HumanoidRootPart.Position` writes survive the server, whether prompts expose
   `KeyboardKeyCode` / `HoldDuration` / `Exclusivity`, whether `ReplicatedStorage`,
   `Backpack` and `PlayerGui` are reachable, what tools are in the bag, and which GUI
   buttons are visible
2. **scans the world** in 7 ms slices, indexing every prompt and click detector
3. **observes prompt activation** — if `ProximityPromptService` is exposed, the toolkit
   knows which prompt is active and whether a press actually triggered it
4. **starts the job loop** — quests, spin wheel, harvest minigame, harvest shop, shop,
   fisherman, corn maze door, secret gnome

Movement picks itself: if position writes stick it teleports, otherwise it holds `W` and
steers the camera with right-mouse drag until `WorldToScreen` puts the target in the middle
of the screen. That fallback is why this should survive places that reject position writes.

Prompts are pressed with their own key code, translated from Roblox's ASCII-flavoured
`Enum.KeyCode` to the Windows VK the OS expects (`E` is 101 in Roblox, `0x45` to Windows).
A prompt with a real hold duration gets a real hold, and a press only counts as successful
when the engine confirms it.

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
  00_boot.lua                 namespace, log, config, utilities, GUI geometry
  10_caps.lua                 capability probe (prompts, tools, backpack, PlayerGui)
  12_keymap.lua               Enum.KeyCode -> Windows virtual-key
  15_input.lua                keyboard/mouse, focus gate, screen-space clicks
  20_move.lua                 writes, walking, camera steering, unstuck
  25_world.lua                sliced world snapshot + name matching + GUI buttons
  30_act.lua                  prompts, click detectors, GUI clicks, activation watch
  35_jobs.lua                 scheduler
  40_ui.lua                   Drawing menu
  50_jobs_world.lua           the eight confirmed jobs
  60_main.lua                 boot, loops, report
tests/                        Luau suite: stub, spec, generated build
tools/DumpScripts.lua         decompile client scripts, extract findings (run this first)
tools/Recon.lua               behavioural recon fallback
docs/MATCHA-API.md            verified API surface — read before writing code
docs/ROBLOX-ENGINE.md         prompts, detectors, tools, GUI, streaming — engine facts
docs/LUAU-NOTES.md            language traps that shaped the code
docs/GAME-MODEL.md            what the place contains, from the dump
docs/ARCHITECTURE.md          module contracts, roadmap, known weak points
legacy/                       v1-v3, kept for reference, does not run
diagnostics/                  recon output goes here
```

Build, check and test:

```powershell
powershell -ExecutionPolicy Bypass -File build.ps1     # src -> dist
powershell -ExecutionPolicy Bypass -File check.ps1     # parse every file as Lua 5.1
node tools\lint.js                                     # forbidden APIs + silent globals
powershell -ExecutionPolicy Bypass -File run-tests.ps1 # execute src in Luau, 44 assertions
```

`check.ps1` parses with a Lua 5.1 grammar and `tools/lint.js` fails the build on
`Instance.new`, `FireServer`, `WorldToViewportPoint`, `task.delay`, `task.defer`,
`CharacterAdded`, `gethwid`, on any assignment to an undeclared global, and on a combined
chunk that gets too close to Lua's 200-local limit.

`run-tests.ps1` runs the real modules in a real Luau VM (0.744) against
`tests/spec.luau`, with `tests/stub.luau` standing in for Roblox. Set `LUAU_EXE` if the
CLI is not at `%USERPROFILE%\tools\luau\luau.exe`. A pass there means the key mapping,
projection, prompt-flag reading, exclusivity logic and GUI click routing actually compute
the right answers — not just that the files parse.

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
6. **`src/` is a Lua 5.1 subset.** `check.ps1` gates on a 5.1 parser, so no `continue`, `+=`,
   `//`, string interpolation or generalized iteration — even though the Luau CLI used by the
   tests accepts them. `docs/LUAU-NOTES.md` lists the rest of the traps.
7. **A press that is not confirmed is a failure.** Every interaction either observes the
   result or reports `false, reason`; nothing returns `true` because a call did not throw.

---

## Changelog

| Version | Notes |
|---|---|
| v5.1.0 | Fixes the prompt key bug (`Enum.KeyCode` is ASCII, not VK — v5.0.0 pressed numpad keys). Adds `12_keymap`, prompt activation observed through `ProximityPromptService`, exclusivity-aware presses, held camera drag during walks, GUI button scanning and clicking, a Luau test suite (44 assertions), `tools/DumpScripts.lua`, and the engine/language notes. |
| v5.0.0 | Module rewrite. Capability probe, dual-mode movement, sliced world scan, scheduler, Drawing menu, eight confirmed world jobs. Restaurant logic deliberately not faked. |
| v4.2.0 | Separate repo (`sinnerk/roblox-matcha-autofarm`). Prompt-first targeting, drawn GUI, capability probe, telemetry. Superseded by this repo. |
| v3.0 | `UI.AddTab` based, threw on load. Kept in `legacy/`. |
| v2.0 / v1.0 | Earlier attempts, same fatal assumptions. `legacy/`. |
