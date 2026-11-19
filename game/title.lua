-- Hearthfire Chronicle: the title screen (a campfire under the stars), founding a new tribe, the Legacy and options.
local Sim = require('sim')
local Art = require('art')
local UI = require('ui')
local Legacy = require('legacy')
local Screens = require('screens')
local Flavor = require('flavor')
local Title = {}
local lg = love.graphics
local floor, max, min, sin, cos, pi = math.floor, math.max, math.min, math.sin, math.cos, math.pi
local C = UI.C

Title.page = 'main'          -- main, new, legacy, options
Title.back = 'main'          -- where the legacy page returns to: 'main' or 'game'
Title.legacyTab = 'perks'
Title.name = ''
Title.onContinue = function() end
Title.onFound = function() end
Title.onQuit = function() end
Title.onBackToGame = function() end
Title.hasGame = function() return false end

---------------------------------------------------------------- the night scene
local stars, sparks, smoke, hills = {}, {}, {}, nil
local function initScene()
  local rng = love.math.newRandomGenerator(42)
  for k = 1, 180 do stars[k] = { rng:random(), rng:random() ^ 1.6 * .62, .4 + rng:random() * 1.3, rng:random() * 6.28 } end
  hills = { {}, {} }
  for layer = 1, 2 do
    for k = 0, 64 do
      local f = k / 64
      local v = .5 * sin(f * 7.1 + layer * 2) + .3 * sin(f * 15.3 + layer) + .2 * sin(f * 31 + layer * 5)
      hills[layer][k + 1] = v
    end
  end
end
initScene()

-- One flickering tongue of flame, drawn as a strip of vertices that narrows toward a swaying tip.
local function tongue(x, base, w, h, sway, c1, c2, a)
  local verts = {}
  for i = 0, 12 do
    local f = i / 12
    local width = w * (1 - f) ^ .75 * (f < .2 and (.55 + f / .2 * .45) or 1)
    local sx = x + sway * f * f
    local y = base - h * f
    local r, g, b = c1[1] + (c2[1] - c1[1]) * f, c1[2] + (c2[2] - c1[2]) * f, c1[3] + (c2[3] - c1[3]) * f
    local al = a * (1 - f * .55)
    verts[#verts + 1] = { sx - width / 2, y, 0, 0, r, g, b, al }
    verts[#verts + 1] = { sx + width / 2, y, 0, 0, r, g, b, al }
  end
  lg.draw(lg.newMesh(verts, 'strip', 'stream'))
end
local function figure(x, y, s, facing, t)
  -- a person sitting by the fire, hunched forward with arms toward the warmth; the side facing the fire catches the light
  local fl = .75 + .25 * sin(t * 6.1 + x)
  local function body(ox, oy, grow)
    lg.push(); lg.translate(x + ox, y + oy); lg.scale(facing, 1)
    lg.ellipse('fill', 0, -16 * s, (12 + grow) * s, (17 + grow) * s, 24)
    lg.circle('fill', 5 * s, -38 * s, (7.5 + grow) * s, 20)
    lg.polygon('fill', 2 * s, -24 * s, 20 * s, -14 * s, 21 * s, -9 * s, 4 * s, -14 * s)
    lg.ellipse('fill', 12 * s, -2 * s, (16 + grow) * s, (6 + grow) * s, 18)
    lg.pop()
  end
  lg.setColor(1, .52, .18, .55 * fl); body(facing * 1.6 * s, -.6 * s, .4)
  lg.setColor(.045, .03, .025, 1); body(0, 0, 0)
end
local function drawScene(W, H, dt)
  local t = love.timer.getTime()
  UI.vgrad(0, 0, W, H * .72, Art.color('#070a14'), Art.color('#1b1410'))
  UI.vgrad(0, H * .72, W, H * .28 + 1, Art.color('#1b1410'), Art.color('#0b0806'))
  for _, st in ipairs(stars) do
    local a = .35 + .35 * sin(t * st[3] + st[4])
    lg.setColor(.95, .93, 1, a * (1 - st[2]))
    lg.circle('fill', st[1] * W, st[2] * H, st[3] * .9, 6)
  end
  -- the moon
  local mx, my = W * .82, H * .16
  for r = 60, 24, -6 do lg.setColor(.9, .9, 1, .012); lg.circle('fill', mx, my, r, 30) end
  lg.setColor(.92, .9, .82, .9); lg.circle('fill', mx, my, 20, 30)
  lg.setColor(.07, .09, .16, 1); lg.circle('fill', mx + 8, my - 4, 18, 30)
  -- hills
  for layer = 1, 2 do
    local base = H * (layer == 1 and .66 or .74)
    local amp = H * (layer == 1 and .06 or .045)
    local pts = { 0, H }
    for k, v in ipairs(hills[layer]) do pts[#pts + 1] = (k - 1) / 64 * W; pts[#pts + 1] = base - v * amp end
    pts[#pts + 1] = W; pts[#pts + 1] = H
    local tris = love.math.triangulate(pts)
    if layer == 1 then lg.setColor(.07, .065, .07, 1) else lg.setColor(.045, .035, .03, 1) end
    for _, tr in ipairs(tris) do lg.polygon('fill', tr) end
  end
  -- the fire
  local fx, fy = W * .5, H * .86
  local s = min(W / 1280, H / 820) * 1.15
  local fl = .85 + .15 * sin(t * 5.3) * sin(t * 2.1 + .4)
  lg.setBlendMode('add')
  for r = 340, 20, -16 do lg.setColor(1, .5, .16, .012 * fl); lg.circle('fill', fx, fy - 30 * s, r * s, 40) end
  lg.setColor(1, .45, .12, .1 * fl); lg.ellipse('fill', fx, fy + 6 * s, 170 * s, 26 * s, 40)
  lg.setBlendMode('alpha')
  -- stones and logs
  lg.setColor(.25, .15, .07, 1)
  lg.push(); lg.translate(fx, fy - 4 * s); lg.rotate(.22); lg.rectangle('fill', -58 * s, -6 * s, 116 * s, 12 * s, 5 * s); lg.pop()
  lg.setColor(.31, .19, .09, 1)
  lg.push(); lg.translate(fx, fy - 6 * s); lg.rotate(-.24); lg.rectangle('fill', -56 * s, -6 * s, 112 * s, 12 * s, 5 * s); lg.pop()
  lg.setColor(1, .45, .1, .55 * fl); lg.ellipse('fill', fx, fy - 6 * s, 38 * s, 8 * s, 20)
  lg.setBlendMode('add')
  local layers = {
    { n = 6, w = 34, h = 120, spread = 46, c1 = { .85, .2, .05 }, c2 = { .5, .05, .02 }, a = .55 },
    { n = 5, w = 28, h = 95, spread = 34, c1 = { 1, .5, .1 }, c2 = { .8, .2, .04 }, a = .6 },
    { n = 4, w = 20, h = 70, spread = 22, c1 = { 1, .82, .35 }, c2 = { 1, .45, .1 }, a = .65 },
    { n = 2, w = 14, h = 40, spread = 8, c1 = { 1, .97, .8 }, c2 = { 1, .75, .3 }, a = .6 },
  }
  for li, L in ipairs(layers) do
    for k = 1, L.n do
      local ph = k * 1.7 + li * .9
      local x = fx + ((k - .5) / L.n - .5) * L.spread * 2 * s
      local h = L.h * s * (.75 + .25 * sin(t * (3.1 + k * .37) + ph) + .1 * sin(t * 9.3 + ph * 2))
      local sway = (sin(t * 2.3 + ph) * 14 + sin(t * 5.7 + ph) * 5) * s
      tongue(x, fy - 6 * s, L.w * s * (1 - math.abs((k - .5) / L.n - .5) * .5), h, sway, L.c1, L.c2, L.a)
    end
  end
  lg.setBlendMode('alpha')
  -- the ring of stones in front hides the foot of the flames
  for k = 0, 10 do
    local a = k / 10 * pi
    local sx, sy = fx - cos(a) * 64 * s, fy - 6 * s + sin(a) * 9 * s
    lg.setColor(.1, .08, .07, 1); lg.ellipse('fill', sx, sy + 2 * s, 17 * s, 11 * s, 16)
    lg.setColor(.27 + .05 * sin(a * 3), .22, .19, 1); lg.ellipse('fill', sx, sy, 16 * s, 10 * s, 16)
    lg.setColor(1, .55, .2, .25 * fl); lg.ellipse('fill', sx, sy - 3 * s, 10 * s, 3 * s, 12)
  end
  -- sparks and smoke
  if #sparks < 70 and love.math.random() < dt * 40 then
    sparks[#sparks + 1] = { x = fx + (love.math.random() - .5) * 60 * s, y = fy - 40 * s, vx = (love.math.random() - .5) * 20, vy = -(40 + love.math.random() * 70), life = 0, max = 1.5 + love.math.random() * 2 }
  end
  if #smoke < 14 and love.math.random() < dt * 3 then smoke[#smoke + 1] = { x = fx + (love.math.random() - .5) * 30 * s, y = fy - 120 * s, life = 0, max = 6 + love.math.random() * 4 } end
  lg.setBlendMode('add')
  local keep = {}
  for _, p in ipairs(sparks) do
    p.life = p.life + dt
    if p.life < p.max then
      p.x = p.x + (p.vx + sin(t * 2 + p.max * 3) * 14) * dt * s; p.y = p.y + p.vy * dt * s; p.vy = p.vy * (1 - dt * .2)
      local a = 1 - p.life / p.max
      lg.setColor(1, .6 + .3 * a, .25, a)
      lg.circle('fill', p.x, p.y, (1 + 1.4 * a) * s, 6)
      keep[#keep + 1] = p
    end
  end
  sparks = keep
  lg.setBlendMode('alpha')
  keep = {}
  for _, p in ipairs(smoke) do
    p.life = p.life + dt
    if p.life < p.max then
      local f = p.life / p.max
      lg.setColor(.5, .48, .5, .05 * sin(f * pi))
      lg.circle('fill', p.x + sin(p.life * .7 + p.max) * 30 * s * f, p.y - f * 260 * s, (16 + f * 60) * s, 24)
      keep[#keep + 1] = p
    end
  end
  smoke = keep
  -- people around the fire
  figure(fx - 150 * s, fy + 2 * s, s * 1.15, 1, t)
  figure(fx + 160 * s, fy + 6 * s, s * 1.1, -1, t + 2)
  figure(fx - 230 * s, fy + 14 * s, s * .9, 1, t + 4)
  figure(fx + 250 * s, fy + 18 * s, s * .85, -1, t + 1)
end

---------------------------------------------------------------- pieces
local function menuButton(id, label, sub, x, y, w, fn, enabled)
  local h = sub and 52 or 40
  local hot = UI.hit(id, x, y, w, h, { click = enabled ~= false and fn or nil, disabled = enabled == false })
  UI.rect(x, y + 3, w, h, C.black, .45, 4)
  UI.vgrad(x, y, w, h, hot and Art.color('#4a3c2a') or Art.color('#32291d'), Art.color('#1c160f'))
  UI.border(x, y, w, h, hot and C.gold or C.frameHi, hot and 1 or .7, 1, 3)
  local a = enabled == false and .45 or 1
  local lw = UI.F.d20:getWidth(label)
  UI.shadowText(label, x + (w - lw) / 2, y + (sub and 6 or 8), UI.F.d20, hot and C.gold or C.text, a)
  if sub then local sw = UI.F.tiny:getWidth(sub); UI.text(sub, x + (w - sw) / 2, y + 31, UI.F.tiny, C.muted, a) end
  return h
end
local function logo(W, y)
  local l1, l2 = 'Hearthfire', 'CHRONICLE'
  local f1, f2 = UI.F.d72, UI.F.d36
  UI.shadowText(l1, (W - f1:getWidth(l1)) / 2, y, f1, Art.color('#e8dcc2'))
  local spacing = 9
  local tw = f2:getWidth(l2) + spacing * (#l2 - 1)
  local cx = (W - tw) / 2
  for k = 1, #l2 do
    local ch = l2:sub(k, k)
    UI.shadowText(ch, cx, y + 86, f2, Art.color('#c9a86a'))
    cx = cx + f2:getWidth(ch) + spacing
  end
end
local function header(bx, by, bw, title, sub)
  UI.shadowText(title, bx + (bw - UI.F.d30:getWidth(title)) / 2, by + 14, UI.F.d30, C.gold)
  if sub then UI.para(sub, bx + 30, by + 56, bw - 60, UI.F.small, C.muted, 'center') end
end

---------------------------------------------------------------- pages
local function drawMain(W, H)
  logo(W, H * .07)
  local game = Title.hasGame()
  local bw = 320
  local bx = (W - bw) / 2
  local y = H * .07 + 150
  if game then y = y + menuButton('t:continue', 'Continue', game, bx, y, bw, function() Title.onContinue() end) + 10 end
  y = y + menuButton('t:new', 'New tribe', nil, bx, y, bw, function() Title.page = 'new'; Title.name = Sim.tribeName() end) + 10
  y = y + menuButton('t:legacy', 'Legacy', Legacy.D.embers .. (Legacy.D.embers == 1 and ' ember' or ' embers') .. '  \u{00b7}  ' .. Legacy.milesDone() .. ' of ' .. #Legacy.MILES .. ' milestones', bx, y, bw, function() Title.page = 'legacy'; Title.back = 'main' end) + 10
  y = y + menuButton('t:options', 'Settings', nil, bx, y, bw, function() Title.page = 'options' end) + 10
  y = y + menuButton('t:quit', 'Quit', nil, bx, y, bw, function() Title.onQuit() end) + 10
  local foot = 'Second edition  \u{00b7}  made with LÖVE'
  Title.quip = Title.quip or Flavor.TITLE[love.math.random(1, #Flavor.TITLE)]
  UI.text(Title.quip, 16, H - 22, UI.F.tinyI, C.muted, .8)
  UI.text(foot, W - 16 - UI.F.tiny:getWidth(foot), H - 22, UI.F.tiny, C.muted, .7)
end

local caretT = 0
local function drawNew(W, H)
  local game = Title.hasGame()
  local bw = min(W - 40, 560)
  local o = Legacy.startOptions(Title.name)
  local people = 9 + (o.adults or 0)
  local start = { people .. ' people' }
  if o.res.fruit then start[#start + 1] = 'extra food, water and sticks' end
  for _, t in ipairs(o.techs) do start[#start + 1] = Sim.TM[t].n end
  local warn = game and ('Your current tribe will be retired: its story is recorded in the legacy and earns about ' .. Legacy.score(Sim.S) .. ' embers.') or nil
  local bh = 262 + (warn and 46 or 0)
  local bx, by = Screens.overlayBox(W, H, bw, bh)
  header(bx, by, bw, 'Found a new tribe')
  local cy = by + 62
  if warn then cy = cy + UI.para(warn, bx + 30, cy, bw - 60, UI.F.small, C.warn, 'center') + 12 end
  UI.text('Name your tribe', bx + 40, cy, UI.F.small, C.muted)
  cy = cy + 22
  local fw = bw - 80 - 150
  UI.rect(bx + 40, cy, fw, 36, C.black, .55, 4); UI.border(bx + 40, cy, fw, 36, C.gold, .9, 1, 4)
  UI.text(Title.name, bx + 52, cy + 6, UI.F.d22, C.text)
  caretT = caretT + (Screens.dt or 0)
  if caretT % 1 < .55 then UI.rect(bx + 54 + UI.F.d22:getWidth(Title.name), cy + 8, 2, 22, C.gold) end
  Screens.blueButton('Another name', 'new:reroll', bx + 40 + fw + 10, cy + 4, function() Title.name = Sim.tribeName() end)
  cy = cy + 50
  cy = cy + UI.para('They begin with ' .. table.concat(start, ', ') .. '.', bx + 40, cy, bw - 80, UI.F.small, C.text) + 6
  UI.para('A new map is drawn for every tribe. Embers and perks carry over.', bx + 40, cy, bw - 80, UI.F.tiny, C.muted)
  local l1, l2 = 'Light the fire', 'Back'
  local w1 = UI.F.smallB:getWidth(l1) + 30
  local w2 = UI.F.smallB:getWidth(l2) + 30
  local x0 = bx + (bw - w1 - w2 - 10) / 2
  Screens.blueButton(l1, 'new:go', x0, by + bh - 48, function() Title.found() end)
  Screens.blueButton(l2, 'new:back', x0 + w1 + 10, by + bh - 48, function() Title.page = 'main' end)
end
function Title.found()
  local name = Title.name:gsub('^%s+', ''):gsub('%s+$', '')
  if name == '' then name = Sim.tribeName() end
  Title.page = 'main'
  Title.onFound(name)
end

local function pips(x, y, have, total)
  for k = 1, total do
    UI.setc(C.black, .6); lg.circle('fill', x + (k - 1) * 14, y, 5.5, 14)
    if k <= have then UI.setc(Art.color('#ffb55a')); lg.circle('fill', x + (k - 1) * 14, y, 4.5, 14) else UI.border(x + (k - 1) * 14 - 4.5, y - 4.5, 9, 9, C.frameHi, .5, 1, 4.5) end
  end
end
local function drawLegacy(W, H)
  local bw, bh = min(W - 40, 980), min(H - 30, 720)
  local bx, by = Screens.overlayBox(W, H, bw, bh)
  header(bx, by, bw, 'The Legacy')
  local D = Legacy.D
  local line = D.embers .. (D.embers == 1 and ' ember' or ' embers') .. ' to spend  \u{00b7}  ' .. D.earned .. ' earned in all  \u{00b7}  ' .. D.founded .. (D.founded == 1 and ' tribe founded' or ' tribes founded')
  local lw = UI.F.small:getWidth(line) + 28
  Art.draw('x.ember', bx + (bw - lw) / 2, by + 52, 22)
  UI.text(line, bx + (bw - lw) / 2 + 28, by + 54, UI.F.small, Art.color('#ffcf8a'))
  -- tabs
  local tabs = { { 'perks', 'Perks' }, { 'miles', 'Milestones' }, { 'tribes', 'Past tribes' } }
  local tx = bx + bw / 2 - 160
  for _, t in ipairs(tabs) do
    local sel = Title.legacyTab == t[1]
    local hot = UI.hit('lt:' .. t[1], tx, by + 84, 104, 26, { click = function() Title.legacyTab = t[1] end })
    if sel then UI.vgrad(tx, by + 84, 104, 26, Art.color('#5b4b35'), Art.color('#2e251a')); UI.border(tx, by + 84, 104, 26, C.gold) else UI.plaque(tx, by + 84, 104, 26, hot) end
    UI.shadowText(t[2], tx + (104 - UI.F.small:getWidth(t[2])) / 2, by + 88, UI.F.small, sel and { 1, 1, 1, 1 } or C.text)
    tx = tx + 108
  end
  local ax, ay, aw, ah = bx + 16, by + 122, bw - 32, bh - 122 - 58
  local gw = aw - 12   -- content stops short of the scrollbar on the right
  local sc = UI.scrollState('legacy:' .. Title.legacyTab)
  sc.x, sc.yTop, sc.w, sc.h = ax, ay, aw, ah
  UI.pushClip(ax, ay, aw, ah)
  local cy = ay + 4 - sc.y
  if Title.legacyTab == 'perks' then
    cy = cy + UI.para('Perks last forever and help every tribe you found from now on. Bonuses to work and growth also help the tribe you are playing now.', ax + 20, cy, aw - 40, UI.F.small, C.muted, 'center') + 10
    local cols = max(1, floor((gw + 8) / 300))
    local cw = (gw - (cols - 1) * 8) / cols
    for k, p in ipairs(Legacy.PERKS) do
      local col, row = (k - 1) % cols, floor((k - 1) / cols)
      local x, y = ax + col * (cw + 8), cy + row * 172
      local lvl, cost = Legacy.level(p.id), Legacy.nextCost(p.id)
      UI.plaque(x, y, cw, 164, lvl > 0)
      UI.tile(x + 10, y + 10, 40, false)
      Art.draw(p.icon, x + 14, y + 14, 32)
      UI.shadowText(p.n, x + 60, y + 12, UI.F.bodyB, C.gold)
      UI.text(lvl == 0 and 'Not learned' or ('Level ' .. lvl .. ' of ' .. #p.cost), x + 60, y + 33, UI.F.tiny, C.muted)
      local dh = UI.para(p.d, x + 12, y + 56, cw - 24, UI.F.tiny, C.text)
      if p.q then UI.para(p.q, x + 12, y + 59 + dh, cw - 24, UI.F.tinyI, C.muted) end
      pips(x + 20, y + 145, lvl, #p.cost)
      if cost then
        local can = D.embers >= cost
        local label = (lvl == 0 and 'Learn' or 'Improve') .. '  \u{00b7}  ' .. cost .. (cost == 1 and ' ember' or ' embers')
        local bwid = UI.F.smallB:getWidth(label) + 26
        local bx2, by2 = x + cw - bwid - 10, y + 132
        local hot = UI.hit('perk:' .. p.id, bx2, by2, bwid, 24, { click = can and function() if Legacy.buy(p.id) then Screens.sfx('milestone') end end or nil, disabled = not can })
        UI.blue(bx2, by2, bwid, 24, not can and 'disabled' or (hot and 'hot' or nil))
        UI.shadowText(label, bx2 + 13, by2 + 3, UI.F.smallB, can and { 1, 1, 1, 1 } or C.muted)
      else UI.text('Mastered', x + cw - 10 - UI.F.smallB:getWidth('Mastered'), y + 135, UI.F.smallB, C.good) end
    end
    cy = cy + math.ceil(#Legacy.PERKS / cols) * 172
  elseif Title.legacyTab == 'miles' then
    cy = cy + UI.para('Milestones are reached once across all your tribes, and each one adds embers.', ax + 20, cy, aw - 40, UI.F.small, C.muted, 'center') + 10
    local cols = max(1, floor((gw + 8) / 230))
    local cw = (gw - (cols - 1) * 8) / cols
    for k, m in ipairs(Legacy.MILES) do
      local col, row = (k - 1) % cols, floor((k - 1) / cols)
      local x, y = ax + col * (cw + 8), cy + row * 76
      local done = D.miles[m.id]
      UI.plaque(x, y, cw, 70, done ~= nil)
      UI.hit('mile:' .. m.id, x, y, cw, 70, { tip = function()
        return { { t = 'title', icon = m.icon, text = m.n }, { t = 'p', text = m.d .. ' Worth ' .. m.e .. (m.e == 1 and ' ember.' or ' embers.') }, Flavor.p(m.q) }
      end })
      Art.draw(m.icon, x + 10, y + 10, 36, done and 1 or .3)
      UI.shadowText(m.n, x + 54, y + 8, UI.F.smallB, done and C.gold or C.muted)
      UI.para(m.d, x + 54, y + 27, cw - 64, UI.F.tiny, done and C.text or C.muted)
      local e = '+' .. m.e
      UI.text(e, x + cw - 10 - UI.F.smallB:getWidth(e), y + 8, UI.F.smallB, done and Art.color('#ffb55a') or C.muted)
      if done and type(done) == 'table' and done.tribe then UI.text('by the ' .. done.tribe, x + 54, y + 50, UI.F.micro, C.muted) end
    end
    cy = cy + math.ceil(#Legacy.MILES / cols) * 76
  else
    if #D.tribes == 0 then
      cy = cy + UI.para('No tribe has ended yet. When a tribe dies out or you retire it, its story is written here.', ax + 20, cy + 30, aw - 40, UI.F.body, C.muted, 'center') + 40
    end
    for _, t in ipairs(D.tribes) do
      local rh = 74
      UI.plaque(ax, cy, gw, rh)
      UI.shadowText('The ' .. tostring(t.name) .. ' tribe', ax + 14, cy + 8, UI.F.d18, C.gold)
      local years = floor((tonumber(t.day) or 0) / 100) + 1
      local info = (t.reason == 'retired' and 'Retired' or 'Died out') .. ' in year ' .. years .. '  \u{00b7}  ' .. tostring(t.era or '') .. '  \u{00b7}  generation ' .. tostring(t.gen or 1)
      UI.text(info, ax + 14, cy + 32, UI.F.tiny, C.muted)
      local stat = 'Up to ' .. tostring(t.peak or 0) .. ' people  \u{00b7}  ' .. tostring(t.techs or 0) .. ' discoveries  \u{00b7}  ' .. tostring(t.wonders or 0) .. ' wonders  \u{00b7}  ' .. tostring(t.born or 0) .. ' born, ' .. tostring(t.deaths or 0) .. ' died'
      UI.text(stat, ax + 14, cy + 50, UI.F.tiny, C.text)
      local e = '+' .. tostring(t.embers or 0)
      Art.draw('x.ember', ax + gw - 44 - UI.F.bodyB:getWidth(e), cy + 22, 26)
      UI.text(e, ax + gw - 14 - UI.F.bodyB:getWidth(e), cy + 26, UI.F.bodyB, Art.color('#ffb55a'))
      -- population over the tribe's life
      local sp = t.spark
      if type(sp) == 'table' and #sp > 1 then
        local sx, sy, sw, shh = ax + gw - 300, cy + 12, 180, 48
        local hi = 1
        for _, v in ipairs(sp) do hi = max(hi, tonumber(v) or 0) end
        local pts = {}
        for k, v in ipairs(sp) do pts[#pts + 1] = sx + (k - 1) / (#sp - 1) * sw; pts[#pts + 1] = sy + shh - (tonumber(v) or 0) / hi * shh end
        UI.rect(sx, sy + shh, sw, 1, C.frameHi, .25)
        UI.setc(C.blueHi); lg.setLineWidth(2); lg.line(pts)
        local lbl = 'people over time'
        UI.text(lbl, sx - 10 - UI.F.micro:getWidth(lbl), sy + shh - UI.F.micro:getHeight(), UI.F.micro, C.muted)
      end
      cy = cy + rh + 6
    end
  end
  sc.max = max(0, cy + sc.y - ay - ah + 10)
  sc.y = min(sc.y, sc.max)
  UI.popClip()
  UI.scrollbar(sc)
  local back = Title.back == 'game' and 'Back to the tribe' or 'Back'
  Screens.centerButton(back, 'legacy:back', bx, by + bh - 46, bw, function()
    if Title.back == 'game' then Title.onBackToGame() else Title.page = 'main' end
  end)
end
local function drawOptions(W, H)
  local bw = min(W - 40, 600)
  local bh = 6 * 56 + 130
  local bx, by = Screens.overlayBox(W, H, bw, bh)
  header(bx, by, bw, 'Settings')
  Screens.drawOptions(bx + 24, by + 66, bw - 48, 'topt:')
  Screens.centerButton('Back', 'opt:back', bx, by + bh - 46, bw, function() Title.page = 'main' end)
end

---------------------------------------------------------------- frame and input
function Title.draw(dt)
  Screens.dt = dt
  local W, H = UI.W, UI.H
  UI.beginFrame()
  lg.push()
  lg.scale(UI.scale)
  drawScene(W, H, dt)
  if Title.page == 'main' then drawMain(W, H)
  elseif Title.page == 'new' then drawNew(W, H)
  elseif Title.page == 'legacy' then drawLegacy(W, H)
  elseif Title.page == 'options' then drawOptions(W, H) end
  UI.drawFloats(dt)
  UI.endFrame()
  local hh = UI.hotHit
  if hh and hh.opts.tip then
    local ok, doc = pcall(hh.opts.tip)
    if ok and doc then UI.tooltip(doc, hh.x, hh.y, hh.w, hh.h) end
  end
  lg.pop()
end
function Title.textinput(t)
  if Title.page ~= 'new' then return end
  if t:match('^[%w%s%-\']$') and #Title.name < 16 then Title.name = Title.name .. t; caretT = 0 end
end
-- Returns true when the key was used here.
function Title.keypressed(key)
  if Title.page == 'new' then
    if key == 'backspace' then Title.name = Title.name:sub(1, -2); caretT = 0; return true end
    if key == 'return' or key == 'kpenter' then Title.found(); return true end
    if key == 'escape' then Title.page = 'main'; return true end
    return true
  end
  if key == 'escape' then
    if Title.page == 'legacy' and Title.back == 'game' then Title.onBackToGame() elseif Title.page ~= 'main' then Title.page = 'main' end
    return true
  end
  if Title.page == 'main' and (key == 'return' or key == 'kpenter') and Title.hasGame() then Title.onContinue(); return true end
  return false
end

return Title
