# 🍽 Run a Restaurant! — Matcha AutoFarm

> **Executor:** Matcha LuaVM · **Version:** v3.0 · **Game:** Run a Restaurant! (Roblox · Place ID 121042)

> [!WARNING]
> **This README is not accurate and the script it describes is not in this repo.**
> It is written against `UI.AddTab` / `UI.GetValue` / `remote:FireServer`, none of which
> exist in Matcha. Read [`docs/STATUS.md`](docs/STATUS.md) and
> [`docs/MATCHA-API.md`](docs/MATCHA-API.md) before writing any code from this file.

---

## ⚡ Quick Start

1. Open Matcha executor
2. Copy `RunRestaurant_Matcha.lua` into a new script tab
3. Run it while in the game
4. Menu opens automatically — **Insert key** toggles it open/closed

---

## 🧠 How It Works

### Remote Scanner
On startup the script scans `ReplicatedStorage`, `ReplicatedFirst`, and `workspace` for `RemoteEvent` and `RemoteFunction` instances. It fuzzy-matches their names against a list of known aliases for each action (seat, cook, serve, etc.) and caches them in the `R` table. If no remotes are found it falls back to **proximity mode** — teleporting to the nearest matching part and interacting without firing remotes.

You can re-run the scanner any time from the **Settings & Status** panel → **Scan Remotes**.

### Farm Loop
Two tiers:
- **Fast** (~180ms default): Seat → Order → Cook → Serve → Clean → Cash → Harvest
- **Slow** (every 5s): Quests → Staff → Upgrade

All actions are wrapped in `pcall` so one failure never kills the loop.

### HUD Overlay
A Drawing API overlay (top-left corner) shows live stats: phase, last action, orders served, dishes cooked, crops harvested, cash collected, ping, and uptime. Toggle it from the menu.

---

## 📋 Matcha API Rules (READ BEFORE EDITING)

Matcha is an **external LuaVM** — it does NOT inject into Roblox memory. This means:

| ❌ Don't use | ✅ Use instead |
|---|---|
| `Instance.new()` | `Drawing.new()` or `UI.AddTab()` |
| `game:HttpGet()` | `httpget(url)` |
| `Camera:WorldToViewportPoint()` | `WorldToScreen(pos)` → `(Vector2, bool)` |
| `fire(remote, ...)` with `...` inside pcall | `fire0(r)` / `fire1(r, a1)` / `fire2(r, a1, a2)` |
| `task.delay()` | `wait(t)` inside `task.spawn()` |
| `RunService.Stepped` with 2 args | Only `deltaTime` is passed |

### The vararg rule
Matcha's LuaVM **cannot** use `...` inside a nested anonymous function passed to `pcall`. This was the main bug in v1/v2. All fire helpers use explicit argument overloads:
```lua
local function fire0(remote)         if remote then pcall(function() remote:FireServer()        end) end end
local function fire1(remote, a1)     if remote then pcall(function() remote:FireServer(a1)      end) end end
local function fire2(remote, a1, a2) if remote then pcall(function() remote:FireServer(a1, a2) end) end end
```

---

## 🗂 File Structure

```
run-restaurant-matcha/
├── RunRestaurant_Matcha.lua   ← Main script (inject this)
└── README.md                 ← You are here
```

---

## 🔧 Menu Layout

### Left Panel — Automation
| Toggle | Default | Description |
|---|---|---|
| Seat Customers | ON | TP to customer NPCs and fire seat remote |
| Take Orders | ON | Collect orders from tables |
| Auto Cook | ON | Interact with stoves/pots |
| Serve Food | ON | Deliver food to tables |
| Clean Dishes | ON | Pick up dirty dishes |
| Collect Cash | ON | Use cash register |
| Harvest Crops | ON | Farm crops in the kitchen garden |
| Claim Quests | OFF | Auto-claim completed quests |
| Hire Staff | OFF | Auto-buy waiters |
| Auto Upgrade | OFF | Fire upgrade remote repeatedly |
| Tick Speed (ms) | 180 | How fast the farm loop runs |
| Keybind | Insert | Open/close the Matcha menu |

### Right Panel — Settings & Status
| Control | Description |
|---|---|
| HUD Overlay | Show/hide the Drawing HUD in top-left |
| Anti-AFK | Jump every 4min to reset AFK timer |
| Auto Server Hop | Periodically rejoin a new server |
| Hop Interval | Minutes between server hops |
| Server Hop Now | Instant server hop button |
| Scan Remotes | Re-run the remote scanner |
| About | Show executor info + remote status |

---

## 🐛 Known Issues / TODO

- [ ] Remote names are guesses — paste real names from `[121042] === REMOTE SCANNER ===.txt` into `REMOTE_MAP` for guaranteed hits
- [ ] `doAutoStaff` always buys "Waiter" — needs combo widget to pick staff type
- [ ] `doAutoOrder` may grab wrong part — needs tighter name filtering once real remote names known
- [ ] No GC-based cash counter yet (needs memory scan offset)
- [ ] Server hop could check player count first before hopping

---

## 🤖 Notes for AI Sessions

If you're an AI picking this up, here's the full context so you don't need the chat history:

- **Game:** `Run a Restaurant!` on Roblox (place ID 121042)
- **Executor:** Matcha — external LuaVM, not injected. Docs at `doc.wabisabi.mom/matcha`
- **Critical rule:** Never use `...` inside `pcall(function() end)` — use explicit `fire0/fire1/fire2` helpers
- **UI system:** `UI.AddTab(name, fn)` → `tab:Section(name, side)` → `sec:Toggle/Slider/Button/Keybind`
- **Drawing:** `Drawing.new("Square"|"Text"|"Line"|"Circle")` for overlays — never `Instance.new`
- **Remote scanner:** `REMOTE_MAP` at top of script — add real remote names from the scanner txt file there
- **State table:** `State` holds all runtime counters, `R` holds cached remotes
- **Next priorities:** plug in real remote names, smarter proximity matching, GC cash counter, staff type combo

---

## 📜 Changelog

| Version | Notes |
|---|---|
| v1.0 | Initial Drawing-only UI, all logic stubs, broken |
| v2.0 | Switched to UI.AddTab, added real logic + remote scanner |
| v3.0 | Fixed vararg crash, fixed or-chain syntax, pcall-safe fires, full README |
