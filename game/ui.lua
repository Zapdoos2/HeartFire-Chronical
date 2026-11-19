-- Hearthfire Chronicle: drawing and input toolkit.
-- Everything is drawn fresh each frame; clickable areas register "hits" that the next click is matched against.
local Art = require('art')
local UI = {}
local lg = love.graphics
local floor, max, min = math.floor, math.max, math.min

---------------------------------------------------------------- palette
local function hex(h) return Art.color(h) end
UI.C = {
  page = hex('#050504'), panel = hex('#2a231a'), frame = hex('#6e5a3c'), frameHi = hex('#c2a06a'), text = hex('#ece4d2'), muted = hex('#a89c85'),
  gold = hex('#e9c47a'), blueHi = hex('#8fb6ea'), good = hex('#8fd17a'), bad = hex('#ff7a63'), warn = hex('#f0c35a'), black = { 0, 0, 0, 1 },
  insight = hex('#8ec5ff'), culture = hex('#e3a6ff'), faith = hex('#ffd27a'), influence = hex('#9fe0a0'),
}
local C = UI.C
local function setc(c, a) lg.setColor(c[1], c[2], c[3], (c[4] or 1) * (a or 1)) end
UI.setc = setc

---------------------------------------------------------------- interface size
-- Everything is laid out in "logical" units and drawn under one scale, so the whole board can be made larger.
-- UI.W and UI.H are the window size in logical units. Fonts are rasterized at the final pixel size to stay sharp.
-- UI.os is the display scale of the operating system where the game has to apply it itself (Windows set to 125%,
-- 150%...; see dpi.lua). UI.pref is the player's own Interface size setting on top of that.
UI.scale, UI.pref, UI.os, UI.W, UI.H = 1, 1, 1, 1280, 820
function UI.fitScale(pref)
  local w, h = lg.getDimensions()
  UI.pref = pref or UI.pref
  local s = math.min(UI.pref * UI.os, w / 1000, h / 640)
  s = math.max(.7, math.floor(s * 100 + .5) / 100)
  local changed = s ~= UI.scale
  UI.scale = s
  UI.W, UI.H = w / s, h / s
  return changed
end
local function px() return UI.scale * lg.getDPIScale() end
-- rounds a coordinate to the nearest physical pixel, which keeps text crisp at any interface size
local function snap(v) local k = px(); return floor(v * k + .5) / k end
UI.snap = snap

---------------------------------------------------------------- fonts
-- LÖVE rounds the spacing of every letter to a whole unit of the font's size. So each font is built with one unit
-- per screen pixel (its size times the number of pixels in a logical unit: 2 on a Retina Mac, 1 on a plain Windows
-- screen, 1.5 on Windows set to 150%...) and drawn scaled back down. Every letter then sits exactly on the pixel
-- grid whatever the display or interface size, which keeps small text sharp and evenly spaced.
-- UI.F holds small wrappers that report sizes in logical units; k is that pixels-per-unit factor.
local FP = {}
FP.__index = FP
function FP:getWidth(s) return self.f:getWidth(s) / self.k end
function FP:getHeight() return self.f:getHeight() / self.k end
function FP:getWrap(s, w) local ww, lines = self.f:getWrap(s, w * self.k); return ww / self.k, lines end
function UI.print(font, str, x, y) lg.setFont(font.f); lg.print(str, x, y, 0, 1 / font.k, 1 / font.k) end
function UI.printf(font, str, x, y, w, align) lg.setFont(font.f); lg.printf(str, x, y, w * font.k, align or 'left', 0, 1 / font.k, 1 / font.k) end
UI.F = {}
function UI.loadFonts()
  local k = lg.getDPIScale() * UI.scale
  local function f(path, size) local ft = lg.newFont(path, floor(size * k + .5), 'normal', 1); ft:setFilter('linear', 'linear'); return setmetatable({ f = ft, k = k }, FP) end
  local reg, bold, med, disp, ital = 'fonts/AlegreyaSans-Regular.ttf', 'fonts/AlegreyaSans-Bold.ttf', 'fonts/AlegreyaSans-Medium.ttf', 'fonts/IMFeENsc28P.ttf', 'fonts/AlegreyaSans-Italic.ttf'
  UI.F = {
    body = f(reg, 16), bodyB = f(bold, 16), med = f(med, 16), small = f(reg, 14), smallB = f(bold, 14), tiny = f(reg, 13), tinyB = f(bold, 13), micro = f(bold, 11),
    bodyI = f(ital, 16), smallI = f(ital, 14), tinyI = f(ital, 13),
    d14 = f(disp, 15), d16 = f(disp, 17), d18 = f(disp, 19), d20 = f(disp, 21), d22 = f(disp, 23), d26 = f(disp, 27), d30 = f(disp, 31), d36 = f(disp, 38), d48 = f(disp, 52), d72 = f(disp, 84),
  }
end

---------------------------------------------------------------- textures
local noiseImg, vignetteImg
function UI.loadTextures()
  local id = love.image.newImageData(160, 160)
  local rnd = love.math.newRandomGenerator(7)
  id:mapPixel(function()
    local v = rnd:random()
    return v, v * .92, v * .8, rnd:random() * .12
  end)
  for _ = 1, 50 do
    local cx, cy, r = rnd:random() * 160, rnd:random() * 160, 4 + rnd:random() * 22
    local dark = rnd:random() < .5
    for y = max(0, floor(cy - r)), min(159, floor(cy + r)) do
      for x = max(0, floor(cx - r)), min(159, floor(cx + r)) do
        if (x - cx) ^ 2 + (y - cy) ^ 2 < r * r then
          local pr, pg, pb, pa = id:getPixel(x, y)
          if dark then id:setPixel(x, y, pr * .9, pg * .9, pb * .9, min(1, pa + .03)) else id:setPixel(x, y, min(1, pr + .03), min(1, pg + .03), min(1, pb + .02), pa) end
        end
      end
    end
  end
  noiseImg = lg.newImage(id)
  noiseImg:setWrap('repeat', 'repeat')
  local vd = love.image.newImageData(128, 128)
  vd:mapPixel(function(x, y)
    local dx, dy = (x - 64) / 64, (y - 52) / 70
    local d = math.sqrt(dx * dx + dy * dy)
    if d < .55 then return 1, .94, .8, .07 * (1 - d / .55) end
    return 0, 0, 0, min(.5, (d - .55) * .9)
  end)
  vignetteImg = lg.newImage(vd)
end

---------------------------------------------------------------- shapes
function UI.vgrad(x, y, w, h, top, bottom) Art.gradRect(x, y, x + w, y + h, top, top, bottom, bottom) end
local vgrad = UI.vgrad
function UI.rect(x, y, w, h, c, a, r) setc(c, a); lg.rectangle('fill', x, y, w, h, r or 0, r or 0) end
function UI.border(x, y, w, h, c, a, lw, r) setc(c, a); lg.setLineWidth(lw or 1); lg.rectangle('line', x + .5, y + .5, w - 1, h - 1, r or 0, r or 0) end

-- textured bronze-framed panel, like the columns of the board
local panelQuad = lg.newQuad(0, 0, 1, 1, 160, 160)
function UI.panel(x, y, w, h)
  setc(C.panel); lg.rectangle('fill', x, y, w, h)
  lg.setColor(1, 1, 1, 1)
  panelQuad:setViewport(x % 160, y % 160, w, h, 160, 160)
  lg.draw(noiseImg, panelQuad, x, y)
  lg.draw(vignetteImg, x, y, 0, w / 128, h / 128)
  UI.border(x - 1, y - 1, w + 2, h + 2, C.black)
  UI.border(x, y, w, h, C.frame, 1, 2)
  UI.border(x + 2, y + 2, w - 4, h - 4, C.black, .6)
end
-- raised plaque used for banners, tabs, cards and info boxes
function UI.plaque(x, y, w, h, hot)
  vgrad(x, y, w, h, hex('#3a3024'), hex('#221b13'))
  UI.border(x - 1, y - 1, w + 2, h + 2, C.black)
  UI.border(x, y, w, h, hot and C.gold or C.frameHi, hot and 1 or .9)
  setc({ 1, 1, 1 }, .12); lg.rectangle('fill', x + 1, y + 1, w - 2, 1)
end
-- glossy blue button
function UI.blue(x, y, w, h, state)
  local dim = state == 'disabled'
  if dim then
    vgrad(x, y, w, h * .5, hex('#5a5a5a'), hex('#3e3e3e')); vgrad(x, y + h * .5, w, h * .5, hex('#2e2e2e'), hex('#383838'))
  elseif state == 'on' then
    vgrad(x, y, w, h, hex('#b4d0f2'), hex('#5f8cc8'))
  else
    local b = state == 'hot' and 1.15 or 1
    local function t(c) local v = hex(c); return { min(1, v[1] * b), min(1, v[2] * b), min(1, v[3] * b), 1 } end
    vgrad(x, y, w, h * .5, t('#4f7dbd'), t('#2c5189')); vgrad(x, y + h * .5, w, h * .5, t('#1c3963'), t('#26497e'))
  end
  UI.border(x, y, w, h, hex('#0b182c'), 1, 1, 3)
  setc({ 1, 1, 1 }, dim and .12 or .35); lg.rectangle('fill', x + 2, y + 1, w - 4, 1)
end
-- dark framed square tile that holds an icon
function UI.tile(x, y, s, hot, tint)
  vgrad(x, y, s, s, tint and hex('#4b5466') or hex('#5c4c37'), tint and hex('#1a1d24') or hex('#221a12'))
  setc(C.black, .45); lg.rectangle('fill', x, y + s * .72, s, s * .28)
  UI.border(x, y, s, s, C.black, 1, 1, 3)
  UI.border(x + 1, y + 1, s - 2, s - 2, hot and C.gold or C.frameHi, hot and 1 or .38, 1, 2)
end

---------------------------------------------------------------- text
function UI.text(str, x, y, font, c, a)
  setc(c or C.text, a); UI.print(font or UI.F.body, str, snap(x), snap(y))
end
function UI.shadowText(str, x, y, font, c, a)
  font = font or UI.F.body
  setc(C.black, .9 * (a or 1)); UI.print(font, str, snap(x), snap(y + 1))
  setc(c or C.text, a); UI.print(font, str, snap(x), snap(y))
end
function UI.textW(str, font) return (font or UI.F.body):getWidth(str) end
function UI.wrapH(str, font, w)
  font = font or UI.F.body
  local _, lines = font:getWrap(str, w)
  return #lines * font:getHeight()
end
function UI.para(str, x, y, w, font, c, align, shadow)
  font = font or UI.F.body
  if shadow then setc(C.black, .85); UI.printf(font, str, snap(x), snap(y + 1), w, align) end
  setc(c or C.text); UI.printf(font, str, snap(x), snap(y), w, align)
  return UI.wrapH(str, font, w)
end

---------------------------------------------------------------- hits and hover
UI.hits, UI.hot, UI.clip = {}, nil, nil
function UI.beginFrame()
  UI.hits = {}
  local mx, my = love.mouse.getPosition()
  if UI.forceMouse then mx, my = UI.forceMouse[1] * UI.scale, UI.forceMouse[2] * UI.scale end   -- set only by test modes
  UI.mx, UI.my = mx / UI.scale, my / UI.scale
end
local function inClip(px, py)
  local c = UI.clip
  return not c or (px >= c[1] and py >= c[2] and px < c[1] + c[3] and py < c[2] + c[4])
end
-- Registers a clickable/hoverable area; returns true when it is the area under the mouse.
function UI.hit(id, x, y, w, h, opts)
  local hcl = UI.clip
  UI.hits[#UI.hits + 1] = { id = id, x = x, y = y, w = w, h = h, clip = hcl and { hcl[1], hcl[2], hcl[3], hcl[4] } or nil, opts = opts or {} }
  return UI.hot == id
end
function UI.endFrame()
  local hot, hotHit
  for k = #UI.hits, 1, -1 do
    local h = UI.hits[k]
    local c = h.clip
    if UI.mx >= h.x and UI.my >= h.y and UI.mx < h.x + h.w and UI.my < h.y + h.h and (not c or (UI.mx >= c[1] and UI.my >= c[2] and UI.mx < c[1] + c[3] and UI.my < c[2] + c[4])) then
      hot, hotHit = h.id, h; break
    end
  end
  UI.hot, UI.hotHit = hot, hotHit
  local want = hotHit and hotHit.opts.click and 'hand' or 'arrow'
  if UI._cursor ~= want then UI._cursor = want; love.mouse.setCursor(love.mouse.getSystemCursor(want)) end
end
-- px, py are logical coordinates. Hits with a drag handler keep receiving the mouse until it is released.
UI.onClick = function() end
-- Button 1 is the left button; button 2 (right-click) only reaches areas that have an rclick handler.
function UI.click(px, py, button)
  button = button or 1
  for k = #UI.hits, 1, -1 do
    local h = UI.hits[k]
    local c = h.clip
    if px >= h.x and py >= h.y and px < h.x + h.w and py < h.y + h.h and (not c or (px >= c[1] and py >= c[2] and px < c[1] + c[3] and py < c[2] + c[4])) then
      if button == 1 then
        if h.opts.drag and not h.opts.disabled then UI.dragging = h; h.opts.drag(px, py, h) end
        if h.opts.click and not h.opts.disabled then UI.onClick(h); h.opts.click(h, button) end
      elseif h.opts.rclick and not h.opts.disabled then UI.onClick(h); h.opts.rclick(h, button) end
      return h
    end
  end
end
function UI.moved(px, py) if UI.dragging then UI.dragging.opts.drag(px, py, UI.dragging) end end
function UI.released() UI.dragging = nil end
local function scissor(c)
  local s = UI.scale
  if c then lg.setScissor(floor(c[1] * s), floor(c[2] * s), max(0, math.ceil(c[3] * s)), max(0, math.ceil(c[4] * s))) else lg.setScissor() end
end
function UI.pushClip(x, y, w, h)
  UI._clipStack = UI._clipStack or {}
  table.insert(UI._clipStack, UI.clip)
  local c = UI.clip
  if c then
    local x2, y2 = math.min(x + w, c[1] + c[3]), math.min(y + h, c[2] + c[4])
    x, y = math.max(x, c[1]), math.max(y, c[2])
    w, h = math.max(0, x2 - x), math.max(0, y2 - y)
  end
  UI.clip = { x, y, w, h }
  scissor(UI.clip)
end
function UI.popClip()
  UI.clip = table.remove(UI._clipStack)
  scissor(UI.clip)
end
UI.inClip = inClip

---------------------------------------------------------------- scroll areas
UI.scroll = {}
function UI.scrollState(name) local s = UI.scroll[name]; if not s then s = { y = 0, max = 0, x = 0, yTop = 0, w = 0, h = 0 }; UI.scroll[name] = s end; return s end
function UI.wheel(dy)
  for name, s in pairs(UI.scroll) do
    if UI.mx >= s.x and UI.my >= s.yTop and UI.mx < s.x + s.w and UI.my < s.yTop + s.h then
      s.y = max(0, min(s.max, s.y - dy * 48))
      s.stick = s.y >= s.max - 4
      return
    end
  end
end
-- scrollbar on the right edge of an area
function UI.scrollbar(s)
  if s.max <= 0 then return end
  local trackH = s.h - 8
  local barH = max(24, trackH * s.h / (s.h + s.max))
  local by = s.yTop + 4 + (trackH - barH) * (s.y / s.max)
  UI.rect(s.x + s.w - 7, s.yTop + 4, 4, trackH, C.black, .35, 2)
  UI.rect(s.x + s.w - 7, by, 4, barH, C.frame, .9, 2)
end

---------------------------------------------------------------- rich documents (tooltips, info boxes, cards)
-- A doc is a list of blocks: {t='title'|'p'|'flow'|'rows'|'h'|'chips'|'gap'}
local function flowItems(items, font)
  -- splits long text items into words so lines can wrap between them; spaces before the first word and
  -- after the last one are kept, since they separate this item from its neighbours
  local out = {}
  for _, it in ipairs(items) do
    if it.text and not it.chip and not it.icon and #it.text > 14 and it.text:find('%S%s+%S') then
      local lead, trail = it.text:match('^(%s*)'), it.text:match('(%s*)$')
      local words = {}
      for word in it.text:gmatch('%S+') do words[#words + 1] = word end
      for k, word in ipairs(words) do
        out[#out + 1] = { text = (k == 1 and lead or ' ') .. word .. (k == #words and trail or ''), col = it.col, font = it.font }
      end
    else out[#out + 1] = it end
  end
  return out
end
local function layoutFlow(items, w, font, iconSize)
  font = font or UI.F.small
  local lh = max(font:getHeight(), iconSize or 0) + 2
  local ops, cx, cy = {}, 0, 0
  for _, it in ipairs(flowItems(items, font)) do
    local iw
    if it.chip then iw = (it.font or font):getWidth(it.text) + (iconSize or lh) + 12
    elseif it.icon then iw = (iconSize or lh) + 2
    else iw = (it.font or font):getWidth(it.text) end
    if cx > 0 and cx + iw > w then cx = 0; cy = cy + lh + (it.chip and 3 or 0) end
    local txt = it.text
    if cx == 0 and txt and txt:find('^%s') then txt = txt:gsub('^%s+', ''); iw = (it.font or font):getWidth(txt) end
    ops[#ops + 1] = { it = it, text = txt, x = cx, y = cy, w = iw }
    cx = cx + iw + (it.chip and 4 or (it.icon and 2 or 0))
  end
  return ops, cy + lh
end

function UI.docHeight(doc, w) return UI.doc(doc, 0, 0, w, true) end
-- Draws a doc (or only measures it when measureOnly is true); returns the height.
function UI.doc(doc, x, y, w, measureOnly)
  local F = UI.F
  local cy = 0
  for bi, b in ipairs(doc) do
    if bi > 1 and b.t ~= 'gap' then cy = cy + (b.t == 'rows' and 4 or 4) end
    if b.t == 'title' then
      local font = b.font or F.d18
      local is = b.iconSize or 26
      local th = max(is, font:getHeight())
      if not measureOnly then
        if b.icon then Art.draw(b.icon, x, y + cy + (th - is) / 2, is) end
        UI.shadowText(b.text, x + (b.icon and is + 6 or 0), y + cy + (th - font:getHeight()) / 2, font, b.col or C.gold)
      end
      cy = cy + th
    elseif b.t == 'p' then
      local font = b.font or F.small
      if measureOnly then cy = cy + UI.wrapH(b.text, font, w)
      else cy = cy + UI.para(b.text, x, y + cy, w, font, b.col or C.text, nil, true) end
    elseif b.t == 'h' then
      if not measureOnly then UI.text(b.text:upper(), x, y + cy, F.micro, C.muted) end
      cy = cy + F.micro:getHeight()
    elseif b.t == 'rows' then
      local font = b.font or F.small
      local rh = font:getHeight() + 2
      for _, r in ipairs(b.rows) do
        if not measureOnly then
          UI.text(r[1], x, y + cy, font, C.text)
          local vw = (F.smallB):getWidth(r[2])
          UI.text(r[2], x + w - vw, y + cy, F.smallB, r[3] or C.text)
          setc(C.frameHi, .22); lg.rectangle('fill', x, y + cy + rh - 1, w, 1)
        end
        cy = cy + rh
      end
    elseif b.t == 'flow' or b.t == 'chips' then
      local font = b.font or F.small
      local items = b.items
      if b.t == 'chips' then
        items = {}
        for _, c in ipairs(b.items) do items[#items + 1] = { chip = true, icon = c[1], text = c[2] } end
        if b.label then table.insert(items, 1, { text = b.label:upper() .. '  ', font = F.micro, col = C.muted }) end
      end
      local is = b.iconSize or (font:getHeight() + 1)
      local ops, h = layoutFlow(items, w, font, is)
      if not measureOnly then
        local lh = max(font:getHeight(), is) + 2
        for _, op in ipairs(ops) do
          local it, ox, oy = op.it, x + op.x, y + cy + op.y
          if it.chip then
            local cw = op.w
            setc(C.black, .3); lg.rectangle('fill', ox, oy, cw, lh, 9, 9)
            setc(C.frameHi, .35); lg.setLineWidth(1); lg.rectangle('line', ox + .5, oy + .5, cw - 1, lh - 1, 9, 9)
            Art.draw(it.icon, ox + 3, oy + (lh - is) / 2, is)
            UI.text(it.text, ox + is + 6, oy + (lh - font:getHeight()) / 2, font, C.text)
          elseif it.icon then Art.draw(it.icon, ox, oy + (lh - is) / 2, is)
          else
            local fnt = it.font or font
            setc(C.black, .8); UI.print(fnt, op.text, snap(ox), snap(oy + (lh - fnt:getHeight()) / 2 + 1))
            setc(it.col or b.col or C.text); UI.print(fnt, op.text, snap(ox), snap(oy + (lh - fnt:getHeight()) / 2))
          end
        end
      end
      cy = cy + h
    elseif b.t == 'gap' then cy = cy + (b.h or 6) end
  end
  return cy
end

---------------------------------------------------------------- controls
-- A horizontal slider for a value from 0 to 1. onChange receives the new value while dragging; onDone when released.
function UI.slider(id, x, y, w, value, onChange)
  local h = 22
  local hot = UI.hit(id, x - 8, y, w + 16, h, { click = function() end, drag = function(mx) onChange(math.max(0, math.min(1, (mx - x) / w))) end })
  UI.rect(x, y + h / 2 - 3, w, 6, C.black, .6, 3)
  UI.vgrad(x, y + h / 2 - 3, math.max(1, w * value), 6, Art.color('#8fb6ea'), Art.color('#3a68a8'))
  UI.border(x, y + h / 2 - 3, w, 6, C.frame, .9, 1, 3)
  local kx = x + w * value
  setc(C.black, .6); lg.circle('fill', kx, y + h / 2 + 1, 9, 20)
  setc((hot or UI.dragging and UI.dragging.id == id) and C.gold or C.frameHi); lg.circle('fill', kx, y + h / 2, 8, 20)
  setc({ 1, 1, 1 }, .35); lg.circle('fill', kx - 2, y + h / 2 - 3, 3, 12)
  return hot
end

---------------------------------------------------------------- floating notes and tooltips
UI.floats = {}
function UI.floatText(text, x, y, col)
  UI.floats[#UI.floats + 1] = { text = text, x = x, y = y, col = col or C.text, t = 0 }
end
function UI.drawFloats(dt)
  local keep = {}
  for _, f in ipairs(UI.floats) do
    f.t = f.t + dt
    if f.t < .9 then
      keep[#keep + 1] = f
      local a = 1 - f.t / .9
      local w = UI.F.smallB:getWidth(f.text)
      UI.shadowText(f.text, f.x - w / 2, f.y - 18 - f.t * 22, UI.F.smallB, f.col, a)
    end
  end
  UI.floats = keep
end
function UI.tooltip(doc, ax, ay, aw, ah)
  local W, H = UI.W, UI.H
  local w = 300
  local h = UI.docHeight(doc, w - 20) + 18
  local x = ax + aw + 8
  if x + w > W - 8 then x = max(8, ax - w - 8) end
  local y = min(H - h - 8, max(8, ay - 4))
  UI.plaque(x, y, w, h)
  UI.doc(doc, x + 10, y + 9, w - 20)
end

return UI
