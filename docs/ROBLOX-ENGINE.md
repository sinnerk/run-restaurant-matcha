# Roblox engine notes for an external client

Matcha is **not** in the engine. It is a Lua VM outside the Roblox process that can
*read* the DataModel and *send* input, but cannot create instances, cannot fire a
`RemoteEvent`, cannot call `Humanoid:MoveTo`, and cannot use
`Camera:WorldToViewportPoint`. Everything this toolkit does is built out of three
things an ordinary player also has: a camera, a keyboard, and a mouse.

That is not a limitation to work around — it is the mechanism. Input injected at the
OS level is indistinguishable from the player's own input, so the game's **own client
scripts** receive it and perform the interaction with full authority: they fire their
remotes, they update their UI, they tell the server. A prompt press goes
prompt UI → client script → remote → server, exactly as a human press would.

Sources: `create.roblox.com/docs/reference/engine/classes/{ProximityPrompt,
ProximityPromptService, ClickDetector, Tool, Camera, Humanoid, BasePart}`,
`/docs/ui/proximity-prompts`, `/docs/workspace/streaming`, plus the observed
instance dump of place 121042 (`diagnostics/`).

---

## 1. Interaction surfaces, ranked

| Surface | Reachable externally | How | Confidence |
|---|---|---|---|
| `ProximityPrompt` | yes | walk in range, aim, send its key for its hold time | documented |
| `ClickDetector` | yes | aim, click the part's pixels | documented |
| GUI button (`TextButton`/`ImageButton`) | yes | click `AbsolutePosition + AbsoluteSize/2` | `AbsolutePosition` is documented; click path is documented |
| `Tool` in hotbar | yes | press its number key, then click | documented |
| `ProximityPrompt:InputHoldBegin()` | maybe | direct method call | **unverified** — opt-in only |
| `RemoteEvent:FireServer` | no | — | not emulated |
| server-only state (`ServerStorage`, `DataStore`) | no | — | never replicated |
| `Humanoid:MoveTo`, `WalkSpeed` writes | no / fragile | walks with `W` instead | position write is a fallback mode |

Anything not in that table needs a different approach, and usually the honest answer is
"reach it through the GUI the player would use".

---

## 2. ProximityPrompt

A prompt is an `Instance` parented to a `BasePart`, `Attachment`, or `Model` (with a
`PrimaryPart`). It is a **client-side UI object**: the server creates it, the client
shows it, the client's input triggers it, and `Triggered` fires on both sides.

### Properties that decide whether a press lands

| Property | Default | Why it matters here |
|---|---|---|
| `MaxActivationDistance` | 10 studs | the server's prompt UI hides it beyond this; `Act.prompt` stops at 75% of it |
| `RequiresLineOfSight` | `true` | the client raycasts from the camera; an occluder hides the prompt even at 2 studs. This is why `Act.prompt` aims before pressing |
| `HoldDuration` | 0 | seconds the key must stay down. `0` fires on key-down; `1.5` needs a real 1.5 s hold, and releasing early resets progress |
| `KeyboardKeyCode` | `E` | an `Enum.KeyCode`, **not** a VK code — see `docs/MATCHA-API.md` and `src/12_keymap.lua` |
| `ClickablePrompt` | `false` | when true the prompt's own UI is a button that can be mouse-clicked as an alternative to the key |
| `Exclusivity` | `OnePerButton` | which prompt owns the key when several are in range |
| `Enabled` | `true` | a disabled prompt is invisible and inert |
| `ActionText` / `ObjectText` | `""` | the two halves of the on-screen label; `ObjectText` is usually the object's name |
| `UIOffset` | `(0,0)` | where the label sits relative to the anchor, in pixels |

### Exclusivity — the detail that silently eats presses

- `OnePerButton` (0): one prompt **per key**. Two `E` prompts in range → only the one
  nearest the camera centre is shown and triggerable.
- `OneGlobally` (1): one prompt **in total**, whatever its key.
- `AlwaysShow` (2): this prompt is always visible; pressing its key triggers **every
  visible prompt with that keycode**, not just this one.

So "walk up and press E" is only correct when the target is the prompt the client has
actually selected. `Act.competitors` answers "who would win right now" from camera
geometry, and when `ProximityPromptService` is observable, `Act.isActive` answers it
authoritatively. `Act.prompt(..., { strict = true })` refuses to press into a losing
contest instead of firing the wrong thing.

### Lifecycle events

Client-side, `ProximityPromptService` emits:

- `PromptShown(prompt)` — this prompt just became the visible one
- `PromptHidden(prompt)` — it stopped being visible
- `PromptTriggered(prompt, player)` — the press **worked**

If Matcha surfaces those connections (the capability probe reports this on first run),
activation stops being a guess: `Act.watch()` records the active prompt and the last
triggered prompt, and `Act.prompt` returns `true, "triggered"` only when the engine
said so. If they are not exposed, the code falls back to camera-centre geometry.

### Hold semantics

The default UI sends `InputHoldBegin()` on key-down, runs a progress ring for
`HoldDuration`, then `InputHoldEnd()`. Matcha can call those methods directly, but
whether an externally-emulated client turns that signal into a trigger is
build-dependent — the methods are on the class, not on the documented emulated surface.
`Act.promptHold` is therefore opt-in (`method = "hold"`) and always paired with a
verification step. The default is the real key path.

---

## 3. ClickDetector

`ClickDetector.MaxActivationDistance` defaults to **32 studs**. `MouseClick` fires
server-side with the player who clicked, but only when the click ray actually hits the
part — the engine raycasts from the cursor into the 3D scene, so:

- the part must be unoccluded at that pixel,
- `CanQuery = false` parts are ignored by the ray,
- a GUI element under the cursor swallows the click,
- `ClickDetector.Enabled = false` makes it inert while the part stays visible.

`ClickDetector` also has `CursorIcon` and `MouseHoverEnter`/`MouseHoverLeave`, which is
useful as a free hover test: move the cursor over the part, see whether the cursor
changed, then click. `Act.clickDetector` walks into range, aims, and clicks the part's
centre; `Act.clickPart` is the primitive underneath.

Place 121042 has **18 ClickDetectors** (gnomes, pet pickups) and **zero** prompts on
cooking stations, so detectors are load-bearing, not a corner case.

---

## 4. Tools and the hotbar

A `Tool` lives in `Player.Backpack` and moves into `Player.Character` when equipped.
The default hotbar binds the first nine tools to keys `1`–`9` (and `0` for slot ten);
clicking a hotbar slot does the same. `Tool.Activated` fires on a click while equipped,
and `Tool:Activate()` exists server-side.

Consequences:

- Equipping is `Input.tap(VK.DIGIT1)` — a real key press, not an instance move.
- The interaction that matters is usually `Activated`, so "equip, then click" is the
  general recipe, and `10_caps` reports `canActivate` by checking that the method
  exists on a backpack tool.
- `Tool.RequiresHandle` defaults to `true`; a tool without a `Handle` still equips but
  may not weld to the hand.
- Tools are invisible to a workspace scan while in the backpack, which is why the
  original dump found none. `Caps.probe` now reads `Backpack` and the character
  directly and records the names — those names are the game's own vocabulary for its
  tools and are worth as much as the prompt list.

---

## 5. GUI — the surface a workspace scan cannot see

`Player.PlayerGui` is populated by client scripts. Shop menus, cooking menus, upgrade
panels and most "systems with no prompt and no part" are `ScreenGui` → `Frame` →
`TextButton` trees in there.

The two properties that make this clickable from outside:

- `GuiObject.AbsolutePosition` — the button's top-left corner **in screen pixels**
- `GuiObject.AbsoluteSize` — its size **in screen pixels**

Both are computed by the engine from the `UDim2` scale/offset chain, so no layout maths
is needed. Center is `AbsolutePosition + AbsoluteSize/2`, and Matcha documents
`mousemoveabs` as using the same pixel space as `WorldToScreen` and
`Camera.ViewportSize` — which is that same space.

Visibility has to be checked up the whole ancestor chain: a button's own `Visible` can
be `true` while its parent `Frame` is hidden or its `ScreenGui.Enabled` is `false`.
`Util.guiShown` walks up to `PlayerGui` and stops at the first `Visible == false` or
`Enabled == false`.

Occlusion is not modelled: if two buttons overlap, the top one (by `ZIndex` /
`DisplayOrder`) gets the click. `Act.clickGui` clicks the best *matching* button, so a
modal covering the screen would swallow it — verify after clicking rather than assuming.

This is the highest-value unexplored surface in this game: the browser scan found
`Shop`, `StationsMerchant`, `BaitMerchant`, `PetMerchant`, `BlackMarket`,
`GlobalMarket`, `LimitedItemStands` as systems with no prompt. If they are GUI-driven,
`World.findGui("Buy")` + `Act.clickGuiNamed("Buy")` reaches them.

---

## 6. Camera and steering

- `Camera.CameraType` defaults to `Custom`, where the right mouse button rotates the
  camera around `CameraSubject` (the humanoid). Mouse drag does nothing when it is
  `Scriptable`, so `Caps.probe` records the type and `Move.lookAt` reports failure
  instead of spinning.
- First person (`Camera.CameraSubject` + `Player.CameraMode = LockFirstPerson`) makes
  the character face the camera; third person does not. Aiming the camera is still what
  selects the active prompt either way.
- `WorldToScreen(v3)` is the only projection available. It returns `(Vector2, bool)`;
  the bool is "in front of the camera", and a false must be treated as "not visible",
  not as `(0,0)`.
- Mouse deltas are applied at the OS level, so the drag has to be **held** across a walk
  (`Move.aimBegin` / `Move.aimEnd`). Press/release per frame makes the camera stutter
  and the character wander.

---

## 7. Character movement

The client's `ControlModule` writes `Humanoid.MoveDirection` every frame from the keys
it sees. That is why:

- `Humanoid:MoveTo` from outside is pointless — nothing calls it, and the control
  module overwrites the result,
- `WalkSpeed` writes are re-read or reverted by the server in most games,
- writing `HumanoidRootPart.CFrame` does move the local character (the client owns its
  own character), and it is the fastest way to travel, but a server-side check can snap
  it back and no game tolerates it forever.

`Move.goto` therefore has three modes and picks with the capability probe:
`position` (fast, works until it doesn't), `velocity`, and `walk` (hold `W`, steer the
camera, verify distance each tick). `Move.goto` always **verifies arrival** rather than
trusting the write — a silent revert is otherwise indistinguishable from success.

Stuck detection is distance-based, not time-based: under 0.35 studs of progress in
0.9 s triggers `Move.unstick` (strafe + jump), because a character pressed against a
wall looks identical to one that is moving in place.

---

## 8. What the client can and cannot see

Replicated to the client: `Workspace`, `ReplicatedStorage`, `Players`, `PlayerGui`,
`Lighting`, `SoundService`, `StarterGui` (as a template), `TextChatService`.

Never replicated: `ServerStorage`, `ServerScriptService`, and anything parented under
them. If a system's logic lives there, the client only ever sees its **effects** — a
prompt appearing, a GUI opening, a value changing. That is a hard ceiling, and the
mitigation is behavioural recon (`tools/Recon.lua`) rather than more tree scanning.

`StreamingEnabled` makes `Workspace` a **partial** view: parts outside the streamed
radius are absent from the client entirely, and models arrive as the player moves.
Defaults are `StreamingMinRadius = 64` and `StreamingTargetRadius = 1024` studs. This
is why the original dump found only 4 of the place's restaurants — the other geometry
had never been replicated. Practical rules:

- a one-shot scan is wrong; `World.scan` is sliced across frames and `World.step`
  keeps merging,
- results are keyed by full name, so a second pass updates rather than duplicates,
- an absent object means "not streamed yet", not "does not exist".

`Instance:GetDescendants()` on `Workspace` is far too slow to call per frame (Matcha's
own docs say so); the scan walks a bounded slice per tick and records `buildMs` so the
cost is visible in the report.

---

## 9. Timing

- `wait(t)` / `task.wait(t)` block for at least `t`, quantised to the frame
  (~1/60 s). Both return nothing — never use the return value.
- `task.delay` and `task.defer` are **no-ops** in this build. Deferred work is
  `task.spawn(function() wait(t) ... end)`.
- `task.spawn(f)` runs synchronously until `f` yields, and does not forward arguments;
  wrap in a closure.
- `tick()` is a monotonic clock, not a Unix timestamp. Use it for deadlines and
  differences only. Wall-clock time for reports is `os.date`.
- `RenderStepped` is for drawing and snapshot work that must not yield; everything that
  can block for seconds runs in the worker thread (`60_main.lua`).

A prompt press therefore costs `HoldDuration + ~0.09 s`, and `Act.prompt` waits another
`~0.08 s` before verifying. Pressing faster than that produces presses the client has
not finished processing, which look exactly like a wrong key.

---

## 10. Verification protocol

Every interaction in `Act` accepts a `verify` callback and polls it for `verifyMs`
(default 900 ms). The rule that came out of this project:

> A press that returns without confirmation is a **failure**, not a success.

The cheapest verifications, in order of preference:

1. `ProximityPromptService.PromptTriggered` observed (`Act.watch`)
2. a world change: the prompt disappears, a part's `Transparency`/`Position` changes
3. a GUI change: a label's `Text` changes, a frame becomes visible
4. a backpack change: a new `Tool` appears
5. a humanoid/stat change: `Humanoid.Health`, a `NumberValue` in the character

If none of those is available, the interaction is not yet understood well enough to
automate — which is the correct time to run `tools/DumpScripts.lua` and read what the
client script actually does.
