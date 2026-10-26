# Matcha API — verified reference

Source: <https://doc.wabisabi.mom/matcha/llms-full.txt> (fetched 2026-10-25).
This file exists because a pasted "official Matcha docs" document circulated earlier
that contained functions which **do not exist** in Matcha (`UI.AddTab`, `UI.GetValue`,
`gethwid`, `fire0/fire1/fire2`, `Workspace:Raycast`, `Ray`, `UDim`, `UDim2`).
Anything not listed here should be treated as unverified until it runs in-game.

Matcha is **not an executor**. It emulates Roblox APIs externally. It does not hook the
engine, so it has no access to internal Roblox API functions. That single fact drives
most of the limitations below.

---

## Globals

| Function | Notes |
|---|---|
| `loadstring(chunk, name?)` / `load` | Syntax errors still return a function; the error only prints when called. Never `nil, msg`. |
| `decompile(script)` | LocalScript / ModuleScript / Script → source string. |
| `getscripthash(script)` | FNV-1a 64-bit of the bytecode, decimal string. |
| `getscriptbytecode(script)` | Raw bytecode as a binary string. |
| `getscripts()` | Every loaded script — large on a real place. |
| `WorldToScreen(v3)` | → `(Vector2, bool)`. Off-screen/behind camera returns `(0,0), false`. |
| `notify(msg, title, secs)` | |
| `identifyexecutor()` | → two strings: name, version. |
| `getgamename()` | Place title. |
| `base64encode(s)` | **Stops at the first `\0`.** |
| `base64decode(s)` | |
| `GetPingValue()` | ms. |
| `tick()` | **Monotonic clock**, not a Unix timestamp. |
| `typeof(v)` | Returns `Vector3`, `CFrame`, `Instance`, `Drawing`, … |
| `getfenv` / `setfenv` | |
| `run_secure(b64)` | Requires a protected base64 payload. Not usable publicly. |
| `setfflag` / `getfflag` | Documented as incomplete; `getfflag` returns 0 for everything. |
| `require(path)` | `.lua` / `.luau` only, resolved from a module root **separate** from the `writefile` workspace. `writefile` a module then `require` it does **not** work. |

`gethwid` is **not** in the docs. Do not ship anything that calls it.

## Console & input

`print` / `printl` / `warn` / `error` / `errorl`, `setrobloxinput`, `isrbxactive`,
`setclipboard`, `keypress` / `keyrelease` / `iskeypressed` (Windows VK codes),
`ismouse1pressed` / `ismouse2pressed`, `mouse1press` / `mouse1release` / `mouse1click`,
`mouse2press` / `mouse2release` / `mouse2click`, `mousemoveabs(x,y)`, `mousemoverel(x,y)`,
`mousescroll(n)`.

`error()` **prints, it does not raise**. Use `assert(false, msg)` for a catchable fault.

`mousemoveabs` uses the same pixel space as `WorldToScreen` and `Camera.ViewportSize`,
so a projection can be fed straight into it — and the same space as
`GuiObject.AbsolutePosition`, so GUI buttons can be clicked directly (see
`Input.clickScreen`).

### KeyCode is not a VK code

`keypress` / `keyrelease` take **Windows virtual-key codes**. A Roblox
`Enum.KeyCode` is not one: it reuses ASCII, so `Enum.KeyCode.E.Value == 101`, while
`VK_E == 69`. Pressing `101` hits numpad-5. Letters are `97..122` (`'a'..'z'`) and map
to VK `65..90`; digits are identical (`48..57`); arrows are `273..276` → `0x26/0x28/
0x27/0x25`; `F1..F12` are `282..293` → `0x70..0x7B`. `src/12_keymap.lua` owns the
conversion, and `KeyMap.resolve` prefers `.Name` over `.Value` because the name is
authoritative.

## Instance property reads — probed, not assumed

Only the classes listed below are documented. A `ProximityPrompt`, `ClickDetector`,
`Tool` or `ScreenGui` is *not* in that list, so no property of one is guaranteed. The
rule in this project is:

1. read every property inside `pcall`,
2. fall back to the **engine default** when the read fails (E, 0 s hold, 10 studs,
   `RequiresLineOfSight = true`, `Exclusivity = OnePerButton`),
3. record what was actually readable in the capability report so the first run tells
   you the truth.

`10_caps.lua` follows that pattern for prompts, tools and `PlayerGui`. An absent
service (`ProximityPromptService`, `Backpack`) is treated as "not exposed" and every
caller has a fallback path, so a build that exposes less still works.

## Scheduler

| | |
|---|---|
| `spawn(f)` | New thread, runs immediately. |
| `task.spawn(f)` | Synchronous until `f` yields. **Does not forward extra args** — use a closure. |
| `task.defer(f)` | **No-op in this build.** |
| `task.delay(t, f)` | **No-op in this build.** Use `wait(t)` inside `task.spawn`. |
| `wait(t)` / `task.wait(t?)` | Both return **nothing**. |

## Memory (needs "unsafe LuaU execution" allowed)

`getbase()` → base address of `RobloxPlayerBeta.exe`.
`memory_read(type, addr)` / `memory_write(type, addr, value)`.
Types: `int`, `float`, `double`, `byte`, `string`, `uintptr_t`.
Reading unmapped memory returns `0`; `string` reads until the first non-printable byte.

## Garbage collector

`getgc(name | {names})` → array of `{ key, value, type, addr }`.
`setgc(key, value)` / `setgc({k=v})` → count changed. Only same-type values are replaced.
`applygc(cache, key, value)` — reuse a `getgc` cache instead of rescanning.
`setgc` scans the heap on every call: never call it in a loop, use `applygc`.

## Filesystem

`writefile` `readfile` `appendfile` `makefolder` `isfile` `isfolder` `listfiles` `delfile` `delfolder`.
Extensions allowed: `.txt .lua .luau .json .cfg .dat .ini`. Binary-safe — use `.dat`.
Paths are relative to the Matcha workspace and case-insensitive; `/` and `\` are interchangeable.

## HTTP

`httpget(url, headers?)`, `httppost(url, body, contentType?, headers?)`.
Both are **synchronous** and **never raise**: an error status returns the body, a
connection failure returns `""`. Guard on `body ~= ""`.

---

## Classes that exist

- **BasePart** — `Size`, `Position`, `Transparency`, `Color`, `Velocity`, `AssemblyLinearVelocity`, `CanCollide`
- **Camera** — `ViewportSize`, `FieldOfView`, `Position`, `lookAt(at, lookAt)`
- **DataModel** — `PlaceId`, `GameId`, `JobId`, `GetService`, `HttpGet`, `HttpPost`
- **HttpService** — `JSONEncode`, `JSONDecode`, `GenerateGUID`
- **Humanoid** — **`Health` and `MaxHealth` only**
- **Model** — `PrimaryPart`
- **Workspace** — `CurrentCamera`
- **Instance** — `Name`, `ClassName`, `Parent`, `Address`; `FindFirstChild`, `FindFirstChildOfClass`, `FindFirstChildWhichIsA`, `GetChildren`, `GetDescendants`, `IsA`, `IsDescendantOf`, `GetFullName`, `GetAttribute(s)`, `SetAttribute`, `WaitForChild`
- **Mouse** — `X`, `Y`
- **Players** — `LocalPlayer`, `GetPlayers()`, `PlayerAdded`, `PlayerRemoving`
- **Player** — `Character`, `Team`, `GetMouse()`
- **UserInputService** — `InputBegan`, `InputEnded`
- **RunService** — `RenderStepped`, `Heartbeat`, `Stepped`; all three pass **`deltaTime` only**
- **ValueBase** — `Value`
- **GuiObject** — `AbsoluteSize`, `AbsolutePosition`
- **TextLabel** — `Text`
- **MeshPart** — `TextureId`, `MeshId`

## Things that do NOT exist

| Call | Reality |
|---|---|
| `Instance.new(...)` | Not available. Draw the UI with `Drawing`, or reuse existing instances. |
| `UI.AddTab` / `UI.GetValue` / any `UI.*` | Not in Matcha. Any script built on it dies on load. |
| `remote:FireServer(...)` / `InvokeServer` | Not emulated. RemoteTargeting is dead — target `ProximityPrompt`s with injected input instead. |
| `Humanoid:MoveTo` / `.Jump` / `.WalkSpeed` / `.StateChanged` | Not exposed. `Humanoid` only has health. |
| `Camera:WorldToViewportPoint` | Use `WorldToScreen`. |
| `Workspace:Raycast` | Not documented. |
| `Lighting` | Not exposed as a class. |
| `Player.CharacterAdded` | Not documented — poll `Player.Character` instead. |
| `Ray`, `UDim`, `UDim2` | Not implemented datatypes. |
| `ProximityPromptService` | Not documented. `Act.watch()` tries it via `game:GetService` and falls back to geometry when the call fails. |
| `Tool.Activate` | Not documented. `10_caps` reports whether the method exists on a backpack tool. |
| `ProximityPrompt:InputHoldBegin()` | Class method exists in the engine; whether an emulated client turns it into a trigger is **unverified**, so it is an opt-in path. |

Datatypes that do exist: **Vector3, CFrame, Vector2, Color3**. Nothing else is documented.
There is no `CFrame.lookAt` / `CFrame.LookAt` constructor; `Camera:lookAt` is the only
look-at in the API.

## Drawing

`Drawing.new("Square" | "Line" | "Circle" | "Text" | "Triangle" | "Image")`, `:Remove()`.

Base: `Color`, `Transparency`, `Visible`, `Position`, `ZIndex`.
Square: `Size`, `Filled` (plus `Corner` in the official example, undocumented).
Line: `From`, `To`, `Thickness`. Circle: `Radius`, `NumSides`, `Thickness`.
Text: `Text`, `Outline`, `Center`, `Font`, `FontSize`.

---

## Practical rules for this project

1. Input is injected at the OS level — it goes to **whatever window is focused**. Check
   `isrbxactive()` before pressing keys, or the bot types into the user's desktop.
2. `Players.PlayerAdded` exists but has been unreliable in practice; poll instead.
3. `Instance:GetDescendants()` on `workspace` is far too slow to call per tick — cache it
   and throttle.
4. There is no `Instance:Destroy`, so anything spawned must be reused or hidden.
5. `pcall` around a remote fire always "succeeds" because the method is missing, not the
   call failing. Verify by observing game state, not by the return value.
