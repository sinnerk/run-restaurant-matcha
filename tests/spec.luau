--[[ ==================================================================
     tests/spec.luau : assertions over the real src modules

     Run with run-tests.ps1. Each check executes code that ships in
     dist/RunRestaurant.lua, so a pass here means the logic is correct
     in a real Luau VM - not just that it parses.
     ================================================================== ]]

local RR = _G.RR
local KeyMap = RR.KeyMap
local Util = RR.Util
local World = RR.World
local Act = RR.Act
local Input = RR.Input

-- ---------------------------------------------------------------------
-- runner
-- ---------------------------------------------------------------------
local pass, fail = 0, 0
local failures = {}
local group = "?"

local function describe(name)
  group = name
  print("")
  print("-- " .. name)
end

local function check(label, fn)
  local ok, err = pcall(fn)
  if ok then
    pass = pass + 1
  else
    fail = fail + 1
    failures[#failures + 1] = group .. " / " .. label .. ": " .. tostring(err)
    print("   FAIL " .. label .. "  " .. tostring(err))
  end
end

local function eq(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s (expected %s, got %s)",
      label, tostring(expected), tostring(actual)), 2)
  end
end

local function near(actual, expected, eps, label)
  if type(actual) ~= "number" or math.abs(actual - expected) > (eps or 0.0001) then
    error(string.format("%s (expected ~%s, got %s)",
      label, tostring(expected), tostring(actual)), 2)
  end
end

-- ---------------------------------------------------------------------
-- 1. the bug that started this
-- ---------------------------------------------------------------------
describe("KeyMap - Roblox KeyCode is not a VK code")

check("E as an EnumItem resolves to VK_E", function()
  -- This is exactly what the bridge hands back for a default prompt.
  eq(KeyMap.resolve({ Name = "E", Value = 101 }), 0x45, "resolve E")
end)

check("E as a bare KeyCode number resolves to VK_E", function()
  eq(KeyMap.codeToVK(101), 0x45, "codeToVK(101)")
end)

check("regression: 101 must never be passed through as 101", function()
  -- 101 is VK_NUMPAD5. This is the bug v5.0.0 shipped with.
  if KeyMap.codeToVK(101) == 101 then
    error("codeToVK(101) returned 101 - numpad-5 regression")
  end
end)

check("every letter maps onto its VK", function()
  for i = 0, 25 do
    eq(KeyMap.codeToVK(97 + i), 0x41 + i, "letter " .. string.char(97 + i))
  end
end)

check("already-VK values pass through", function()
  eq(KeyMap.resolve(69), 69, "69 is VK_E")
  eq(KeyMap.codeToVK(0x57), 0x57, "0x57")
end)

check("digits, space, enter, escape, tab", function()
  eq(KeyMap.codeToVK(48), 0x30, "zero")
  eq(KeyMap.codeToVK(57), 0x39, "nine")
  eq(KeyMap.codeToVK(32), 0x20, "space")
  eq(KeyMap.codeToVK(13), 0x0D, "return")
  eq(KeyMap.codeToVK(27), 0x1B, "escape")
  eq(KeyMap.codeToVK(9), 0x09, "tab")
  eq(KeyMap.codeToVK(8), 0x08, "backspace")
end)

check("arrows are not ASCII", function()
  eq(KeyMap.codeToVK(273), 0x26, "up")
  eq(KeyMap.codeToVK(274), 0x28, "down")
  eq(KeyMap.codeToVK(275), 0x27, "right")
  eq(KeyMap.codeToVK(276), 0x25, "left")
end)

check("F1..F12 are a clean run", function()
  for i = 0, 11 do
    eq(KeyMap.codeToVK(282 + i), 0x70 + i, "F" .. (i + 1))
  end
end)

check("keypad does not collide with digits", function()
  eq(KeyMap.codeToVK(256), 0x60, "keypad zero")
  eq(KeyMap.codeToVK(265), 0x69, "keypad nine")
end)

check("names resolve", function()
  eq(KeyMap.nameToVK("E"), 0x45, "E")
  eq(KeyMap.nameToVK("e"), 0x45, "e")
  eq(KeyMap.nameToVK("LeftShift"), 0xA0, "LeftShift")
  eq(KeyMap.nameToVK("F5"), 0x74, "F5")
  eq(KeyMap.nameToVK("space"), 0x20, "space")
  eq(KeyMap.nameToVK("0"), 0x30, "0")
end)

check("tostring form resolves", function()
  eq(KeyMap.resolve("Enum.KeyCode.E"), 0x45, "Enum.KeyCode.E")
  eq(KeyMap.resolve("KeyCode.Return"), 0x0D, "KeyCode.Return")
end)

check("unknown values fall back instead of guessing", function()
  eq(KeyMap.resolve(nil, 0x45), 0x45, "nil")
  eq(KeyMap.resolve(0, 0x45), 0x45, "KeyCode.None")
  eq(KeyMap.resolve(9999, 0x45), 0x45, "gamepad button")
  eq(KeyMap.resolve({}, 0x45), 0x45, "empty table")
end)

check("describe produces a readable pair", function()
  local s = KeyMap.describe({ Name = "E", Value = 101 })
  if not string.find(s, "0x45", 1, true) then
    error("describe missing 0x45: " .. s)
  end
end)

-- ---------------------------------------------------------------------
-- 2. shared table
-- ---------------------------------------------------------------------
describe("Input uses the same VK table")

check("Input.VK is KeyMap.VK", function()
  eq(Input.VK, KeyMap.VK, "identity")
  eq(Input.VK.E, 0x45, "E")
  eq(Input.VK.W, 0x57, "W")
end)

-- ---------------------------------------------------------------------
-- 3. Util
-- ---------------------------------------------------------------------
describe("Util")

check("split", function()
  local parts = Util.split("a|b|c", "|")
  eq(#parts, 3, "count")
  eq(parts[1], "a", "1")
  eq(parts[3], "c", "3")
end)

check("cleanName strips the place's guid suffix", function()
  eq(Util.cleanName("Stove_1a2b3c4d-1111-2222-3333-444455556666"), "Stove", "guid suffix")
  eq(Util.cleanName("Plain"), "Plain", "untouched")
end)

check("clamp", function()
  eq(Util.clamp(5, 1, 10), 5, "inside")
  eq(Util.clamp(-1, 0, 10), 0, "low")
  eq(Util.clamp(99, 0, 10), 10, "high")
end)

check("round", function()
  eq(Util.round(1.234, 2), 1.23, "two places")
  eq(Util.round(1.5), 2, "integer")
end)

check("viewport comes from the camera", function()
  local vp = Util.viewport()
  eq(vp.X, 1000, "width")
  eq(vp.Y, 800, "height")
end)

check("project returns nil behind the camera", function()
  eq(Util.project(Vector3.new(-900, 0, 0)), nil, "off screen")
  eq(Util.project(nil), nil, "nil input")
end)

check("focusScore is zero at the centre", function()
  near(Util.focusScore(Vector3.new(0, 0, 0)), 0, 0.001, "centre")
  near(Util.focusScore(Vector3.new(500, 0, 0)), 500, 0.001, "offset")
  eq(Util.focusScore(Vector3.new(-900, 0, 0)), math.huge, "off screen")
end)

-- ---------------------------------------------------------------------
-- 4. world matching
-- ---------------------------------------------------------------------
describe("World pattern matching")

check("parsePattern separates include and exclude", function()
  local inc, exc = World.parsePattern("Stove|Oven|!Broken")
  eq(#inc, 2, "includes")
  eq(#exc, 1, "excludes")
  eq(inc[1], "stove", "inc 1")
  eq(exc[1], "broken", "exc 1")
end)

check("score ranks exact > prefix > word > substring", function()
  eq(World.score("stove", { "stove" }, {}), 100, "exact")
  eq(World.score("stovetop", { "stove" }, {}), 70, "prefix")
  eq(World.score("old stove", { "stove" }, {}), 50, "word")
  eq(World.score("mystove", { "stove" }, {}), 25, "substring")
  eq(World.score("fridge", { "stove" }, {}), nil, "miss")
end)

check("score honours exclusion", function()
  eq(World.score("broken stove", { "stove" }, { "broken" }), nil, "excluded")
end)

check("find filters by class and sorts by score", function()
  local s = World.state
  s.items = {
    { inst = {}, cls = "ProximityPrompt", name = "Stove", clean = "Stove", lower = "stove" },
    { inst = {}, cls = "Part", name = "StoveTop", clean = "StoveTop", lower = "stovetop" },
    { inst = {}, cls = "ProximityPrompt", name = "Broken Stove", clean = "Broken Stove", lower = "broken stove" },
  }
  s.itemCount = 3

  local all = World.find("Stove")
  eq(#all, 3, "all classes")
  eq(all[1].name, "Stove", "best first")

  local parts = World.find("Stove", "Part")
  eq(#parts, 1, "class filter")

  local clean = World.find("Stove|!Broken")
  eq(#clean, 2, "exclusion")

  s.items = {}
  s.itemCount = 0
end)

-- ---------------------------------------------------------------------
-- 5. reading a prompt
-- ---------------------------------------------------------------------
describe("Act.flags")

check("defaults match the engine docs", function()
  local f = Act.flags(makeInstance("ProximityPrompt", "ProximityPrompt", {}))
  eq(f.maxDist, 10, "MaxActivationDistance default")
  eq(f.hold, 0, "HoldDuration default")
  eq(f.los, true, "RequiresLineOfSight defaults true")
  eq(f.clickable, false, "ClickablePrompt defaults false")
  eq(f.exclName, "OnePerButton", "Exclusivity defaults OnePerButton")
  eq(f.vk, 0x45, "unnamed key falls back to E")
end)

check("reads a populated prompt", function()
  local f = Act.flags(makeInstance("ProximityPrompt", "ProximityPrompt", {
    KeyboardKeyCode = { Name = "F", Value = 102 },
    HoldDuration = 1.5,
    MaxActivationDistance = 12,
    RequiresLineOfSight = false,
    ClickablePrompt = true,
    Exclusivity = { Name = "OneGlobally" },
    ActionText = "Cook",
    ObjectText = "Stove",
  }))
  eq(f.vk, 0x46, "F")
  eq(f.hold, 1.5, "hold")
  eq(f.maxDist, 12, "range")
  eq(f.los, false, "los")
  eq(f.clickable, true, "clickable")
  eq(f.exclName, "OneGlobally", "exclusivity")
  eq(f.actionText, "Cook", "action")
end)

check("negative or zero values do not poison the arithmetic", function()
  local f = Act.flags(makeInstance("ProximityPrompt", "ProximityPrompt", {
    HoldDuration = -4,
    MaxActivationDistance = 0,
  }))
  eq(f.hold, 0, "hold clamped")
  eq(f.maxDist, 10, "range clamped")
end)

-- ---------------------------------------------------------------------
-- 6. live prompts carry what Act needs
-- ---------------------------------------------------------------------
describe("World.livePrompts")

check("a prompt exposes vk, hold, los and exclusivity", function()
  local anchor = makeInstance("Part", "Stove", { Position = Vector3.new(1, 2, 3) })
  local prompt = makeInstance("ProximityPrompt", "ProximityPrompt", {
    Enabled = true,
    KeyboardKeyCode = { Name = "E", Value = 101 },
    HoldDuration = 0.5,
    MaxActivationDistance = 10,
    RequiresLineOfSight = true,
    ClickablePrompt = false,
    Exclusivity = { Name = "OnePerButton" },
    ActionText = "Cook",
    ObjectText = "Stove",
  })

  local s = World.state
  s.prompts = { { inst = prompt, anchor = anchor } }
  s.promptCount = 1

  local list = World.livePrompts()
  eq(#list, 1, "count")
  eq(list[1].aname, "Stove", "anchor name")
  eq(list[1].vk, 0x45, "vk")
  eq(list[1].hold, 0.5, "hold")
  eq(list[1].los, true, "los")
  eq(list[1].exclName, "OnePerButton", "exclusivity")
  eq(list[1].action, "Cook", "action text")

  s.prompts = {}
  s.promptCount = 0
end)

-- ---------------------------------------------------------------------
-- 7. exclusivity - who actually gets the key press
-- ---------------------------------------------------------------------
describe("Act.competitors")

local function rivalSetup(rivalKey, exclName)
  local targetInst = { tag = "target" }
  local rivalInst = { tag = "rival" }

  local p = { inst = targetInst, anchor = targetInst }
  local anchorPos = Vector3.new(300, 0, 0)   -- 300 px right of centre

  RR.Util.charPos = function() return Vector3.new(0, 0, 0) end
  RR.World.livePrompts = function()
    return {
      {
        inst = rivalInst,
        pos = Vector3.new(10, 0, 0),         -- 10 px right of centre: wins
        vk = rivalKey,
        maxDist = 12,
        aname = "Rival",
      },
    }
  end

  local f = { vk = 0x45, exclName = exclName }
  return Act.competitors(p, f, anchorPos)
end

check("OnePerButton: a same-key rival in front of ours blocks the press", function()
  local r = rivalSetup(0x45, "OnePerButton")
  eq(r.count, 1, "blocked")
  eq(r.best.aname, "Rival", "names the winner")
end)

check("OnePerButton: a different-key rival does not block", function()
  local r = rivalSetup(0x46, "OnePerButton")
  eq(r.count, 0, "clear")
end)

check("OneGlobally: any rival can take the slot", function()
  local r = rivalSetup(0x46, "OneGlobally")
  eq(r.count, 1, "blocked")
end)

check("AlwaysShow: nobody takes anything away", function()
  local r = rivalSetup(0x45, "AlwaysShow")
  eq(r.count, 0, "clear")
end)

check("a centred target beats an off-centre rival", function()
  local p = { inst = {}, anchor = {} }
  RR.Util.charPos = function() return Vector3.new(0, 0, 0) end
  RR.World.livePrompts = function()
    return {
      { inst = {}, pos = Vector3.new(200, 0, 0), vk = 0x45, maxDist = 400, aname = "Rival" },
    }
  end
  local r = Act.competitors(p, { vk = 0x45, exclName = "OnePerButton" }, Vector3.new(0, 0, 0))
  eq(r.count, 0, "clear")
end)

-- ---------------------------------------------------------------------
-- 8. GUI buttons - the surface no workspace scan can see
-- ---------------------------------------------------------------------
describe("GUI clicking")

check("guiShown walks the ancestor chain", function()
  local lp = Util.localPlayer()
  local pg = lp:FindFirstChildOfClass("PlayerGui")
  local list = pg:GetDescendants()
  local button, hidden = nil, nil
  for i = 1, #list do
    if list[i].Name == "BuyButton" then button = list[i] end
    if list[i].Name == "SecretButton" then hidden = list[i] end
  end
  eq(Util.guiShown(button), true, "visible button")
  eq(Util.guiShown(hidden), false, "button under a hidden frame")
  eq(Util.guiShown(nil), false, "nil")
end)

check("guiCenter is the middle of AbsolutePosition/AbsoluteSize", function()
  local lp = Util.localPlayer()
  local pg = lp:FindFirstChildOfClass("PlayerGui")
  local button = nil
  local list = pg:GetDescendants()
  for i = 1, #list do
    if list[i].Name == "BuyButton" then button = list[i] end
  end
  local c = Util.guiCenter(button)
  eq(c.X, 140, "x")
  eq(c.Y, 220, "y")
end)

check("guiCenter refuses zero-size objects", function()
  eq(Util.guiCenter({ AbsolutePosition = Vector2.new(0, 0), AbsoluteSize = Vector2.new(0, 0) }), nil, "empty")
end)

check("guiButtons returns only what is really on screen", function()
  local list = World.guiButtons()
  eq(#list, 1, "one visible button")
  eq(list[1].name, "BuyButton", "name")
  eq(list[1].text, "Buy 10", "label")
  eq(list[1].pos.X, 140, "x")
end)

check("findGui matches the label, not just the instance name", function()
  eq(#World.findGui("Buy 10"), 1, "label match")
  eq(#World.findGui("BuyButton"), 1, "name match")
  eq(#World.findGui("Secret"), 0, "hidden buttons are not offered")
end)

check("clickGui moves the cursor onto the button and clicks", function()
  __stub.clicks = 0
  __stub.moves = {}
  local ok, how = Act.clickGuiNamed("Buy 10")
  eq(ok, true, "clicked")
  eq(how, "gui", "method")
  eq(__stub.clicks, 1, "one click")
  eq(#__stub.moves, 1, "one move")
  eq(__stub.moves[1].x, 140, "cursor x")
  eq(__stub.moves[1].y, 220, "cursor y")
end)

check("clickScreen refuses points outside the viewport", function()
  eq(Input.clickScreen(2000, 2000), false, "off screen")
  eq(Input.clickScreen(0 / 0, 10), false, "NaN")
end)

check("clicking a hidden button is refused", function()
  local lp = Util.localPlayer()
  local pg = lp:FindFirstChildOfClass("PlayerGui")
  local list = pg:GetDescendants()
  local hidden = nil
  for i = 1, #list do
    if list[i].Name == "SecretButton" then hidden = list[i] end
  end
  local ok, why = Act.clickGui({ inst = hidden })
  eq(ok, false, "refused")
  if not string.find(tostring(why), "visible", 1, true) then
    error("wrong reason: " .. tostring(why))
  end
end)

-- ---------------------------------------------------------------------
-- 9. Act.prompt when the prompt service is observable
-- ---------------------------------------------------------------------
describe("Act.prompt - observed activation")

local function fakePrompt()
  local anchor = makeInstance("Part", "Stove", { Position = Vector3.new(0, 0, 0) })
  local prompt = makeInstance("ProximityPrompt", "ProximityPrompt", {
    Enabled = true,
    KeyboardKeyCode = { Name = "E", Value = 101 },
    HoldDuration = 0,
    MaxActivationDistance = 10,
  })
  return { inst = prompt, anchor = anchor, pos = Vector3.new(0, 0, 0) }
end

-- run one Act.prompt with a controlled service and press
local function runWatched(p, onPress, preset)
  local savedWatching, savedActive = Act.watching, Act.active
  local savedTriggered, savedAt = Act.lastTriggered, Act.triggeredAt
  local savedHold = Input.hold
  local savedLook = RR.Move.lookAt

  Act.watching = true
  Act.active = p.inst
  Act.lastTriggered = nil
  Act.triggeredAt = nil
  if preset then preset() end
  RR.Move.lookAt = function() return true end
  Input.hold = function()
    if onPress then onPress() end
    return true
  end

  local ok, how = Act.prompt(p, {})

  Act.watching = savedWatching
  Act.active = savedActive
  Act.lastTriggered = savedTriggered
  Act.triggeredAt = savedAt
  Input.hold = savedHold
  RR.Move.lookAt = savedLook

  return ok, how
end

check("a trigger caused by the press is success", function()
  local p = fakePrompt()
  local ok, how = runWatched(p, function()
    Act.lastTriggered = p.inst
    Act.triggeredAt = tick()
  end)
  eq(ok, true, "confirmed")
  eq(how, "triggered", "method")
end)

check("a press with no trigger is a failure", function()
  local p = fakePrompt()
  local ok, why = runWatched(p, nil)
  eq(ok, false, "unconfirmed")
  if not string.find(tostring(why), "did not trigger", 1, true) then
    error("wrong reason: " .. tostring(why))
  end
end)

check("a trigger left over from a previous press does not count", function()
  local p = fakePrompt()
  local ok = runWatched(p, nil, function()
    Act.lastTriggered = p.inst
    Act.triggeredAt = tick() - 30
  end)
  eq(ok, false, "stale trigger rejected")
end)

check("the wrong prompt being active blocks the press", function()
  local p = fakePrompt()
  local savedWatching, savedActive = Act.watching, Act.active
  local savedLook = RR.Move.lookAt
  local savedHold = Input.hold

  Act.watching = true
  Act.active = { tag = "someone else" }
  RR.Move.lookAt = function() return true end
  local pressed = false
  Input.hold = function() pressed = true return true end

  local ok, why = Act.prompt(p, {})

  Act.watching = savedWatching
  Act.active = savedActive
  RR.Move.lookAt = savedLook
  Input.hold = savedHold

  eq(ok, false, "refused")
  eq(pressed, false, "no key was sent")
  if not string.find(tostring(why), "not the active prompt", 1, true) then
    error("wrong reason: " .. tostring(why))
  end
end)

-- ---------------------------------------------------------------------
-- 10. stats surface
-- ---------------------------------------------------------------------
describe("summaries are safe to render before anything ran")

check("Act.summary", function()
  local s = Act.summary()
  if type(s) ~= "string" or #s == 0 then error("empty") end
end)

check("World.summary", function()
  local s = World.summary()
  if type(s) ~= "string" or #s == 0 then error("empty") end
end)

-- ---------------------------------------------------------------------
-- result
-- ---------------------------------------------------------------------
print("")
print(string.format("%d passed, %d failed", pass, fail))
if fail > 0 then
  print("")
  for i = 1, #failures do print("  " .. failures[i]) end
  error("test suite failed")
end
