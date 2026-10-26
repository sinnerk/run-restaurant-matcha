--[[ ==================================================================
     DumpScripts.lua - the recon that answers "how does this game work"

     The instance-tree scan told us there are 20 prompts and no cooking
     stations. That is a fact about geometry, not about logic. The logic
     is in the client's scripts, and the client can read them:

         getscripts()  -> every script loaded in the local DataModel
         decompile(s)  -> its source

     LocalScripts and ModuleScripts are fully replicated to the client,
     so this gets the real interaction code - what a prompt's Triggered
     handler does, which tool starts cooking, which remote a GUI button
     calls. That is far more useful than another tree dump.

     OUTPUT (written to the Matcha workspace, NOT to this repo):
         scripts\index.txt        path, class, size, ok/fail
         scripts\###_name.lua     one file per script
         scripts\findings.txt     derived keywords only - safe to share

     findings.txt is the part you can commit: no source, just the object
     names, key codes, remote names and Method calls the scripts mention.

     Run it once, then look at findings.txt before anything else.
     ================================================================== ]]

local VERSION = "1.0"
local DIR = "scripts"
local MAX_SCRIPTS = 500
local MAX_BYTES = 400000

-- Default Roblox character/chat scripts: decompiling them is noise.
local SKIP_NAMES = {
  Animate = true,
  Health = true,
  Sound = true,
  ChatScript = true,
  CameraScript = true,
  ControlScript = true,
  BubbleChat = true,
  PlayerModule = true,
  TouchGui = true,
}

local function say(line)
  print("[dump] " .. tostring(line))
end

pcall(function() makefolder(DIR) end)

local function safeName(text, limit)
  local s = tostring(text or "script")
  s = string.gsub(s, "[^%w_%-]+", "_")
  s = string.gsub(s, "^_+", "")
  s = string.gsub(s, "_+$", "")
  if s == "" then s = "script" end
  if #s > (limit or 60) then s = string.sub(s, 1, limit or 60) end
  return s
end

local function write(path, body)
  local ok = pcall(function() writefile(path, body) end)
  return ok
end

-- ---------------------------------------------------------------------
-- gather
-- ---------------------------------------------------------------------
local scripts = nil
local okScripts = pcall(function() scripts = getscripts() end)
if not okScripts or type(scripts) ~= "table" then
  say("getscripts() unavailable in this build")
  return
end

say("getscripts() returned " .. tostring(#scripts) .. " scripts")

local index = {}
index[#index + 1] = "# client script dump " .. VERSION
index[#index + 1] = "# scripts: " .. tostring(#scripts)
index[#index + 1] = ""

-- keywords pulled out of decompiled source; these are facts about the
-- game's vocabulary, not its code
local found = {}
local foundOrder = {}
local function note(kind, value)
  local key = kind .. "\t" .. value
  if not found[key] then
    found[key] = true
    foundOrder[#foundOrder + 1] = key
  end
end

local dumped, skipped, failed = 0, 0, 0

for i = 1, #scripts do
  local script = scripts[i]

  local cls = ""
  local name = ""
  local full = ""
  pcall(function() cls = script.ClassName end)
  pcall(function() name = script.Name end)
  pcall(function() full = script:GetFullName() end)

  local skip = false
  if SKIP_NAMES[name] then skip = true end
  if cls ~= "LocalScript" and cls ~= "ModuleScript" and cls ~= "Script" then skip = true end
  if dumped >= MAX_SCRIPTS then skip = true end

  if skip then
    skipped = skipped + 1
  else
    local src = nil
    local ok = pcall(function() src = decompile(script) end)

    if not ok or type(src) ~= "string" or #src == 0 then
      failed = failed + 1
      index[#index + 1] = string.format("FAIL  %-13s %s", cls, full)
      note("UNDECOMPILABLE", cls .. " " .. full)
    else
      if #src > MAX_BYTES then
        note("TRUNCATED", full .. " (" .. tostring(#src) .. " bytes)")
        src = string.sub(src, 1, MAX_BYTES)
      end

      dumped = dumped + 1
      local file = string.format("%03d_%s.lua", dumped, safeName(name))
      local wrote = write(DIR .. "/" .. file, "-- " .. full .. "\n" .. src)

      index[#index + 1] = string.format("%-5s %-13s %7d  %s  -> %s",
        wrote and "ok" or "wfail", cls, #src, full, file)

      ------------------- findings extraction -------------------
      -- remotes: the entire point of a client script dump
      if string.find(src, ":FireServer", 1, true) then
        note("REMOTE", "FireServer in " .. full)
      end
      if string.find(src, ":InvokeServer", 1, true) then
        note("REMOTE", "InvokeServer in " .. full)
      end

      -- names the code looks up
      for arg in string.gmatch(src, "FindFirstChild%s*%(%s*[\"']([^\"']+)[\"']") do
        note("FINDFIRST", arg)
      end
      for arg in string.gmatch(src, "WaitForChild%s*%(%s*[\"']([^\"']+)[\"']") do
        note("WAITFOR", arg)
      end
      for arg in string.gmatch(src, "GetService%s*%(%s*[\"']([^\"']+)[\"']") do
        note("SERVICE", arg)
      end

      -- keys the game listens for
      for code in string.gmatch(src, "Enum%.KeyCode%.(%w+)") do
        note("KEYCODE", code)
      end

      -- interaction surfaces mentioned at all
      for word in string.gmatch(src, "(ProximityPrompt%w*)") do
        note("CLASS", word)
      end
      for word in string.gmatch(src, "(ClickDetector%w*)") do
        note("CLASS", word)
      end
      for word in string.gmatch(src, "(RemoteEvent%w*)") do
        note("CLASS", word)
      end
      for word in string.gmatch(src, "(BindableEvent%w*)") do
        note("CLASS", word)
      end

      -- short quoted strings: prompt text, tool names, remote names
      for text in string.gmatch(src, "\"([%w][%w%s_%-%./]*)\"") do
        if #text >= 3 and #text <= 40 then
          note("STRING", text)
        end
      end
      for text in string.gmatch(src, "'([%w][%w%s_%-%./]*)'") do
        if #text >= 3 and #text <= 40 then
          note("STRING", text)
        end
      end
    end
  end

  if i % 15 == 0 then wait() end
end

index[#index + 1] = ""
index[#index + 1] = string.format("dumped=%d skipped=%d undecompilable=%d", dumped, skipped, failed)
index[#index + 1] = ""

write(DIR .. "/index.txt", table.concat(index, "\n"))

-- ---------------------------------------------------------------------
-- findings
-- ---------------------------------------------------------------------
table.sort(foundOrder)

local out = {}
out[#out + 1] = "# derived findings " .. VERSION
out[#out + 1] = "# extracted from decompiled client scripts - no source included"
out[#out + 1] = "# scripts dumped: " .. tostring(dumped)
out[#out + 1] = ""

local lastKind = nil
for i = 1, #foundOrder do
  local kind, value = string.match(foundOrder[i], "^(%w+)\t(.*)$")
  if kind ~= lastKind then
    out[#out + 1] = ""
    out[#out + 1] = "== " .. kind .. " =="
    lastKind = kind
  end
  out[#out + 1] = "  " .. tostring(value)
end

local body = table.concat(out, "\n")
local wrote = write(DIR .. "/findings.txt", body)

say(string.format("dumped=%d skipped=%d undecompilable=%d", dumped, skipped, failed))
say("findings: " .. tostring(wrote and "written" or "FAILED") .. " (" .. #body .. " bytes)")

if dumped == 0 then
  say("nothing decompiled - the build may not expose script source")
  say("fall back to tools/Recon.lua, which observes behaviour instead")
end
