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
