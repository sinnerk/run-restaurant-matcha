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
