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
