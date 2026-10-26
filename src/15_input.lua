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
