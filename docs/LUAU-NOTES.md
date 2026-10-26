# Lua / Luau notes that changed this code

Two interpreters are in play and they are not the same one:

| Where | What runs |
|---|---|
| `dist/RunRestaurant.lua` inside Roblox | Matcha's Lua VM (Lua 5.1-shaped, no Roblox API internals) |
| `src/*.lua` under `run-tests.ps1` | Luau CLI 0.744 at `%USERPROFILE%\tools\luau` |
| `src/*.lua` under `check.ps1` | luaparse with `luaVersion: 5.1` — syntax gate only |

Because the gate is 5.1, **`src/` stays inside a Lua 5.1 subset**: no `continue`, no
`+=`, no `//`, no string interpolation, no generalized iteration (`for i, v in t`), no
`table.clone`/`string.split`/`math.clamp` (the code has its own `Util.split`,
`Util.clamp`, `Util.round`). The Luau-only forms were confirmed to work in the CLI and
are still banned in `src/`, because the CLI is not the runtime.

Everything below was executed, not recalled: `luau-facts.luau` and `luau-sort.luau`
against Luau 0.744 on 2026-10-26. Where Lua 5.1 differs, it says so.

---

## 1. Multiple returns

```lua
string.gsub("aXbXc", "X", "-")            --> "a-b-c", 2
"[" .. string.gsub("aXb", "X", "-") .. "]" --> "[a-b]"
```

`gsub` returns `(string, count)`. A call is trimmed to one value everywhere except the
last position of an argument list or a `return`. The bug is always the same shape:

```lua
local body = string.gsub(src, "x", "y")       -- fine
RR.log(string.gsub(src, "x", "y"))            -- logs the count too
```

Rule: bind `gsub` to a local, or parenthesise it `(string.gsub(...))`, whenever the
result is not alone on the right-hand side.

`select("#", ...)` returned `3` for `select("#", 1, nil, 3)`. `{...}` truncates at the
first `nil`, so count varargs before packing.

## 2. `#` on a table with holes is not a length

`#{1, 2, nil, 4}` returned `4` in this build. That is a legal answer, not a promise —
the border is implementation-defined, and Lua 5.1 may return `1`. Any code that trims
or indexes by `#` assumes a dense array.

That is why `World.state` keeps `itemCount`, `promptCount`, `clickCount` next to the
arrays: the scan fills arrays by index and can leave gaps when an instance is filtered
out, and `#` would then lie. Use the counter, or `table.remove`/`table.insert` so the
array stays dense.

## 3. Sorting needs a consistent comparator

```lua
table.sort(t, function(a, b) return a > b end)        -- descending, correct
table.sort(t, function(a, b) return a >= b end)       -- returns true for equals
```

An inconsistent comparator (`return true`, `return math.random() < 0.5`) raised
`invalid order function for sorting` at n=50 and n=200. `>=` did *not* raise at
n=500 — it just sorts wrongly when duplicates exist, which is worse because it is
silent. Comparators that tie-break must be total:

```lua
table.sort(hits, function(a, b)
  if a.score ~= b.score then return a.score > b.score end
  return a.name < b.name
end)
```

## 4. Numbers

| Expression | Result | Note |
|---|---|---|
| `-1 % 3` | `2` | sign follows the divisor, not the dividend |
| `-7 // 3` | `-3` | floor division |
| `math.fmod(-1, 3)` | `-1` | C-style remainder |
| `1 // 0` | `inf` | no error, no NaN |
| `math.floor(-0.5)` | `-1` | |
| `t[1.0]` with `t[1] = "a"` | `"a"` | float and integer keys are the same key |
| `0/0 == 0/0` | `false` | NaN never equals itself |
| `x ~= x` | `true` for NaN | the only reliable NaN test |
| `string.format("%d", 3.5)` | `3` | truncates, no error in this build |
| `tonumber("0x45")` | `69` in Luau, **`nil` in Lua 5.1** | never parse hex from input |

Angle wrapping in camera code must use `%`, never `math.fmod` — the signs differ and
the camera turns the long way round. `Input.clickScreen` uses the NaN trick
(`x ~= x`) to reject a projection that produced NaN instead of clicking at (0/0).

## 5. Patterns are not regex

```lua
string.find("a-b", "-")      --> 2   (leading '-' is literal)
string.find("axb", "a-b")    --> 3   ('-' in the middle is a lazy quantifier!)
string.find("a.b", "%.")     --> 2
```

A bare `-` is magic when it follows something. `World.find` receives user typing like
`"!broken"`, and its exclusion test uses `string.find(text, needle, 1, true)` — the
fourth argument is the plain-text flag. Every search for a literal needle in this
codebase passes `true`; only the deliberate pattern work in `DumpScripts.lua` uses
patterns.

## 6. Errors are values, and Matcha does not raise

`pcall` returns `false, err`, and `err` is only a string if you passed a string:

```lua
pcall(function() error({ code = 7 }) end)  --> false, table
tostring(err)                              --> "table: 0x7ffe958bb0"
```

Matcha's own documentation says `error()` prints and does not raise, so an `error`-based
assertion inside this toolkit silently continues. Neither the modules nor the tests use
`error` for control flow: every function returns `false, reason`, and `reason` is always
a string built by the caller. `RR.err` renders unknown error objects through `tostring`
so a table error cannot crash the log path.

`string.format("%s", nil)` raised `string expected, got nil` — every value interpolated
into a log line is wrapped in `tostring` first, including `nil`s.

## 7. One chunk, 200 locals

`dist/RunRestaurant.lua` is concatenated into a single script, and Matcha loads it as
one chunk. All 11 modules' top-level `local`s share one function's register budget
(200 in Lua 5.1 and Luau). It is currently **44/200** and `tools/lint.js` now counts it
on every run, failing at 190 and warning at 160 — this failure otherwise appears as a
nonsense syntax error at load time.

The counter also means `local RR = _G.RR` at the top of every module is not just style:
a global lookup is a hash read, a local is a register. In the `RenderStepped` loop that
difference is the whole point.

## 8. Strings and tables in hot paths

- `s = s .. x` in a loop is O(n²). Every report builder in this repo appends to a
  table and calls `table.concat` once (`RR.dumpReport`, `Caps.format`).
- `table.concat` accepts numbers directly (`1,2,3`), so no `tostring` pass is needed
  for numeric status output.
- `pairs` order was `delta,beta,alpha,gamma` for a four-key table and is not stable
  between runs. Anything that must be deterministic (the findings file, the report,
  the tests) iterates an ordered array instead — `DumpScripts.lua` keeps a parallel
  `foundOrder` list for exactly this reason.
- `("abc"):sub(-1)` returns `"c"`; `sub(0)` behaves like `sub(1)` rather than returning
  an empty string. `Util.cleanName` relies on the negative-index form to strip GUID
  suffixes.

## 9. Coroutines are not workers

`coroutine.resume` on a function that errors returns `false, err` and leaves the
coroutine dead — the error does not propagate into the caller. There is no scheduler:
`task.delay` and `task.defer` are documented no-ops in this build, so anything
deferred must be a `wait(t)` inside `task.spawn`, or a deadline checked by the worker
loop in `60_main.lua`.

---

## Checklist for new code in `src/`

1. Does it parse as Lua 5.1? (`check.ps1` will tell you.)
2. Does it use a multiple-return call in the middle of an expression? Bind it first.
3. Does it index or size an array by `#` where the array can have gaps? Use the
   explicit counter.
4. Does every interpolated value pass through `tostring`?
5. Does it search for a literal needle with `string.find(..., true)`?
6. Does it use `%` (not `math.fmod`) for angles?
7. Does a new top-level `local` still leave the chunk under 200?
8. Is the behaviour covered by a `check(...)` in `tests/spec.luau` that runs in Luau?
