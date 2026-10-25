--[[ ==================================================================
     Recon.lua - standalone Matcha reconnaissance script

     Purpose: this place has almost no prompts (20 in the whole map) and
     no cooking stations among them. That means interaction happens some
     other way - most likely tools in the backpack, on-screen text, or
     prompts that only exist while something is active.

     This script answers that question with data instead of guesses. It
     walks every root the API exposes, records the action surfaces, then
     watches for 90 seconds and logs anything new that appears.

     RUN IT, THEN COMMIT THE OUTPUT:
       1. paste into Matcha, execute
       2. it writes recon.txt to the Matcha workspace
       3. copy that file into this repo as diagnostics/recon.txt

     The file is small (action surfaces only, not the 64k-instance tree).
     ================================================================== ]]

local VERSION = "1.0"
local OUT = "recon.txt"
local WATCH_SECONDS = 90
local ACTIONABLE = {
  ProximityPrompt = true,
  ClickDetector = true,
  Tool = true,
  TextLabel = true,
  TextButton = true,
  ImageButton = true,
  StringValue = true,
  NumberValue = true,
  BoolValue = true,
  IntValue = true,
  Color3Value = true,
  ObjectValue = true,
  RemoteEvent = true,
  RemoteFunction = true,
  BindableEvent = true,
  BindableFunction = true,
  SurfaceGui = true,
  BillboardGui = true,
  ScreenGui = true,
  Highlight = true,
}

local out = {}
local function say(line)
  out[#out + 1] = line
end

local function flush()
  local body = table.concat(out, "\n")
  local ok = pcall(function() writefile(OUT, body) end)
  if ok then
    print("recon written: " .. OUT .. " (" .. #body .. " bytes, " .. #out .. " lines)")
  else
    print("recon: writefile failed")
  end
end

local function name(inst)
  local n = ""
  pcall(function() n = inst.Name end)
  return n or ""
end

local function cls(inst)
  local c = ""
  pcall(function() c = inst.ClassName end)
  return c or ""
end

local function full(inst)
  local f = ""
  pcall(function() f = inst:GetFullName() end)
  return f or ""
end

local function prop(inst, key)
  local v = nil
  pcall(function() v = inst[key] end)
  return v
end

local function guidStrip(s)
  return (string.gsub(s, "_%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x", ""))
end

local function player()
  local P = game:GetService("Players")
  return P.LocalPlayer
end

local function charPos()
  local p = player()
  if not p then return nil end
  local c = nil
  pcall(function() c = p.Character end)
  if not c then return nil end
  local h = nil
  pcall(function() h = c:FindFirstChild("HumanoidRootPart") end)
  if not h then return nil end
  local pos = nil
  pcall(function() pos = h.Position end)
  return pos
end

local function collect(inst, list, budget)
  local kids = nil
  local ok = pcall(function() kids = inst:GetDescendants() end)
  if not ok then return end
  for i = 1, #kids do
    list[#list + 1] = kids[i]
    if budget and #list >= budget then return end
  end
end

-- ---------------------------------------------------------------------
-- header
-- ---------------------------------------------------------------------
local ename, ever = identifyexecutor()
local gname = "?"
pcall(function() gname = getgamename() end)

say("# recon " .. VERSION .. "  " .. tostring(gname))
say("# executor: " .. tostring(ename) .. " " .. tostring(ever))
say("# place id: " .. tostring(game.PlaceId))
say("# job id: " .. tostring(game.JobId))
say("")

local me = player()
if me then
  say("player: " .. name(me))
  local pos = charPos()
  if pos then
    say(string.format("position: %.1f, %.1f, %.1f", pos.X, pos.Y, pos.Z))
  end
end
say("")

-- ---------------------------------------------------------------------
-- roots
-- ---------------------------------------------------------------------
local roots = {}
local function addRoot(label, inst)
  if inst then
    roots[#roots + 1] = { label = label, inst = inst }
  else
    say("root missing: " .. label)
  end
end

addRoot("Workspace", game:GetService("Workspace"))
addRoot("ReplicatedStorage", game:GetService("ReplicatedStorage"))
addRoot("ReplicatedFirst", game:GetService("ReplicatedFirst"))
addRoot("Lighting", game:GetService("Lighting"))
if me then
  addRoot("Backpack", me:FindFirstChildOfClass("Backpack"))
  addRoot("PlayerGui", me:FindFirstChildOfClass("PlayerGui"))
  local c = nil
  pcall(function() c = me.Character end)
  addRoot("Character", c)
  local pg = me:FindFirstChildOfClass("PlayerGui")
  if pg then addRoot("PlayerScripts", pg:FindFirstChild("PlayerScripts")) end
end

-- one pass per root, but capped and yielding
local all = {}
for r = 1, #roots do
  local before = #all
  collect(roots[r].inst, all, 120000)
  say(string.format("root %-18s %6d instances", roots[r].label, #all - before))
end
say("total instances: " .. #all)
say("")

-- ---------------------------------------------------------------------
-- actionable surfaces
-- ---------------------------------------------------------------------
local buckets = {}
local order = {}
local counts = {}

for i = 1, #all do
  local inst = all[i]
  local c = cls(inst)
  if ACTIONABLE[c] then
    if not buckets[c] then
      buckets[c] = {}
      order[#order + 1] = c
    end
    local b = buckets[c]
    b[#b + 1] = inst
    counts[c] = (counts[c] or 0) + 1
  end
  if i % 800 == 0 then wait() end
end

table.sort(order)
say("== action surfaces ==")
for i = 1, #order do
  say(string.format("  %-16s %d", order[i], counts[order[i]]))
end
say("")

local function reportPrompts()
  local list = buckets["ProximityPrompt"] or {}
  say("== ProximityPrompts (" .. #list .. ") ==")
  for i = 1, #list do
    local p = list[i]
    local anchor = nil
    pcall(function() anchor = p.Parent end)
    local pos = anchor and prop(anchor, "Position") or nil
    say(string.format("  %s", guidStrip(full(p))))
    say(string.format("     anchor=%s  enabled=%s  key=%s  hold=%s  range=%s",
      anchor and name(anchor) or "?",
      tostring(prop(p, "Enabled")),
      tostring(prop(p, "KeyboardKeyCode")),
      tostring(prop(p, "HoldDuration")),
      tostring(prop(p, "MaxActivationDistance"))))
    say(string.format("     action=%q object=%q",
      tostring(prop(p, "ActionText")), tostring(prop(p, "ObjectText"))))
    if pos then
      say(string.format("     pos=%.1f, %.1f, %.1f", pos.X, pos.Y, pos.Z))
    end
  end
  say("")
end

local function reportClicks()
  local list = buckets["ClickDetector"] or {}
  say("== ClickDetectors (" .. #list .. ") ==")
  for i = 1, #list do
    local d = list[i]
    local anchor = nil
    pcall(function() anchor = d.Parent end)
    say(string.format("  %s  anchor=%s  range=%s",
      guidStrip(full(d)), anchor and name(anchor) or "?",
      tostring(prop(d, "MaxActivationDistance"))))
  end
  say("")
end

local function reportTools()
  local list = buckets["Tool"] or {}
  say("== Tools (" .. #list .. ") ==")
  for i = 1, #list do
    local t = list[i]
    say("  " .. full(t) .. "  equipped=" .. tostring(prop(t, "ToolTip")) .. "  requiresHandle=" .. tostring(prop(t, "RequiresHandle")))
  end
  say("")
end

local function shortText(t, maxLen)
  t = tostring(t or "")
  t = string.gsub(t, "\n", " / ")
  if #t > maxLen then t = string.sub(t, 1, maxLen) .. "..." end
  return t
end

local function reportGui()
  local kinds = { "TextLabel", "TextButton", "ImageButton", "SurfaceGui", "BillboardGui", "ScreenGui" }
  say("== GUI text ==")
  for k = 1, #kinds do
    local kind = kinds[k]
    local list = buckets[kind] or {}
    if #list > 0 then
      say("  -- " .. kind .. " (" .. #list .. ")")
      for i = 1, math.min(#list, 120) do
        local g = list[i]
        local txt = prop(g, "Text")
        if txt ~= nil and tostring(txt) ~= "" then
          say("     " .. guidStrip(full(g)) .. " = " .. shortText(txt, 90))
        elseif kind == "SurfaceGui" or kind == "BillboardGui" or kind == "ScreenGui" then
          say("     " .. guidStrip(full(g)))
        end
      end
    end
  end
  say("")
end

local function reportValues()
  local kinds = { "StringValue", "NumberValue", "IntValue", "BoolValue", "ObjectValue", "Color3Value" }
  local printed = 0
  say("== values (game state often lives here) ==")
  for k = 1, #kinds do
    local list = buckets[kinds[k]] or {}
    for i = 1, #list do
      local v = list[i]
      local val = prop(v, "Value")
      local f = guidStrip(full(v))
      -- skip the noisy per-instance bookkeeping values
      if not string.find(f, "Path") and not string.find(f, "Bone") then
        say("  " .. f .. " = " .. tostring(val))
        printed = printed + 1
        if printed > 400 then
          say("  ... truncated")
          k = #kinds
          break
        end
      end
    end
  end
  say("")
end

reportPrompts()
reportClicks()
reportTools()
reportGui()
reportValues()

-- ---------------------------------------------------------------------
-- nearby world, so stations show up by name
-- ---------------------------------------------------------------------
local pos = charPos()
if pos then
  say("== parts within 60 studs ==")
  local near = {}
  for i = 1, #all do
    local inst = all[i]
    local c = cls(inst)
    if c == "Part" or c == "MeshPart" or c == "UnionOperation" then
      local p = prop(inst, "Position")
      if p then
        local d = (p - pos).Magnitude
        if d <= 60 then
          near[#near + 1] = { d = d, inst = inst }
        end
      end
    end
    if i % 800 == 0 then wait() end
  end
  table.sort(near, function(a, b) return a.d < b.d end)
  for i = 1, math.min(#near, 150) do
    local n = near[i]
    say(string.format("  %5.1f  %-14s %s", n.d, cls(n.inst), guidStrip(full(n.inst))))
  end
  say("")
end

flush()

-- ---------------------------------------------------------------------
-- watcher: things that only exist while you play
-- ---------------------------------------------------------------------
say("")
say("== watch (next " .. WATCH_SECONDS .. " seconds) ==")
say("move around, start cooking, open menus - new prompts and text land here")

local seenPrompt = {}
for i = 1, #(buckets["ProximityPrompt"] or {}) do
  seenPrompt[full((buckets["ProximityPrompt"])[i])] = true
end
local seenText = {}

local deadline = tick() + WATCH_SECONDS
local lastFlush = tick()
local events = 0

while tick() < deadline do
  local ws = game:GetService("Workspace")
  local prompts = nil
  pcall(function() prompts = ws:GetDescendants() end)
  if prompts then
    for i = 1, #prompts do
      local p = prompts[i]
      local c = cls(p)
      if c == "ProximityPrompt" then
        local f = full(p)
        if not seenPrompt[f] then
          seenPrompt[f] = true
          events = events + 1
          say(string.format("[%6.1fs] NEW PROMPT %s  key=%s hold=%s range=%s",
            WATCH_SECONDS - (deadline - tick()), guidStrip(f),
            tostring(prop(p, "KeyboardKeyCode")), tostring(prop(p, "HoldDuration")),
            tostring(prop(p, "MaxActivationDistance"))))
        end
      elseif c == "TextLabel" or c == "TextButton" then
        local txt = prop(p, "Text")
        if txt and tostring(txt) ~= "" then
          local key = tostring(txt)
          if not seenText[key] then
            seenText[key] = true
            local f = full(p)
            if string.find(string.lower(f), "playergui") or string.find(string.lower(f), "screen") then
              events = events + 1
              say(string.format("[%6.1fs] GUI TEXT %s = %s",
                WATCH_SECONDS - (deadline - tick()), guidStrip(f), shortText(txt, 80)))
            end
          end
        end
      end
    end
  end

  if tick() - lastFlush > 10 then
    lastFlush = tick()
    flush()
  end
  wait(0.5)
end

say("watch finished: " .. events .. " new surface(s)")
flush()
print("recon complete - commit " .. OUT .. " and the next build can target real names")
