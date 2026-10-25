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
