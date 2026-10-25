--[[
  ╔══════════════════════════════════════════════════════════╗
  ║   Run a Restaurant!  —  Matcha AutoFarm  v3.0           ║
  ║   Engine : Matcha LuaVM  (doc.wabisabi.mom/matcha)      ║
  ║   No Instance.new · No HttpGet · No WorldToViewport     ║
  ╚══════════════════════════════════════════════════════════╝

  OPEN / CLOSE : Insert key  (or the keybind in the menu)
  All toggles persist while the GUI is closed.
  Remote scanner runs on load; re-run from the Status tab.
]]

-- ════════════════════════════════════════════════════════════
--  SERVICES
-- ════════════════════════════════════════════════════════════
local Players     = game:GetService("Players")
local RunService  = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

-- ════════════════════════════════════════════════════════════
--  STATE
-- ════════════════════════════════════════════════════════════
local State = {
  startTime    = tick(),
  cash         = 0,
  ordersServed = 0,
  dishesCooked = 0,
  cropsHarv    = 0,
  lastAction   = "Idle",
  phase        = "Scanning...",
  guiOpen      = true,
}

-- ════════════════════════════════════════════════════════════
--  REMOTE CACHE
-- ════════════════════════════════════════════════════════════
local R = {
  SeatCustomer   = nil,
  TakeOrder      = nil,
  CookDish       = nil,
  ServeFood      = nil,
  CleanDish      = nil,
  CollectCash    = nil,
  HarvestCrop    = nil,
  PlantCrop      = nil,
  CompleteQuest  = nil,
  UpgradeStation = nil,
  BuyStaff       = nil,
  HopServer      = nil,
}

local REMOTE_MAP = {
  SeatCustomer   = {"SeatCustomer","Seat","SeatGuest","AssignSeat","SeatingEvent"},
  TakeOrder      = {"TakeOrder","OrderEvent","GetOrder","SubmitOrder","TakeOrderEvent"},
  CookDish       = {"CookDish","Cook","CookFood","StartCooking","CookingEvent"},
  ServeFood      = {"ServeFood","Serve","ServeDish","ServeOrder","ServeEvent"},
  CleanDish      = {"CleanDish","Clean","WashDish","CleanPlate","DishClean"},
  CollectCash    = {"CollectCash","Collect","CashRegister","CollectRegister","ClaimCash"},
  HarvestCrop    = {"HarvestCrop","Harvest","HarvestPlant","FarmHarvest","HarvestEvent"},
  PlantCrop      = {"PlantCrop","Plant","PlantSeed","FarmPlant","PlantEvent"},
  CompleteQuest  = {"CompleteQuest","QuestComplete","FinishQuest","QuestEvent","ClaimQuest"},
  UpgradeStation = {"UpgradeStation","Upgrade","BuyUpgrade","StationUpgrade","UpgradeEvent"},
  BuyStaff       = {"BuyStaff","HireStaff","HireWorker","StaffEvent","BuyWorker"},
  HopServer      = {"HopServer","ServerHop","RejoinServer","TeleportEvent","HopEvent"},
}

-- ════════════════════════════════════════════════════════════
--  REMOTE SCANNER
-- ════════════════════════════════════════════════════════════
local function scanRemotes()
  State.phase = "Scanning..."
  local all = {}

  local roots = {}
  local rs  = game:FindFirstChild("ReplicatedStorage")
  local rf  = game:FindFirstChild("ReplicatedFirst")
  if rs then roots[#roots+1] = rs end
  if rf then roots[#roots+1] = rf end
  roots[#roots+1] = workspace

  for i = 1, #roots do
    local ok, desc = pcall(function() return roots[i]:GetDescendants() end)
    if ok then
      for j = 1, #desc do
        local v = desc[j]
        local isRem = false
        pcall(function()
          isRem = v:IsA("RemoteEvent") or v:IsA("RemoteFunction")
        end)
        if isRem then
          local clean = v.Name:lower():gsub("[%s_%-]","")
          all[clean]  = v
          all[v.Name] = v
        end
      end
    end
  end

  local matched = 0
  for key, aliases in pairs(REMOTE_MAP) do
    for ai = 1, #aliases do
      local alias = aliases[ai]
      local clean = alias:lower():gsub("[%s_%-]","")
      local found = all[alias] or all[clean]
      if found then
        R[key]  = found
        matched = matched + 1
        break
      end
    end
  end

  if matched > 0 then
    State.phase = "Live — " .. matched .. " remotes"
  else
    State.phase = "Passive (proximity only)"
  end
  return matched
end

-- ════════════════════════════════════════════════════════════
--  HELPER : safe fire  (NO varargs — Matcha limitation)
-- ════════════════════════════════════════════════════════════
-- Each overload is explicit so we never use ... inside pcall.
local function fire0(remote)
  if remote then pcall(function() remote:FireServer() end) end
end
local function fire1(remote, a1)
  if remote then pcall(function() remote:FireServer(a1) end) end
end
local function fire2(remote, a1, a2)
  if remote then pcall(function() remote:FireServer(a1, a2) end) end
end

-- ════════════════════════════════════════════════════════════
--  HELPER : find nearest matching instance
-- ════════════════════════════════════════════════════════════
local function findNearest(className, namePart, maxDist)
  maxDist = maxDist or 60
  local char = LocalPlayer.Character
  local hrp  = char and char:FindFirstChild("HumanoidRootPart")
  if not hrp then return nil, nil end

  local best     = nil
  local bestDist = maxDist

  local ok, desc = pcall(function() return workspace:GetDescendants() end)
  if not ok then return nil, nil end

  for i = 1, #desc do
    local v = desc[i]
    local match = false
    pcall(function()
      local classOk   = (className == nil) or v:IsA(className)
      local nameOk    = (namePart  == nil) or (v.Name:lower():find(namePart:lower()) ~= nil)
      match = classOk and nameOk
    end)
    if match then
      local pos = nil
      pcall(function()
        if v:IsA("BasePart") then
          pos = v.Position
        else
          local p = v:FindFirstChild("HumanoidRootPart")
          if p then pos = p.Position end
          if not pos then
            local pp = v:FindFirstChild("PrimaryPart")
            if pp then pos = pp.Position end
          end
        end
      end)
      if pos then
        local d = (hrp.Position - pos).Magnitude
        if d < bestDist then
          bestDist = d
          best     = v
        end
      end
    end
  end
  return best, bestDist
end

-- ════════════════════════════════════════════════════════════
--  HELPER : teleport to position
-- ════════════════════════════════════════════════════════════
local function tpTo(pos)
  if not pos then return end
  local char = LocalPlayer.Character
  local hrp  = char and char:FindFirstChild("HumanoidRootPart")
  if hrp then
    pcall(function()
      hrp.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
    end)
  end
end

-- ════════════════════════════════════════════════════════════
--  HELPER : get position from any instance
-- ════════════════════════════════════════════════════════════
local function getPos(inst)
  if not inst then return nil end
  local pos = nil
  pcall(function()
    if inst:IsA("BasePart") then
      pos = inst.Position
    else
      local hrp = inst:FindFirstChild("HumanoidRootPart")
      if hrp then pos = hrp.Position; return end
      local pp  = inst:FindFirstChild("PrimaryPart")
      if pp  then pos = pp.Position;  return end
    end
  end)
  return pos
end

-- ════════════════════════════════════════════════════════════
--  AUTO LOGIC
-- ════════════════════════════════════════════════════════════
local function doAutoSeat()
  local v = findNearest("Model", "customer", 60)
  if v then
    local pos = getPos(v)
    if pos then
      tpTo(pos)
      wait(0.12)
      fire1(R.SeatCustomer, v)
      State.lastAction = "Seated customer"
    end
  end
end

local function doAutoOrder()
  local v = findNearest("BasePart", "order", 80)
  if not v then v = findNearest("Model", "order", 80) end
  if v then
    local pos = getPos(v)
    if pos then
      tpTo(pos)
      wait(0.12)
      fire1(R.TakeOrder, v)
      State.lastAction = "Took order"
    end
  end
end

local function doAutoCook()
  local v = findNearest("BasePart", "stove", 80)
  if not v then v = findNearest("Model", "stove", 80) end
  if not v then v = findNearest("BasePart", "pot", 80) end
  if v then
    local pos = getPos(v)
    if pos then
      tpTo(pos)
      wait(0.18)
      fire1(R.CookDish, v)
      State.dishesCooked = State.dishesCooked + 1
      State.lastAction   = "Cooked dish"
    end
  end
end

local function doAutoServe()
  local v = findNearest("BasePart", "table", 80)
  if not v then v = findNearest("Model", "table", 80) end
  if v then
    local pos = getPos(v)
    if pos then
      tpTo(pos)
      wait(0.12)
      fire1(R.ServeFood, v)
      State.ordersServed = State.ordersServed + 1
      State.lastAction   = "Served food"
    end
  end
end

local function doAutoClean()
  local v = findNearest("BasePart", "dirty", 80)
  if not v then v = findNearest("BasePart", "dish",  80) end
  if not v then v = findNearest("Model",    "dish",  80) end
  if v then
    local pos = getPos(v)
    if pos then
      tpTo(pos)
      wait(0.10)
      fire1(R.CleanDish, v)
      State.lastAction = "Cleaned dish"
    end
  end
end

local function doAutoCash()
  local v = findNearest("BasePart", "register", 80)
  if not v then v = findNearest("Model",    "register", 80) end
  if not v then v = findNearest("BasePart", "cash",     80) end
  if v then
    local pos = getPos(v)
    if pos then
      tpTo(pos)
      wait(0.10)
      fire1(R.CollectCash, v)
      State.cash       = State.cash + 1
      State.lastAction = "Collected cash"
    end
  end
end

local function doAutoHarvest()
  local v = findNearest("BasePart", "crop",   100)
  if not v then v = findNearest("BasePart", "wheat",  100) end
  if not v then v = findNearest("BasePart", "carrot", 100) end
  if not v then v = findNearest("BasePart", "farm",   100) end
  if v then
    local pos = getPos(v)
    if pos then
      tpTo(pos)
      wait(0.18)
      fire1(R.HarvestCrop, v)
      State.cropsHarv  = State.cropsHarv + 1
      State.lastAction = "Harvested crop"
    end
  end
end

local function doAutoQuest()
  local v = findNearest("BasePart", "quest", 80)
  if not v then v = findNearest("Model", "quest", 80) end
  if v then
    local pos = getPos(v)
    if pos then
      tpTo(pos)
      wait(0.12)
      fire0(R.CompleteQuest)
      State.lastAction = "Claimed quest"
    end
  end
end

local function doAutoStaff()
  fire1(R.BuyStaff, "Waiter")
  State.lastAction = "Hired staff"
end

local function doAutoUpgrade()
  fire0(R.UpgradeStation)
  State.lastAction = "Upgraded station"
end

local function doServerHop()
  fire0(R.HopServer)
  State.lastAction = "Server hopped"
  notify("Hopping server!", "AutoFarm", 3)
end

-- ════════════════════════════════════════════════════════════
--  ANTI-AFK  (own thread)
-- ════════════════════════════════════════════════════════════
local function startAntiAFK()
  task.spawn(function()
    while true do
      wait(250)
      if UI.GetValue("antiAFK") then
        local char = LocalPlayer.Character
        local hum  = char and char:FindFirstChild("Humanoid")
        if hum then
          pcall(function() hum.Jump = true end)
        end
      end
    end
  end)
end

-- ════════════════════════════════════════════════════════════
--  HUD OVERLAY  (Drawing)
-- ════════════════════════════════════════════════════════════
local HUD = {}

-- Background card
HUD.bg = Drawing.new("Square")
HUD.bg.Filled       = true
HUD.bg.Color        = Color3.fromRGB(8, 8, 14)
HUD.bg.Size         = Vector2.new(220, 150)
HUD.bg.Position     = Vector2.new(10, 10)
HUD.bg.ZIndex       = 10
HUD.bg.Visible      = false
HUD.bg.Transparency = 0.15

-- Purple accent bar (top edge)
HUD.accent = Drawing.new("Square")
HUD.accent.Filled   = true
HUD.accent.Color    = Color3.fromRGB(130, 80, 255)
HUD.accent.Size     = Vector2.new(220, 2)
HUD.accent.Position = Vector2.new(10, 10)
HUD.accent.ZIndex   = 11
HUD.accent.Visible  = false

-- Title text
HUD.title = Drawing.new("Text")
HUD.title.Text     = "AutoFarm  v3"
HUD.title.Position = Vector2.new(15, 15)
HUD.title.Color    = Color3.fromRGB(195, 170, 255)
HUD.title.FontSize = 14
HUD.title.Outline  = true
HUD.title.ZIndex   = 12
HUD.title.Visible  = false

-- Stat lines (8 lines, 16px apart starting at y=32)
local STAT_KEYS  = {"phase","action","served","cooked","crops","cash","ping","uptime"}
local STAT_LABEL = {
  phase  = "Phase  ", action = "Last   ", served = "Served ",
  cooked = "Cooked ", crops  = "Crops  ", cash   = "Cash   ",
  ping   = "Ping   ", uptime = "Uptime ",
}
HUD.lines = {}
for i = 1, #STAT_KEYS do
  local t = Drawing.new("Text")
  t.Text     = ""
  t.Position = Vector2.new(15, 32 + (i-1)*15)
  t.Color    = Color3.fromRGB(200, 195, 230)
  t.FontSize = 12
  t.Outline  = true
  t.ZIndex   = 12
  t.Visible  = false
  HUD.lines[STAT_KEYS[i]] = t
end

local function setHUDVisible(v)
  HUD.bg.Visible     = v
  HUD.accent.Visible = v
  HUD.title.Visible  = v
  for _, t in pairs(HUD.lines) do t.Visible = v end
end

local function updateHUD()
  local show = UI.GetValue("statusOverlay") == true
  setHUDVisible(show)
  if not show then return end

  local elapsed = math.floor(tick() - State.startTime)
  local mins    = math.floor(elapsed / 60)
  local secs    = elapsed % 60
  local pingVal = 0
  pcall(function() pingVal = GetPingValue() end)

  local data = {
    phase  = State.phase,
    action = State.lastAction,
    served = tostring(State.ordersServed),
    cooked = tostring(State.dishesCooked),
    crops  = tostring(State.cropsHarv),
    cash   = tostring(State.cash) .. "x",
    ping   = tostring(pingVal) .. " ms",
    uptime = tostring(mins) .. "m " .. tostring(secs) .. "s",
  }

  for key, t in pairs(HUD.lines) do
    t.Text = (STAT_LABEL[key] or key) .. " " .. (data[key] or "—")
  end
end

-- ════════════════════════════════════════════════════════════
--  OPEN / CLOSE TOGGLE BUTTON  (Drawing — bottom-left)
-- ════════════════════════════════════════════════════════════
-- Matcha's native UI (UI.AddTab) has its own open/close built in.
-- This extra Drawing button is a fallback clickable for the HUD only.
-- The Matcha menu itself is shown/hidden by its built-in keybind.

-- ════════════════════════════════════════════════════════════
--  MATCHA NATIVE UI
-- ════════════════════════════════════════════════════════════
UI.AddTab("Restaurant", function(tab)

  -- ── LEFT : Automation ──────────────────────────────────
  local left = tab:Section("Automation", "Left")

  left:Toggle("autoSeat",    "Seat Customers",    true)
  left:Toggle("autoOrder",   "Take Orders",       true)
  left:Toggle("autoCook",    "Auto Cook",         true)
  left:Toggle("autoServe",   "Serve Food",        true)
  left:Toggle("autoClean",   "Clean Dishes",      true)
  left:Toggle("autoCash",    "Collect Cash",      true)
  left:Toggle("autoHarvest", "Harvest Crops",     true)
  left:Toggle("autoQuest",   "Claim Quests",      false)
  left:Toggle("autoStaff",   "Hire Staff",        false)
  left:Toggle("autoUpgrade", "Auto Upgrade",      false)
  left:Spacing()
  left:SliderInt("farmSpeed", "Tick Speed (ms)", 50, 1000, 180)
  left:Keybind("openClose", 0x2D)   -- Insert key default

  -- ── RIGHT : Settings & Status ──────────────────────────
  local right = tab:Section("Settings & Status", "Right")

  right:Toggle("statusOverlay", "HUD Overlay",   true)
  right:Toggle("antiAFK",       "Anti-AFK",      true)
  right:Spacing()
  right:Text("Server")
  right:Toggle("autoServerHop", "Auto Server Hop", false)
  right:SliderInt("hopInterval", "Hop Interval (min)", 1, 60, 10)
  right:Button("Server Hop Now", function()
    doServerHop()
  end)
  right:Spacing()
  right:Text("Remotes")
  right:Button("Scan Remotes", function()
    local n = scanRemotes()
    notify(
      tostring(n) .. " remotes found\n" .. State.phase,
      "Scanner",
      4
    )
  end)
  right:Spacing()
  right:Button("About", function()
    local exName = "Matcha"
    local exVer  = ""
    pcall(function()
      exName, exVer = identifyexecutor()
    end)
    notify(
      "Run a Restaurant AutoFarm v3.0\n"
        .. "Executor: " .. exName .. " " .. exVer .. "\n"
        .. State.phase,
      "About",
      5
    )
  end)
end)

-- ════════════════════════════════════════════════════════════
--  STARTUP
-- ════════════════════════════════════════════════════════════
notify("Loading AutoFarm v3...", "Run a Restaurant", 2)

task.spawn(function()
  wait(1.2)
  scanRemotes()
  startAntiAFK()
  notify("AutoFarm ready!  " .. State.phase, "Run a Restaurant", 4)
end)

-- ════════════════════════════════════════════════════════════
--  MAIN FARM LOOP
-- ════════════════════════════════════════════════════════════
task.spawn(function()
  -- Wait for character
  local char = LocalPlayer.Character
  if not char then
    char = LocalPlayer.CharacterAdded:Wait()
  end
  local ok2, _ = pcall(function()
    char:WaitForChild("HumanoidRootPart", 10)
  end)

  -- slow tick counters
  local slowTick = 0

  while true do
    local ms = UI.GetValue("farmSpeed")
    if type(ms) ~= "number" then ms = 180 end
    local interval = ms / 1000

    -- fast actions
    if UI.GetValue("autoSeat")    then pcall(doAutoSeat)    end
    if UI.GetValue("autoOrder")   then pcall(doAutoOrder)   end
    if UI.GetValue("autoCook")    then pcall(doAutoCook)    end
    if UI.GetValue("autoServe")   then pcall(doAutoServe)   end
    if UI.GetValue("autoClean")   then pcall(doAutoClean)   end
    if UI.GetValue("autoCash")    then pcall(doAutoCash)    end
    if UI.GetValue("autoHarvest") then pcall(doAutoHarvest) end

    -- slow actions every ~5s
    slowTick = slowTick + interval
    if slowTick >= 5 then
      slowTick = 0
      if UI.GetValue("autoQuest")   then pcall(doAutoQuest)   end
      if UI.GetValue("autoStaff")   then pcall(doAutoStaff)   end
      if UI.GetValue("autoUpgrade") then pcall(doAutoUpgrade) end
    end

    -- server hop
    if UI.GetValue("autoServerHop") then
      local hopMins = UI.GetValue("hopInterval")
      if type(hopMins) ~= "number" then hopMins = 10 end
      local elapsed = tick() - State.startTime
      if elapsed > 0 and math.floor(elapsed) % (hopMins * 60) == 0 then
        pcall(doServerHop)
      end
    end

    -- HUD
    pcall(updateHUD)

    wait(interval)
  end
end)
