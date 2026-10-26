--[[ ==================================================================
     30_act : actions

     The only interaction surfaces that exist from outside the process:

       - ProximityPrompt, activated by standing close, facing it, and
         sending its own key code for its own hold duration
       - ClickDetector, activated by clicking the part on screen
       - a Tool in the hotbar, equipped with its number key

     Anything the game does through a RemoteEvent is out of reach, and
     this place has exactly one RemoteEvent, so this is the toolkit.

     Two things here come straight out of the engine docs and were wrong
     in the first build:

     1. KeyboardKeyCode is an Enum.KeyCode, whose .Value is ASCII
        (E = 101), not a Windows virtual-key code (E = 69). Pressing 101
        hits numpad-5. src/12_keymap resolves this properly.

     2. A prompt only triggers when the client has it *active*, and only
        one prompt per key can be active at a time (Exclusivity defaults
        to OnePerButton). If a second prompt is closer to the centre of
        the screen, pressing the key activates that one instead. So a
        press is only meaningful once we have aimed at ours.

     Docs: ProximityPrompt, ProximityPromptExclusivity, ClickDetector.
     ================================================================== ]]

local RR = _G.RR
local Act = RR.Act or {}
RR.Act = Act

Act.Stats = Act.Stats or {
  prompts     = 0,
  promptOk    = 0,
  promptMiss  = 0,
  holdOk      = 0,
  rivals      = 0,
  clicks      = 0,
  clickOk     = 0,
  guiClicks   = 0,
  lastErr     = "",
}

local VK = RR.KeyMap.VK

-- prompt field with a fallback that never throws
local function field(inst, key, default)
  local v = nil
  local ok = pcall(function() v = inst[key] end)
  if ok and v ~= nil then return v end
  return default
end

-- enum item -> short name ("OnePerButton"), without assuming .Name exists
local function enumName(v)
  if v == nil then return nil end
  local n = nil
  pcall(function() n = v.Name end)
  if type(n) == "string" and n ~= "" then return n end
  local s = tostring(v)
  local tail = string.match(s, "([%w_]+)$")
  if tail then return tail end
  return nil
end

-- ---------------------------------------------------------------------
-- reading a prompt
-- ---------------------------------------------------------------------
-- Everything a press depends on, read once per attempt.
function Act.flags(prompt)
  local key = field(prompt, "KeyboardKeyCode", nil)

  local hold = field(prompt, "HoldDuration", 0)
  if type(hold) ~= "number" or hold < 0 then hold = 0 end

  local maxDist = field(prompt, "MaxActivationDistance", 10)
  if type(maxDist) ~= "number" or maxDist <= 0 then maxDist = 10 end

  local excl = field(prompt, "Exclusivity", nil)

  return {
    key         = key,
    vk          = RR.KeyMap.resolve(key, VK.E),
    hold        = hold,
    maxDist     = maxDist,
    los         = field(prompt, "RequiresLineOfSight", true) == true,
    clickable   = field(prompt, "ClickablePrompt", false) == true,
    enabled     = field(prompt, "Enabled", true) ~= false,
    exclusivity = excl,
    exclName    = enumName(excl) or "OnePerButton",
    actionText  = field(prompt, "ActionText", ""),
    objectText  = field(prompt, "ObjectText", ""),
  }
end

-- how far a world position is from the middle of the screen, in pixels.
-- Nearer means "this is the prompt the client will activate".
function Act.focusScore(pos)
  return RR.Util.focusScore(pos)
end

-- ---------------------------------------------------------------------
-- ground truth: ProximityPromptService
-- ---------------------------------------------------------------------
-- PromptShown / PromptHidden are client-side signals that fire exactly
-- when a prompt becomes the active one. If the executor surfaces them we
-- stop guessing which prompt owns the key and simply ask.
Act.watching = Act.watching or false
Act.active = Act.active or nil
Act.lastTriggered = Act.lastTriggered or nil

function Act.watch()
  if Act.watching then return true end

  local svc = nil
  pcall(function()
    local pp = game:GetService("ProximityPromptService")
    svc = pp
  end)
  if not svc then return false end

  local conns = {}
  local ok = pcall(function()
    local c1 = svc.PromptShown:Connect(function(prompt)
      Act.active = prompt
      Act.shownAt = tick()
    end)
    if c1 then conns[#conns + 1] = c1 end

    local c2 = svc.PromptHidden:Connect(function(prompt)
      if Act.active == prompt then Act.active = nil end
    end)
    if c2 then conns[#conns + 1] = c2 end

    -- PromptTriggered is the authoritative "the press worked" signal
    local c3 = svc.PromptTriggered:Connect(function(prompt)
      Act.lastTriggered = prompt
      Act.triggeredAt = tick()
    end)
    if c3 then conns[#conns + 1] = c3 end
  end)

  Act.conns = conns
  Act.watching = ok
  if ok then RR.log("prompt service observed: activation is verifiable") end
  return ok
end

function Act.unwatch()
  local conns = Act.conns or {}
  for i = 1, #conns do
    pcall(function() conns[i]:Disconnect() end)
  end
  Act.conns = {}
  Act.watching = false
  Act.active = nil
  Act.lastTriggered = nil
end

-- true / false when the service is available, nil when we do not know
function Act.isActive(p)
  if not Act.watching or not p then return nil end
  local inst = p.inst or p
  return Act.active == inst
end

function Act.activeName()
  local a = Act.active
  if not a then return "none" end
  local n = nil
  pcall(function() n = a:GetFullName() end)
  return n or "?"
end

-- one line for the report and the menu: whether activation is observed
-- or guessed
function Act.watchSummary()
  if Act.watching then
    return "observed (active: " .. Act.activeName() .. ")"
  end
  return "not exposed - using camera heuristics"
end

-- ---------------------------------------------------------------------
-- competing prompts
-- ---------------------------------------------------------------------
-- Roblox shows at most one prompt per key (OnePerButton), or one prompt
-- in total (OneGlobally). Either way the camera decides the winner, and
-- the loser swallows the key press. This finds the prompts that would
-- beat ours right now, so the caller can aim again instead of pressing
-- into the void.
function Act.competitors(p, f, anchorPos)
  local out = { count = 0, best = nil, bestScore = nil, mine = math.huge }
  if not p or not anchorPos then return out end

  local list = RR.World.livePrompts()
  if #list == 0 then return out end

  local me = RR.Util.charPos()
  if not me then return out end

  out.mine = RR.Util.focusScore(anchorPos)
  if out.mine == math.huge then return out end

  for i = 1, #list do
    local q = list[i]
    if q.inst ~= p.inst then
      local sameKey = (q.vk == nil) or (q.vk == f.vk)
      -- OneGlobally: any prompt can take the slot, whatever its key
      local relevant = sameKey or (f.exclName == "OneGlobally")
      -- AlwaysShow never takes anything away from anyone
      if f.exclName == "AlwaysShow" then relevant = false end

      if relevant then
        local d = (me - q.pos).Magnitude
        local qmax = q.maxDist or 10
        if d <= qmax then
          local score = RR.Util.focusScore(q.pos)
          if score < out.mine then
            out.count = out.count + 1
            if not out.bestScore or score < out.bestScore then
              out.best = q
              out.bestScore = score
            end
          end
        end
      end
    end
  end

  return out
end

-- ---------------------------------------------------------------------
-- pressing
-- ---------------------------------------------------------------------
-- The documented path: real key input, real hold duration.
function Act.pressKey(f)
  local holdMs = (f.hold * 1000) + 90
  if not RR.Input.hold(f.vk, holdMs, "prompt") then
    return false, "input gate closed"
  end
  return true, "key"
end

-- The documented-but-unverified path: ProximityPrompt:InputHoldBegin()
-- exists on the class and is what the default prompt UI calls when you
-- click a ClickablePrompt. Whether an externally emulated client turns
-- that signal into a trigger is build-dependent, so this is opt-in and
-- always followed by the caller's verify function.
function Act.promptHold(p, f)
  if not p or not p.inst then return false, "no prompt" end

  local began = pcall(function() p.inst:InputHoldBegin() end)
  if not began then return false, "InputHoldBegin unavailable" end

  wait((f.hold + 0.14))
  pcall(function() p.inst:InputHoldEnd() end)

  Act.Stats.holdOk = Act.Stats.holdOk + 1
  return true, "inputHold"
end

-- ClickablePrompt is a second documented activation path: the prompt's
-- own UI is a button. We cannot see that UI, but the click lands on the
-- anchor part, which is where the UI hovers.
function Act.promptClick(p, opts)
  if not p or not p.anchor then return false, "no anchor" end
  local pos = p.pos or RR.World.posOf(p.anchor)
  if not pos then return false, "no position" end
  return Act.clickPart(p.anchor, { offsetY = opts and opts.offsetY })
end

-- ---------------------------------------------------------------------
-- the main entry point
-- ---------------------------------------------------------------------
-- Activate one prompt. opts:
--   approach     : false to skip walking (default true)
--   tol          : arrival tolerance in studs (default 6)
--   timeout      : seconds allowed for the approach (default 12)
--   aim          : false to skip camera aiming (default true)
--   strict       : true to give up when a rival prompt wins the slot
--   method       : "key" (default) | "hold" | "click"
--   verify       : function(inst) -> boolean, polled after the press
--   verifyMs     : how long to poll verify (default 900)
function Act.prompt(p, opts)
  opts = opts or {}
  if not p or not p.inst then return false, "no prompt" end
  Act.Stats.prompts = Act.Stats.prompts + 1

  local anchorPos = p.pos or RR.World.posOf(p.anchor)
  if not anchorPos then
    Act.Stats.lastErr = "prompt has no position"
    return false, Act.Stats.lastErr
  end

  local f = Act.flags(p.inst)

  if f.enabled == false then
    Act.Stats.lastErr = "prompt is disabled"
    return false, Act.Stats.lastErr
  end

  -- 1. get in range -------------------------------------------------
  local want = math.min(f.maxDist * 0.75, opts.tol or 6)
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

  -- 2. aim ----------------------------------------------------------
  -- Required for two independent reasons: a prompt with
  -- RequiresLineOfSight (default true) is hidden when something blocks
  -- the camera, and the client picks the on-screen prompt by camera
  -- direction, not by distance.
  local aimed = true
  if opts.aim ~= false then
    aimed = RR.Move.lookAt(anchorPos + Vector3.new(0, 1.5, 0), 70, 800)
  end

  if f.los and not aimed then
    -- one more, wider sweep before giving up on line of sight
    aimed = RR.Move.lookAt(anchorPos + Vector3.new(0, 1.5, 0), 110, 600)
    if not aimed then
      Act.Stats.promptMiss = Act.Stats.promptMiss + 1
      Act.Stats.lastErr = "prompt out of view (RequiresLineOfSight)"
      return false, Act.Stats.lastErr
    end
  end

  -- 3. make sure the key is not going to hit a neighbour ------------
  -- The service, when available, is authoritative. Otherwise fall back
  -- to the camera-centre heuristic, which is what the client uses when
  -- Exclusivity is OnePerButton or OneGlobally.
  if Act.watching then
    if not Act.isActive(p) then
      RR.Move.lookAt(anchorPos + Vector3.new(0, 1.5, 0), 40, 600)
    end
    if not Act.isActive(p) then
      Act.Stats.promptMiss = Act.Stats.promptMiss + 1
      Act.Stats.lastErr = "not the active prompt (active: " .. Act.activeName() .. ")"
      return false, Act.Stats.lastErr
    end
  elseif opts.strict then
    local rivals = Act.competitors(p, f, anchorPos)
    if rivals.count > 0 then
      RR.Move.lookAt(anchorPos + Vector3.new(0, 1.5, 0), 40, 500)
      rivals = Act.competitors(p, f, anchorPos)
      if rivals.count > 0 then
        Act.Stats.rivals = Act.Stats.rivals + 1
        local who = rivals.best and rivals.best.aname or "?"
        Act.Stats.lastErr = "another prompt owns the key: " .. tostring(who)
        return false, Act.Stats.lastErr
      end
    end
  end

  -- 4. press --------------------------------------------------------
  local method = opts.method or RR.Cfg.get("promptMethod", "key")
  local pressed, how

  if method == "hold" then
    pressed, how = Act.promptHold(p, f)
    if not pressed then
      pressed, how = Act.pressKey(f)
    end
  elseif method == "click" then
    pressed, how = Act.promptClick(p, opts)
    if not pressed then
      pressed, how = Act.pressKey(f)
    end
  else
    pressed, how = Act.pressKey(f)
  end

  if not pressed then
    Act.Stats.lastErr = tostring(how)
    return false, Act.Stats.lastErr
  end
  wait(0.08)

  -- 5. confirm ------------------------------------------------------
  -- A PromptTriggered observation beats any heuristic: the game said so.
  if Act.watching and Act.lastTriggered == p.inst then
    Act.Stats.promptOk = Act.Stats.promptOk + 1
    return true, "triggered"
  end

  if opts.verify then
    local deadline = tick() + ((opts.verifyMs or 900) / 1000)
    while tick() < deadline do
      if Act.watching and Act.lastTriggered == p.inst then
        Act.Stats.promptOk = Act.Stats.promptOk + 1
        return true, "triggered"
      end
      local ok, res = pcall(opts.verify, p.inst)
      if ok and res == true then
        Act.Stats.promptOk = Act.Stats.promptOk + 1
        return true, how or "verified"
      end
      wait(0.06)
    end
    Act.Stats.promptMiss = Act.Stats.promptMiss + 1
    Act.Stats.lastErr = "pressed (" .. tostring(how) .. ") but no confirmation"
    return false, Act.Stats.lastErr
  end

  Act.Stats.promptOk = Act.Stats.promptOk + 1
  return true, how or "pressed"
end

-- ---------------------------------------------------------------------
-- clicking
-- ---------------------------------------------------------------------
function Act.clickPart(part, opts)
  opts = opts or {}
  -- accept either an instance or a position
  local pos = opts.pos or RR.World.posOf(part)
  if not pos then return false, "no position" end

  Act.Stats.clicks = Act.Stats.clicks + 1
  local ok = RR.Input.clickAt(pos, opts.offsetX, opts.offsetY)
  if ok then
    Act.Stats.clickOk = Act.Stats.clickOk + 1
    return true, "clicked"
  end
  Act.Stats.lastErr = "click point off screen or gate closed"
  return false, Act.Stats.lastErr
end

-- ClickDetector: walk into range first, then click the parent part.
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

-- ---------------------------------------------------------------------
-- GUI buttons
-- ---------------------------------------------------------------------
-- Shop, cooking and upgrade menus are almost always TextButtons in
-- PlayerGui. A real click at the button's AbsolutePosition is
-- indistinguishable from the player's own click: the client's own code
-- receives it and does whatever it would have done. This is the one
-- interaction path that works for systems with no prompt and no part.
function Act.clickGui(button, opts)
  opts = opts or {}
  if not button or not button.inst then return false, "no button" end
  if not RR.Util.guiShown(button.inst) then return false, "button not visible" end

  local centre = button.pos or RR.Util.guiCenter(button.inst)
  if not centre then return false, "button has no size" end

  Act.Stats.clicks = Act.Stats.clicks + 1
  Act.Stats.guiClicks = (Act.Stats.guiClicks or 0) + 1

  if not RR.Input.clickScreen(centre.X, centre.Y) then
    Act.Stats.lastErr = "gui click off screen or gate closed"
    return false, Act.Stats.lastErr
  end
  Act.Stats.clickOk = Act.Stats.clickOk + 1

  if opts.verify then
    local deadline = tick() + ((opts.verifyMs or 800) / 1000)
    while tick() < deadline do
      local ok, res = pcall(opts.verify)
      if ok and res == true then return true, "gui" end
      wait(0.05)
    end
    Act.Stats.lastErr = "clicked gui but no confirmation"
    return false, Act.Stats.lastErr
  end

  return true, "gui"
end

-- click the best visible button whose name or label matches a pattern
function Act.clickGuiNamed(pattern, opts)
  local hits = RR.World.findGui(pattern)
  if #hits == 0 then
    return false, "no visible button matching " .. tostring(pattern)
  end
  return Act.clickGui(hits[1], opts)
end

-- Is a prompt currently usable from where we stand?
function Act.promptInRange(p)
  if not p then return false end
  local me = RR.Util.charPos()
  local pos = p.pos or RR.World.posOf(p.anchor)
  if not me or not pos then return false end
  local f = Act.flags(p.inst)
  return (me - pos).Magnitude <= f.maxDist
end

function Act.summary()
  local s = Act.Stats
  return string.format("prompts %d/%d miss=%d rivals=%d  clicks %d/%d gui=%d",
    s.promptOk, s.prompts, s.promptMiss, s.rivals, s.clickOk, s.clicks, s.guiClicks or 0)
end
