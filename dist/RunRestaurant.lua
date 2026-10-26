-- Run a Restaurant! - Matcha toolkit
-- built 2026-10-26 03:13
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

RR.VERSION  = "5.1.0"
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

-- camera viewport, with a sane fallback so callers never nil-index
function Util.viewport()
  local ws = svc("Workspace")
  if not ws then return Vector2.new(1280, 720) end
  local cam = nil
  pcall(function() cam = ws.CurrentCamera end)
  if not cam then return Vector2.new(1280, 720) end
  local vp = nil
  pcall(function() vp = cam.ViewportSize end)
  if vp then return vp end
  return Vector2.new(1280, 720)
end

-- world -> screen, nil when behind the camera or the projection failed.
-- WorldToScreen returns (Vector2, bool) so both results matter.
function Util.project(pos)
  if not pos then return nil end
  local sp, onScreen = nil, false
  local ok = pcall(function() sp, onScreen = WorldToScreen(pos) end)
  if not ok or onScreen ~= true or not sp then return nil end
  return sp
end

-- pixel distance from the centre of the screen; math.huge when off-screen.
-- lower means "closer to where the camera is looking", which is how
-- Roblox picks which of several in-range prompts is the visible one.
function Util.focusScore(pos)
  local sp = Util.project(pos)
  if not sp then return math.huge end
  local vp = Util.viewport()
  local dx = sp.X - (vp.X / 2)
  local dy = sp.Y - (vp.Y / 2)
  return math.sqrt(dx * dx + dy * dy)
end

-- ---------------------------------------------------------------------
-- GUI geometry
-- ---------------------------------------------------------------------
-- A button is only really clickable when every ancestor is visible and
-- its ScreenGui is enabled. Reading .Visible on the button alone reports
-- every hidden menu in PlayerGui as clickable, and then the click lands
-- on whatever is behind it.
function Util.guiShown(obj)
  if not obj then return false end
  local cur = obj
  for _ = 1, 32 do
    local vis, en, cls, parent = nil, nil, nil, nil
    pcall(function()
      vis = cur.Visible
      en = cur.Enabled
      cls = cur.ClassName
      parent = cur.Parent
    end)

    if vis == false then return false end
    if en == false then return false end
    if cls == "PlayerGui" or parent == nil then return true end
    cur = parent
  end
  return false
end

-- centre of a GuiObject, in the same pixel space as mousemoveabs and
-- Camera.ViewportSize. AbsolutePosition/AbsoluteSize are already
-- resolved to pixels by the engine, so no UDim2 arithmetic is needed.
function Util.guiCenter(obj)
  local ap, as = nil, nil
  pcall(function()
    ap = obj.AbsolutePosition
    as = obj.AbsoluteSize
  end)
  if not ap or not as then return nil end
  if as.X <= 1 or as.Y <= 1 then return nil end
  return Vector2.new(ap.X + (as.X / 2), ap.Y + (as.Y / 2))
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
  -- If this is Scriptable, mouse-drag steering does nothing and walk mode
  -- has to give up instead of spinning in place.
  local ctype = tryRead(cam, "CameraType")
  if ctype ~= nil then
    local n = nil
    pcall(function() n = ctype.Name end)
    out.cameraType = n or string.match(tostring(ctype), "([%w_]+)$")
  end
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
  out.clickable = tryRead(prompt, "ClickablePrompt")
  out.objectText = tryRead(prompt, "ObjectText")
  out.actionText = tryRead(prompt, "ActionText")

  -- The exact value the bridge hands back matters: an Enum.KeyCode's
  -- .Value is ASCII (E = 101), a VK is 69, and pressing the wrong one
  -- silently does nothing.
  out.keyRaw  = tostring(out.keyCode)
  out.keyVK   = RR.KeyMap.resolve(out.keyCode, nil)
  out.keyDesc = RR.KeyMap.describe(out.keyCode)

  local excl = tryRead(prompt, "Exclusivity")
  if excl ~= nil then
    local n = nil
    pcall(function() n = excl.Name end)
    out.exclusivity = n or string.match(tostring(excl), "([%w_]+)$")
  end

  -- Does the class method exist? Only checked, never called: calling it
  -- on a live prompt could trigger it.
  out.inputHold = false
  pcall(function() out.inputHold = type(prompt.InputHoldBegin) == "function" end)

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

-- Tools are the interaction surface the original scan could not see:
-- the workspace had zero Tool instances because everything sits in the
-- Backpack or the character's hand. Names here drive the hotbar jobs.
local function probeTools()
  local out = { backpack = 0, equipped = 0, names = {} }

  local lp = RR.Util.localPlayer()
  if not lp then return out end

  local function scan(container, key)
    if not container then return end
    local kids = nil
    local ok = pcall(function() kids = container:GetChildren() end)
    if not ok or type(kids) ~= "table" then return end
    for i = 1, #kids do
      local child = kids[i]
      if tryRead(child, "ClassName") == "Tool" then
        out[key] = out[key] + 1
        if #out.names < 24 then
          out.names[#out.names + 1] = tostring(tryRead(child, "Name"))
        end
      end
    end
  end

  local bp = nil
  pcall(function() bp = lp:FindFirstChildOfClass("Backpack") end)
  scan(bp, "backpack")

  local ch = nil
  pcall(function() ch = lp.Character end)
  scan(ch, "equipped")

  out.canActivate = false
  if bp then
    local kids = nil
    pcall(function() kids = bp:GetChildren() end)
    for i = 1, #(kids or {}) do
      if tryRead(kids[i], "ClassName") == "Tool" then
        pcall(function() out.canActivate = type(kids[i].Activate) == "function" end)
        break
      end
    end
  end

  return out
end

-- GUI recon: the menus are the part of the game no workspace scan can
-- see, and their labels are the game's own vocabulary for every action
-- it offers. This is usually the most useful section of the report.
local function probeGui()
  local out = { count = 0, screens = {}, labels = {}, readable = false }

  local lp = RR.Util.localPlayer()
  if not lp then return out end

  local pg = nil
  pcall(function() pg = lp:FindFirstChildOfClass("PlayerGui") end)
  if not pg then return out end

  local list = nil
  local ok = pcall(function() list = pg:GetDescendants() end)
  if not ok or type(list) ~= "table" then return out end
  out.readable = true

  for i = 1, #list do
    local o = list[i]
    local cls = tryRead(o, "ClassName")

    if cls == "ScreenGui" then
      if #out.screens < 14 then
        out.screens[#out.screens + 1] = tostring(tryRead(o, "Name"))
      end
    elseif cls == "TextButton" or cls == "ImageButton" then
      if RR.Util.guiShown(o) then
        out.count = out.count + 1
        local label = tryRead(o, "Text")
        if type(label) == "string" and label ~= "" and #out.labels < 20 then
          out.labels[#out.labels + 1] = label
        end
      end
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
  d.tools = probeTools()
  d.gui = probeGui()

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
  out[#out + 1] = "prompt        : " .. (d.prompt.found and ("key=" .. yn(d.prompt.keyDesc) .. " hold=" .. yn(d.prompt.hold) .. " range=" .. yn(d.prompt.maxDist) .. " los=" .. yn(d.prompt.requiresLineOfSight) .. " click=" .. yn(d.prompt.clickable) .. " inputHold=" .. yn(d.prompt.inputHold)) or "none in workspace")
  out[#out + 1] = "prompt excl   : " .. yn(d.prompt.exclusivity)
  out[#out + 1] = "movement      : mode=" .. tostring(d.move.mode) .. " pos=" .. yn(d.move.positionStuck) .. " vel=" .. yn(d.move.velocityMoved)
  out[#out + 1] = "camera type   : " .. yn(d.camera.cameraType)
  out[#out + 1] = "replicatedstg : " .. yn(d.storage.replicatedStorage) .. " children=" .. yn(d.storage.replicatedStorageChildren)
  out[#out + 1] = "backpack      : " .. yn(d.storage.backpack) .. " items=" .. yn(d.storage.backpackItems)
  out[#out + 1] = "playergui     : " .. yn(d.storage.playerGui) .. " nodes=" .. yn(d.storage.playerGuiDescendants)
  local tools = d.tools or {}
  local tnames = tools.names or {}
  out[#out + 1] = "tools         : bag=" .. yn(tools.backpack) .. " held=" .. yn(tools.equipped) .. " activate=" .. yn(tools.canActivate)
  if #tnames > 0 then
    out[#out + 1] = "tool names    : " .. table.concat(tnames, ", ")
  end
  local gui = d.gui or {}
  out[#out + 1] = "gui           : readable=" .. yn(gui.readable) .. " buttons=" .. yn(gui.count)
  local screens = gui.screens or {}
  if #screens > 0 then
    out[#out + 1] = "gui screens   : " .. table.concat(screens, ", ")
  end
  local labels = gui.labels or {}
  if #labels > 0 then
    out[#out + 1] = "gui buttons   : " .. table.concat(labels, " | ")
  end
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
-- 12_keymap.lua
-- ======================================================================
--[[ ==================================================================
     12_keymap : Roblox KeyCode  ->  Windows virtual-key

     This module exists because of a bug that would have made every
     prompt press land on the wrong key.

     Roblox's KeyCode enum is not a Windows VK code. It reuses ASCII:

         Enum.KeyCode.A   = 97    ('a')      Windows VK_A  = 65
         Enum.KeyCode.E   = 101   ('e')      Windows VK_E  = 69
         Enum.KeyCode.Z   = 122   ('z')      Windows VK_Z  = 90

     So reading `.Value` and handing it to keypress() presses numpad
     keys: 101 is VK_NUMPAD5, not E. The cheat never fires, the prompt
     never opens, and nothing in the log says why.

     Everything here is pure: no services, no globals, no side effects,
     so tests/ can execute it under a real Luau VM.

     Reference: https://create.roblox.com/docs/reference/engine/enums/KeyCode
     ================================================================== ]]

local RR = rawget(_G, "RR")
if type(RR) ~= "table" then
  RR = {}
  _G.RR = RR
end

local KeyMap = RR.KeyMap or {}
RR.KeyMap = KeyMap

-- ---------------------------------------------------------------------
-- named constants (VK)
-- ---------------------------------------------------------------------
KeyMap.VK = {
  A = 0x41, B = 0x42, C = 0x43, D = 0x44, E = 0x45, F = 0x46, G = 0x47,
  H = 0x48, I = 0x49, J = 0x4A, K = 0x4B, L = 0x4C, M = 0x4D, N = 0x4E,
  O = 0x4F, P = 0x50, Q = 0x51, R = 0x52, S = 0x53, T = 0x54, U = 0x55,
  V = 0x56, W = 0x57, X = 0x58, Y = 0x59, Z = 0x5A,

  DIGIT0 = 0x30, DIGIT1 = 0x31, DIGIT2 = 0x32, DIGIT3 = 0x33, DIGIT4 = 0x34,
  DIGIT5 = 0x35, DIGIT6 = 0x36, DIGIT7 = 0x37, DIGIT8 = 0x38, DIGIT9 = 0x39,

  SPACE = 0x20, ENTER = 0x0D, ESC = 0x1B, TAB = 0x09, BACKSPACE = 0x08,
  SHIFT = 0x10, CTRL = 0x11, ALT = 0x12, CAPSLOCK = 0x14,
  LSHIFT = 0xA0, RSHIFT = 0xA1, LCTRL = 0xA2, RCTRL = 0xA3,
  LALT = 0xA4, RALT = 0xA5,

  LEFT = 0x25, UP = 0x26, RIGHT = 0x27, DOWN = 0x28,
  INSERT = 0x2D, DELETE = 0x2E, HOME = 0x24, END = 0x23,
  PAGEUP = 0x21, PAGEDOWN = 0x22,

  F1 = 0x70, F2 = 0x71, F3 = 0x72, F4 = 0x73, F5 = 0x74, F6 = 0x75,
  F7 = 0x76, F8 = 0x77, F9 = 0x78, F10 = 0x79, F11 = 0x7A, F12 = 0x7B,
}

local VK = KeyMap.VK

-- ---------------------------------------------------------------------
-- Roblox KeyCode -> VK
-- ---------------------------------------------------------------------
-- Only codes that are unambiguously Roblox KeyCodes go in this table.
-- Anything not listed returns nil and the caller decides the fallback;
-- guessing here means pressing a key nobody asked for.
local CODE_TO_VK = {
  [8]   = VK.BACKSPACE,
  [9]   = VK.TAB,
  [13]  = VK.ENTER,
  [27]  = VK.ESC,
  [32]  = VK.SPACE,
  [44]  = 0xBC,          -- Comma
  [45]  = 0xBD,          -- Minus
  [46]  = 0xBE,          -- Period
  [47]  = 0xBF,          -- Slash
  [59]  = 0xBA,          -- Semicolon
  [61]  = 0xBB,          -- Equals
  [91]  = 0xDB,          -- LeftBracket
  [92]  = 0xDC,          -- BackSlash
  [93]  = 0xDD,          -- RightBracket
  [96]  = 0xC0,          -- Backquote
  [127] = VK.DELETE,
  [273] = VK.UP,
  [274] = VK.DOWN,
  [275] = VK.RIGHT,
  [276] = VK.LEFT,
  [277] = VK.INSERT,
  [278] = VK.HOME,
  [279] = VK.END,
  [280] = VK.PAGEUP,
  [281] = VK.PAGEDOWN,
  [300] = 0x90,          -- NumLock
  [301] = VK.CAPSLOCK,
  [302] = 0x91,          -- ScrollLock
  [303] = VK.RSHIFT,
  [304] = VK.LSHIFT,
  [305] = VK.RCTRL,
  [306] = VK.LCTRL,
  [307] = VK.RALT,
  [308] = VK.LALT,
}

-- digits 48..57 are already VK 0x30..0x39
for i = 0, 9 do
  CODE_TO_VK[48 + i] = 0x30 + i
end

-- keypad 256..265 -> VK 0x60..0x69, then the operators
for i = 0, 9 do
  CODE_TO_VK[256 + i] = 0x60 + i
end
CODE_TO_VK[266] = 0x6E   -- KeypadPeriod
CODE_TO_VK[267] = 0x6F   -- KeypadDivide
CODE_TO_VK[268] = 0x6A   -- KeypadMultiply
CODE_TO_VK[269] = 0x6D   -- KeypadMinus
CODE_TO_VK[270] = 0x6B   -- KeypadPlus
CODE_TO_VK[271] = VK.ENTER
CODE_TO_VK[272] = 0xBB   -- KeypadEquals

-- F1..F12 are 282..293, which is VK 0x70..0x7B exactly
for i = 0, 11 do
  CODE_TO_VK[282 + i] = 0x70 + i
end

-- letters are 97..122 ('a'..'z'), which is VK 0x41..0x5A
for i = 0, 25 do
  CODE_TO_VK[97 + i] = 0x41 + i
end

function KeyMap.codeToVK(code)
  if type(code) ~= "number" then return nil end
  if code <= 0 then return nil end

  local vk = CODE_TO_VK[code]
  if vk then return vk end

  -- 65..90 is not a valid Roblox KeyCode at all, so a value in that
  -- range is already a virtual-key code for a letter. Pass it through.
  if code >= 65 and code <= 90 then return code end

  return nil
end

-- ---------------------------------------------------------------------
-- name -> VK
-- ---------------------------------------------------------------------
local NAME_TO_VK = {
  space = VK.SPACE, spacebar = VK.SPACE,
  ["return"] = VK.ENTER, enter = VK.ENTER,
  escape = VK.ESC, esc = VK.ESC,
  tab = VK.TAB, backspace = VK.BACKSPACE, delete = VK.DELETE,
  insert = VK.INSERT, home = VK.HOME, ["end"] = VK.END,
  pageup = VK.PAGEUP, pagedown = VK.PAGEDOWN,
  up = VK.UP, down = VK.DOWN, left = VK.LEFT, right = VK.RIGHT,
  leftshift = VK.LSHIFT, rightshift = VK.RSHIFT,
  leftcontrol = VK.LCTRL, rightcontrol = VK.RCTRL,
  leftctrl = VK.LCTRL, rightctrl = VK.RCTRL,
  leftalt = VK.LALT, rightalt = VK.RALT,
  capslock = VK.CAPSLOCK, numlock = 0x90, scrolllock = 0x91,
  zero = 0x30, one = 0x31, two = 0x32, three = 0x33, four = 0x34,
  five = 0x35, six = 0x36, seven = 0x37, eight = 0x38, nine = 0x39,
  keypadzero = 0x60, keypadone = 0x61, keypadtwo = 0x62, keypadthree = 0x63,
  keypadfour = 0x64, keypadfive = 0x65, keypadsix = 0x66, keypadseven = 0x67,
  keypadeight = 0x68, keypadnine = 0x69,
  semicolon = 0xBA, equals = 0xBB, comma = 0xBC, minus = 0xBD,
  period = 0xBE, slash = 0xBF, backquote = 0xC0,
  leftbracket = 0xDB, backslash = 0xDC, rightbracket = 0xDD,
}

for i = 1, 12 do
  NAME_TO_VK["f" .. i] = 0x6F + i
end

-- strips "Enum.KeyCode." / "KeyCode." / surrounding noise, lowercases
local function normalizeName(name)
  local s = tostring(name or "")
  s = string.lower(s)
  s = string.gsub(s, "^enum%.", "")
  s = string.gsub(s, "^keycode%.", "")
  s = string.gsub(s, "%s+", "")
  return s
end

function KeyMap.nameToVK(name)
  local n = normalizeName(name)
  if n == "" then return nil end

  local direct = NAME_TO_VK[n]
  if direct then return direct end

  -- a bare letter: "e" -> VK_E
  if #n == 1 then
    local byte = string.byte(n)
    if byte and byte >= 97 and byte <= 122 then
      return byte - 32
    end
    if byte and byte >= 48 and byte <= 57 then
      return byte
    end
  end

  return nil
end

-- ---------------------------------------------------------------------
-- resolve whatever the bridge handed us
-- ---------------------------------------------------------------------
-- Order matters: EnumItem.Name is authoritative, because .Value is the
-- ASCII-flavoured number that caused the original bug.
function KeyMap.resolve(value, fallback)
  if value == nil then return fallback end

  -- EnumItem / userdata / table with a Name field
  local n = nil
  pcall(function() n = value.Name end)
  if type(n) == "string" and n ~= "" then
    local vk = KeyMap.nameToVK(n)
    if vk then return vk end
  end

  -- EnumItem / number with a Value field
  local v = nil
  pcall(function() v = value.Value end)
  if type(v) == "number" then
    local vk = KeyMap.codeToVK(v)
    if vk then return vk end
  end

  if type(value) == "number" then
    return KeyMap.codeToVK(value) or fallback
  end

  if type(value) == "string" then
    -- "Enum.KeyCode.E"
    local tail = string.match(value, "([%w_]+)$")
    return KeyMap.nameToVK(tail or value) or fallback
  end

  return fallback
end

-- "E (0x45)" for reports
function KeyMap.describe(value)
  local vk = KeyMap.resolve(value, nil)
  if not vk then return "none" end

  local name = tostring(value)
  if type(value) == "number" then
    name = string.format("#%d", value)
  end
  return string.format("%s -> 0x%02X", name, vk)
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

-- The canonical table lives in 12_keymap so prompt keys and movement keys
-- cannot drift apart. Roblox KeyCode values are NOT VK codes; see that file.
Input.VK = RR.KeyMap.VK

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

-- Click a point that is already in viewport pixels, as returned by
-- GuiObject.AbsolutePosition/AbsoluteSize. Matcha documents mousemoveabs
-- as using the same pixel space as WorldToScreen and Camera.ViewportSize,
-- which is exactly the space AbsolutePosition resolves to, so no window
-- origin maths is needed.
function Input.clickScreen(x, y)
  if type(x) ~= "number" or type(y) ~= "number" then return false end
  if x ~= x or y ~= y then return false end -- NaN guard

  local vp = RR.Util.viewport()
  if x < 2 or y < 2 or x > vp.X - 2 or y > vp.Y - 2 then return false end
  if not Input.moveAbs(x, y) then return false end
  wait(0.05)
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
  return RR.Util.viewport()
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
-- Right-mouse drag is the only documented way to rotate the camera, and
-- it is a *held* gesture: pressing and releasing it every frame makes
-- the view jitter and wastes input. These two track the state so a walk
-- can hold the drag for its whole duration.
Move.aimHeld = false

function Move.aimBegin()
  if Move.aimHeld then return true end
  local ok = pcall(function() mouse2press() end)
  Move.aimHeld = ok and true or false
  return Move.aimHeld
end

function Move.aimEnd()
  if not Move.aimHeld then return false end
  pcall(function() mouse2release() end)
  Move.aimHeld = false
  return true
end

-- keepHeld: leave the right button down so the caller can steer again
-- without a press/release cycle around every correction.
function Move.lookAt(target, tolPx, maxMs, keepHeld)
  tolPx = tolPx or 45
  maxMs = maxMs or 900
  if not RR.Input.focused() then return false, "not focused" end

  local vp = viewport()
  local cx = vp.X / 2
  local cy = vp.Y / 2

  local held = Move.aimBegin()
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
      -- cap the step so one frame cannot spin past the target
      local stepX = RR.Util.clamp(dx * 0.42, -140, 140)
      local stepY = RR.Util.clamp(dy * 0.42, -110, 110)
      RR.Input.moveRel(stepX, stepY)
    else
      -- behind us: drag sideways in fixed steps until it is on screen
      RR.Input.moveRel(150, 0)
      searched = searched + 1
      if searched > 24 then break end
    end
    wait(0.03)
  end

  if not keepHeld then
    Move.aimEnd()
  end
  return converged, held and nil or "right-mouse drag unavailable"
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

  -- single exit so W is always released, even on the error paths
  local function finish(ok, why)
    RR.Input.keyUp(VK.W)
    Move.aimEnd()
    if ok then
      Move.Stats.arrived = Move.Stats.arrived + 1
    else
      Move.Stats.failed = Move.Stats.failed + 1
      Move.Stats.lastErr = why or "walk failed"
    end
    return ok, why
  end

  RR.Input.keyDown(VK.W)

  while tick() < deadline do
    if not RR.Util.alive() then
      return finish(false, "died")
    end

    local pos = RR.Util.charPos()
    if pos and (pos - target).Magnitude <= tol then
      return finish(true, "walk")
    end

    -- keep the right button held across corrections; releasing it every
    -- loop made the camera stutter and the walk slower
    Move.lookAt(target, 60, 260, true)

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

  return finish(false, "timeout")
end

function Move.stop()
  pcall(function() RR.Input.keyUp(VK.W) end)
  pcall(function() Move.aimEnd() end)
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
local function readField(inst, key, default)
  local v = nil
  local ok = pcall(function() v = inst[key] end)
  if ok and v ~= nil then return v end
  return default
end

local function readEnumName(v)
  if v == nil then return nil end
  local n = nil
  pcall(function() n = v.Name end)
  if type(n) == "string" and n ~= "" then return n end
  return string.match(tostring(v), "([%w_]+)$")
end

function World.livePrompts()
  local s = World.state
  local out = {}
  if not s.prompts then return out end
  for i = 1, s.promptCount do
    local p = s.prompts[i]
    local anchorPos = World.posOf(p.anchor)
    local enabled = readField(p.inst, "Enabled", true)
    if anchorPos and enabled ~= false then
      local key = readField(p.inst, "KeyboardKeyCode", nil)
      local maxDist = readField(p.inst, "MaxActivationDistance", 10)
      if type(maxDist) ~= "number" or maxDist <= 0 then maxDist = 10 end

      local hold = readField(p.inst, "HoldDuration", 0)
      if type(hold) ~= "number" or hold < 0 then hold = 0 end

      out[#out + 1] = {
        inst    = p.inst,
        anchor  = p.anchor,
        pos     = anchorPos,
        name    = readName(p.inst),
        aname   = clean(readName(p.anchor)),
        key     = key,
        vk      = RR.KeyMap.resolve(key, nil),
        hold    = hold,
        maxDist = maxDist,
        los     = readField(p.inst, "RequiresLineOfSight", true) == true,
        clickable = readField(p.inst, "ClickablePrompt", false) == true,
        exclName  = readEnumName(readField(p.inst, "Exclusivity", nil)) or "OnePerButton",
        action  = tostring(readField(p.inst, "ActionText", "")),
        object  = tostring(readField(p.inst, "ObjectText", "")),
      }
    end
  end
  return out
end

function World.summary()
  local s = World.state
  return string.format("%d items, %d prompts, %d clicks, scan %.0f ms",
    s.itemCount, s.promptCount, s.clickCount, s.buildMs)
end

-- ---------------------------------------------------------------------
-- GUI buttons
-- ---------------------------------------------------------------------
-- Not part of the workspace scan: PlayerGui is rebuilt by client scripts
-- every time a menu opens, so this is read on demand instead of cached.
-- A button's label lives in .Text, and half these menus have no useful
-- instance name, so both are searched.
function World.guiButtons()
  local out = {}
  local lp = RR.Util.localPlayer()
  if not lp then return out end

  local pg = nil
  pcall(function() pg = lp:FindFirstChildOfClass("PlayerGui") end)
  if not pg then return out end

  local list = nil
  local ok = pcall(function() list = pg:GetDescendants() end)
  if not ok or type(list) ~= "table" then return out end

  for i = 1, #list do
    local o = list[i]
    local cls = nil
    pcall(function() cls = o.ClassName end)
    if cls == "TextButton" or cls == "ImageButton" then
      if RR.Util.guiShown(o) then
        local centre = RR.Util.guiCenter(o)
        if centre then
          local text, name = "", ""
          pcall(function()
            text = tostring(o.Text or "")
            name = tostring(o.Name or "")
          end)
          out[#out + 1] = {
            inst  = o,
            cls   = cls,
            name  = name,
            text  = text,
            pos   = centre,
          }
        end
      end
    end
  end

  return out
end

-- best-scoring visible button for a pattern; matches name and label
function World.findGui(pattern, maxResults)
  local inc, exc = World.parsePattern(pattern)
  if #inc == 0 then return {} end
  local list = World.guiButtons()
  local hits = {}
  for i = 1, #list do
    local b = list[i]
    local hay = string.lower(b.name .. " " .. b.text)
    local sc = World.score(hay, inc, exc)
    if sc then
      b.score = sc
      hits[#hits + 1] = b
    end
  end
  table.sort(hits, function(a, b) return a.score > b.score end)
  if maxResults and #hits > maxResults then
    local cut = {}
    for i = 1, maxResults do cut[i] = hits[i] end
    return cut
  end
  return hits
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
       - a Tool in the hotbar, equipped with its number key

     Anything the game does through a RemoteEvent is out of reach, and
     this place has exactly one RemoteEvent, so this is the toolkit.

     Two things here come straight out of the engine docs and were wrong
     in the first build:

     1. KeyboardKeyCode is an Enum.KeyCode, whose .Value is ASCII
        (E = 101), not a Windows virtual-key code (E = 69). Pressing 101
        hits numpad-5. src/12_keymap resolves this properly.

     2. A prompt only triggers when the client has it *active*, and only
        one prompt per key can be active at a time (Exclusivity defaults
        to OnePerButton). If a second prompt is closer to the centre of
        the screen, pressing the key activates that one instead. So a
        press is only meaningful once we have aimed at ours.

     Docs: ProximityPrompt, ProximityPromptExclusivity, ClickDetector.
     ================================================================== ]]

local RR = _G.RR
local Act = RR.Act or {}
RR.Act = Act

Act.Stats = Act.Stats or {
  prompts     = 0,
  promptOk    = 0,
  promptMiss  = 0,
  holdOk      = 0,
  rivals      = 0,
  clicks      = 0,
  clickOk     = 0,
  guiClicks   = 0,
  lastErr     = "",
}

local VK = RR.KeyMap.VK

-- prompt field with a fallback that never throws
local function field(inst, key, default)
  local v = nil
  local ok = pcall(function() v = inst[key] end)
  if ok and v ~= nil then return v end
  return default
end

-- enum item -> short name ("OnePerButton"), without assuming .Name exists
local function enumName(v)
  if v == nil then return nil end
  local n = nil
  pcall(function() n = v.Name end)
  if type(n) == "string" and n ~= "" then return n end
  local s = tostring(v)
  local tail = string.match(s, "([%w_]+)$")
  if tail then return tail end
  return nil
end

-- ---------------------------------------------------------------------
-- reading a prompt
-- ---------------------------------------------------------------------
-- Everything a press depends on, read once per attempt.
function Act.flags(prompt)
  local key = field(prompt, "KeyboardKeyCode", nil)

  local hold = field(prompt, "HoldDuration", 0)
  if type(hold) ~= "number" or hold < 0 then hold = 0 end

  local maxDist = field(prompt, "MaxActivationDistance", 10)
  if type(maxDist) ~= "number" or maxDist <= 0 then maxDist = 10 end

  local excl = field(prompt, "Exclusivity", nil)

  return {
    key         = key,
    vk          = RR.KeyMap.resolve(key, VK.E),
    hold        = hold,
    maxDist     = maxDist,
    los         = field(prompt, "RequiresLineOfSight", true) == true,
    clickable   = field(prompt, "ClickablePrompt", false) == true,
    enabled     = field(prompt, "Enabled", true) ~= false,
    exclusivity = excl,
    exclName    = enumName(excl) or "OnePerButton",
    actionText  = field(prompt, "ActionText", ""),
    objectText  = field(prompt, "ObjectText", ""),
  }
end

-- how far a world position is from the middle of the screen, in pixels.
-- Nearer means "this is the prompt the client will activate".
function Act.focusScore(pos)
  return RR.Util.focusScore(pos)
end

-- ---------------------------------------------------------------------
-- ground truth: ProximityPromptService
-- ---------------------------------------------------------------------
-- PromptShown / PromptHidden are client-side signals that fire exactly
-- when a prompt becomes the active one. If the executor surfaces them we
-- stop guessing which prompt owns the key and simply ask.
Act.watching = Act.watching or false
Act.active = Act.active or nil
Act.lastTriggered = Act.lastTriggered or nil

function Act.watch()
  if Act.watching then return true end

  local svc = nil
  pcall(function()
    local pp = game:GetService("ProximityPromptService")
    svc = pp
  end)
  if not svc then return false end

  local conns = {}
  local ok = pcall(function()
    local c1 = svc.PromptShown:Connect(function(prompt)
      Act.active = prompt
      Act.shownAt = tick()
    end)
    if c1 then conns[#conns + 1] = c1 end

    local c2 = svc.PromptHidden:Connect(function(prompt)
      if Act.active == prompt then Act.active = nil end
    end)
    if c2 then conns[#conns + 1] = c2 end

    -- PromptTriggered is the authoritative "the press worked" signal
    local c3 = svc.PromptTriggered:Connect(function(prompt)
      Act.lastTriggered = prompt
      Act.triggeredAt = tick()
    end)
    if c3 then conns[#conns + 1] = c3 end
  end)

  Act.conns = conns
  Act.watching = ok
  if ok then RR.log("prompt service observed: activation is verifiable") end
  return ok
end

function Act.unwatch()
  local conns = Act.conns or {}
  for i = 1, #conns do
    pcall(function() conns[i]:Disconnect() end)
  end
  Act.conns = {}
  Act.watching = false
  Act.active = nil
  Act.lastTriggered = nil
end

-- true / false when the service is available, nil when we do not know
function Act.isActive(p)
  if not Act.watching or not p then return nil end
  local inst = p.inst or p
  return Act.active == inst
end

function Act.activeName()
  local a = Act.active
  if not a then return "none" end
  local n = nil
  pcall(function() n = a:GetFullName() end)
  return n or "?"
end

-- one line for the report and the menu: whether activation is observed
-- or guessed
function Act.watchSummary()
  if Act.watching then
    return "observed (active: " .. Act.activeName() .. ")"
  end
  return "not exposed - using camera heuristics"
end

-- ---------------------------------------------------------------------
-- competing prompts
-- ---------------------------------------------------------------------
-- Roblox shows at most one prompt per key (OnePerButton), or one prompt
-- in total (OneGlobally). Either way the camera decides the winner, and
-- the loser swallows the key press. This finds the prompts that would
-- beat ours right now, so the caller can aim again instead of pressing
-- into the void.
function Act.competitors(p, f, anchorPos)
  local out = { count = 0, best = nil, bestScore = nil, mine = math.huge }
  if not p or not anchorPos then return out end

  local list = RR.World.livePrompts()
  if #list == 0 then return out end

  local me = RR.Util.charPos()
  if not me then return out end

  out.mine = RR.Util.focusScore(anchorPos)
  if out.mine == math.huge then return out end

  for i = 1, #list do
    local q = list[i]
    if q.inst ~= p.inst then
      local sameKey = (q.vk == nil) or (q.vk == f.vk)
      -- OneGlobally: any prompt can take the slot, whatever its key
      local relevant = sameKey or (f.exclName == "OneGlobally")
      -- AlwaysShow never takes anything away from anyone
      if f.exclName == "AlwaysShow" then relevant = false end

      if relevant then
        local d = (me - q.pos).Magnitude
        local qmax = q.maxDist or 10
        if d <= qmax then
          local score = RR.Util.focusScore(q.pos)
          if score < out.mine then
            out.count = out.count + 1
            if not out.bestScore or score < out.bestScore then
              out.best = q
              out.bestScore = score
            end
          end
        end
      end
    end
  end

  return out
end

-- ---------------------------------------------------------------------
-- pressing
-- ---------------------------------------------------------------------
-- The documented path: real key input, real hold duration.
function Act.pressKey(f)
  local holdMs = (f.hold * 1000) + 90
  if not RR.Input.hold(f.vk, holdMs, "prompt") then
    return false, "input gate closed"
  end
  return true, "key"
end

-- The documented-but-unverified path: ProximityPrompt:InputHoldBegin()
-- exists on the class and is what the default prompt UI calls when you
-- click a ClickablePrompt. Whether an externally emulated client turns
-- that signal into a trigger is build-dependent, so this is opt-in and
-- always followed by the caller's verify function.
function Act.promptHold(p, f)
  if not p or not p.inst then return false, "no prompt" end

  local began = pcall(function() p.inst:InputHoldBegin() end)
  if not began then return false, "InputHoldBegin unavailable" end

  wait((f.hold + 0.14))
  pcall(function() p.inst:InputHoldEnd() end)

  Act.Stats.holdOk = Act.Stats.holdOk + 1
  return true, "inputHold"
end

-- ClickablePrompt is a second documented activation path: the prompt's
-- own UI is a button. We cannot see that UI, but the click lands on the
-- anchor part, which is where the UI hovers.
function Act.promptClick(p, opts)
  if not p or not p.anchor then return false, "no anchor" end
  local pos = p.pos or RR.World.posOf(p.anchor)
  if not pos then return false, "no position" end
  return Act.clickPart(p.anchor, { offsetY = opts and opts.offsetY })
end

-- ---------------------------------------------------------------------
-- the main entry point
-- ---------------------------------------------------------------------
-- Activate one prompt. opts:
--   approach     : false to skip walking (default true)
--   tol          : arrival tolerance in studs (default 6)
--   timeout      : seconds allowed for the approach (default 12)
--   aim          : false to skip camera aiming (default true)
--   strict       : true to give up when a rival prompt wins the slot
--   method       : "key" (default) | "hold" | "click"
--   verify       : function(inst) -> boolean, polled after the press
--   verifyMs     : how long to poll verify (default 900)
function Act.prompt(p, opts)
  opts = opts or {}
  if not p or not p.inst then return false, "no prompt" end
  Act.Stats.prompts = Act.Stats.prompts + 1

  local anchorPos = p.pos or RR.World.posOf(p.anchor)
  if not anchorPos then
    Act.Stats.lastErr = "prompt has no position"
    return false, Act.Stats.lastErr
  end

  local f = Act.flags(p.inst)

  if f.enabled == false then
    Act.Stats.lastErr = "prompt is disabled"
    return false, Act.Stats.lastErr
  end

  -- 1. get in range -------------------------------------------------
  local want = math.min(f.maxDist * 0.75, opts.tol or 6)
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

  -- 2. aim ----------------------------------------------------------
  -- Required for two independent reasons: a prompt with
  -- RequiresLineOfSight (default true) is hidden when something blocks
  -- the camera, and the client picks the on-screen prompt by camera
  -- direction, not by distance.
  local aimed = true
  if opts.aim ~= false then
    aimed = RR.Move.lookAt(anchorPos + Vector3.new(0, 1.5, 0), 70, 800)
  end

  if f.los and not aimed then
    -- one more, wider sweep before giving up on line of sight
    aimed = RR.Move.lookAt(anchorPos + Vector3.new(0, 1.5, 0), 110, 600)
    if not aimed then
      Act.Stats.promptMiss = Act.Stats.promptMiss + 1
      Act.Stats.lastErr = "prompt out of view (RequiresLineOfSight)"
      return false, Act.Stats.lastErr
    end
  end

  -- 3. make sure the key is not going to hit a neighbour ------------
  -- The service, when available, is authoritative. Otherwise fall back
  -- to the camera-centre heuristic, which is what the client uses when
  -- Exclusivity is OnePerButton or OneGlobally.
  if Act.watching then
    if not Act.isActive(p) then
      RR.Move.lookAt(anchorPos + Vector3.new(0, 1.5, 0), 40, 600)
    end
    if not Act.isActive(p) then
      Act.Stats.promptMiss = Act.Stats.promptMiss + 1
      Act.Stats.lastErr = "not the active prompt (active: " .. Act.activeName() .. ")"
      return false, Act.Stats.lastErr
    end
  elseif opts.strict then
    local rivals = Act.competitors(p, f, anchorPos)
    if rivals.count > 0 then
      RR.Move.lookAt(anchorPos + Vector3.new(0, 1.5, 0), 40, 500)
      rivals = Act.competitors(p, f, anchorPos)
      if rivals.count > 0 then
        Act.Stats.rivals = Act.Stats.rivals + 1
        local who = rivals.best and rivals.best.aname or "?"
        Act.Stats.lastErr = "another prompt owns the key: " .. tostring(who)
        return false, Act.Stats.lastErr
      end
    end
  end

  -- 4. press --------------------------------------------------------
  local method = opts.method or RR.Cfg.get("promptMethod", "key")
  local pressed, how

  if method == "hold" then
    pressed, how = Act.promptHold(p, f)
    if not pressed then
      pressed, how = Act.pressKey(f)
    end
  elseif method == "click" then
    pressed, how = Act.promptClick(p, opts)
    if not pressed then
      pressed, how = Act.pressKey(f)
    end
  else
    pressed, how = Act.pressKey(f)
  end

  if not pressed then
    Act.Stats.lastErr = tostring(how)
    return false, Act.Stats.lastErr
  end
  wait(0.08)

  -- 5. confirm ------------------------------------------------------
  -- A PromptTriggered observation beats any heuristic: the game said so.
  if Act.watching and Act.lastTriggered == p.inst then
    Act.Stats.promptOk = Act.Stats.promptOk + 1
    return true, "triggered"
  end

  if opts.verify then
    local deadline = tick() + ((opts.verifyMs or 900) / 1000)
    while tick() < deadline do
      if Act.watching and Act.lastTriggered == p.inst then
        Act.Stats.promptOk = Act.Stats.promptOk + 1
        return true, "triggered"
      end
      local ok, res = pcall(opts.verify, p.inst)
      if ok and res == true then
        Act.Stats.promptOk = Act.Stats.promptOk + 1
        return true, how or "verified"
      end
      wait(0.06)
    end
    Act.Stats.promptMiss = Act.Stats.promptMiss + 1
    Act.Stats.lastErr = "pressed (" .. tostring(how) .. ") but no confirmation"
    return false, Act.Stats.lastErr
  end

  Act.Stats.promptOk = Act.Stats.promptOk + 1
  return true, how or "pressed"
end

-- ---------------------------------------------------------------------
-- clicking
-- ---------------------------------------------------------------------
function Act.clickPart(part, opts)
  opts = opts or {}
  -- accept either an instance or a position
  local pos = opts.pos or RR.World.posOf(part)
  if not pos then return false, "no position" end

  Act.Stats.clicks = Act.Stats.clicks + 1
  local ok = RR.Input.clickAt(pos, opts.offsetX, opts.offsetY)
  if ok then
    Act.Stats.clickOk = Act.Stats.clickOk + 1
    return true, "clicked"
  end
  Act.Stats.lastErr = "click point off screen or gate closed"
  return false, Act.Stats.lastErr
end

-- ClickDetector: walk into range first, then click the parent part.
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

-- ---------------------------------------------------------------------
-- GUI buttons
-- ---------------------------------------------------------------------
-- Shop, cooking and upgrade menus are almost always TextButtons in
-- PlayerGui. A real click at the button's AbsolutePosition is
-- indistinguishable from the player's own click: the client's own code
-- receives it and does whatever it would have done. This is the one
-- interaction path that works for systems with no prompt and no part.
function Act.clickGui(button, opts)
  opts = opts or {}
  if not button or not button.inst then return false, "no button" end
  if not RR.Util.guiShown(button.inst) then return false, "button not visible" end

  local centre = button.pos or RR.Util.guiCenter(button.inst)
  if not centre then return false, "button has no size" end

  Act.Stats.clicks = Act.Stats.clicks + 1
  Act.Stats.guiClicks = (Act.Stats.guiClicks or 0) + 1

  if not RR.Input.clickScreen(centre.X, centre.Y) then
    Act.Stats.lastErr = "gui click off screen or gate closed"
    return false, Act.Stats.lastErr
  end
  Act.Stats.clickOk = Act.Stats.clickOk + 1

  if opts.verify then
    local deadline = tick() + ((opts.verifyMs or 800) / 1000)
    while tick() < deadline do
      local ok, res = pcall(opts.verify)
      if ok and res == true then return true, "gui" end
      wait(0.05)
    end
    Act.Stats.lastErr = "clicked gui but no confirmation"
    return false, Act.Stats.lastErr
  end

  return true, "gui"
end

-- click the best visible button whose name or label matches a pattern
function Act.clickGuiNamed(pattern, opts)
  local hits = RR.World.findGui(pattern)
  if #hits == 0 then
    return false, "no visible button matching " .. tostring(pattern)
  end
  return Act.clickGui(hits[1], opts)
end

-- Is a prompt currently usable from where we stand?
function Act.promptInRange(p)
  if not p then return false end
  local me = RR.Util.charPos()
  local pos = p.pos or RR.World.posOf(p.anchor)
  if not me or not pos then return false end
  local f = Act.flags(p.inst)
  return (me - pos).Magnitude <= f.maxDist
end

function Act.summary()
  local s = Act.Stats
  return string.format("prompts %d/%d miss=%d rivals=%d  clicks %d/%d gui=%d",
    s.promptOk, s.prompts, s.promptMiss, s.rivals, s.clickOk, s.clicks, s.guiClicks or 0)
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
  lines[#lines + 1] = "activation  : " .. RR.Act.watchSummary()
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
  UI.addLabel(function() return "prompts : " .. RR.Act.watchSummary() end)
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
  pcall(function() RR.Act.unwatch() end)
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

  -- Observe ProximityPromptService before the first press. When the
  -- executor exposes it, "which prompt is active" and "did the press
  -- land" stop being heuristics and become events.
  pcall(function() RR.Act.watch() end)

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