# Game model — what the place actually contains

Evidence source: `[121042] === REMOTE SCANNER ===.txt`, 64,056 lines captured from the live
server on 2026-10-21 at 12:10. Paths below are quoted verbatim with the `_<guid>` suffixes
stripped.

This file is the map. If a module disagrees with it, the module is wrong.

---

## 1. Top-level layout

`Workspace.__THINGS` holds the world; `Workspace.__DEBRIS` holds loose NPCs.

| Node | Instances | What it is |
|---|---:|---|
| `Restaurants` | 45,938 | the playable plots |
| `Shop` | 5,649 | main store |
| `CornMazeEntrance` | 591 | maze + leaderboard board |
| `FlowerBedGeneration` | 385 | generated farming plots |
| `BaitMerchant` | 307 | fishing bait vendor |
| `StationsMerchant` | 184 | station upgrades |
| `Gnomes` | 151 | collectible secret gnomes (ClickDetector) |
| `Pets` | 116 | pets (ClickDetector) |
| `FireworkNodes` | 41 | firework event |
| `PetMerchant` | 39 | pet vendor |
| `WorldZones` | 21 | zone volumes |
| `DeepFishingLocations` | 19 | deep-water fishing spots |
| `Spots` | 19 | generic interaction spots |
| `LimitedItemStands` | 14 | rotating stock |
| `QuestNPCSpots` | 10 | quest NPC anchors |
| `ExternalNodes` | 9 | out-of-plot nodes |
| `BlackMarketNodes` / `BlackMarket` | 7 / 7 | black market |
| `SpinWheel` | 6 | daily spin |
| `GlobalMarketNPCSpots` / `GlobalMarketScreens` | 5 / 5 | player market |
| `FlowerBedBlueprint` | 5 | farming blueprint |
| `FireworkCrateSpots` | 2 | firework crates |
| `__REMOTES` | 2 | **one** RemoteEvent: `__INTRO` |
| `RestaurantCollisionFloor` | 1 | plot floor |

That is roughly a dozen progression systems. The v3 autofarm only ever touched one of them.

---

## 2. The plots

Four restaurants exist in the server at once:

| Plot | Instances |
|---|---:|
| `Restaurant_42` | 20,329 |
| `Restaurant_58` | 15,308 |
| `Restaurant_69` | 5,955 |
| `Restaurant_68` | 4,345 |

Each has an `Entities` folder. The counts differ by a factor of five, which means the folders
are not a fixed template — a developed plot carries far more content than a fresh one. That
is useful: **the player's own plot is likely identifiable by content or by a value, not by
index.**

Confirmed entities across all four plots:

```
Cash Register            Interact.ProximityPrompt
Rusty Fridge             Root.ProximityPrompt
Piano                    Root.InteractAttachment.ProximityPrompt
Trading Booth            Interact.ProximityPrompt
Pirate Trading Booth     Interact.ProximityPrompt
Basement Guy             UpperTorso.ProximityPrompt
```

Notably absent: any stove, grill, pot, sink, table, or customer prompt. See §4.

---

## 3. Complete interaction inventory

### ProximityPrompts — 20 unique paths in the entire place

```
__DEBRIS.DailyQuestNPC.HumanoidRootPart.ProximityPrompt
__DEBRIS.FishermanNPC.HumanoidRootPart.ProximityPrompt
__DEBRIS.HarvestMiniGameNPC.HumanoidRootPart.ProximityPrompt
__DEBRIS.HarvestShopNPC.HumanoidRootPart.ProximityPrompt
__DEBRIS.ShopNPC.HumanoidRootPart.ProximityPrompt
__DEBRIS.1..4.HumanoidRootPart.ProximityPrompt
__DEBRIS.Part.ProximityPrompt
__THINGS.CornMazeEntrance.Door.ProximityPrompt
__THINGS.SpinWheel.Interact.ProximityPrompt
__THINGS.Restaurants.Restaurant_42.Entities.Basement Guy.UpperTorso.ProximityPrompt
__THINGS.Restaurants.Restaurant_42.Entities.Trading Booth.Interact.ProximityPrompt
__THINGS.Restaurants.Restaurant_58.Entities.Basement Guy.UpperTorso.ProximityPrompt
__THINGS.Restaurants.Restaurant_58.Entities.Piano.Root.InteractAttachment.ProximityPrompt
__THINGS.Restaurants.Restaurant_58.Entities.Pirate Trading Booth.Interact.ProximityPrompt
__THINGS.Restaurants.Restaurant_68.Entities.Cash Register.Interact.ProximityPrompt
__THINGS.Restaurants.Restaurant_68.Entities.Rusty Fridge.Root.ProximityPrompt
__THINGS.Restaurants.Restaurant_69.Entities.Basement Guy.UpperTorso.ProximityPrompt
__THINGS.Restaurants.Restaurant_69.Entities.Trading Booth.Interact.ProximityPrompt
```

### ClickDetectors — 18

- `__THINGS.Gnomes.Gnome.__SecretGnomeClickDetector` (repeated instances)
- `__THINGS.Pets.Model.ClickDetector`

### Everything else

- `RemoteEvent`: **1** (`__THINGS.__REMOTES.__INTRO`)
- `Tool` in workspace: **0** — because tools live in `Player.Backpack` until equipped, and the
  scan never touched `Backpack`. `Caps.probe` now reads `Backpack` and the character and
  records the tool names; any tool in there is an interaction the dump could not see.
- `LocalScript`: 4 · `BindableFunction`: 4 · `ImageButton`: 8 · `SurfaceGui`: 29
- `TextLabel`: 240 · `Frame`: 5,055 · `BillboardGui`: 64

Those 8 `ImageButton`s are inside `SurfaceGui`s **in the workspace**, not in `PlayerGui`:
they are drawn on the surface of a part, so they are clicked through the part, not through
`AbsolutePosition`. `Act.clickPart` hits the part's centre, which is not necessarily where
the button is on its face — a targeted offset is needed once the surface is identified.

The 5,055 `Frame`s and 240 `TextLabel`s are also workspace UI (billboards and surfaces).
`PlayerGui` is a separate tree that the dump never saw; `Caps.probe` reports it now.

---

## 4. The open question

**Cooking, serving, seating and cleaning produce no prompts in the dump.**

Three explanations, all testable:

1. **Tool-gated.** The station prompts are created, or enabled, only while the player holds
   the relevant tool. The scan ran with no tools equipped in `Workspace`.
2. **GUI-driven.** `PlayerGui` was never scanned (it is not in `Workspace`), and 8
   `ImageButton`s exist inside `SurfaceGui`s. A station menu could be entirely on-screen.
3. **Proximity to NPC.** Prompts appear when a customer is seated nearby, and the scan caught
   the server between waves.

Distinguishing these needs one of two captures:

1. **`tools/DumpScripts.lua`** (preferred) — `getscripts()` + `decompile()` returns the
   client's own LocalScripts and ModuleScripts. Whatever handles a stove is in there, along
   with the GUI wiring and the remote names. `scripts/findings.txt` is the derived summary
   (names, key codes, classes, quoted labels) and is safe to commit; the decompiled `.lua`
   files are not.
2. **`tools/Recon.lua`** — behavioural fallback. Watches `Backpack`, `PlayerGui` and the
   prompt set for 90 seconds while you play a round, and writes `diagnostics/recon.txt`.

Until one of them exists, a "cook" job would be written against names nobody has seen, which
is exactly how v1–v3 failed.

---

## 5. What can be automated today, with zero new information

These are confirmed by name and reachable by prompt:

| Job | Target | Weight |
|---|---|---:|
| quests | `DailyQuestNPC` | 8 |
| spinwheel | `SpinWheel.Interact` | 7 |
| harvest | `HarvestMiniGameNPC` | 7 |
| harvestshop | `HarvestShopNPC` | 4 |
| shop | `ShopNPC` | 4 |
| fisherman | `FishermanNPC` | 4 |
| cornmaze | `CornMazeEntrance.Door` | 3 |
| gnome | `Gnomes.Gnome.__SecretGnomeClickDetector` | 2 |

The four `__DEBRIS.1..4` prompts have no descriptive name and were not guessed at; they show
up in the world scan and can be inspected live from the report menu.

---

## 6. Numbers worth remembering

- 64,056 scanned lines, 63,984 of them under `Workspace`.
- 39,181 `Part`, 6,738 `Model`, 6,434 `MeshPart` — the place is geometry-heavy, so any
  per-tick `GetDescendants()` is fatal.
- 5,055 `Frame` and 240 `TextLabel` **inside the workspace**, i.e. billboard and surface UI,
  not `PlayerGui`.
- 351 `Motor6D`, 208 `Bone`, 22 `Humanoid` — enough animated NPCs that prompt anchors move.
