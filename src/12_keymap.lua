--[[ ==================================================================
     12_keymap : Roblox KeyCode  ->  Windows virtual-key

     This module exists because of a bug that would have made every
     prompt press land on the wrong key.

     Roblox's KeyCode enum is not a Windows VK code. It reuses ASCII:

         Enum.KeyCode.A   = 97    ('a')      Windows VK_A  = 65
         Enum.KeyCode.E   = 101   ('e')      Windows VK_E  = 69
         Enum.KeyCode.Z   = 122   ('z')      Windows VK_Z  = 90

     So reading `.Value` and handing it to keypress() presses numpad
     keys: 101 is VK_NUMPAD5, not E. The cheat never fires, the prompt
     never opens, and nothing in the log says why.

     Everything here is pure: no services, no globals, no side effects,
     so tests/ can execute it under a real Luau VM.

     Reference: https://create.roblox.com/docs/reference/engine/enums/KeyCode
     ================================================================== ]]

local RR = rawget(_G, "RR")
if type(RR) ~= "table" then
  RR = {}
  _G.RR = RR
end

local KeyMap = RR.KeyMap or {}
RR.KeyMap = KeyMap

-- ---------------------------------------------------------------------
-- named constants (VK)
-- ---------------------------------------------------------------------
KeyMap.VK = {
  A = 0x41, B = 0x42, C = 0x43, D = 0x44, E = 0x45, F = 0x46, G = 0x47,
  H = 0x48, I = 0x49, J = 0x4A, K = 0x4B, L = 0x4C, M = 0x4D, N = 0x4E,
  O = 0x4F, P = 0x50, Q = 0x51, R = 0x52, S = 0x53, T = 0x54, U = 0x55,
  V = 0x56, W = 0x57, X = 0x58, Y = 0x59, Z = 0x5A,

  DIGIT0 = 0x30, DIGIT1 = 0x31, DIGIT2 = 0x32, DIGIT3 = 0x33, DIGIT4 = 0x34,
  DIGIT5 = 0x35, DIGIT6 = 0x36, DIGIT7 = 0x37, DIGIT8 = 0x38, DIGIT9 = 0x39,

  SPACE = 0x20, ENTER = 0x0D, ESC = 0x1B, TAB = 0x09, BACKSPACE = 0x08,
  SHIFT = 0x10, CTRL = 0x11, ALT = 0x12, CAPSLOCK = 0x14,
  LSHIFT = 0xA0, RSHIFT = 0xA1, LCTRL = 0xA2, RCTRL = 0xA3,
  LALT = 0xA4, RALT = 0xA5,

  LEFT = 0x25, UP = 0x26, RIGHT = 0x27, DOWN = 0x28,
  INSERT = 0x2D, DELETE = 0x2E, HOME = 0x24, END = 0x23,
  PAGEUP = 0x21, PAGEDOWN = 0x22,

  F1 = 0x70, F2 = 0x71, F3 = 0x72, F4 = 0x73, F5 = 0x74, F6 = 0x75,
  F7 = 0x76, F8 = 0x77, F9 = 0x78, F10 = 0x79, F11 = 0x7A, F12 = 0x7B,
}

local VK = KeyMap.VK

-- ---------------------------------------------------------------------
-- Roblox KeyCode -> VK
-- ---------------------------------------------------------------------
-- Only codes that are unambiguously Roblox KeyCodes go in this table.
-- Anything not listed returns nil and the caller decides the fallback;
-- guessing here means pressing a key nobody asked for.
local CODE_TO_VK = {
  [8]   = VK.BACKSPACE,
  [9]   = VK.TAB,
  [13]  = VK.ENTER,
  [27]  = VK.ESC,
  [32]  = VK.SPACE,
  [44]  = 0xBC,          -- Comma
  [45]  = 0xBD,          -- Minus
  [46]  = 0xBE,          -- Period
  [47]  = 0xBF,          -- Slash
  [59]  = 0xBA,          -- Semicolon
  [61]  = 0xBB,          -- Equals
  [91]  = 0xDB,          -- LeftBracket
  [92]  = 0xDC,          -- BackSlash
  [93]  = 0xDD,          -- RightBracket
  [96]  = 0xC0,          -- Backquote
  [127] = VK.DELETE,
  [273] = VK.UP,
  [274] = VK.DOWN,
  [275] = VK.RIGHT,
  [276] = VK.LEFT,
  [277] = VK.INSERT,
  [278] = VK.HOME,
  [279] = VK.END,
  [280] = VK.PAGEUP,
  [281] = VK.PAGEDOWN,
  [300] = 0x90,          -- NumLock
  [301] = VK.CAPSLOCK,
  [302] = 0x91,          -- ScrollLock
  [303] = VK.RSHIFT,
  [304] = VK.LSHIFT,
  [305] = VK.RCTRL,
  [306] = VK.LCTRL,
  [307] = VK.RALT,
  [308] = VK.LALT,
}

-- digits 48..57 are already VK 0x30..0x39
for i = 0, 9 do
  CODE_TO_VK[48 + i] = 0x30 + i
end

-- keypad 256..265 -> VK 0x60..0x69, then the operators
for i = 0, 9 do
  CODE_TO_VK[256 + i] = 0x60 + i
end
CODE_TO_VK[266] = 0x6E   -- KeypadPeriod
CODE_TO_VK[267] = 0x6F   -- KeypadDivide
CODE_TO_VK[268] = 0x6A   -- KeypadMultiply
CODE_TO_VK[269] = 0x6D   -- KeypadMinus
CODE_TO_VK[270] = 0x6B   -- KeypadPlus
CODE_TO_VK[271] = VK.ENTER
CODE_TO_VK[272] = 0xBB   -- KeypadEquals

-- F1..F12 are 282..293, which is VK 0x70..0x7B exactly
for i = 0, 11 do
  CODE_TO_VK[282 + i] = 0x70 + i
end

-- letters are 97..122 ('a'..'z'), which is VK 0x41..0x5A
for i = 0, 25 do
  CODE_TO_VK[97 + i] = 0x41 + i
end

function KeyMap.codeToVK(code)
  if type(code) ~= "number" then return nil end
  if code <= 0 then return nil end

  local vk = CODE_TO_VK[code]
  if vk then return vk end

  -- 65..90 is not a valid Roblox KeyCode at all, so a value in that
  -- range is already a virtual-key code for a letter. Pass it through.
  if code >= 65 and code <= 90 then return code end

  return nil
end

-- ---------------------------------------------------------------------
-- name -> VK
-- ---------------------------------------------------------------------
local NAME_TO_VK = {
  space = VK.SPACE, spacebar = VK.SPACE,
  ["return"] = VK.ENTER, enter = VK.ENTER,
  escape = VK.ESC, esc = VK.ESC,
  tab = VK.TAB, backspace = VK.BACKSPACE, delete = VK.DELETE,
  insert = VK.INSERT, home = VK.HOME, ["end"] = VK.END,
  pageup = VK.PAGEUP, pagedown = VK.PAGEDOWN,
  up = VK.UP, down = VK.DOWN, left = VK.LEFT, right = VK.RIGHT,
  leftshift = VK.LSHIFT, rightshift = VK.RSHIFT,
  leftcontrol = VK.LCTRL, rightcontrol = VK.RCTRL,
  leftctrl = VK.LCTRL, rightctrl = VK.RCTRL,
  leftalt = VK.LALT, rightalt = VK.RALT,
  capslock = VK.CAPSLOCK, numlock = 0x90, scrolllock = 0x91,
  zero = 0x30, one = 0x31, two = 0x32, three = 0x33, four = 0x34,
  five = 0x35, six = 0x36, seven = 0x37, eight = 0x38, nine = 0x39,
  keypadzero = 0x60, keypadone = 0x61, keypadtwo = 0x62, keypadthree = 0x63,
  keypadfour = 0x64, keypadfive = 0x65, keypadsix = 0x66, keypadseven = 0x67,
  keypadeight = 0x68, keypadnine = 0x69,
  semicolon = 0xBA, equals = 0xBB, comma = 0xBC, minus = 0xBD,
  period = 0xBE, slash = 0xBF, backquote = 0xC0,
  leftbracket = 0xDB, backslash = 0xDC, rightbracket = 0xDD,
}

for i = 1, 12 do
  NAME_TO_VK["f" .. i] = 0x6F + i
end

-- strips "Enum.KeyCode." / "KeyCode." / surrounding noise, lowercases
local function normalizeName(name)
  local s = tostring(name or "")
  s = string.lower(s)
  s = string.gsub(s, "^enum%.", "")
  s = string.gsub(s, "^keycode%.", "")
  s = string.gsub(s, "%s+", "")
  return s
end

function KeyMap.nameToVK(name)
  local n = normalizeName(name)
  if n == "" then return nil end

  local direct = NAME_TO_VK[n]
  if direct then return direct end

  -- a bare letter: "e" -> VK_E
  if #n == 1 then
    local byte = string.byte(n)
    if byte and byte >= 97 and byte <= 122 then
      return byte - 32
    end
    if byte and byte >= 48 and byte <= 57 then
      return byte
    end
  end

  return nil
end

-- ---------------------------------------------------------------------
-- resolve whatever the bridge handed us
-- ---------------------------------------------------------------------
-- Order matters: EnumItem.Name is authoritative, because .Value is the
-- ASCII-flavoured number that caused the original bug.
function KeyMap.resolve(value, fallback)
  if value == nil then return fallback end

  -- EnumItem / userdata / table with a Name field
  local n = nil
  pcall(function() n = value.Name end)
  if type(n) == "string" and n ~= "" then
    local vk = KeyMap.nameToVK(n)
    if vk then return vk end
  end

  -- EnumItem / number with a Value field
  local v = nil
  pcall(function() v = value.Value end)
  if type(v) == "number" then
    local vk = KeyMap.codeToVK(v)
    if vk then return vk end
  end

  if type(value) == "number" then
    return KeyMap.codeToVK(value) or fallback
  end

  if type(value) == "string" then
    -- "Enum.KeyCode.E"
    local tail = string.match(value, "([%w_]+)$")
    return KeyMap.nameToVK(tail or value) or fallback
  end

  return fallback
end

-- "E (0x45)" for reports
function KeyMap.describe(value)
  local vk = KeyMap.resolve(value, nil)
  if not vk then return "none" end

  local name = tostring(value)
  if type(value) == "number" then
    name = string.format("#%d", value)
  end
  return string.format("%s -> 0x%02X", name, vk)
end
