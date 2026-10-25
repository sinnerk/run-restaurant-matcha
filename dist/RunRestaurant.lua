-- Run a Restaurant! - Matcha toolkit
-- built 2026-10-25 13:30
-- paste this whole file into Matcha and execute


-- ======================================================================
-- 00_boot.lua
-- ======================================================================
--[[ ==================================================================
     Run a Restaurant! - Matcha toolkit
     00_boot : namespace, logging, config store, shared utilities

     Everything below assumes only what doc.wabisabi.mom/matcha
     documents. No Instance.new, no RemoteEvent:FireServer, no
     Humanoid:MoveTo, no camera WorldToViewportPoint.
     ================================================================== ]]

local RR = rawget(_G, "RR")
if type(RR) ~= "table" then
  RR = {}
  _G.RR = RR
end

RR.VERSION  = "5.0.0"
RR.NAME     = "Run a Restaurant! toolkit"
RR.STARTED  = tick()
RR.FEATURES = RR.FEATURES or {}

-- service access that never throws -----------------------------------
local function svc(name)
  local ok, s = pcall(function() return game:GetService(name) end)
  if ok then return s end
  return nil
end
RR.svc = svc

-- ---------------------------------------------------------------------
-- logging
-- ---------------------------------------------------------------------
local Log = RR.Log or {}
RR.Log = Log

Log.lines   = Log.lines or {}
Log.n       = Log.n or 0
Log.cap     = 600
Log.toFile  = Log.toFile or false
Log.quiet   = Log.quiet or false

local _print = print
local _warn  = rawget(_G, "warn") or print
local _errl  = rawget(_G, "errorl") or rawget(_G, "warn") or print

local function stamp()
  local d = tick() - RR.STARTED
  if d < 0 then d = 0 end
  return string.format("%8.2f", d)
end

function Log.add(level, msg)
  Log.n = Log.n + 1
  local line = stamp() .. " [" .. tostring(level) .. "] " .. tostring(msg)
  Log.lines[Log.n] = line
  if Log.n > Log.cap then
    table.remove(Log.lines, 1)
    Log.n = Log.n - 1
  end
  if Log.quiet then return line end
  if level == "error" then
    pcall(function() _errl(line) end)
  elseif level == "warn" then
    pcall(function() _warn(line) end)
  else
    pcall(function() _print(line) end)
  end
  return line
end

function Log.tail(count)
  count = count or 40
  local out = {}
  local first = Log.n - count + 1
  if first < 1 then first = 1 end
  local k = 0
  for i = first, Log.n do
    k = k + 1
    out[k] = Log.lines[i]
  end
  return out
end

function Log.text(count)
  return table.concat(Log.tail(count), "\n")
end

function Log.flush()
  if not Log.toFile then return false end
  local body = table.concat(Log.tail(Log.cap), "\n")
  local ok = pcall(function() writefile("runrestaurant.log.txt", body) end)
  return ok
end

function RR.log(msg)  return Log.add("info",  msg) end
function RR.warn(msg) return Log.add("warn",  msg) end
function RR.err(msg)  return Log.add("error", msg) end

-- run a chunk of game-specific work without letting it kill a thread
function RR.safe(label, fn)
  local ok, err = pcall(fn)
  if not ok then
    RR.err(tostring(label) .. " failed: " .. tostring(err))
  end
  return ok
end

-- ---------------------------------------------------------------------
-- config store (persists through the Matcha workspace)
-- ---------------------------------------------------------------------
local Cfg = RR.Cfg or {}
RR.Cfg = Cfg

Cfg.data  = Cfg.data or {}
Cfg.path  = Cfg.path or "runrestaurant.cfg.json"
Cfg.loaded = Cfg.loaded or false
Cfg.dirty  = Cfg.dirty or false

local Http = svc("HttpService")
RR.HttpService = Http

function Cfg.load()
  local okFile = false
  pcall(function() okFile = isfile(Cfg.path) end)
  if not okFile then return false end

  local raw
  local ok = pcall(function() raw = readfile(Cfg.path) end)
  if not ok or type(raw) ~= "string" or raw == "" then return false end

  local tbl
  local ok2 = pcall(function() tbl = Http:JSONDecode(raw) end)
  if not ok2 or type(tbl) ~= "table" then return false end

  for k, v in pairs(tbl) do Cfg.data[k] = v end
  Cfg.loaded = true
  RR.log("config loaded from " .. Cfg.path)
  return true
end

function Cfg.save()
  if not Http then return false end
  local raw
  local ok = pcall(function() raw = Http:JSONEncode(Cfg.data) end)
  if not ok then return false end
  local ok2 = pcall(function() writefile(Cfg.path, raw) end)
  if ok2 then
    Cfg.dirty = false
    return true
  end
  RR.warn("config save failed")
  return false
end

function Cfg.get(key, default)
  local v = Cfg.data[key]
  if v == nil then return default end
  return v
end

function Cfg.set(key, value)
  if Cfg.data[key] ~= value then
    Cfg.data[key] = value
    Cfg.dirty = true
  end
  return value
end

function Cfg.toggle(key, default)
  return Cfg.set(key, not Cfg.get(key, default == true))
end

-- ---------------------------------------------------------------------
-- utilities
-- ---------------------------------------------------------------------
local Util = RR.Util or {}
RR.Util = Util

function Util.localPlayer()
  local P = svc("Players")
  if not P then return nil end
  local p = nil
  pcall(function() p = P.LocalPlayer end)
  return p
end

function Util.character()
  local p = Util.localPlayer()
  if not p then return nil end
  local c = nil
  pcall(function() c = p.Character end)
  return c
end

function Util.hrp()
  local c = Util.character()
  if not c then return nil end
  local h = nil
  pcall(function() h = c:FindFirstChild("HumanoidRootPart") end)
  return h
end

function Util.humanoid()
  local c = Util.character()
  if not c then return nil end
  local h = nil
  pcall(function() h = c:FindFirstChildOfClass("Humanoid") end)
  if not h then
    pcall(function() h = c:FindFirstChild("Humanoid") end)
  end
  return h
end

function Util.charPos()
  local h = Util.hrp()
  if not h then return nil end
  local p = nil
  pcall(function() p = h.Position end)
  return p
end

function Util.alive()
  local h = Util.humanoid()
  if not h then return false end
  local hp = 0
  pcall(function() hp = h.Health end)
  return (hp or 0) > 0
end

function Util.dist(a, b)
  if not a or not b then return math.huge end
  return (a - b).Magnitude
end

function Util.clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

function Util.round(n, places)
  local m = 10 ^ (places or 0)
  return math.floor(n * m + 0.5) / m
end

-- Instance identity that survives table keys and renaming
function Util.addr(inst)
  if not inst then return nil end
  local a = nil
  pcall(function() a = inst.Address end)
  return a
end

function Util.fullName(inst)
  if not inst then return "" end
  local n = ""
  pcall(function() n = inst:GetFullName() end)
  return n or ""
end

function Util.name(inst)
  if not inst then return "" end
  local n = ""
  pcall(function() n = inst.Name end)
  return n or ""
end

function Util.cls(inst)
  if not inst then return "" end
  local c = ""
  pcall(function() c = inst.ClassName end)
  return c or ""
end

function Util.children(inst)
  local out = {}
  if not inst then return out end
  local ok, kids = pcall(function() return inst:GetChildren() end)
  if ok and type(kids) == "table" then return kids end
  return out
end

-- strip the trailing _<guid> the place puts on entity models
local GUID = "_%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x"
function Util.cleanName(name)
  name = tostring(name or "")
  local trimmed = string.gsub(name, GUID, "")
  if trimmed ~= "" then return trimmed end
  return name
end

function Util.split(text, sep)
  local out = {}
  local pattern = "([^" .. sep .. "]+)"
  for piece in string.gmatch(text, pattern) do
    out[#out + 1] = piece
  end
  return out
end

function Util.contains(haystack, needle)
  return string.find(string.lower(haystack), string.lower(needle), 1, true) ~= nil
end

RR.log("boot ok - " .. RR.VERSION)

-- ======================================================================
-- 10_caps.lua
-- ======================================================================
--[[ ==================================================================
     10_caps : capability probe

     Matcha emulates the Roblox API from outside the process. Some
     things that look documented behave differently in a given build,
     and some things the place itself blocks (server-side position
     correction, for example). Rather than guessing, probe once at
     startup and record what actually works, then let every other
     module read the answer.

     The probe is cheap and runs before the UI so the first paint can
     show real values.
     ================================================================== ]]

local RR = _G.RR
local Caps = RR.Caps or {}
RR.Caps = Caps

Caps.done   = Caps.done or false
Caps.data   = Caps.data or {}
Caps.report = Caps.report or ""

local PROBE_GLOBALS = {
  "loadstring", "getscripts", "decompile", "getscriptbytecode", "getscripthash",
  "WorldToScreen", "notify", "identifyexecutor", "getgamename", "GetPingValue",
  "base64encode", "base64decode", "tick", "typeof", "gethwid",
  "httpget", "httppost", "readfile", "writefile", "isfile", "isfolder",
  "makefolder", "listfiles", "getgc", "setgc", "applygc", "getbase",
  "memory_read", "memory_write", "isrbxactive", "keypress", "keyrelease",
  "ismouse1pressed", "mouse1click", "mousemoveabs", "mousemoverel",
  "setclipboard", "setrobloxinput", "iskeypressed",
}

local function has(name)
  local v = rawget(_G, name)
  return v ~= nil
end

local function tryRead(obj, field)
  local ok, v = pcall(function() return obj[field] end)
  if ok then return v end
  return nil
end

local function tryWrite(obj, field, value)
  local ok = pcall(function() obj[field] = value end)
  return ok
end

-- Does a position write survive the server's next correction pass?
local function probeMovement()
  local hrp = RR.Util.hrp()
  if not hrp then
    return { canMove = false, reason = "no character yet" }
  end

  local origin = nil
  pcall(function() origin = hrp.Position end)
  if not origin then
    return { canMove = false, reason = "position unreadable" }
  end

  local function readBack()
    local p = nil
    pcall(function() p = hrp.Position end)
    return p
  end

  local result = { origin = origin }

  -- 1. position write
  local offset = origin + Vector3.new(0, 3, 0)
  local wrote = tryWrite(hrp, "Position", offset)
  wait(0.22)
  local after = readBack()
  result.positionWrite = wrote
  result.positionStuck = false
  if wrote and after then
    result.positionStuck = (after - offset).Magnitude < 3
  end

  -- put the character back before anything else looks at it
  pcall(function() hrp.Position = origin end)
  wait(0.1)

  -- 2. velocity write
  local beforeV = readBack()
  local velOk = tryWrite(hrp, "AssemblyLinearVelocity", Vector3.new(0, 12, 0))
  wait(0.12)
  local afterV = readBack()
  result.velocityWrite = velOk
  result.velocityMoved = false
  if velOk and beforeV and afterV then
    result.velocityMoved = (afterV - beforeV).Magnitude > 0.4
  end
  pcall(function() hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0) end)

  result.canMove = (result.positionWrite and result.positionStuck) or result.velocityMoved
  result.mode = "none"
  if result.positionWrite and result.positionStuck then
    result.mode = "position"
  elseif result.velocityMoved then
    result.mode = "velocity"
  end

  pcall(function() hrp.Position = origin end)
  return result
end

local function probeHumanoid()
  local hum = RR.Util.humanoid()
  if not hum then return { present = false } end
  local out = { present = true }
  out.health    = tryRead(hum, "Health")
  out.maxHealth = tryRead(hum, "MaxHealth")
  out.walkSpeed = tryRead(hum, "WalkSpeed")
  out.jumpPower = tryRead(hum, "JumpPower")
  out.useJumpPower = tryRead(hum, "UseJumpPower")
  out.stateChanged = tryRead(hum, "StateChanged") ~= nil
  out.moveTo = false
  local ok = pcall(function() hum:MoveTo(Vector3.new(0, 0, 0)) end)
  out.moveTo = ok
  return out
end

local function probeCamera()
  local cam = nil
  local ws = RR.svc("Workspace")
  if ws then pcall(function() cam = ws.CurrentCamera end) end
  if not cam then return { present = false } end
  local out = { present = true }
  out.viewport = tryRead(cam, "ViewportSize")
  out.position = tryRead(cam, "Position")
  out.fieldOfView = tryRead(cam, "FieldOfView")
  out.cframe = tryRead(cam, "CFrame")
  out.worldToViewport = false
  local ok = pcall(function() cam:WorldToViewportPoint(Vector3.new(0, 0, 0)) end)
  out.worldToViewport = ok
  return out
end

local function probePrompt()
  local prompt = nil
  local ws = RR.svc("Workspace")
  if ws then
    pcall(function()
      local found = ws:GetDescendants()
      for i = 1, #found do
        if found[i].ClassName == "ProximityPrompt" then
          prompt = found[i]
          return
        end
      end
    end)
  end
  if not prompt then return { found = false } end

  local out = { found = true }
  out.enabled  = tryRead(prompt, "Enabled")
  out.keyCode  = tryRead(prompt, "KeyboardKeyCode")
  out.hold     = tryRead(prompt, "HoldDuration")
  out.maxDist  = tryRead(prompt, "MaxActivationDistance")
  out.requiresLineOfSight = tryRead(prompt, "RequiresLineOfSight")
  out.objectText = tryRead(prompt, "ObjectText")
  out.actionText = tryRead(prompt, "ActionText")
  return out
end

local function probeStorage()
  local out = {}
  local rs = RR.svc("ReplicatedStorage")
  out.replicatedStorage = rs ~= nil
  if rs then
    local ok, kids = pcall(function() return rs:GetChildren() end)
    out.replicatedStorageChildren = ok and #kids or 0
  end
  local rf = RR.svc("ReplicatedFirst")
  out.replicatedFirst = rf ~= nil

  local lp = RR.Util.localPlayer()
  if lp then
    local bp = nil
    pcall(function() bp = lp:FindFirstChildOfClass("Backpack") end)
    out.backpack = bp ~= nil
    if bp then
      local ok, kids = pcall(function() return bp:GetChildren() end)
      out.backpackItems = ok and #kids or 0
    end
    local pg = nil
    pcall(function() pg = lp:FindFirstChildOfClass("PlayerGui") end)
    out.playerGui = pg ~= nil
    if pg then
      local ok, kids = pcall(function() return pg:GetDescendants() end)
      out.playerGuiDescendants = ok and #kids or 0
    end
  end
  return out
end

function Caps.probe()
  Caps.data = {}
  local d = Caps.data

  d.executor = { identifyexecutor() }
  local ok, name = pcall(function() return getgamename() end)
  d.gameName = ok and name or "?"
  local ws = RR.svc("Workspace")
  if ws then pcall(function() d.placeId = game.PlaceId end) end
  if game then pcall(function() d.jobId = game.JobId end) end

  d.globals = {}
  local missing = {}
  for i = 1, #PROBE_GLOBALS do
    local key = PROBE_GLOBALS[i]
    local present = has(key)
    d.globals[key] = present
    if not present then missing[#missing + 1] = key end
  end
  d.missing = missing

  d.humanoid = probeHumanoid()
  d.camera = probeCamera()
  d.prompt = probePrompt()
  d.storage = probeStorage()

  local doMove = RR.Cfg.get("capsMoveTest", true)
  if doMove then
    d.move = probeMovement()
  else
    d.move = { canMove = false, reason = "probe disabled in config", mode = "untested" }
  end

  -- record the movement mode so Move can use it immediately
  if d.move and d.move.mode and d.move.mode ~= "none" and d.move.mode ~= "untested" then
    RR.Cfg.set("moveMode", d.move.mode)
  end

  d.finishedAt = tick()
  Caps.done = true
  Caps.report = Caps.format()
  RR.log("capability probe finished")
  return d
end

local function yn(v)
  if v == true then return "yes" end
  if v == false then return "no" end
  if v == nil then return "?" end
  if type(v) == "number" then return tostring(v) end
  if type(v) == "string" then return v end
  return tostring(v)
end

function Caps.format()
  local d = Caps.data
  if not d or not d.executor then return "not probed" end
  local out = {}
  out[#out + 1] = "executor      : " .. tostring(d.executor[1]) .. " " .. tostring(d.executor[2])
  out[#out + 1] = "place         : " .. tostring(d.gameName) .. "  id=" .. tostring(d.placeId)
  out[#out + 1] = "missing       : " .. (#d.missing == 0 and "none" or table.concat(d.missing, ", "))
  out[#out + 1] = "humanoid      : health=" .. yn(d.humanoid.health) .. " walk=" .. yn(d.humanoid.walkSpeed) .. " moveTo=" .. yn(d.humanoid.moveTo)
  out[#out + 1] = "camera        : cframe=" .. yn(d.camera.cframe ~= nil) .. " w2v=" .. yn(d.camera.worldToViewport)
  out[#out + 1] = "prompt        : " .. (d.prompt.found and ("key=" .. yn(d.prompt.keyCode) .. " hold=" .. yn(d.prompt.hold) .. " range=" .. yn(d.prompt.maxDist)) or "none in workspace")
  out[#out + 1] = "movement      : mode=" .. tostring(d.move.mode) .. " pos=" .. yn(d.move.positionStuck) .. " vel=" .. yn(d.move.velocityMoved)
  out[#out + 1] = "replicatedstg : " .. yn(d.storage.replicatedStorage) .. " children=" .. yn(d.storage.replicatedStorageChildren)
  out[#out + 1] = "backpack      : " .. yn(d.storage.backpack) .. " items=" .. yn(d.storage.backpackItems)
  out[#out + 1] = "playergui     : " .. yn(d.storage.playerGui) .. " nodes=" .. yn(d.storage.playerGuiDescendants)
  return table.concat(out, "\n")
end

function Caps.get(key, default)
  local v = Caps.data[key]
  if v == nil then return default end
  return v
end

function Caps.hasGlobal(name)
  return rawget(_G, name) ~= nil
end

-- ======================================================================
-- 15_input.lua
-- ======================================================================
--[[ ==================================================================
     15_input : focus-gated input

     Matcha injects at the OS level. Anything that presses a key while
     the user is in Chrome presses it in Chrome. Every call here goes
     through the gate first, and the gate is on by default.
     ================================================================== ]]

local RR = _G.RR
local Input = RR.Input or {}
RR.Input = Input

Input.Stats = Input.Stats or {
  keys    = 0,
  clicks  = 0,
  blocked = 0,
  lastAt  = 0,
}

Input.VK = {
  A = 0x41, B = 0x42, C = 0x43, D = 0x44, E = 0x45, F = 0x46, G = 0x47,
  H = 0x48, I = 0x49, J = 0x4A, K = 0x4B, L = 0x4C, M = 0x4D, N = 0x4E,
  O = 0x4F, P = 0x50, Q = 0x51, R = 0x52, S = 0x53, T = 0x54, U = 0x55,
  V = 0x56, W = 0x57, X = 0x58, Y = 0x59, Z = 0x5A,
  SPACE = 0x20, ENTER = 0x0D, ESC = 0x1B, TAB = 0x09, SHIFT = 0x10,
  CTRL = 0x11, ALT = 0x12, LEFT = 0x25, UP = 0x26, RIGHT = 0x27, DOWN = 0x28,
  DIGIT1 = 0x31, DIGIT2 = 0x32, DIGIT3 = 0x33, DIGIT4 = 0x34, DIGIT5 = 0x35,
  DIGIT6 = 0x36, DIGIT7 = 0x37, DIGIT8 = 0x38, DIGIT9 = 0x39, DIGIT0 = 0x30,
}

local lastBlockLog = 0

-- true when it is safe to send input into the game right now
function Input.focused()
  if not RR.Cfg.get("requireFocus", true) then return true end
  local active = false
  local ok = pcall(function() active = isrbxactive() end)
  if not ok then return false end
  return active == true
end

function Input.gate(who)
  if Input.focused() then return true end
  Input.Stats.blocked = Input.Stats.blocked + 1
  local now = tick()
  if now - lastBlockLog > 5 then
    lastBlockLog = now
    RR.Log.add("warn", "input blocked (" .. tostring(who) .. ") - Roblox is not the foreground window")
  end
  return false
end

function Input.keyDown(vk)
  Input.Stats.keys = Input.Stats.keys + 1
  pcall(function() keypress(vk) end)
end

function Input.keyUp(vk)
  pcall(function() keyrelease(vk) end)
end

-- press, hold for ms, release. Returns false if the gate refused.
function Input.hold(vk, ms, who)
  if not Input.gate(who or "hold") then return false end
  ms = ms or 60
  Input.keyDown(vk)
  wait(ms / 1000)
  Input.keyUp(vk)
  Input.Stats.lastAt = tick()
  return true
end

function Input.tap(vk, times, gapMs, who)
  times = times or 1
  gapMs = gapMs or 90
  for _ = 1, times do
    if not Input.hold(vk, 45, who) then return false end
    wait(gapMs / 1000)
  end
  return true
end

function Input.typeKey(vk, holdMs)
  return Input.hold(vk, holdMs or 55, "type")
end

function Input.moveAbs(x, y)
  if not Input.gate("mousemoveabs") then return false end
  pcall(function() mousemoveabs(math.floor(x), math.floor(y)) end)
  return true
end

function Input.moveRel(dx, dy)
  if not Input.gate("mousemoverel") then return false end
  pcall(function() mousemoverel(math.floor(dx), math.floor(dy)) end)
  return true
end

function Input.click()
  if not Input.gate("click") then return false end
  Input.Stats.clicks = Input.Stats.clicks + 1
  pcall(function() mouse1click() end)
  Input.Stats.lastAt = tick()
  return true
end

function Input.clickAt(worldPos, offsetX, offsetY)
  local cam = nil
  local ws = RR.svc("Workspace")
  if ws then pcall(function() cam = ws.CurrentCamera end) end
  if not cam or not worldPos then return false end

  local screen, onScreen = nil, false
  local ok = pcall(function()
    screen, onScreen = WorldToScreen(worldPos)
  end)
  if not ok or not screen or not onScreen then return false end

  local vp = nil
  pcall(function() vp = cam.ViewportSize end)
  if vp then
    if screen.X < 2 or screen.Y < 2 or screen.X > vp.X - 2 or screen.Y > vp.Y - 2 then
      return false
    end
  end

  if not Input.moveAbs(screen.X + (offsetX or 0), screen.Y + (offsetY or 0)) then
    return false
  end
  wait(0.04)
  return Input.click()
end

-- hold a key while a condition stays true, with a hard ceiling
function Input.holdWhile(vk, condition, maxMs)
  if not Input.gate("holdWhile") then return false end
  maxMs = maxMs or 2000
  Input.keyDown(vk)
  local deadline = tick() + (maxMs / 1000)
  while tick() < deadline do
    local alive = false
    pcall(function() alive = condition() end)
    if not alive then break end
    wait(0.03)
  end
  Input.keyUp(vk)
  return true
end

function Input.releaseAll()
  for _, vk in pairs(Input.VK) do
    pcall(function() keyrelease(vk) end)
  end
end

function Input.summary()
  local s = Input.Stats
  return string.format("keys=%d clicks=%d blocked=%d", s.keys, s.clicks, s.blocked)
end

-- ======================================================================
-- 20_move.lua
-- ======================================================================
--[[ ==================================================================
     20_move : locomotion

     Two ways to get somewhere, chosen by the capability probe:

       write mode  - assign HumanoidRootPart.Position. Instant, silent,
                     but a place with server-side position checks will
                     snap the character back. The probe measures this.
       walk mode   - hold W and steer the camera with right-mouse drag
                     until WorldToScreen puts the target near the centre.
                     Slower, but it moves the character the way the game
                     expects, so anti-cheat has nothing to flag.

     Walk mode exists because "it worked on my machine" is how v3 died.
     If writes are blocked, the bot should still be able to play.
     ================================================================== ]]

local RR = _G.RR
local Move = RR.Move or {}
RR.Move = Move

Move.Stats = Move.Stats or {
  writes  = 0,
  walks   = 0,
  arrived = 0,
  failed  = 0,
  stuck   = 0,
  mode    = "auto",
  lastErr = "",
}

local VK = RR.Input.VK

local function camera()
  local ws = RR.svc("Workspace")
  if not ws then return nil end
  local cam = nil
  pcall(function() cam = ws.CurrentCamera end)
  return cam
end

local function viewport()
  local cam = camera()
  if not cam then return Vector2.new(1280, 720) end
  local vp = nil
  pcall(function() vp = cam.ViewportSize end)
  if vp then return vp end
  return Vector2.new(1280, 720)
end

local function project(pos)
  local sp, onScreen = nil, false
  local ok = pcall(function()
    sp, onScreen = WorldToScreen(pos)
  end)
  if not ok then return nil, false end
  return sp, onScreen
end

function Move.probeMode()
  local caps = RR.Caps.data and RR.Caps.data.move
  if caps and caps.mode and caps.mode ~= "none" and caps.mode ~= "untested" then
    return caps.mode
  end
  return RR.Cfg.get("moveMode", "position")
end

function Move.setMode(mode)
  RR.Cfg.set("moveMode", mode)
  Move.Stats.mode = mode
end

-- ---------------------------------------------------------------------
-- direct writes
-- ---------------------------------------------------------------------
function Move.writePosition(pos)
  local hrp = RR.Util.hrp()
  if not hrp then return false, "no character" end
  local ok = pcall(function() hrp.Position = pos end)
  if not ok then
    Move.Stats.lastErr = "position write rejected"
    return false
  end
  Move.Stats.writes = Move.Stats.writes + 1
  wait(0.05)
  local now = RR.Util.charPos()
  if now and (now - pos).Magnitude > 8 then
    Move.Stats.lastErr = "position write reverted"
    return false
  end
  return true
end

function Move.pushVelocity(pos, speed)
  local hrp = RR.Util.hrp()
  if not hrp then return false, "no character" end
  local origin = RR.Util.charPos()
  if not origin then return false, "no position" end
  local delta = pos - origin
  local dist = delta.Magnitude
  if dist < 0.6 then return true end
  local unit = delta / dist
  local v = speed or RR.Util.clamp(dist * 4, 45, 240)
  local ok = pcall(function() hrp.AssemblyLinearVelocity = unit * v end)
  if not ok then
    Move.Stats.lastErr = "velocity write rejected"
    return false
  end
  Move.Stats.writes = Move.Stats.writes + 1
  return true
end

-- ---------------------------------------------------------------------
-- camera steering + walking
-- ---------------------------------------------------------------------
function Move.lookAt(target, tolPx, maxMs)
  tolPx = tolPx or 45
  maxMs = maxMs or 900
  if not RR.Input.focused() then return false, "not focused" end

  local vp = viewport()
  local cx = vp.X / 2
  local cy = vp.Y / 2

  local held = false
  local deadline = tick() + (maxMs / 1000)
  local converged = false
  local searched = 0

  while tick() < deadline do
    local sp, onScreen = project(target)

    if sp and onScreen then
      local dx = sp.X - cx
      local dy = sp.Y - cy
      if math.abs(dx) <= tolPx and math.abs(dy) <= tolPx then
        converged = true
        break
      end
      if not held then
        pcall(function() mouse2press() end)
        held = true
      end
      -- cap the step so one frame cannot spin past the target
      local stepX = RR.Util.clamp(dx * 0.42, -140, 140)
      local stepY = RR.Util.clamp(dy * 0.42, -110, 110)
      RR.Input.moveRel(stepX, stepY)
    else
      -- behind us: drag sideways in fixed steps until it is on screen
      if not held then
        pcall(function() mouse2press() end)
        held = true
      end
      RR.Input.moveRel(150, 0)
      searched = searched + 1
      if searched > 24 then break end
    end
    wait(0.03)
  end

  if held then
    pcall(function() mouse2release() end)
  end
  return converged
end

function Move.unstick()
  Move.Stats.stuck = Move.Stats.stuck + 1
  RR.Input.keyUp(VK.W)
  RR.Input.keyDown(VK.SPACE)
  wait(0.12)
  RR.Input.keyUp(VK.SPACE)

  local dir = (math.random(0, 1) == 0) and VK.A or VK.D
  RR.Input.keyDown(dir)
  wait(0.25)
  RR.Input.keyUp(dir)
  RR.Input.keyDown(VK.W)
end

function Move.walkTo(target, tol, maxMs)
  tol = tol or 7
  maxMs = maxMs or 12000
  if not RR.Input.focused() then return false, "not focused" end
  if not RR.Util.alive() then return false, "dead" end

  Move.Stats.walks = Move.Stats.walks + 1
  local deadline = tick() + (maxMs / 1000)
  local lastPos = RR.Util.charPos()
  local lastProgress = tick()

  RR.Input.keyDown(VK.W)

  while tick() < deadline do
    if not RR.Util.alive() then
      RR.Input.keyUp(VK.W)
      return false, "died"
    end

    local pos = RR.Util.charPos()
    if pos and (pos - target).Magnitude <= tol then
      RR.Input.keyUp(VK.W)
      Move.Stats.arrived = Move.Stats.arrived + 1
      return true
    end

    Move.lookAt(target, 60, 260)

    if pos and lastPos then
      if (pos - lastPos).Magnitude < 0.35 then
        if tick() - lastProgress > 0.9 then
          Move.unstick()
          lastProgress = tick()
        end
      else
        lastPos = pos
        lastProgress = tick()
      end
    end

    wait(0.04)
  end

  RR.Input.keyUp(VK.W)
  Move.Stats.failed = Move.Stats.failed + 1
  Move.Stats.lastErr = "walk timeout"
  return false, "timeout"
end

function Move.stop()
  pcall(function() RR.Input.keyUp(VK.W) end)
  local hrp = RR.Util.hrp()
  if hrp then
    pcall(function() hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0) end)
  end
end

-- ---------------------------------------------------------------------
-- unified entry point
-- ---------------------------------------------------------------------
function Move.arrived(target, tol)
  local pos = RR.Util.charPos()
  if not pos or not target then return false end
  return (pos - target).Magnitude <= (tol or 8)
end

-- opts: { mode = "auto"|"position"|"velocity"|"walk", tol, timeout, exact }
function Move.goto(target, opts)
  if not target then return false, "no target" end
  opts = opts or {}
  local tol = opts.tol or 7
  local timeout = opts.timeout or 14
  local mode = opts.mode or Move.Stats.mode or "auto"
  if mode == "auto" then mode = Move.probeMode() end

  if Move.arrived(target, tol) then
    Move.Stats.arrived = Move.Stats.arrived + 1
    return true, "already there"
  end

  local deadline = tick() + timeout

  if mode == "position" then
    while tick() < deadline do
      local ok = Move.writePosition(target)
      if ok and Move.arrived(target, tol) then
        Move.Stats.arrived = Move.Stats.arrived + 1
        return true, "position"
      end
      wait(0.08)
    end
    Move.Stats.lastErr = "position mode failed"
  elseif mode == "velocity" then
    while tick() < deadline do
      Move.pushVelocity(target)
      wait(0.08)
      if Move.arrived(target, tol) then
        Move.Stats.arrived = Move.Stats.arrived + 1
        return true, "velocity"
      end
    end
    Move.Stats.lastErr = "velocity mode failed"
  end

  -- fall through to walking, which also covers "exact = true" approaches
  local okWalk, why = Move.walkTo(target, tol, math.max(1000, (deadline - tick()) * 1000))
  if okWalk then return true, "walk" end

  Move.Stats.failed = Move.Stats.failed + 1
  Move.Stats.lastErr = why or "unreachable"
  return false, Move.Stats.lastErr
end

function Move.summary()
  local s = Move.Stats
  return string.format("mode=%s arrived=%d writes=%d walks=%d stuck=%d fail=%d",
    tostring(s.mode), s.arrived, s.writes, s.walks, s.stuck, s.failed)
end

-- ======================================================================
-- 25_world.lua
-- ======================================================================
--[[ ==================================================================
     25_world : world snapshot

     Walking the whole place at once freezes the game (the workspace in
     this place holds ~64,000 instances). This builds the snapshot in
     slices: every tick it spends a small time budget, then yields, so
     the frame rate never collapses.

     Roots scanned: Workspace, ReplicatedStorage, ReplicatedFirst, the
     local Backpack and PlayerGui. The last two matter here - tools and
     on-screen text are how a restaurant game usually tells you what it
     wants, and the workspace alone will not show them.
     ================================================================== ]]

local RR = _G.RR
local World = RR.World or {}
RR.World = World

World.state = World.state or {
  scanning   = false,
  phase      = "idle",
  queue      = {},
  qIndex     = 1,
  qTotal     = 0,
  items      = nil,
  itemCount  = 0,
  prompts    = nil,
  promptCount = 0,
  clicks     = nil,
  clickCount = 0,
  startedAt  = 0,
  finishedAt = 0,
  lastScan   = 0,
  buildMs    = 0,
}

World.maxItems   = 90000
World.budgetMs   = 7

local GUID = "_%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x"

local function clean(name)
  local s = string.gsub(tostring(name or ""), GUID, "")
  if s == "" then return tostring(name or "") end
  return s
end

local function readName(inst)
  local n = ""
  pcall(function() n = inst.Name end)
  return n or ""
end

local function readClass(inst)
  local c = ""
  pcall(function() c = inst.ClassName end)
  return c or ""
end

function World.roots()
  local out = {}
  local ws = RR.svc("Workspace")
  if ws then out[#out + 1] = ws end
  local rs = RR.svc("ReplicatedStorage")
  if rs then out[#out + 1] = rs end
  local rf = RR.svc("ReplicatedFirst")
  if rf then out[#out + 1] = rf end

  local lp = RR.Util.localPlayer()
  if lp then
    local bp = nil
    pcall(function() bp = lp:FindFirstChildOfClass("Backpack") end)
    if bp then out[#out + 1] = bp end
    local pg = nil
    pcall(function() pg = lp:FindFirstChildOfClass("PlayerGui") end)
    if pg then out[#out + 1] = pg end
    local plr = lp
    pcall(function() plr = lp.Character end)
    if plr then out[#out + 1] = plr end
  end
  return out
end

function World.scan()
  local s = World.state
  s.scanning = true
  s.phase = "collect"
  s.queue = {}
  s.qIndex = 1
  s.qTotal = 0
  s.items = {}
  s.itemCount = 0
  s.prompts = {}
  s.promptCount = 0
  s.clicks = {}
  s.clickCount = 0
  s.startedAt = tick()

  local roots = World.roots()
  for i = 1, #roots do
    local root = roots[i]
    local kids = nil
    local ok = pcall(function() kids = root:GetDescendants() end)
    if ok and type(kids) == "table" then
      local q = s.queue
      local n = s.qTotal
      for j = 1, #kids do
        n = n + 1
        q[n] = kids[j]
        if n >= World.maxItems then break end
      end
      s.qTotal = n
    end
  end

  s.phase = "walk"
  RR.log("world scan started: " .. tostring(s.qTotal) .. " instances")
  return s.qTotal
end

-- process a slice of the queue; call this every frame
function World.step()
  local s = World.state
  if not s.scanning or s.phase ~= "walk" then return false end

  local deadline = tick() + (World.budgetMs / 1000)
  local q = s.queue
  local i = s.qIndex
  local items = s.items
  local n = s.itemCount
  local prompts = s.prompts
  local pn = s.promptCount
  local clicks = s.clicks
  local cn = s.clickCount

  while i <= s.qTotal do
    local inst = q[i]
    i = i + 1

    if inst then
      local cls = readClass(inst)
      if cls ~= "" then
        local name = readName(inst)
        n = n + 1
        items[n] = {
          inst  = inst,
          cls   = cls,
          name  = name,
          clean = clean(name),
          lower = string.lower(name),
        }

        if cls == "ProximityPrompt" then
          local anchor = nil
          pcall(function() anchor = inst.Parent end)
          if anchor then
            pn = pn + 1
            prompts[pn] = { inst = inst, anchor = anchor }
          end
        elseif cls == "ClickDetector" then
          local anchor = nil
          pcall(function() anchor = inst.Parent end)
          if anchor then
            cn = cn + 1
            clicks[cn] = { inst = inst, anchor = anchor }
          end
        end
      end
    end

    if tick() > deadline then break end
    if n >= World.maxItems then break end
  end

  s.qIndex = i
  s.itemCount = n
  s.promptCount = pn
  s.clickCount = cn
  s.items = items
  s.prompts = prompts
  s.clicks = clicks

  if i > s.qTotal then
    s.scanning = false
    s.phase = "done"
    s.finishedAt = tick()
    s.lastScan = s.finishedAt
    s.buildMs = (s.finishedAt - s.startedAt) * 1000
    RR.log(string.format("world scan done: %d instances, %d prompts, %d click detectors in %.0f ms",
      s.itemCount, s.promptCount, s.clickCount, s.buildMs))
    return true
  end
  return false
end

function World.ready()
  return World.state.phase == "done" and World.state.itemCount > 0
end

function World.progress()
  local s = World.state
  if s.qTotal <= 0 then return 0 end
  return s.qIndex / s.qTotal
end

-- position of an instance, without assuming it is a BasePart
function World.posOf(inst)
  if not inst then return nil end
  local pos = nil
  pcall(function() pos = inst.Position end)
  if pos then return pos end

  local primary = nil
  pcall(function() primary = inst.PrimaryPart end)
  if primary then
    pcall(function() pos = primary.Position end)
    if pos then return pos end
  end

  local kids = nil
  pcall(function() kids = inst:GetChildren() end)
  if kids then
    for i = 1, #kids do
      local child = kids[i]
      pcall(function() pos = child.Position end)
      if pos then return pos end
    end
  end
  return nil
end

-- pattern: "a|b|!c" - any include term, reject anything matching c
function World.parsePattern(pattern)
  local inc, exc = {}, {}
  if type(pattern) == "table" then
    for i = 1, #pattern do inc[#inc + 1] = string.lower(pattern[i]) end
    return inc, exc
  end
  local parts = RR.Util.split(string.lower(pattern or ""), "|")
  for i = 1, #parts do
    local p = parts[i]
    if p ~= "" then
      if string.sub(p, 1, 1) == "!" then
        exc[#exc + 1] = string.sub(p, 2)
      else
        inc[#inc + 1] = p
      end
    end
  end
  return inc, exc
end

-- exact > prefix > word boundary > substring
function World.score(text, inc, exc)
  if text == nil or text == "" then return nil end
  for i = 1, #exc do
    if string.find(text, exc[i], 1, true) then return nil end
  end
  local best = nil
  for i = 1, #inc do
    local needle = inc[i]
    if text == needle then
      return 100
    elseif string.sub(text, 1, #needle) == needle then
      if not best or 70 > best then best = 70 end
    elseif string.find(text, " " .. needle, 1, true) or string.find(text, "_" .. needle, 1, true) then
      if not best or 50 > best then best = 50 end
    elseif string.find(text, needle, 1, true) then
      if not best or 25 > best then best = 25 end
    end
  end
  return best
end

-- best-scoring match among items of a class (or any class if nil)
function World.find(pattern, clsFilter, maxResults)
  local s = World.state
  if not s.items then return {} end
  local inc, exc = World.parsePattern(pattern)
  if #inc == 0 then return {} end
  maxResults = maxResults or 50

  local hits = {}
  local items = s.items
  for i = 1, s.itemCount do
    local it = items[i]
    if not clsFilter or it.cls == clsFilter then
      local sc = World.score(it.lower, inc, exc)
      if not sc then
        sc = World.score(string.lower(it.clean), inc, exc)
      end
      if sc then
        hits[#hits + 1] = { item = it, score = sc }
      end
    end
  end

  table.sort(hits, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    return a.item.name < b.item.name
  end)

  local out = {}
  for i = 1, math.min(#hits, maxResults) do
    out[i] = hits[i].item
  end
  return out
end

function World.nearest(pattern, clsFilter, maxDist, skipFn)
  local origin = RR.Util.charPos()
  if not origin then return nil end
  maxDist = maxDist or 120

  local candidates = World.find(pattern, clsFilter, 200)
  local best, bestDist = nil, maxDist

  for i = 1, #candidates do
    local it = candidates[i]
    local skip = false
    if skipFn then
      local ok, v = pcall(skipFn, it.inst)
      skip = ok and v == true
    end
    if not skip then
      local pos = World.posOf(it.inst)
      if pos then
        local d = (origin - pos).Magnitude
        if d <= bestDist then
          best, bestDist = it, d
        end
      end
    end
  end

  if best then return best, bestDist end
  return nil, nil
end

-- live prompt entries with anchor position, computed on demand so a
-- prompt that moves with a customer is never stale
function World.livePrompts()
  local s = World.state
  local out = {}
  if not s.prompts then return out end
  for i = 1, s.promptCount do
    local p = s.prompts[i]
    local anchorPos = World.posOf(p.anchor)
    local enabled = nil
    pcall(function() enabled = p.inst.Enabled end)
    if anchorPos and enabled ~= false then
      out[#out + 1] = {
        inst   = p.inst,
        anchor = p.anchor,
        pos    = anchorPos,
        name   = readName(p.inst),
        aname  = clean(readName(p.anchor)),
        key    = nil,
        hold   = nil,
      }
      local e = out[#out]
      pcall(function() e.key = p.inst.KeyboardKeyCode end)
      pcall(function() e.hold = p.inst.HoldDuration end)
    end
  end
  return out
end

function World.summary()
  local s = World.state
  return string.format("%d items, %d prompts, %d clicks, scan %.0f ms",
    s.itemCount, s.promptCount, s.clickCount, s.buildMs)
end

-- ======================================================================
-- 30_act.lua
-- ======================================================================
--[[ ==================================================================
     30_act : actions

     The only interaction surfaces that exist from outside the process:
       - ProximityPrompt, activated by standing close, facing it, and
         sending its own key code for its own hold duration
       - ClickDetector, activated by clicking the part on screen
       - things that respond to a tool being equipped, via the number
         keys, which only works if the tool is already in the hotbar

     Anything the game does through a RemoteEvent is out of reach, and
     the place has exactly one RemoteEvent, so this is the whole toolkit.
     ================================================================== ]]

local RR = _G.RR
local Act = RR.Act or {}
RR.Act = Act

Act.Stats = Act.Stats or {
  prompts   = 0,
  promptOk  = 0,
  clicks    = 0,
  clickOk   = 0,
  lastErr   = "",
}

local VK = RR.Input.VK

-- prompt field with a fallback
local function field(inst, key, default)
  local v = nil
  local ok = pcall(function() v = inst[key] end)
  if ok and v ~= nil then return v end
  return default
end

local function promptKeyVK(prompt)
  local k = field(prompt, "KeyboardKeyCode", nil)
  if type(k) == "number" and k > 0 then return k end
  if type(k) == "userdata" or type(k) == "table" then
    -- Enum.KeyCode -> number, if the bridge exposes .Value
    local n = nil
    pcall(function() n = k.Value end)
    if type(n) == "number" and n > 0 then return n end
  end
  return VK.E
end

-- Activate one prompt. opts:
--   approach  : false to skip walking (default true)
--   tol       : arrival tolerance in studs (default 4)
--   verify    : function(inst) -> boolean, polled after the press
--   verifyMs  : how long to poll verify (default 800)
function Act.prompt(p, opts)
  opts = opts or {}
  if not p or not p.inst then return false, "no prompt" end
  Act.Stats.prompts = Act.Stats.prompts + 1

  local anchorPos = p.pos or RR.World.posOf(p.anchor)
  if not anchorPos then
    Act.Stats.lastErr = "prompt has no position"
    return false, Act.Stats.lastErr
  end

  local maxDist = field(p.inst, "MaxActivationDistance", 10)
  if type(maxDist) ~= "number" or maxDist <= 0 then maxDist = 10 end
  local want = math.min(maxDist * 0.75, opts.tol or 6)

  if opts.approach ~= false then
    local pos = RR.Util.charPos()
    if not pos or (pos - anchorPos).Magnitude > want then
      local ok = RR.Move.goto(anchorPos, { tol = want, timeout = opts.timeout or 12 })
      if not ok then
        Act.Stats.lastErr = "could not reach prompt"
        return false, Act.Stats.lastErr
      end
    end
  end

  -- face it, otherwise the prompt is not focused and E does nothing
  RR.Move.lookAt(anchorPos + Vector3.new(0, 1.5, 0), 70, 700)

  local vk = promptKeyVK(p.inst)
  local hold = field(p.inst, "HoldDuration", 0)
  if type(hold) ~= "number" or hold < 0 then hold = 0 end
  local holdMs = (hold * 1000) + 90

  if not RR.Input.hold(vk, holdMs, "prompt") then
    Act.Stats.lastErr = "input gate closed"
    return false, Act.Stats.lastErr
  end
  wait(0.08)

  if opts.verify then
    local deadline = tick() + ((opts.verifyMs or 800) / 1000)
    while tick() < deadline do
      local ok, res = pcall(opts.verify, p.inst)
      if ok and res == true then
        Act.Stats.promptOk = Act.Stats.promptOk + 1
        return true, "verified"
      end
      wait(0.06)
    end
    Act.Stats.lastErr = "no confirmation"
    return false, Act.Stats.lastErr
  end

  Act.Stats.promptOk = Act.Stats.promptOk + 1
  return true, "pressed"
end

-- Click a world position
function Act.clickPart(part, opts)
  opts = opts or {}
  if not part then return false, "no part" end
  local pos = RR.World.posOf(part)
  if not pos then return false, "no position" end

  local ok = RR.Input.clickAt(pos, opts.offsetX, opts.offsetY)
  Act.Stats.clicks = Act.Stats.clicks + 1
  if ok then
    Act.Stats.clickOk = Act.Stats.clickOk + 1
    return true, "clicked"
  end
  Act.Stats.lastErr = "click point off screen or gate closed"
  return false, Act.Stats.lastErr
end

-- ClickDetector: walk into range first, then click the parent part
function Act.clickDetector(entry, opts)
  opts = opts or {}
  if not entry or not entry.anchor then return false, "no detector" end

  local maxDist = field(entry.inst, "MaxActivationDistance", 32)
  if type(maxDist) ~= "number" or maxDist <= 0 then maxDist = 32 end
  local want = math.min(maxDist * 0.7, 20)

  local pos = RR.World.posOf(entry.anchor)
  if not pos then return false, "detector parent has no position" end

  local me = RR.Util.charPos()
  if not me or (me - pos).Magnitude > want then
    local ok = RR.Move.goto(pos, { tol = want, timeout = opts.timeout or 14 })
    if not ok then return false, "could not reach detector" end
  end

  RR.Move.lookAt(pos, 60, 600)
  return Act.clickPart(entry.anchor, opts)
end

-- Is a prompt currently usable from where we stand?
function Act.promptInRange(p)
  if not p then return false end
  local me = RR.Util.charPos()
  local pos = p.pos or RR.World.posOf(p.anchor)
  if not me or not pos then return false end
  local maxDist = field(p.inst, "MaxActivationDistance", 10)
  if type(maxDist) ~= "number" or maxDist <= 0 then maxDist = 10 end
  return (me - pos).Magnitude <= maxDist
end

function Act.summary()
  local s = Act.Stats
  return string.format("prompts %d/%d  clicks %d/%d", s.promptOk, s.prompts, s.clickOk, s.clicks)
end

-- ======================================================================
-- 35_jobs.lua
-- ======================================================================
--[[ ==================================================================
     35_jobs : scheduler

     A job is one thing the bot can do. Every job declares a weight
     (how much it matters), a cooldown (how often it may run) and a
     run function that does one attempt and returns true when it
     actually did something.

     The scheduler always runs the highest-weight job that is ready, so
     a restaurant that is on fire never waits behind a fishing trip.
     A job that keeps failing backs off instead of spinning.
     ================================================================== ]]

local RR = _G.RR
local Jobs = RR.Jobs or {}
RR.Jobs = Jobs

Jobs.list   = Jobs.list or {}
Jobs.n      = Jobs.n or 0
Jobs.byId   = Jobs.byId or {}
Jobs.Stats  = Jobs.Stats or { runs = 0, ok = 0, fail = 0, skipped = 0, lastId = "-" }
Jobs.paused = false

-- def = { id, label, weight, cooldown, enabled, run }
function Jobs.add(def)
  if not def or not def.id then return nil end
  local existing = Jobs.byId[def.id]
  if existing then
    existing.label    = def.label or existing.label
    existing.weight   = def.weight or existing.weight
    existing.cooldown = def.cooldown or existing.cooldown
    existing.enabled  = def.enabled or existing.enabled
    existing.run      = def.run or existing.run
    return existing
  end

  def.weight      = def.weight or 5
  def.cooldown    = def.cooldown or 2
  def.lastRun     = -1e9
  def.lastOk      = nil
  def.failStreak  = 0
  def.runs        = 0
  def.lastResult  = "-"
  def.stats       = { ok = 0, fail = 0 }

  Jobs.n = Jobs.n + 1
  Jobs.list[Jobs.n] = def
  Jobs.byId[def.id] = def
  return def
end

function Jobs.get(id)
  return Jobs.byId[id]
end

function Jobs.enabled(def)
  if Jobs.paused then return false end
  if def.enabled then
    local ok, res = pcall(def.enabled)
    if ok then return res == true end
    return false
  end
  return RR.Cfg.get("job." .. def.id, true) == true
end

-- effective cooldown grows with consecutive failures, capped
function Jobs.ready(def, now)
  local cd = def.cooldown or 2
  if def.failStreak > 0 then
    cd = cd * (1 + math.min(def.failStreak, 5))
  end
  return (now - (def.lastRun or -1e9)) >= cd
end

function Jobs.pick(now)
  local best, bestWeight = nil, -1
  for i = 1, Jobs.n do
    local def = Jobs.list[i]
    if Jobs.enabled(def) and Jobs.ready(def, now) then
      local w = def.weight or 5
      if w > bestWeight then
        best, bestWeight = def, w
      end
    end
  end
  return best
end

-- run at most one job per call; the caller decides the cadence
function Jobs.tick()
  if not RR.World.ready() then return end
  local now = tick()
  local def = Jobs.pick(now)
  if not def then return end

  def.lastRun = now
  def.runs = def.runs + 1
  Jobs.Stats.runs = Jobs.Stats.runs + 1
  Jobs.Stats.lastId = def.id

  local ok, result = pcall(def.run)
  if not ok then
    def.failStreak = def.failStreak + 1
    def.stats.fail = def.stats.fail + 1
    def.lastOk = false
    def.lastResult = "error: " .. tostring(result)
    Jobs.Stats.fail = Jobs.Stats.fail + 1
    RR.Log.add("error", "job " .. def.id .. " threw: " .. tostring(result))
    return
  end

  if result == true then
    def.failStreak = 0
    def.lastOk = true
    def.stats.ok = def.stats.ok + 1
    def.lastResult = "ok"
    Jobs.Stats.ok = Jobs.Stats.ok + 1
  else
    def.failStreak = def.failStreak + 1
    def.lastOk = false
    def.lastResult = tostring(result or "no action")
    if def.failStreak >= 3 then
      RR.Log.add("warn", "job " .. def.id .. " cooling down: " .. def.lastResult)
    end
  end
end

function Jobs.summary()
  local s = Jobs.Stats
  return string.format("%d jobs, %d runs (%d ok / %d fail)", Jobs.n, s.runs, s.ok, s.fail)
end

-- ======================================================================
-- 40_ui.lua
-- ======================================================================
--[[ ==================================================================
     40_ui : Drawing-based menu

     Instance.new is not available, so there is no ScreenGui anywhere.
     The menu is a stack of Drawing squares and text, laid out on a grid
     and hit-tested against the real mouse position from Player:GetMouse.
     Input is read, never injected, so the panel works even while the
     focus gate is closed.
     ================================================================== ]]

local RR = _G.RR
local UI = RR.UI or {}
RR.UI = UI

UI.visible  = false
UI.controls = {}
UI.pool     = { text = {}, square = {} }
UI.textN    = 0
UI.squareN  = 0
UI.x        = 40
UI.y        = 110
UI.width    = 320
UI.rowH     = 21
UI.pad      = 10
UI.headerH  = 34
UI.scale    = 1

local COL = {
  bg      = Color3.fromRGB(18, 18, 22),
  header  = Color3.fromRGB(38, 40, 52),
  accent  = Color3.fromRGB(120, 200, 140),
  text    = Color3.fromRGB(226, 228, 236),
  dim     = Color3.fromRGB(140, 144, 160),
  ok      = Color3.fromRGB(120, 210, 130),
  bad     = Color3.fromRGB(230, 110, 110),
  rowOn   = Color3.fromRGB(48, 62, 52),
  rowOff  = Color3.fromRGB(30, 30, 38),
}
UI.COL = COL

local lastDown = false

-- ---------------------------------------------------------------------
-- pools
-- ---------------------------------------------------------------------
local function textObj()
  UI.textN = UI.textN + 1
  local t = UI.pool.text[UI.textN]
  if not t then
    t = Drawing.new("Text")
    t.Outline = true
    t.Center = false
    t.Font = 0
    t.FontSize = 14
    t.Visible = false
    UI.pool.text[UI.textN] = t
  end
  return t
end

local function squareObj()
  UI.squareN = UI.squareN + 1
  local s = UI.pool.square[UI.squareN]
  if not s then
    s = Drawing.new("Square")
    s.Filled = true
    s.Thickness = 1
    s.Visible = false
    UI.pool.square[UI.squareN] = s
  end
  return s
end

local function resetPools()
  for i = 1, UI.textN do
    local t = UI.pool.text[i]
    if t then t.Visible = false end
  end
  for i = 1, UI.squareN do
    local s = UI.pool.square[i]
    if s then s.Visible = false end
  end
  UI.textN = 0
  UI.squareN = 0
end

-- ---------------------------------------------------------------------
-- control registration
-- ---------------------------------------------------------------------
function UI.addToggle(id, label, getFn, setFn)
  UI.controls[#UI.controls + 1] = {
    kind = "toggle", id = id, label = label, get = getFn, set = setFn, h = UI.rowH,
  }
end

function UI.addButton(label, fn)
  UI.controls[#UI.controls + 1] = {
    kind = "button", label = label, fn = fn, h = UI.rowH,
  }
end

function UI.addLabel(fn)
  UI.controls[#UI.controls + 1] = {
    kind = "label", fn = fn, h = UI.rowH - 4,
  }
end

function UI.addHeader(text)
  UI.controls[#UI.controls + 1] = {
    kind = "header", text = text, h = UI.rowH + 4,
  }
end

function UI.clear()
  UI.controls = {}
end

-- ---------------------------------------------------------------------
-- input
-- ---------------------------------------------------------------------
local function mousePos()
  local p = RR.Util.localPlayer()
  if not p then return -1, -1 end
  local m = nil
  pcall(function() m = p:GetMouse() end)
  if not m then return -1, -1 end
  local x, y = -1, -1
  pcall(function()
    x = m.X
    y = m.Y
  end)
  return x, y
end

local function clicked()
  local down = false
  pcall(function() down = ismouse1pressed() end)
  local fired = down and not lastDown
  lastDown = down
  return fired
end

local function inRect(px, py, x, y, w, h)
  return px >= x and px <= x + w and py >= y and py <= y + h
end

-- ---------------------------------------------------------------------
-- layout + draw
-- ---------------------------------------------------------------------
local function totalHeight()
  local h = UI.headerH + UI.pad
  for i = 1, #UI.controls do
    h = h + UI.controls[i].h
  end
  return h + UI.pad
end

function UI.toggleVisible()
  UI.visible = not UI.visible
  if not UI.visible then resetPools() end
end

function UI.draw()
  if not UI.visible then return end

  local mx, my = mousePos()
  local fire = clicked()

  resetPools()

  local x, y = UI.x, UI.y
  local w = UI.width
  local height = totalHeight()

  local bg = squareObj()
  bg.Color = COL.bg
  bg.Transparency = 0.12
  bg.Position = Vector2.new(x, y)
  bg.Size = Vector2.new(w, height)
  bg.Visible = true

  local head = squareObj()
  head.Color = COL.header
  head.Transparency = 0.05
  head.Position = Vector2.new(x, y)
  head.Size = Vector2.new(w, UI.headerH)
  head.Visible = true

  local title = textObj()
  title.Text = "RUN A RESTAURANT  v" .. RR.VERSION
  title.Color = COL.text
  title.FontSize = 15
  title.Position = Vector2.new(x + UI.pad, y + 8)
  title.Visible = true

  local hint = textObj()
  hint.Text = UI.visible and "INSERT to hide" or "INSERT to show"
  hint.Color = COL.dim
  hint.FontSize = 11
  hint.Position = Vector2.new(x + w - 104, y + 11)
  hint.Visible = true

  local cy = y + UI.headerH + UI.pad

  for i = 1, #UI.controls do
    local c = UI.controls[i]

    if c.kind == "header" then
      local t = textObj()
      t.Text = string.upper(c.text)
      t.Color = COL.accent
      t.FontSize = 11
      t.Position = Vector2.new(x + UI.pad, cy + 4)
      t.Visible = true
      cy = cy + c.h

    elseif c.kind == "label" then
      local ok, txt = pcall(c.fn)
      if ok and txt ~= nil then
        local t = textObj()
        t.Text = tostring(txt)
        t.Color = COL.dim
        t.FontSize = 12
        t.Position = Vector2.new(x + UI.pad, cy + 2)
        t.Visible = true
      end
      cy = cy + c.h

    elseif c.kind == "toggle" then
      local on = false
      local ok = pcall(function() on = c.get() == true end)
      if not ok then on = false end

      local row = squareObj()
      row.Color = on and COL.rowOn or COL.rowOff
      row.Transparency = 0.35
      row.Position = Vector2.new(x + 4, cy)
      row.Size = Vector2.new(w - 8, c.h - 2)
      row.Visible = true

      local box = squareObj()
      box.Color = on and COL.ok or COL.dim
      box.Transparency = 0
      box.Position = Vector2.new(x + UI.pad, cy + 6)
      box.Size = Vector2.new(9, 9)
      box.Visible = true

      local t = textObj()
      t.Text = c.label
      t.Color = on and COL.text or COL.dim
      t.FontSize = 13
      t.Position = Vector2.new(x + UI.pad + 18, cy + 3)
      t.Visible = true

      if fire and inRect(mx, my, x + 4, cy, w - 8, c.h - 2) then
        pcall(function() c.set(not on) end)
      end
      cy = cy + c.h

    elseif c.kind == "button" then
      local hover = inRect(mx, my, x + 4, cy, w - 8, c.h - 2)
      local row = squareObj()
      row.Color = hover and COL.header or COL.rowOff
      row.Transparency = 0.25
      row.Position = Vector2.new(x + 4, cy)
      row.Size = Vector2.new(w - 8, c.h - 2)
      row.Visible = true

      local t = textObj()
      t.Text = c.label
      t.Color = hover and COL.text or COL.dim
      t.FontSize = 13
      t.Position = Vector2.new(x + UI.pad, cy + 3)
      t.Visible = true

      if fire and hover then
        pcall(c.fn)
      end
      cy = cy + c.h
    end
  end
end

-- ---------------------------------------------------------------------
-- toggle key
-- ---------------------------------------------------------------------
UI.key = 0x2D  -- INSERT
local lastKey = false

function UI.pollKey()
  local down = false
  pcall(function() down = iskeypressed(UI.key) end)
  if down and not lastKey then
    UI.toggleVisible()
  end
  lastKey = down
end

function UI.destroy()
  resetPools()
  for i = 1, #UI.pool.text do
    pcall(function() UI.pool.text[i]:Remove() end)
  end
  for i = 1, #UI.pool.square do
    pcall(function() UI.pool.square[i]:Remove() end)
  end
  UI.pool = { text = {}, square = {} }
  UI.textN, UI.squareN = 0, 0
end

-- ======================================================================
-- 50_jobs_world.lua
-- ======================================================================
--[[ ==================================================================
     50_jobs_world : the jobs we can prove exist

     Every target below was read out of the live place by the scanner
     dump, so these are not guesses:

       __DEBRIS.DailyQuestNPC.HumanoidRootPart.ProximityPrompt
       __DEBRIS.HarvestMiniGameNPC.HumanoidRootPart.ProximityPrompt
       __DEBRIS.HarvestShopNPC.HumanoidRootPart.ProximityPrompt
       __DEBRIS.ShopNPC.HumanoidRootPart.ProximityPrompt
       __DEBRIS.FishermanNPC.HumanoidRootPart.ProximityPrompt
       __THINGS.SpinWheel.Interact.ProximityPrompt
       __THINGS.CornMazeEntrance.Door.ProximityPrompt
       __THINGS.Gnomes.Gnome.__SecretGnomeClickDetector

     These are the free progression loops: daily quests, the harvest
     minigame, the shop, the fisherman, the spin wheel, the corn maze
     and the secret gnome. They run while the restaurant work happens.
     ================================================================== ]]

local RR = _G.RR
local W = RR.World
local Jobs = RR.Jobs

local function nearestPrompt(pattern, maxDist)
  local best, bestDist = nil, maxDist or 140
  local list = W.livePrompts()
  local inc, exc = W.parsePattern(pattern)

  for i = 1, #list do
    local p = list[i]
    local score = W.score(string.lower(p.aname), inc, exc)
    if not score then
      score = W.score(string.lower(p.name), inc, exc)
    end
    if score then
      local me = RR.Util.charPos()
      if me then
        local d = (me - p.pos).Magnitude
        if d <= bestDist then
          best, bestDist = p, d
        end
      end
    end
  end
  return best, bestDist
end

local function promptJob(pattern, label, weight, cooldown, keyless)
  return Jobs.add({
    id = "world." .. label,
    label = label,
    weight = weight,
    cooldown = cooldown,
    enabled = function() return RR.Cfg.get("job." .. label, true) == true end,
    run = function()
      local p = nearestPrompt(pattern, 160)
      if not p then return "nothing to interact with" end
      if not keyless and not RR.Input.focused() then return "roblox not focused" end
      local ok, why = RR.Act.prompt(p, { tol = 5, timeout = 12 })
      if ok then
        RR.log(label .. ": " .. p.aname .. " -> " .. tostring(why))
      end
      return ok and true or ("failed: " .. tostring(why))
    end,
  })
end

promptJob("DailyQuest",       "quests",     8, 30)
promptJob("SpinWheel",        "spinwheel",  7, 90)
promptJob("HarvestMiniGame",  "harvest",    7, 45)
promptJob("HarvestShop",      "harvestshop", 4, 120)
promptJob("ShopNPC",          "shop",       4, 120)
promptJob("Fisherman",        "fisherman",  4, 120)
promptJob("CornMaze",         "cornmaze",   3, 180)

-- the gnome is a ClickDetector, not a prompt
Jobs.add({
  id = "world.gnome",
  label = "gnome",
  weight = 2,
  cooldown = 300,
  enabled = function() return RR.Cfg.get("job.gnome", true) == true end,
  run = function()
    local s = RR.World.state
    if not s.clicks or s.clickCount == 0 then return "no click detectors" end

    local me = RR.Util.charPos()
    if not me then return "no character" end

    local best, bestDist = nil, 90
    for i = 1, s.clickCount do
      local c = s.clicks[i]
      local pos = W.posOf(c.anchor)
      if pos then
        local d = (me - pos).Magnitude
        if d <= bestDist then
          best, bestDist = c, d
        end
      end
    end
    if not best then return "no gnome nearby" end

    local ok, why = RR.Act.clickDetector(best, { timeout = 14 })
    if ok then RR.log("gnome clicked") end
    return ok and true or ("failed: " .. tostring(why))
  end,
})

-- housekeeping: keep the snapshot fresh without stalling the game
Jobs.add({
  id = "world.rescan",
  label = "rescan",
  weight = 1,
  cooldown = 600,
  enabled = function() return true end,
  run = function()
    if RR.World.state.scanning then return "already scanning" end
    RR.World.scan()
    return true
  end,
})

-- ======================================================================
-- 60_main.lua
-- ======================================================================
--[[ ==================================================================
     60_main : wiring

     Two loops, deliberately separate:

       RenderStepped  - drawing, key polling, world snapshot slicing.
                        Never yields, so the menu stays at frame rate.
       worker thread  - jobs, movement, waiting. Everything here is
                        allowed to block for seconds without touching
                        the render path.
     ================================================================== ]]

local RR = _G.RR
local W = RR.World
local Jobs = RR.Jobs
local UI = RR.UI

RR.stopped = false

local RunService = RR.svc("RunService")

-- ---------------------------------------------------------------------
-- wait for a character before doing anything that needs one
-- ---------------------------------------------------------------------
local function waitForCharacter(timeout)
  local deadline = tick() + (timeout or 60)
  while tick() < deadline do
    if RR.Util.hrp() and RR.Util.alive() then return true end
    wait(0.25)
  end
  -- a dead character still has a HumanoidRootPart, and a respawn will
  -- restore health, so treat "has root" as good enough
  return RR.Util.hrp() ~= nil
end

-- ---------------------------------------------------------------------
-- report
-- ---------------------------------------------------------------------
function RR.dumpReport()
  local lines = {}
  lines[#lines + 1] = "Run a Restaurant! toolkit " .. RR.VERSION
  local stamp = "unknown time"
  pcall(function() stamp = os.date("%Y-%m-%d %H:%M:%S") end)
  lines[#lines + 1] = "generated " .. tostring(stamp)
  lines[#lines + 1] = ""
  lines[#lines + 1] = "== capabilities =="
  lines[#lines + 1] = RR.Caps.report
  lines[#lines + 1] = ""
  lines[#lines + 1] = "== world =="
  lines[#lines + 1] = W.summary()
  lines[#lines + 1] = ""
  lines[#lines + 1] = "== movement =="
  lines[#lines + 1] = RR.Move.summary()
  lines[#lines + 1] = ""
  lines[#lines + 1] = "== interaction =="
  lines[#lines + 1] = RR.Act.summary()
  lines[#lines + 1] = RR.Input.summary()
  lines[#lines + 1] = ""
  lines[#lines + 1] = "== jobs =="
  for i = 1, Jobs.n do
    local d = Jobs.list[i]
    lines[#lines + 1] = string.format("%-18s w=%-2d runs=%-4d ok=%-4d fail=%-3d %s",
      d.id, d.weight, d.runs, d.stats.ok, d.stats.fail, tostring(d.lastResult))
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "== prompts in place =="
  local plist = W.livePrompts()
  for i = 1, #plist do
    local p = plist[i]
    lines[#lines + 1] = string.format("  %-32s at %.0f, %.0f, %.0f",
      p.aname .. " / " .. p.name, p.pos.X, p.pos.Y, p.pos.Z)
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "== log tail =="
  lines[#lines + 1] = RR.Log.text(60)

  local body = table.concat(lines, "\n")
  local ok = pcall(function() writefile("runrestaurant_report.txt", body) end)
  if ok then RR.log("report written to runrestaurant_report.txt") end
  return ok, body
end

-- ---------------------------------------------------------------------
-- menu
-- ---------------------------------------------------------------------
local function buildUI()
  UI.clear()

  UI.addHeader("Status")
  UI.addLabel(function() return "world   : " .. W.summary() end)
  UI.addLabel(function() return "move    : " .. RR.Move.summary() end)
  UI.addLabel(function() return "interact: " .. RR.Act.summary() end)
  UI.addLabel(function() return "input   : " .. RR.Input.summary() end)
  UI.addLabel(function()
    local d = Jobs.Stats
    return string.format("jobs    : %d runs, %d ok, %d fail, last %s", d.runs, d.ok, d.fail, tostring(d.lastId))
  end)

  UI.addHeader("Job toggles")
  local toggles = {
    { "quests",     "Daily quests" },
    { "spinwheel",  "Spin wheel" },
    { "harvest",    "Harvest minigame" },
    { "harvestshop", "Harvest shop" },
    { "shop",       "Shop NPC" },
    { "fisherman",  "Fisherman" },
    { "cornmaze",   "Corn maze door" },
    { "gnome",      "Secret gnome" },
  }
  for i = 1, #toggles do
    local key = toggles[i][1]
    local label = toggles[i][2]
    UI.addToggle(key, label,
      function() return RR.Cfg.get("job." .. key, true) == true end,
      function(v) RR.Cfg.set("job." .. key, v) end)
  end

  UI.addHeader("Movement")
  UI.addToggle("movewrite", "Allow position writes",
    function() return RR.Cfg.get("moveMode", "position") ~= "walk" end,
    function(v) RR.Move.setMode(v and "position" or "walk") end)

  UI.addHeader("System")
  UI.addToggle("focus", "Act only when game focused",
    function() return RR.Cfg.get("requireFocus", true) == true end,
    function(v) RR.Cfg.set("requireFocus", v) end)
  UI.addToggle("logfile", "Write log to file",
    function() return RR.Log.toFile == true end,
    function(v) RR.Log.toFile = v end)

  UI.addHeader("Actions")
  UI.addButton("Rescan world", function() W.scan() end)
  UI.addButton("Run capability probe", function() RR.Caps.probe() end)
  UI.addButton("Write report file", function() RR.dumpReport() end)
  UI.addButton("Save config", function() RR.Cfg.save() end)
  UI.addButton("Stop toolkit", function() RR.stop() end)
end

function RR.stop()
  RR.stopped = true
  Jobs.paused = true
  pcall(function() RR.Move.stop() end)
  pcall(function() RR.Input.releaseAll() end)
  pcall(function() RR.Cfg.save() end)
  pcall(function() RR.Log.flush() end)
  pcall(function() UI.destroy() end)
  RR.log("toolkit stopped")
end

-- ---------------------------------------------------------------------
-- boot
-- ---------------------------------------------------------------------
local function boot()
  RR.Cfg.load()
  RR.Cfg.set("capsMoveTest", RR.Cfg.get("capsMoveTest", true))

  waitForCharacter(45)

  pcall(function() RR.Caps.probe() end)
  pcall(function() W.scan() end)

  buildUI()

  if RunService then
    local ok = pcall(function()
      RunService.RenderStepped:Connect(function()
        if RR.stopped then return end
        pcall(UI.pollKey)
        pcall(UI.draw)
        pcall(W.step)
      end)
    end)
    if not ok then RR.warn("RenderStepped hook failed; world scan will run in the worker") end
  end

  task.spawn(function()
    local lastSave = tick()
    local lastScanPush = tick()

    if not RunService then
      -- fallback: scan from the worker instead of the render path
      while not RR.stopped do
        W.step()
        wait(0.02)
      end
    end

    while not RR.stopped do
      wait(0.06)

      if not W.state.scanning and W.ready() and not Jobs.paused then
        pcall(Jobs.tick)
      end

      if tick() - lastScanPush > 1 and W.state.scanning then
        lastScanPush = tick()
        pcall(W.step)
      end

      if tick() - lastSave > 30 then
        lastSave = tick()
        if RR.Cfg.dirty then pcall(RR.Cfg.save) end
        pcall(RR.Log.flush)
      end
    end
  end)

  RR.log("toolkit ready - press INSERT for the menu")
  pcall(function()
    notify("v" .. RR.VERSION .. " loaded - INSERT for menu",
      "Run a Restaurant", 5)
  end)
end

task.spawn(function()
  local ok, err = pcall(boot)
  if not ok then
    RR.err("boot failed: " .. tostring(err))
  end
end)