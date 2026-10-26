--[[ ==================================================================
     tests/stub.luau : just enough Roblox to load the real modules

     This is NOT a Roblox emulator. It implements only the globals and
     datatypes that src/ touches at load time and in the pure functions
     under test, so the suite can execute actual src/*.lua files in a
     real Luau VM instead of only parsing them.

     Anything a module calls that is missing here shows up as a load
     error, which is itself a useful signal: it means the module needs
     a Roblox service the pure layer should not depend on.
     ================================================================== ]]

-- ---------------------------------------------------------------------
-- fake clock: tick() advances every read so deadline loops terminate
-- ---------------------------------------------------------------------
-- The Luau CLI marks the real global table readonly, so shadow it. The
-- whole suite is concatenated into one chunk, which means every module
-- below resolves _G to this plain table - the same contract Matcha gives
-- them at runtime, minus the freeze.
local _G = {}

local clock = 0

function tick()
  clock = clock + 0.001
  return clock
end

function wait(seconds)
  clock = clock + (seconds or 0)
end

-- ---------------------------------------------------------------------
-- datatypes
-- ---------------------------------------------------------------------
local V3 = {}
local function v3(x, y, z)
  return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V3)
end

V3.__index = function(t, k)
  if k == "Magnitude" then
    return math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z)
  end
  if k == "Unit" then
    local m = math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z)
    if m == 0 then return v3(0, 0, 0) end
    return v3(t.X / m, t.Y / m, t.Z / m)
  end
  return nil
end
V3.__add = function(a, b) return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V3.__sub = function(a, b) return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V3.__mul = function(a, b)
  if type(b) == "number" then return v3(a.X * b, a.Y * b, a.Z * b) end
  if type(a) == "number" then return v3(b.X * a, b.Y * a, b.Z * a) end
  return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3.__div = function(a, b)
  if type(b) == "number" then return v3(a.X / b, a.Y / b, a.Z / b) end
  return v3(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
V3.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
V3.__tostring = function(a)
  return string.format("%.1f, %.1f, %.1f", a.X, a.Y, a.Z)
end

Vector3 = { new = v3 }

local V2 = {}
local function v2(x, y)
  return setmetatable({ X = x or 0, Y = y or 0 }, V2)
end

V2.__add = function(a, b) return v2(a.X + b.X, a.Y + b.Y) end
V2.__sub = function(a, b) return v2(a.X - b.X, a.Y - b.Y) end
V2.__eq = function(a, b) return a.X == b.X and a.Y == b.Y end
V2.__tostring = function(a) return string.format("%.1f, %.1f", a.X, a.Y) end

Vector2 = { new = v2 }

Color3 = {
  fromRGB = function(r, g, b) return { R = r, G = g, B = b } end,
  new = function(r, g, b) return { R = r, G = g, B = b } end,
}

CFrame = {
  new = function(x, y, z)
    if type(x) == "table" then return { Position = x } end
    return { Position = Vector3.new(x, y, z) }
  end,
}

Drawing = {
  new = function(kind)
    local d = { kind = kind, Visible = true, Position = Vector2.new(0, 0) }
    function d:Remove() self.removed = true end
    return d
  end,
}

-- ---------------------------------------------------------------------
-- services
-- ---------------------------------------------------------------------
local camera = {
  ViewportSize = Vector2.new(1000, 800),
  FieldOfView = 70,
  Position = Vector3.new(0, 0, 0),
  CFrame = CFrame.new(0, 0, 0),
  CameraType = "Custom",
}

-- ---------------------------------------------------------------------
-- player / PlayerGui: enough for GUI scanning and clicking
-- ---------------------------------------------------------------------
local screenGui = { ClassName = "ScreenGui", Name = "Main", Enabled = true }
local visibleFrame = { ClassName = "Frame", Name = "BuyFrame", Visible = true }
local hiddenFrame = { ClassName = "Frame", Name = "HiddenFrame", Visible = false }

local buyButton = {
  ClassName = "TextButton",
  Name = "BuyButton",
  Text = "Buy 10",
  Visible = true,
  AbsolutePosition = Vector2.new(100, 200),
  AbsoluteSize = Vector2.new(80, 40),
}

local hiddenButton = {
  ClassName = "TextButton",
  Name = "SecretButton",
  Text = "Secret",
  Visible = true,             -- own flag says yes, parent says no
  AbsolutePosition = Vector2.new(400, 400),
  AbsoluteSize = Vector2.new(60, 30),
}

buyButton.Parent = visibleFrame
hiddenButton.Parent = hiddenFrame
visibleFrame.Parent = screenGui
hiddenFrame.Parent = screenGui

local playerGui = {
  ClassName = "PlayerGui",
  Name = "PlayerGui",
  GetDescendants = function()
    return { screenGui, visibleFrame, buyButton, hiddenFrame, hiddenButton }
  end,
  GetChildren = function() return { screenGui } end,
}

local localPlayer = {
  ClassName = "Player",
  Name = "Tester",
  Character = nil,
  FindFirstChildOfClass = function(_, cls)
    if cls == "PlayerGui" then return playerGui end
    return nil
  end,
}

local services = {
  Workspace = {
    CurrentCamera = camera,
    GetDescendants = function() return {} end,
    GetChildren = function() return {} end,
  },
  Players = { LocalPlayer = localPlayer },
  HttpService = {
    JSONEncode = function(_, v) return "{}" end,
    JSONDecode = function(_, s) return {} end,
    GenerateGUID = function() return "guid" end,
  },
  RunService = {
    RenderStepped = { Connect = function() return { Disconnect = function() end } end },
    Heartbeat = { Connect = function() return { Disconnect = function() end } end },
    Stepped = { Connect = function() return { Disconnect = function() end } end },
  },
  ReplicatedStorage = { GetChildren = function() return {} end, GetDescendants = function() return {} end },
  UserInputService = {},
}

game = {
  PlaceId = 121042,
  GameId = 0,
  JobId = "",
  GetService = function(_, name) return services[name] end,
}

workspace = services.Workspace

-- ---------------------------------------------------------------------
-- executor globals
-- ---------------------------------------------------------------------
-- observable side effects, so tests can assert that a click really moved
-- the cursor to the pixels a button occupies
__stub = { moves = {}, clicks = 0, cursor = { x = 0, y = 0 } }

local log = {}

function printl(msg) log[#log + 1] = tostring(msg) end
function notify() end
function identifyexecutor() return "stub", "0.0" end
function getgamename() return "stub place" end
function isrbxactive() return true end
function iskeypressed() return false end
function ismouse1pressed() return false end
function ismouse2pressed() return false end
function keypress() end
function keyrelease() end
function mouse1click() __stub.clicks = __stub.clicks + 1 end
function mouse1press() end
function mouse1release() end
function mouse2press() end
function mouse2release() end
function mouse2click() end
function mousemoveabs(x, y)
  __stub.moves[#__stub.moves + 1] = { x = x, y = y }
  __stub.cursor.x, __stub.cursor.y = x, y
end
function mousemoverel() end
function mousescroll() end
function writefile() end
function readfile() return "" end
function isfile() return false end
function isfolder() return false end
function makefolder() end
function base64encode(s) return s end
function base64decode(s) return s end
function httpget() return "" end
function httppost() return "" end

-- Projection is the only behaviour the tests need to steer: a world
-- position's X becomes a screen offset from the centre.
function WorldToScreen(pos)
  if type(pos) ~= "table" then return Vector2.new(0, 0), false end
  local x = pos.X or 0
  if x < -800 then return Vector2.new(0, 0), false end
  return Vector2.new(500 + x, 400), true
end

-- ---------------------------------------------------------------------
-- tiny instance stand-in
-- ---------------------------------------------------------------------
function makeInstance(className, name, fields)
  local inst = { ClassName = className, Name = name or className }
  for k, v in pairs(fields or {}) do inst[k] = v end
  return inst
end
