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
