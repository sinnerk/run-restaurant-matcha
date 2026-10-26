# History — why v5 looks like this

## v1 → v3: built on APIs that do not exist

v3.0 (`legacy/RunRestaurant_Matcha_v3.lua`) called `UI.AddTab("Restaurant", ...)` at line 472
and `UI.GetValue("farmSpeed")` at line 559.

There is no `UI` table in Matcha. The call threw on load, the menu block died, and the farm
thread was killed by the first `UI.GetValue` before it ran a single tick. Every
`remote:FireServer(...)` in the file was wrapped in `pcall`, so those calls "succeeded" while
doing nothing at all — the remote scanner, the remote map and the server hop button were
dead weight from the first line.

That is the failure mode this repo is now built to prevent: a script that looks complete,
parses fine, and does nothing.

## Why v4 lived in a second repo

`sinnerk/roblox-matcha-autofarm` holds v4.2.0, a working rewrite that switched to a drawn
GUI and ProximityPrompt targeting. It was produced after the v3 failure and is the version
that proved which primitives actually work in this VM.

This repo (`run-restaurant-matcha`) was created afterwards and initially contained only a
README describing v3 — i.e. the design that had already been proven dead. That mismatch is
why `docs/MATCHA-API.md` now exists: so a future reader can check a claim against the real
docs instead of trusting a hand-written summary.

## What v5 changed

1. **Merged the two repos' truths.** The working primitives from v4.2.0 (focus gate, prompt
   targeting, drawn GUI) plus the verified API list.
2. **Measurement before code.** `10_caps` probes position-write persistence, prompt field
   readability and storage reachability at startup. Nothing is assumed about the build.
3. **Two movement modes.** v4 wrote `HumanoidRootPart.Position` and hoped. v5 verifies the
   write and falls back to camera-steered walking, which does not need an anti-cheat bypass.
4. **Sliced scanning.** A 64k-instance workspace cannot be walked in one frame.
5. **Honest scope.** Eight jobs with confirmed names ship; restaurant logic does not,
   because the place shows no cooking prompts and no cook remote. See `GAME-MODEL.md`.

## What v5.1 changed

The v5.0.0 build had a bug that would have made every prompt press miss: it read
`Enum.KeyCode.Value` and passed it to `keypress`, but Roblox KeyCodes are ASCII-flavoured
(`E = 101`) while the OS wants virtual-key codes (`E = 0x45`). Every press landed on the
numpad. That bug is the reason this version exists, and it is the reason the code is now
executed rather than reviewed:

1. **`12_keymap`** translates `Enum.KeyCode` → VK and is unit-tested against every letter,
   digit, arrow and function key.
2. **`tests/` + `run-tests.ps1`** run the real modules in a real Luau VM (44 assertions).
   Parsing was never proof; now arithmetic, exclusivity and click routing are checked.
3. **Activation is observed.** `Act.watch` connects to `ProximityPromptService` when the
   build exposes it, so "the prompt triggered" replaces "the key was pressed".
4. **Exclusivity is respected.** A press is spent on the prompt the camera has selected, and
   `strict` mode refuses to press when a neighbour would win.
5. **The camera drag is held** across a walk instead of pressed and released every frame.
6. **GUI buttons became a first-class surface.** `PlayerGui` is scannable and clickable at
   `AbsolutePosition + AbsoluteSize/2`, which reaches every menu-driven system the workspace
   scan could not see.
7. **`tools/DumpScripts.lua`** decompiles the client's own scripts and extracts names, keys
   and classes — the fastest route to the restaurant logic that `GAME-MODEL.md` still lists
   as unknown.

## Decisions on record

- **This repo owns the code.** `roblox-matcha-autofarm` is frozen at v4.2.0 as a reference.
- **No fabricated targets.** A job name is either in the scan dump or it waits for
  `diagnostics/recon.txt`.
- **The repo is public.** Every commit passes `.githooks/pre-commit` (secrets, personal
  paths, emails, >2 MB files). `tools/scan-history.ps1` covers the history, not just HEAD.
- **Legacy is kept, not deleted.** `legacy/RunRestaurant_Matcha_v3.lua` stays as the concrete
  example of the mistake.
