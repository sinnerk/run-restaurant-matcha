--[[ ==================================================================
     30_act : actions

     The only interaction surfaces that exist from outside the process:
       - ProximityPrompt, activated by standing close, facing it, and
         sending its own key code for its own hold duration
       - ClickDetector, activated by clicking the part on screen
       - things that respond to a tool being equipped, via the number
         keys, which only works if the tool is already in the hotbar

     Anything the game does through a RemoteEvent is out of reach, and
     the place has exactly one RemoteEvent, so this is the whole toolkit.
     ================================================================== ]]

local RR = _G.RR
local Act = RR.Act or {}
RR.Act = Act

Act.Stats = Act.Stats or {
  prompts   = 0,
  promptOk  = 0,
  clicks    = 0,
  clickOk   = 0,
  lastErr   = "",
}

local VK = RR.Input.VK

-- prompt field with a fallback
local function field(inst, key, default)
  local v = nil
  local ok = pcall(function() v = inst[key] end)
  if ok and v ~= nil then return v end
  return default
end

local function promptKeyVK(prompt)
  local k = field(prompt, "KeyboardKeyCode", nil)
  if type(k) == "number" and k > 0 then return k end
  if type(k) == "userdata" or type(k) == "table" then
    -- Enum.KeyCode -> number, if the bridge exposes .Value
    local n = nil
    pcall(function() n = k.Value end)
    if type(n) == "number" and n > 0 then return n end
  end
  return VK.E
end

-- Activate one prompt. opts:
--   approach  : false to skip walking (default true)
--   tol       : arrival tolerance in studs (default 4)
--   verify    : function(inst) -> boolean, polled after the press
--   verifyMs  : how long to poll verify (default 800)
function Act.prompt(p, opts)
  opts = opts or {}
  if not p or not p.inst then return false, "no prompt" end
  Act.Stats.prompts = Act.Stats.prompts + 1

  local anchorPos = p.pos or RR.World.posOf(p.anchor)
  if not anchorPos then
    Act.Stats.lastErr = "prompt has no position"
    return false, Act.Stats.lastErr
  end

  local maxDist = field(p.inst, "MaxActivationDistance", 10)
  if type(maxDist) ~= "number" or maxDist <= 0 then maxDist = 10 end
  local want = math.min(maxDist * 0.75, opts.tol or 6)

  if opts.approach ~= false then
    local pos = RR.Util.charPos()
    if not pos or (pos - anchorPos).Magnitude > want then
      local ok = RR.Move.goto(anchorPos, { tol = want, timeout = opts.timeout or 12 })
      if not ok then
        Act.Stats.lastErr = "could not reach prompt"
        return false, Act.Stats.lastErr
      end
    end
  end

  -- face it, otherwise the prompt is not focused and E does nothing
  RR.Move.lookAt(anchorPos + Vector3.new(0, 1.5, 0), 70, 700)

  local vk = promptKeyVK(p.inst)
  local hold = field(p.inst, "HoldDuration", 0)
  if type(hold) ~= "number" or hold < 0 then hold = 0 end
  local holdMs = (hold * 1000) + 90

  if not RR.Input.hold(vk, holdMs, "prompt") then
    Act.Stats.lastErr = "input gate closed"
    return false, Act.Stats.lastErr
  end
  wait(0.08)

  if opts.verify then
    local deadline = tick() + ((opts.verifyMs or 800) / 1000)
    while tick() < deadline do
      local ok, res = pcall(opts.verify, p.inst)
      if ok and res == true then
        Act.Stats.promptOk = Act.Stats.promptOk + 1
        return true, "verified"
      end
      wait(0.06)
    end
    Act.Stats.lastErr = "no confirmation"
    return false, Act.Stats.lastErr
  end

  Act.Stats.promptOk = Act.Stats.promptOk + 1
  return true, "pressed"
end

-- Click a world position
function Act.clickPart(part, opts)
  opts = opts or {}
  if not part then return false, "no part" end
  local pos = RR.World.posOf(part)
  if not pos then return false, "no position" end

  local ok = RR.Input.clickAt(pos, opts.offsetX, opts.offsetY)
  Act.Stats.clicks = Act.Stats.clicks + 1
  if ok then
    Act.Stats.clickOk = Act.Stats.clickOk + 1
    return true, "clicked"
  end
  Act.Stats.lastErr = "click point off screen or gate closed"
  return false, Act.Stats.lastErr
end

-- ClickDetector: walk into range first, then click the parent part
function Act.clickDetector(entry, opts)
  opts = opts or {}
  if not entry or not entry.anchor then return false, "no detector" end

  local maxDist = field(entry.inst, "MaxActivationDistance", 32)
  if type(maxDist) ~= "number" or maxDist <= 0 then maxDist = 32 end
  local want = math.min(maxDist * 0.7, 20)

  local pos = RR.World.posOf(entry.anchor)
  if not pos then return false, "detector parent has no position" end

  local me = RR.Util.charPos()
  if not me or (me - pos).Magnitude > want then
    local ok = RR.Move.goto(pos, { tol = want, timeout = opts.timeout or 14 })
    if not ok then return false, "could not reach detector" end
  end

  RR.Move.lookAt(pos, 60, 600)
  return Act.clickPart(entry.anchor, opts)
end

-- Is a prompt currently usable from where we stand?
function Act.promptInRange(p)
  if not p then return false end
  local me = RR.Util.charPos()
  local pos = p.pos or RR.World.posOf(p.anchor)
  if not me or not pos then return false end
  local maxDist = field(p.inst, "MaxActivationDistance", 10)
  if type(maxDist) ~= "number" or maxDist <= 0 then maxDist = 10 end
  return (me - pos).Magnitude <= maxDist
end

function Act.summary()
  local s = Act.Stats
  return string.format("prompts %d/%d  clicks %d/%d", s.promptOk, s.prompts, s.clickOk, s.clicks)
end
