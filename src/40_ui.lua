--[[ ==================================================================
     40_ui : Drawing-based menu

     Instance.new is not available, so there is no ScreenGui anywhere.
     The menu is a stack of Drawing squares and text, laid out on a grid
     and hit-tested against the real mouse position from Player:GetMouse.
     Input is read, never injected, so the panel works even while the
     focus gate is closed.
     ================================================================== ]]

local RR = _G.RR
local UI = RR.UI or {}
RR.UI = UI

UI.visible  = false
UI.controls = {}
UI.pool     = { text = {}, square = {} }
UI.textN    = 0
UI.squareN  = 0
UI.x        = 40
UI.y        = 110
UI.width    = 320
UI.rowH     = 21
UI.pad      = 10
UI.headerH  = 34
UI.scale    = 1

local COL = {
  bg      = Color3.fromRGB(18, 18, 22),
  header  = Color3.fromRGB(38, 40, 52),
  accent  = Color3.fromRGB(120, 200, 140),
  text    = Color3.fromRGB(226, 228, 236),
  dim     = Color3.fromRGB(140, 144, 160),
  ok      = Color3.fromRGB(120, 210, 130),
  bad     = Color3.fromRGB(230, 110, 110),
  rowOn   = Color3.fromRGB(48, 62, 52),
  rowOff  = Color3.fromRGB(30, 30, 38),
}
UI.COL = COL

local lastDown = false

-- ---------------------------------------------------------------------
-- pools
-- ---------------------------------------------------------------------
local function textObj()
  UI.textN = UI.textN + 1
  local t = UI.pool.text[UI.textN]
  if not t then
    t = Drawing.new("Text")
    t.Outline = true
    t.Center = false
    t.Font = 0
    t.FontSize = 14
    t.Visible = false
    UI.pool.text[UI.textN] = t
  end
  return t
end

local function squareObj()
  UI.squareN = UI.squareN + 1
  local s = UI.pool.square[UI.squareN]
  if not s then
    s = Drawing.new("Square")
    s.Filled = true
    s.Thickness = 1
    s.Visible = false
    UI.pool.square[UI.squareN] = s
  end
  return s
end

local function resetPools()
  for i = 1, UI.textN do
    local t = UI.pool.text[i]
    if t then t.Visible = false end
  end
  for i = 1, UI.squareN do
    local s = UI.pool.square[i]
    if s then s.Visible = false end
  end
  UI.textN = 0
  UI.squareN = 0
end

-- ---------------------------------------------------------------------
-- control registration
-- ---------------------------------------------------------------------
function UI.addToggle(id, label, getFn, setFn)
  UI.controls[#UI.controls + 1] = {
    kind = "toggle", id = id, label = label, get = getFn, set = setFn, h = UI.rowH,
  }
end

function UI.addButton(label, fn)
  UI.controls[#UI.controls + 1] = {
    kind = "button", label = label, fn = fn, h = UI.rowH,
  }
end

function UI.addLabel(fn)
  UI.controls[#UI.controls + 1] = {
    kind = "label", fn = fn, h = UI.rowH - 4,
  }
end

function UI.addHeader(text)
  UI.controls[#UI.controls + 1] = {
    kind = "header", text = text, h = UI.rowH + 4,
  }
end

function UI.clear()
  UI.controls = {}
end

-- ---------------------------------------------------------------------
-- input
-- ---------------------------------------------------------------------
local function mousePos()
  local p = RR.Util.localPlayer()
  if not p then return -1, -1 end
  local m = nil
  pcall(function() m = p:GetMouse() end)
  if not m then return -1, -1 end
  local x, y = -1, -1
  pcall(function()
    x = m.X
    y = m.Y
  end)
  return x, y
end

local function clicked()
  local down = false
  pcall(function() down = ismouse1pressed() end)
  local fired = down and not lastDown
  lastDown = down
  return fired
end

local function inRect(px, py, x, y, w, h)
  return px >= x and px <= x + w and py >= y and py <= y + h
end

-- ---------------------------------------------------------------------
-- layout + draw
-- ---------------------------------------------------------------------
local function totalHeight()
  local h = UI.headerH + UI.pad
  for i = 1, #UI.controls do
    h = h + UI.controls[i].h
  end
  return h + UI.pad
end

function UI.toggleVisible()
  UI.visible = not UI.visible
  if not UI.visible then resetPools() end
end

function UI.draw()
  if not UI.visible then return end

  local mx, my = mousePos()
  local fire = clicked()

  resetPools()

  local x, y = UI.x, UI.y
  local w = UI.width
  local height = totalHeight()

  local bg = squareObj()
  bg.Color = COL.bg
  bg.Transparency = 0.12
  bg.Position = Vector2.new(x, y)
  bg.Size = Vector2.new(w, height)
  bg.Visible = true

  local head = squareObj()
  head.Color = COL.header
  head.Transparency = 0.05
  head.Position = Vector2.new(x, y)
  head.Size = Vector2.new(w, UI.headerH)
  head.Visible = true

  local title = textObj()
  title.Text = "RUN A RESTAURANT  v" .. RR.VERSION
  title.Color = COL.text
  title.FontSize = 15
  title.Position = Vector2.new(x + UI.pad, y + 8)
  title.Visible = true

  local hint = textObj()
  hint.Text = UI.visible and "INSERT to hide" or "INSERT to show"
  hint.Color = COL.dim
  hint.FontSize = 11
  hint.Position = Vector2.new(x + w - 104, y + 11)
  hint.Visible = true

  local cy = y + UI.headerH + UI.pad

  for i = 1, #UI.controls do
    local c = UI.controls[i]

    if c.kind == "header" then
      local t = textObj()
      t.Text = string.upper(c.text)
      t.Color = COL.accent
      t.FontSize = 11
      t.Position = Vector2.new(x + UI.pad, cy + 4)
      t.Visible = true
      cy = cy + c.h

    elseif c.kind == "label" then
      local ok, txt = pcall(c.fn)
      if ok and txt ~= nil then
        local t = textObj()
        t.Text = tostring(txt)
        t.Color = COL.dim
        t.FontSize = 12
        t.Position = Vector2.new(x + UI.pad, cy + 2)
        t.Visible = true
      end
      cy = cy + c.h

    elseif c.kind == "toggle" then
      local on = false
      local ok = pcall(function() on = c.get() == true end)
      if not ok then on = false end

      local row = squareObj()
      row.Color = on and COL.rowOn or COL.rowOff
      row.Transparency = 0.35
      row.Position = Vector2.new(x + 4, cy)
      row.Size = Vector2.new(w - 8, c.h - 2)
      row.Visible = true

      local box = squareObj()
      box.Color = on and COL.ok or COL.dim
      box.Transparency = 0
      box.Position = Vector2.new(x + UI.pad, cy + 6)
      box.Size = Vector2.new(9, 9)
      box.Visible = true

      local t = textObj()
      t.Text = c.label
      t.Color = on and COL.text or COL.dim
      t.FontSize = 13
      t.Position = Vector2.new(x + UI.pad + 18, cy + 3)
      t.Visible = true

      if fire and inRect(mx, my, x + 4, cy, w - 8, c.h - 2) then
        pcall(function() c.set(not on) end)
      end
      cy = cy + c.h

    elseif c.kind == "button" then
      local hover = inRect(mx, my, x + 4, cy, w - 8, c.h - 2)
      local row = squareObj()
      row.Color = hover and COL.header or COL.rowOff
      row.Transparency = 0.25
      row.Position = Vector2.new(x + 4, cy)
      row.Size = Vector2.new(w - 8, c.h - 2)
      row.Visible = true

      local t = textObj()
      t.Text = c.label
      t.Color = hover and COL.text or COL.dim
      t.FontSize = 13
      t.Position = Vector2.new(x + UI.pad, cy + 3)
      t.Visible = true

      if fire and hover then
        pcall(c.fn)
      end
      cy = cy + c.h
    end
  end
end

-- ---------------------------------------------------------------------
-- toggle key
-- ---------------------------------------------------------------------
UI.key = 0x2D  -- INSERT
local lastKey = false

function UI.pollKey()
  local down = false
  pcall(function() down = iskeypressed(UI.key) end)
  if down and not lastKey then
    UI.toggleVisible()
  end
  lastKey = down
end

function UI.destroy()
  resetPools()
  for i = 1, #UI.pool.text do
    pcall(function() UI.pool.text[i]:Remove() end)
  end
  for i = 1, #UI.pool.square do
    pcall(function() UI.pool.square[i]:Remove() end)
  end
  UI.pool = { text = {}, square = {} }
  UI.textN, UI.squareN = 0, 0
end
