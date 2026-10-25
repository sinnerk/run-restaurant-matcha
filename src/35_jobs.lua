--[[ ==================================================================
     35_jobs : scheduler

     A job is one thing the bot can do. Every job declares a weight
     (how much it matters), a cooldown (how often it may run) and a
     run function that does one attempt and returns true when it
     actually did something.

     The scheduler always runs the highest-weight job that is ready, so
     a restaurant that is on fire never waits behind a fishing trip.
     A job that keeps failing backs off instead of spinning.
     ================================================================== ]]

local RR = _G.RR
local Jobs = RR.Jobs or {}
RR.Jobs = Jobs

Jobs.list   = Jobs.list or {}
Jobs.n      = Jobs.n or 0
Jobs.byId   = Jobs.byId or {}
Jobs.Stats  = Jobs.Stats or { runs = 0, ok = 0, fail = 0, skipped = 0, lastId = "-" }
Jobs.paused = false

-- def = { id, label, weight, cooldown, enabled, run }
function Jobs.add(def)
  if not def or not def.id then return nil end
  local existing = Jobs.byId[def.id]
  if existing then
    existing.label    = def.label or existing.label
    existing.weight   = def.weight or existing.weight
    existing.cooldown = def.cooldown or existing.cooldown
    existing.enabled  = def.enabled or existing.enabled
    existing.run      = def.run or existing.run
    return existing
  end

  def.weight      = def.weight or 5
  def.cooldown    = def.cooldown or 2
  def.lastRun     = -1e9
  def.lastOk      = nil
  def.failStreak  = 0
  def.runs        = 0
  def.lastResult  = "-"
  def.stats       = { ok = 0, fail = 0 }

  Jobs.n = Jobs.n + 1
  Jobs.list[Jobs.n] = def
  Jobs.byId[def.id] = def
  return def
end

function Jobs.get(id)
  return Jobs.byId[id]
end

function Jobs.enabled(def)
  if Jobs.paused then return false end
  if def.enabled then
    local ok, res = pcall(def.enabled)
    if ok then return res == true end
    return false
  end
  return RR.Cfg.get("job." .. def.id, true) == true
end

-- effective cooldown grows with consecutive failures, capped
function Jobs.ready(def, now)
  local cd = def.cooldown or 2
  if def.failStreak > 0 then
    cd = cd * (1 + math.min(def.failStreak, 5))
  end
  return (now - (def.lastRun or -1e9)) >= cd
end

function Jobs.pick(now)
  local best, bestWeight = nil, -1
  for i = 1, Jobs.n do
    local def = Jobs.list[i]
    if Jobs.enabled(def) and Jobs.ready(def, now) then
      local w = def.weight or 5
      if w > bestWeight then
        best, bestWeight = def, w
      end
    end
  end
  return best
end

-- run at most one job per call; the caller decides the cadence
function Jobs.tick()
  if not RR.World.ready() then return end
  local now = tick()
  local def = Jobs.pick(now)
  if not def then return end

  def.lastRun = now
  def.runs = def.runs + 1
  Jobs.Stats.runs = Jobs.Stats.runs + 1
  Jobs.Stats.lastId = def.id

  local ok, result = pcall(def.run)
  if not ok then
    def.failStreak = def.failStreak + 1
    def.stats.fail = def.stats.fail + 1
    def.lastOk = false
    def.lastResult = "error: " .. tostring(result)
    Jobs.Stats.fail = Jobs.Stats.fail + 1
    RR.Log.add("error", "job " .. def.id .. " threw: " .. tostring(result))
    return
  end

  if result == true then
    def.failStreak = 0
    def.lastOk = true
    def.stats.ok = def.stats.ok + 1
    def.lastResult = "ok"
    Jobs.Stats.ok = Jobs.Stats.ok + 1
  else
    def.failStreak = def.failStreak + 1
    def.lastOk = false
    def.lastResult = tostring(result or "no action")
    if def.failStreak >= 3 then
      RR.Log.add("warn", "job " .. def.id .. " cooling down: " .. def.lastResult)
    end
  end
end

function Jobs.summary()
  local s = Jobs.Stats
  return string.format("%d jobs, %d runs (%d ok / %d fail)", Jobs.n, s.runs, s.ok, s.fail)
end
