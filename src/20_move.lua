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
  local cam = camera()
  if not cam then return Vector2.new(1280, 720) end
  local vp = nil
  pcall(function() vp = cam.ViewportSize end)
  if vp then return vp end
  return Vector2.new(1280, 720)
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
function Move.lookAt(target, tolPx, maxMs)
  tolPx = tolPx or 45
  maxMs = maxMs or 900
  if not RR.Input.focused() then return false, "not focused" end

  local vp = viewport()
  local cx = vp.X / 2
  local cy = vp.Y / 2

  local held = false
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
      if not held then
        pcall(function() mouse2press() end)
        held = true
      end
      -- cap the step so one frame cannot spin past the target
      local stepX = RR.Util.clamp(dx * 0.42, -140, 140)
      local stepY = RR.Util.clamp(dy * 0.42, -110, 110)
      RR.Input.moveRel(stepX, stepY)
    else
      -- behind us: drag sideways in fixed steps until it is on screen
      if not held then
        pcall(function() mouse2press() end)
        held = true
      end
      RR.Input.moveRel(150, 0)
      searched = searched + 1
      if searched > 24 then break end
    end
    wait(0.03)
  end

  if held then
    pcall(function() mouse2release() end)
  end
  return converged
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

  RR.Input.keyDown(VK.W)

  while tick() < deadline do
    if not RR.Util.alive() then
      RR.Input.keyUp(VK.W)
      return false, "died"
    end

    local pos = RR.Util.charPos()
    if pos and (pos - target).Magnitude <= tol then
      RR.Input.keyUp(VK.W)
      Move.Stats.arrived = Move.Stats.arrived + 1
      return true
    end

    Move.lookAt(target, 60, 260)

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

  RR.Input.keyUp(VK.W)
  Move.Stats.failed = Move.Stats.failed + 1
  Move.Stats.lastErr = "walk timeout"
  return false, "timeout"
end

function Move.stop()
  pcall(function() RR.Input.keyUp(VK.W) end)
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
