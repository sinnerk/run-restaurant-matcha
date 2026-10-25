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

So every job must reach its goal through one of three doors:

1. **walk there and press the prompt's own key** (`ProximityPrompt`)
2. **walk there and click the part** (`ClickDetector`)
3. **equip a hotbar tool and press its number** (only if the tool is already in the hotbar)

Anything that cannot be expressed as one of those is not automatable in this build, and the
modules below say so out loud instead of failing silently.

---

## 2. Module map

Build order matters — `build.ps1` concatenates these in filename order into one file.

| Module | Owns | Guarantee |
|---|---|---|
| `00_boot` | namespace, logging, config, utilities | nothing throws at the top level; config persists across runs |
| `10_caps` | capability probe | every later module reads facts, not assumptions |
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

**Proven by execution:** only the syntax and the static checks in `check.ps1` / `tools/lint.js`.
Nothing here has been run inside Roblox yet. That is why `10_caps` exists — first run tells
us which assumptions held.

**Not known:** how cooking, serving, seating and cleaning are actually triggered. See
`GAME-MODEL.md`. Until `diagnostics/recon.txt` exists, any "restaurant job" would be
fiction, so there isn't one.

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
prompt that appears mid-order.

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
`LimitedItemStands`, `FireworkNodes`. None of these expose prompts in the dump, so purchase
interaction is unknown: likely ClickDetector on a stand, or a GUI.

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

1. `Move.lookAt` assumes right-mouse drag rotates the camera the default way. Places that
   force first-person or lock the camera will defeat it; the probe should be extended to
   detect that.
2. `Act.prompt` presses the key without confirming focus. If the prompt is not selected, the
   key press goes to the game world instead (often harmless, sometimes a tool swing).
3. The scheduler runs one job per 60 ms slice; a job that blocks for 10 s starves the rest.
   That is acceptable now, not forever.
4. `World.maxItems = 90000` is above the current 64k, so a bigger place would truncate
   silently. It logs the queue size at scan start, which is the tell.
5. Config values are flat strings; there is no schema or migration.
