# Architecture

Three audiences for this file: me in six months, another model picking this up cold, and
whoever is debugging at 2am. It explains what each module guarantees, why it is built the
way it is, and where the remaining game knowledge has to come from.

---

## 1. The constraint that shapes everything

Matcha is an external emulator, not an injector. From the official docs
(`doc.wabisabi.mom/matcha`, verified 2026-10-25):

> Matcha **is not an executor** — it does not hook any functions in the Roblox engine.
> Instead it emulates them externally ... it has no direct access to internal Roblox API
> functions.

Concretely, that removes four things every normal autofarm assumes:

| Assumed capability | Reality | Consequence for the design |
|---|---|---|
| `Instance.new` | absent | every pixel is `Drawing` or an existing instance |
| `RemoteEvent:FireServer` | not emulated | no packet-level automation, ever |
| `Humanoid:MoveTo` / `.WalkSpeed` | absent (only `Health`, `MaxHealth`) | movement is either a position write or injected keys |
| `Camera:WorldToViewportPoint` | absent | `WorldToScreen(pos) -> (Vector2, bool)` |

The place itself reinforces this: the entire workspace contains **one** `RemoteEvent`
(`__THINGS.__REMOTES.__INTRO`). There is no cooking remote to fire even if firing worked.

So every job must reach its goal through one of four doors:

1. **walk there and press the prompt's own key** (`ProximityPrompt`)
2. **walk there and click the part** (`ClickDetector`)
3. **equip a hotbar tool and press its number** (only if the tool is already in the hotbar)
4. **click the button the player would click** (`PlayerGui`, via `AbsolutePosition`)

Anything that cannot be expressed as one of those is not automatable in this build, and the
modules below say so out loud instead of failing silently.

---

## 2. Module map

Build order matters — `build.ps1` concatenates these in filename order into one file.

| Module | Owns | Guarantee |
|---|---|---|
| `00_boot` | namespace, logging, config, utilities | nothing throws at the top level; config persists across runs |
| `10_caps` | capability probe | every later module reads facts, not assumptions |
| `12_keymap` | `Enum.KeyCode` → VK translation | a prompt's key is pressed on the key the engine meant, not the ASCII value |
| `15_input` | keyboard/mouse injection | no input leaves the process unless Roblox is foreground |
| `20_move` | locomotion | reaches a target with writes *or* walking, and says which |
| `25_world` | world snapshot | the place never freezes, even at 64k instances |
| `30_act` | interaction | a prompt press is confirmed or reported as unconfirmed |
| `35_jobs` | scheduler | highest-value ready job runs; failures back off |
| `40_ui` | menu | usable without `Instance.new`; reads input only |
| `50_jobs_world` | the proven jobs | each target exists in the place by name |
| `60_main` | wiring | render path never blocks on game work |

### Why the probe exists (`10_caps`)

v1–v3 died because someone assumed an API existed. The probe answers the dangerous
questions once, at startup, and records the answers:

- does a position write **stick**, or does the server snap the character back?
- does `HumanoidRootPart.Position` exist as a writable field at all?
- is `Camera.CFrame` readable (needed for anything camera-relative)?
- are `ProximityPrompt` fields readable (`KeyboardKeyCode`, `HoldDuration`,
  `MaxActivationDistance`)?
- is `ReplicatedStorage` populated? is there a `Backpack`? a `PlayerGui`?

The position-write test is deliberate: it moves the character up 3 studs, waits 220 ms,
reads it back, then restores. If the write survives, write-mode movement is safe to use. If
not, the bot silently switches to walking. That single measurement is the difference
between a tool that works in one game and a tool that works generally.

### Why movement has two modes (`20_move`)

Write mode is instant and silent, but a place with server-side position checks will revert
it — and the revert is invisible unless you read the position back afterwards. So
`Move.writePosition` always verifies, and `Move.goto` falls through to `Move.walkTo` when
writes do not stick.

Walk mode steers the way a human does, using only documented calls:

```
mouse2press()                      -- hold right mouse to look
WorldToScreen(target) -> screen xy
mousemoverel((screenX - cx) * k, (screenY - cy) * k)
hold W until distance <= tol
```

Off-screen targets (behind camera) return `(0,0), false`, so the loop sweeps sideways in
fixed steps until the target projects, rather than spinning blindly. Progress is tracked and
`Move.unstick` jumps and strafes after 900 ms of no movement.

### Why the snapshot is sliced (`25_world`)

`GetDescendants()` on this workspace returns ~64,000 instances. Reading `ClassName` on all
of them in one frame drops the client to single-digit FPS or freezes it outright. The
scanner therefore builds a queue and processes ~7 ms per frame, so the menu keeps drawing
while the map is indexed.

Roots are `Workspace`, `ReplicatedStorage`, `ReplicatedFirst`, `Backpack`, `PlayerGui` and
the local `Character`. The last three matter because tools and on-screen state are how a
restaurant game usually communicates, and a workspace-only scan cannot see them.

### Why prompts are re-read live (`World.livePrompts`)

A prompt attached to a customer moves. A cached `Position` from scan time would send the bot
to where that customer was thirty seconds ago. `livePrompts()` re-reads the anchor position
per call; with 20 prompts that is free.

### Why there is a key-code table (`12_keymap`)

`Enum.KeyCode` is not a virtual-key code. It reuses ASCII, so `Enum.KeyCode.E.Value` is
`101`, and `keypress(101)` presses numpad-5 — the prompt never opens and nothing in the log
says why. `12_keymap` maps Roblox codes onto VK codes and prefers `.Name` over `.Value`
because the name is authoritative. The same table feeds movement keys, so `15_input` and
`30_act` cannot drift apart.

### Why activation is observed, not assumed (`Act.watch`)

Roblox shows at most one prompt per key (`OnePerButton`) or one in total
(`OneGlobally`), and decides by camera direction. A press aimed at the wrong prompt is
swallowed without an error. `ProximityPromptService.PromptShown` / `PromptHidden` /
`PromptTriggered` turn that into events: when the service is exposed, "is mine active"
and "did the press land" stop being heuristics. When it is not, `Act.competitors` answers
the same question from camera geometry, and `strict` mode refuses to press at all rather
than trigger a neighbour.

### Why GUI buttons are a first-class surface (`World.guiButtons`, `Act.clickGui`)

`PlayerGui` is where the game keeps everything with no part and no prompt: shops, cooking
menus, upgrades. `GuiObject.AbsolutePosition` and `AbsoluteSize` are already in screen
pixels, which is the same space `mousemoveabs` uses, so a button can be clicked at
`centre = AbsolutePosition + AbsoluteSize/2`. Visibility is checked up the whole ancestor
chain (`Util.guiShown`), because a button's own `Visible` stays `true` inside a hidden
frame or a disabled `ScreenGui`. This is the only path that reaches GUI-driven systems.

### Why the scheduler separates weight from cooldown (`35_jobs`)

Weight is "how much does this matter right now", cooldown is "how often may it run". A job
that finds nothing returns a string and retries in under a second; a job that acted gets its
full cooldown. Failures multiply the cooldown by up to 6× so a broken job cannot starve the
others by spinning.

---

## 3. What is proven, and what is not

**Proven by the place dump:** the 20 prompts, the 18 click detectors, the 4 restaurants, the
named NPCs, the shops, the one RemoteEvent.

**Proven by the docs:** the API surface in `MATCHA-API.md`.

**Proven by execution:** `src/` is parsed as Lua 5.1 by `check.ps1` (13 files), linted by
`tools/lint.js` (forbidden APIs, silent globals, chunk-local budget), and the seven
client-independent modules are executed in a real Luau VM by `run-tests.ps1` — 44
assertions covering key mapping, projection, prompt flags, exclusivity, GUI geometry and
click routing. A green run means the logic is correct, not just parseable.

**Not yet proven:** none of it has run inside Roblox. `10_caps` exists to convert the
remaining assumptions into facts on the first launch.

**Not known:** how cooking, serving, seating and cleaning are actually triggered. See
`GAME-MODEL.md`. `tools/DumpScripts.lua` is the intended answer — `getscripts()` +
`decompile()` returns the client's own interaction code, which is where the prompt
handlers and GUI wiring live. Until that or `diagnostics/recon.txt` exists, any
"restaurant job" would be fiction, so there isn't one.

---

## 4. How to add a job

```lua
RR.Jobs.add({
  id       = "restaurant.cook",
  label    = "cook",
  weight   = 9,                    -- higher runs first
  cooldown = 1.5,                  -- seconds
  enabled  = function()            -- optional; defaults to config toggle
    return RR.Cfg.get("job.cook", true) == true
  end,
  run      = function()
    local p = findPrompt("Stove")   -- must return an entry from World.livePrompts
    if not p then return "no stove" end
    local ok, why = RR.Act.prompt(p, { tol = 5 })
    return ok and true or ("failed: " .. why)
  end,
})
```

Rules that keep jobs honest:

- return `true` only when something actually changed; return a **string** otherwise and it
  lands in the job table and the report
- never `wait` longer than the job's cooldown budget
- never assume a name exists — `find` returns `{}`, `nearest` returns `nil`
- never call `World.scan()` from inside a job; use the rescan job

---

## 5. Roadmap: the modules that make it beat the game

Ordered by dependency, not by importance. Each one lists the evidence needed before it can
be written truthfully.

### 5.1 Restaurant state machine — *blocked on recon*

The four restaurants (`Restaurant_42`, `_58`, `_68`, `_69`) each carry an `Entities` folder.
Empirically confirmed entities: `Cash Register`, `Rusty Fridge`, `Piano`, `Trading Booth`,
`Pirate Trading Booth`, `Basement Guy`. **No cooking station prompts exist**, which means
either the station prompts spawn with a tool equipped, or cooking happens through the
backpack tool, or through GUI buttons.

Needed from recon: the tool list, the PlayerGui text while standing at a stove, and any
prompt that appears mid-order. `tools/DumpScripts.lua` answers all three faster than
behavioural capture, because the client's own prompt handlers and GUI wiring are in the
source.

### 5.2 Identity: which restaurant is mine

A job must never cook in someone else's plot. Candidate signals: a `StringValue`/`ObjectValue`
holding the player's plot, a `Highlight` on the owned model, or the plot whose `Entities`
folder already contains this player's name. Recon captures values and highlights for exactly
this reason.

### 5.3 Customer lifecycle

Seat → order → cook → serve → clean → cash is a state machine per customer, not a loop of
independent actions. The scheduler model above is deliberately *stateless per tick*, so
this module keeps its own table keyed by customer instance address, with a "last seen"
timeout. Without remote access there is no event to subscribe to, so state is derived from
position and prompt presence.

### 5.4 Passive systems (already partly live)

Daily quests, harvest minigame, shops, fisherman, spin wheel, corn maze, secret gnome — the
prompt jobs in `50_jobs_world.lua` already cover these, because the names are confirmed.

### 5.5 Economy systems — *blocked on recon*

`Shop`, `StationsMerchant`, `BaitMerchant`, `PetMerchant`, `BlackMarket`, `GlobalMarket`,
`LimitedItemStands`, `FireworkNodes`. None of these expose prompts in the dump. Either
case is now covered: `Act.clickDetector` for a stand, `World.findGui` +
`Act.clickGuiNamed` for a menu. The remaining unknown is *when* a menu is open, which is
what `Caps.probe`'s GUI section reports (screen names and button labels) on first run.

### 5.6 Fishing — *partially unblocked*

`DeepFishingLocations` (19) and `Spots` (19) exist as parts. `BaitMerchant` sells bait.
The cast action is unknown; if it is a tool, the tool name from recon finishes it.

### 5.7 Pets — *partially unblocked*

`Pets` (116 instances) plus `PetMerchant` and click detectors on `Pets.Model`. Click-to-equip
is plausible and testable today.

### 5.8 Anti-idle and session hygiene

`isrbxactive` gating already prevents input leaking. A long session also needs: re-anchor
after teleport, rescan on `WorldZones` change, and a watchdog that stops the toolkit if the
character has not moved for 60 s with jobs enabled.

---

## 6. Known weak points

1. `Move.lookAt` assumes right-mouse drag rotates the camera the default way. `CameraType`
   is reported by the probe now, but a place that locks first-person still defeats manual
   steering; walk mode then fails instead of looping forever.
2. A prompt press is only meaningful when the target owns the input slot. `strict` mode and
   `Act.watch` cover that, but without `ProximityPromptService` the geometry fallback can be
   wrong when two prompts project to nearly the same pixel.
3. GUI clicks do not model occlusion. If a modal covers the button, the click lands on the
   modal; `verify` is the only defence.
4. The scheduler runs one job per 60 ms slice; a job that blocks for 10 s starves the rest.
   That is acceptable now, not forever.
5. `World.maxItems = 90000` is above the current 64k, so a bigger place would truncate
   silently. It logs the queue size at scan start, which is the tell.
6. Config values are flat strings; there is no schema or migration.
7. `PlayerGui` is re-read on demand rather than cached, because client scripts rebuild menus
   constantly. That is correct, but it means `World.findGui` is O(descendants) and must not
   be called in a tight loop.

---

## 7. Verification pipeline

```powershell
.\build.ps1        # src/*.lua -> dist/RunRestaurant.lua, one module per file, in order
.\check.ps1        # luaparse 5.1 syntax gate on every src file, dist and tools
node tools\lint.js # forbidden APIs, undeclared globals, chunk-local budget
.\run-tests.ps1    # executes src in Luau 0.744 against tests/spec.luau
```

`run-tests.ps1` concatenates `tests/stub.luau` (a minimal fake Roblox: clock, Vector2/3,
CFrame, Drawing, services, a PlayerGui with one visible and one hidden button), the seven
client-independent modules, and `tests/spec.luau`. The stub shadows `_G` with a plain
table because the Luau CLI freezes the real one; every module resolves `_G` to that table
exactly as Matcha's loader would.

A module belongs in the suite only if it loads without a live client. `35_jobs`, `40_ui`,
`50_jobs_world` and `60_main` need services the stub does not pretend to provide, so they
are covered by `check.ps1` and `lint.js` only.
