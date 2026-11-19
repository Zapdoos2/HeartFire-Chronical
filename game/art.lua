-- Hearthfire Chronicle: every icon in the game, painted in code.
-- Each icon is drawn on a 32x32 grid as outlined shapes with a light-to-dark shading and a soft shadow,
-- rendered once into a 128x128 canvas at startup so they stay sharp at large interface sizes.
local Art = {}
local lg = love.graphics
local cos, sin, pi, floor, max, min = math.cos, math.sin, math.pi, math.floor, math.max, math.min

---------------------------------------------------------------- colours
local cache = {}
function Art.color(c)
  if type(c) == 'table' then return c end
  if cache[c] then return cache[c] end
  local out
  if c:sub(1, 1) == '#' then
    out = { tonumber(c:sub(2, 3), 16) / 255, tonumber(c:sub(4, 5), 16) / 255, tonumber(c:sub(6, 7), 16) / 255, 1 }
  else
    local r, g, b, a = c:match('rgba%(%s*([%d.]+)%s*,%s*([%d.]+)%s*,%s*([%d.]+)%s*,%s*([%d.]+)%s*%)')
    out = { tonumber(r) / 255, tonumber(g) / 255, tonumber(b) / 255, tonumber(a) }
  end
  cache[c] = out
  return out
end
local color = Art.color
function Art.tone(c, a)
  local v = color(c)
  local function f(x) return a > 0 and x + (1 - x) * a or x * (1 + a) end
  return { f(v[1]), f(v[2]), f(v[3]), v[4] or 1 }
end
local tone = Art.tone
local OUTL = color('#150d06')

---------------------------------------------------------------- geometry
local function flat(pts) local o = {}; for _, p in ipairs(pts) do o[#o + 1] = p[1]; o[#o + 1] = p[2] end; return o end
local function ellipsePts(cx, cy, rx, ry, rot, seg)
  seg = seg or 28
  local o, cr, srr = {}, cos(rot or 0), sin(rot or 0)
  for k = 0, seg - 1 do
    local a = k / seg * pi * 2
    local x, y = cos(a) * rx, sin(a) * ry
    o[#o + 1] = cx + x * cr - y * srr; o[#o + 1] = cy + x * srr + y * cr
  end
  return o
end
local function rrectPts(x, y, w, h, r)
  r = min(r or 1, w / 2, h / 2)
  if r <= .05 then return { x, y, x + w, y, x + w, y + h, x, y + h } end
  local o = {}
  local corners = { { x + w - r, y + r, -pi / 2 }, { x + w - r, y + h - r, 0 }, { x + r, y + h - r, pi / 2 }, { x + r, y + r, pi } }
  for _, c in ipairs(corners) do
    for k = 0, 4 do local a = c[3] + k / 4 * pi / 2; o[#o + 1] = c[1] + cos(a) * r; o[#o + 1] = c[2] + sin(a) * r end
  end
  return o
end
local function quadPts(a, b, c, steps)
  steps = steps or 14
  local o = {}
  for k = 0, steps do
    local t = k / steps
    local u = 1 - t
    o[#o + 1] = u * u * a[1] + 2 * u * t * b[1] + t * t * c[1]
    o[#o + 1] = u * u * a[2] + 2 * u * t * b[2] + t * t * c[2]
  end
  return o
end
local function bbox(p)
  local x0, y0, x1, y1 = 1e9, 1e9, -1e9, -1e9
  for k = 1, #p, 2 do x0 = min(x0, p[k]); x1 = max(x1, p[k]); y0 = min(y0, p[k + 1]); y1 = max(y1, p[k + 1]) end
  return x0, y0, x1, y1
end
local function triangles(p)
  -- drop repeated points, which the triangulator rejects
  local q = {}
  for k = 1, #p, 2 do
    local n = #q
    if n < 2 or math.abs(q[n - 1] - p[k]) > 1e-4 or math.abs(q[n] - p[k + 1]) > 1e-4 then q[#q + 1] = p[k]; q[#q + 1] = p[k + 1] end
  end
  if #q >= 4 and math.abs(q[1] - q[#q - 1]) < 1e-4 and math.abs(q[2] - q[#q]) < 1e-4 then q[#q] = nil; q[#q] = nil end
  if #q < 6 then return {} end
  local ok, tris = pcall(love.math.triangulate, q)
  if ok then return tris end
  return { q }
end
Art.triangles, Art.ellipsePts, Art.rrectPts, Art.quadPts = triangles, ellipsePts, rrectPts, quadPts

---------------------------------------------------------------- reusable meshes
-- Gradients, chart fills and flames are drawn as small meshes, many of them every frame. Making a new mesh for
-- each one asks the graphics card for a new buffer and leaves garbage that stalls frames when it is collected,
-- so one mesh per drawing mode is kept and refilled instead. It grows when a longer one is needed.
local meshPool = {}
function Art.mesh(verts, mode)
  local n = #verts
  local m = meshPool[mode]
  if not m or m:getVertexCount() < n then
    if m then m:release() end
    m = lg.newMesh(max(n, 64), mode, 'stream')
    meshPool[mode] = m
  end
  m:setVertices(verts)
  m:setDrawRange(1, n)
  return m
end
-- the four corners of a gradient rectangle, filled in place to make no garbage
local quadVerts = { { 0, 0, 0, 0, 1, 1, 1, 1 }, { 0, 0, 0, 0, 1, 1, 1, 1 }, { 0, 0, 0, 0, 1, 1, 1, 1 }, { 0, 0, 0, 0, 1, 1, 1, 1 } }
local function corner(k, x, y, c, a)
  local v = quadVerts[k]
  v[1], v[2], v[5], v[6], v[7], v[8] = x, y, c[1], c[2], c[3], a or c[4] or 1
end
-- Draws a rectangle whose four corners have the given colors (top-left, top-right, bottom-right, bottom-left).
function Art.gradRect(x0, y0, x1, y1, c1, c2, c3, c4, a)
  corner(1, x0, y0, c1, a); corner(2, x1, y0, c2, a); corner(3, x1, y1, c3, a); corner(4, x0, y1, c4, a)
  lg.setColor(1, 1, 1, 1); lg.draw(Art.mesh(quadVerts, 'fan'))
end

---------------------------------------------------------------- the painter
local function gradientFill(stencilFn, x0, y0, x1, y1, col)
  lg.stencil(stencilFn, 'replace', 1)
  lg.setStencilTest('greater', 0)
  local L, D, Mc = tone(col, .32), tone(col, -.32), color(col)
  Art.gradRect(x0, y0, x1 + .01, y1 + .01, L, Mc, D, Mc, 1)
  lg.setStencilTest()
end
local function roundLine(p, w)
  if #p < 4 then return end
  lg.setLineWidth(w); lg.line(p)
  for k = 1, #p, 2 do lg.circle('fill', p[k], p[k + 1], w / 2, 10) end
end

local function render(s)
  local t = s.t
  if t == 'poly' then
    local tris = triangles(s.pts)
    lg.setColor(OUTL); lg.setLineWidth(2); lg.setLineJoin('bevel'); lg.polygon('line', s.pts)
    for k = 1, #s.pts, 2 do lg.circle('fill', s.pts[k], s.pts[k + 1], .95, 8) end
    local x0, y0, x1, y1 = bbox(s.pts)
    gradientFill(function() for _, tri in ipairs(tris) do lg.polygon('fill', tri) end end, x0, y0, x1, y1, s.col)
  elseif t == 'blob' then
    lg.setColor(OUTL)
    for _, c in ipairs(s.circles) do lg.circle('fill', c[1], c[2], c[3] + 1, 32) end
    local x0, y0, x1, y1 = 1e9, 1e9, -1e9, -1e9
    for _, c in ipairs(s.circles) do x0 = min(x0, c[1] - c[3]); x1 = max(x1, c[1] + c[3]); y0 = min(y0, c[2] - c[3]); y1 = max(y1, c[2] + c[3]) end
    gradientFill(function() for _, c in ipairs(s.circles) do lg.circle('fill', c[1], c[2], c[3], 32) end end, x0, y0, x1, y1, s.col)
  elseif t == 'line' then
    lg.setColor(OUTL); roundLine(s.pts, s.w + 2)
    lg.setColor(color(s.col)); roundLine(s.pts, s.w)
  elseif t == 'dline' then
    lg.setColor(color(s.col)); lg.setLineWidth(s.w); lg.setLineJoin('bevel'); lg.line(s.pts)
  elseif t == 'dpoly' then
    lg.setColor(color(s.col))
    for _, tri in ipairs(triangles(s.pts)) do lg.polygon('fill', tri) end
  end
end

Art.RES = 128
Art.MIP_SHARPNESS = .5   -- a little sharper than the default when icons are drawn smaller than they were painted
local bodyCanvas   -- the multisampled canvas icons are painted on; one is shared by every icon (see Art.load)
function Art.paint(draw)
  local L = {}
  local g = {}
  function g.c(cx, cy, r, col) L[#L + 1] = { t = 'poly', pts = ellipsePts(cx, cy, r, r, 0, 32), col = col } end
  function g.e(cx, cy, rx, ry, col, rot) L[#L + 1] = { t = 'poly', pts = ellipsePts(cx, cy, rx, ry, rot, 32), col = col } end
  function g.r(x, y, w, h, col, rad) L[#L + 1] = { t = 'poly', pts = rrectPts(x, y, w, h, rad == nil and 1 or rad), col = col } end
  function g.p(pts, col) L[#L + 1] = { t = 'poly', pts = flat(pts), col = col } end
  function g.b(circles, col) L[#L + 1] = { t = 'blob', circles = circles, col = col } end
  function g.l(pts, w, col) L[#L + 1] = { t = 'line', pts = flat(pts), w = w, col = col } end
  function g.q(a, b, c, w, col) L[#L + 1] = { t = 'line', pts = quadPts(a, b, c), w = w, col = col } end
  function g.dl(pts, w, col) L[#L + 1] = { t = 'dline', pts = flat(pts), w = w, col = col } end
  function g.dq(a, b, c, w, col) L[#L + 1] = { t = 'dline', pts = quadPts(a, b, c), w = w, col = col } end
  function g.dc(cx, cy, r, col) L[#L + 1] = { t = 'dpoly', pts = ellipsePts(cx, cy, r, r, 0, 20), col = col } end
  function g.de(cx, cy, rx, ry, col, rot) L[#L + 1] = { t = 'dpoly', pts = ellipsePts(cx, cy, rx, ry, rot, 24), col = col } end
  function g.dp(pts, col) L[#L + 1] = { t = 'dpoly', pts = flat(pts), col = col } end
  function g.hl(cx, cy, r) L[#L + 1] = { t = 'dpoly', pts = ellipsePts(cx, cy, r, r, 0, 16), col = 'rgba(255,255,255,.42)' } end
  draw(g)

  local R = Art.RES
  local body = bodyCanvas or lg.newCanvas(R, R, { msaa = 8, dpiscale = 1 })
  lg.push('all')
  lg.setCanvas({ body, stencil = true })
  lg.clear(0, 0, 0, 0)
  lg.origin(); lg.scale(R / 32, R / 32)
  for _, s in ipairs(L) do render(s) end
  lg.pop()

  -- Icons are painted large and usually drawn much smaller (down to a quarter size on a plain, non-Retina screen).
  -- Mipmaps give the graphics card ready-made half, quarter... size copies to pick from, so shrunken icons stay
  -- smooth instead of jagged. Old graphics cards that cannot do this get the plain picture.
  local okMip, out = pcall(lg.newCanvas, R, R, { dpiscale = 1, mipmaps = 'auto' })
  if not okMip then out = lg.newCanvas(R, R, { dpiscale = 1 }) end
  local k = R / 64
  lg.push('all')
  lg.setCanvas(out)
  lg.clear(0, 0, 0, 0)
  lg.origin()
  lg.setBlendMode('alpha', 'premultiplied')
  for _, o in ipairs({ { 0, 2.5 }, { 1.2, 3 }, { -1.2, 3 }, { 0, 4 } }) do lg.setColor(0, 0, 0, .2); lg.draw(body, o[1] * k, o[2] * k) end
  lg.setColor(1, 1, 1, 1); lg.draw(body, 0, 0)
  lg.pop()
  if body ~= bodyCanvas then body:release() end
  if okMip then pcall(out.setMipmapFilter, out, 'linear', Art.MIP_SHARPNESS) end
  return out
end

---------------------------------------------------------------- palette and shared shapes
local SKIN, HAIR, WOOD, WOODL, STONE, IRON, LEAF, PARCH, GOLD, CLAY = '#d8a06a', '#4b2d18', '#8a5a2b', '#a8743c', '#8e8a84', '#9aa3ad', '#5c9c3a', '#e3d3a8', '#e2b23c', '#c4733f'

local function person(g, o)
  o = o or {}
  local s, ox, oy = o.s or 1, o.x or 0, o.y or 0
  local function P(px, py) return { 16 + ox + (px - 16) * s, 31 + oy - (31 - py) * s } end
  local function box(px, py, w, h, col) local q = P(px, py); g.r(q[1], q[2], w * s, h * s, col, s) end
  local skin, hair, tunic, legs = o.skin or SKIN, o.hair or HAIR, o.tunic or '#8a6b45', o.legs or '#5b3c22'
  box(12, 24, 3.4, 6.5, legs); box(16.6, 24, 3.4, 6.5, legs)
  if o.robe then g.p({ P(11, 14), P(21, 14), P(23.5, 30.5), P(8.5, 30.5) }, tunic)
  else g.p({ P(11, 14), P(21, 14), P(23, 26), P(9, 26) }, tunic) end
  if o.belt then g.dl({ P(9.8, 21.5), P(22.2, 21.5) }, 1.3 * s, o.belt) end
  if o.armL ~= false then g.l({ P(11.2, 15.5), P(8, 22) }, 2.6 * s, skin) end
  if o.armR ~= false then g.l({ P(20.8, 15.5), P(24, 21) }, 2.6 * s, skin) end
  local h = P(16, 9)
  local hx, hy = h[1], h[2]
  g.c(hx, hy, 5 * s, skin)
  if hair ~= 'none' then
    local pts = {}
    for k = 0, 12 do local a = pi + pi * k / 12; pts[#pts + 1] = { hx + cos(a) * 5.4 * s, hy - .5 * s + sin(a) * 5.3 * s } end
    g.p(pts, hair)
  end
  if o.eyes == 'closed' then
    g.dq({ hx - 3 * s, hy + s }, { hx - 1.8 * s, hy + 2 * s }, { hx - .7 * s, hy + s }, .7 * s, '#2a1a0e')
    g.dq({ hx + .7 * s, hy + s }, { hx + 1.8 * s, hy + 2 * s }, { hx + 3 * s, hy + s }, .7 * s, '#2a1a0e')
  else
    g.dc(hx - 1.8 * s, hy + s, .8 * s, '#2a1a0e'); g.dc(hx + 1.8 * s, hy + s, .8 * s, '#2a1a0e')
  end
  return { hand = P(24, 21), handL = P(8, 22), head = { hx, hy } }
end
local function flame(g, x, y, s, outer, inner)
  s = s or 1
  g.p({ { x, y - 6.5 * s }, { x + 2.2 * s, y - 3 * s }, { x + 3.6 * s, y - .5 * s }, { x + 3 * s, y + 2.6 * s }, { x, y + 3.8 * s }, { x - 3 * s, y + 2.6 * s }, { x - 3.6 * s, y - .8 * s }, { x - 1.6 * s, y - 2.6 * s } }, outer or '#e8671f')
  g.dp({ { x + .2 * s, y - 3.4 * s }, { x + 1.9 * s, y + .3 * s }, { x + 1.3 * s, y + 2.5 * s }, { x - 1.3 * s, y + 2.5 * s }, { x - 1.9 * s, y + .3 * s } }, inner or '#ffd34d')
end
local function drop(g, x, y, s, col)
  local pts = { { x, y - 11 * s } }
  for k = 0, 14 do local a = -.45 + (pi + .9) * k / 14; pts[#pts + 1] = { x + cos(a) * 7 * s, y + 2 * s + sin(a) * 7 * s } end
  g.p(pts, col); g.hl(x - 2.8 * s, y + .6 * s, 1.7 * s)
end
local function leaf(g, x, y, ang, s, col)
  g.e(x, y, 4 * s, 1.7 * s, col or LEAF, ang)
  g.dl({ { x - cos(ang) * 3 * s, y - sin(ang) * 3 * s }, { x + cos(ang) * 3 * s, y + sin(ang) * 3 * s } }, .6, 'rgba(20,50,10,.5)')
end
local function spear(g, x1, y1, x2, y2)
  g.l({ { x1, y1 }, { x2, y2 } }, 1.6, WOOD)
  local a, W, Ln = math.atan2(y2 - y1, x2 - x1), 1.9, 4.5
  g.p({ { x2 + cos(a + 1.57) * W, y2 + sin(a + 1.57) * W }, { x2 + cos(a) * Ln, y2 + sin(a) * Ln }, { x2 + cos(a - 1.57) * W, y2 + sin(a - 1.57) * W } }, IRON)
end
local function star(g, x, y, r, col)
  local pts = {}
  for k = 0, 7 do local a = -pi / 2 + k * pi / 4; local rr = (k % 2 == 1) and r * .38 or r; pts[#pts + 1] = { x + cos(a) * rr, y + sin(a) * rr } end
  g.p(pts, col or '#ffe27a')
end
local function grainStalk(g, x, y, ang)
  g.l({ { 16 + (x - 16) * .3, 30 }, { x, y + 5 } }, 1.3, '#a7843a')
  g.e(x, y, 2.4, 6, '#e3b64a', ang)
  g.dl({ { x - sin(ang) * 4.5, y + cos(ang) * 4.5 }, { x + sin(ang) * 4.5, y - cos(ang) * 4.5 } }, .7, 'rgba(110,70,10,.6)')
end
local function hutArt(g)
  g.r(6, 16, 20, 11, '#9b6a35', 0)
  g.dl({ { 6, 20 }, { 26, 20 } }, .7, 'rgba(40,20,5,.5)'); g.dl({ { 6, 23.5 }, { 26, 23.5 } }, .7, 'rgba(40,20,5,.5)')
  g.p({ { 3, 17.5 }, { 16, 5 }, { 29, 17.5 } }, '#c9a24a')
  for k = 0, 4 do g.dl({ { 16, 6.5 }, { 6 + k * 5, 17 } }, .6, 'rgba(90,60,10,.55)') end
  g.r(13.5, 19.5, 5, 7.5, '#3a2614', .5)
end
local function cloud(g, x, y, s, col) g.b({ { x - 6 * s, y + 1.5 * s, 4.2 * s }, { x - s, y - 2 * s, 5.6 * s }, { x + 5 * s, y + .5 * s, 4.6 * s }, { x, y + 3 * s, 4.4 * s } }, col) end
local function face(g, lvl)
  g.c(16, 16, 12, '#f0c445'); g.hl(11, 10, 2.6)
  g.dc(11.5, 13.5, 1.5, '#3a2410'); g.dc(20.5, 13.5, 1.5, '#3a2410')
  local off = ({ -5, -2.5, 0, 3, 5.5 })[lvl + 1]
  g.dq({ 10, 21 }, { 16, 21 + off }, { 22, 21 }, 1.5, '#3a2410')
  if lvl == 0 then g.dp({ { 22, 15.5 }, { 23.4, 19 }, { 21.6, 19.4 } }, '#5aa0e0') end
  if lvl == 4 then g.dc(9, 18, 1.6, 'rgba(230,90,70,.4)'); g.dc(23, 18, 1.6, 'rgba(230,90,70,.4)') end
end
local function bone(g, x1, y1, x2, y2)
  local a = math.atan2(y2 - y1, x2 - x1)
  local px, py = cos(a + 1.57) * 1.8, sin(a + 1.57) * 1.8
  for _, e in ipairs({ { x1, y1 }, { x2, y2 } }) do g.c(e[1] + px, e[2] + py, 2.2, '#ece3cc'); g.c(e[1] - px, e[2] - py, 2.2, '#ece3cc') end
  g.l({ { x1, y1 }, { x2, y2 } }, 3.2, '#ece3cc')
end

---------------------------------------------------------------- the icons
local I = {}
-- food and water
I.fruit = function(g)
  g.l({ { 16, 12 }, { 18, 6 } }, 1, '#6b4a22'); leaf(g, 21, 7, -.5, 1.1, '#4f8f34')
  for _, b in ipairs({ { 12, 15, 4.2, '#5a3592' }, { 20, 15, 4.2, '#6a3fa8' }, { 16, 21, 4.4, '#4d2c80' }, { 10.5, 21.5, 3.4, '#6a3fa8' }, { 22, 22, 3.4, '#5a3592' } }) do
    g.c(b[1], b[2], b[3], b[4]); g.hl(b[1] - 1.2, b[2] - 1.3, 1.1)
  end
end
I.meat = function(g)
  g.c(26.5, 25, 2, '#efe6d2'); g.c(24.5, 27.5, 2, '#efe6d2'); g.l({ { 19, 19 }, { 25.5, 26 } }, 3, '#efe6d2')
  g.e(14, 14.5, 10, 8, '#b8322a', -.5); g.dq({ 7, 16 }, { 12, 10 }, { 20, 9.5 }, 1.3, 'rgba(255,225,215,.75)'); g.hl(11, 12, 1.6)
end
I.fish = function(g)
  g.p({ { 24, 16 }, { 30.5, 10 }, { 29, 16 }, { 30.5, 22 } }, '#4f7a9c'); g.e(15, 16, 10.5, 6.2, '#7fa8c9')
  g.dc(9, 14.6, 1.2, '#1b1b1b'); g.dq({ 12.5, 11.5 }, { 15.5, 16 }, { 12.5, 20.5 }, .9, 'rgba(30,50,70,.55)'); g.dl({ { 15, 19.5 }, { 22, 18.5 } }, .8, 'rgba(255,255,255,.35)'); g.hl(11, 13, 1.4)
end
I.cooked = function(g)
  g.c(26.5, 25, 2, '#efe6d2'); g.c(24.5, 27.5, 2, '#efe6d2'); g.l({ { 19, 19 }, { 25.5, 26 } }, 3, '#efe6d2')
  g.e(13.5, 13.5, 9.5, 8, '#9a5523', -.7); g.dq({ 7, 16 }, { 11, 20 }, { 17, 18 }, 1.1, 'rgba(60,25,5,.55)'); g.hl(10, 10, 1.9); g.dc(16, 11, .9, 'rgba(255,230,180,.5)')
end
I.grain = function(g) leaf(g, 11, 22, -2.2, 1.1, '#8aa03a'); grainStalk(g, 10, 12, -.35); grainStalk(g, 22, 12, .35); grainStalk(g, 16, 9, 0) end
I.bread = function(g)
  g.e(16, 19, 12.5, 7.5, '#b57a32'); g.e(16, 17, 10.5, 5.5, '#d9a056')
  for _, l in ipairs({ { 10, 15, 12, 19.5 }, { 15, 14, 17, 19.5 }, { 20, 14, 22, 19 } }) do g.dl({ { l[1], l[2] }, { l[3], l[4] } }, 1.1, 'rgba(110,60,15,.75)') end
  g.hl(10.5, 14.5, 1.4)
end
I.water = function(g) drop(g, 16, 16.5, 1.15, '#3f86d6') end
I.muddy = function(g) drop(g, 16, 16.5, 1.15, '#86603a'); g.dc(18, 20, 1, 'rgba(40,25,10,.5)'); g.dc(14, 23, .8, 'rgba(40,25,10,.5)'); g.dc(19.5, 15.5, .7, 'rgba(40,25,10,.5)') end
-- materials
I.sticks = function(g) g.l({ { 5, 25 }, { 26, 10 } }, 2.3, '#7a4e25'); g.l({ { 6, 12 }, { 26, 25 } }, 2.3, WOODL); g.l({ { 11, 28 }, { 21, 5 } }, 2.1, WOOD); g.l({ { 18, 13 }, { 22, 11 } }, 1.2, WOODL) end
I.wood = function(g)
  g.p({ { 6, 13 }, { 21, 8 }, { 25, 20 }, { 10, 25 } }, '#8a5a2b'); g.dl({ { 9, 16 }, { 21, 12 } }, .7, 'rgba(40,20,5,.55)'); g.dl({ { 10, 20 }, { 22, 16 } }, .7, 'rgba(40,20,5,.55)')
  g.e(23, 14, 3.6, 6.4, '#d9a865', -.32); g.de(23, 14, 2, 3.8, 'rgba(140,90,40,.6)', -.32); g.dc(23, 14, .8, 'rgba(120,70,30,.8)')
end
I.stone = function(g)
  g.p({ { 4, 24 }, { 7, 15 }, { 14, 11 }, { 20, 15 }, { 19, 25 }, { 10, 27.5 } }, '#87837d'); g.p({ { 15, 27 }, { 17, 18.5 }, { 24, 15 }, { 29, 20 }, { 27.5, 27 } }, '#a39e96')
  g.hl(9.5, 16.5, 1.7); g.hl(21, 19, 1.3); g.dl({ { 11, 19 }, { 13.5, 22.5 } }, .8, 'rgba(0,0,0,.3)')
end
I.clay = function(g) g.e(16, 21, 12, 7, '#a9653a'); g.e(16, 17.5, 8.5, 5, '#c98250'); g.dc(13, 17, 1.3, 'rgba(90,40,15,.45)'); g.dc(18, 18.5, 1.1, 'rgba(90,40,15,.45)'); g.hl(12, 15.5, 1.3) end
I.herbs = function(g) g.q({ 16, 30 }, { 15, 18 }, { 18, 6 }, 1.4, '#4d7a2a'); for _, l in ipairs({ { 11.5, 23, -2.4 }, { 20.5, 21, -.8 }, { 11, 15, -2.5 }, { 20.5, 13, -.7 }, { 17.5, 7, -1.3 } }) do leaf(g, l[1], l[2], l[3], 1.25, '#5fa03c') end end
I.fiber = function(g)
  for k = -3, 3 do g.q({ 16 + k * .5, 29 }, { 16 + k * 1.4, 18 }, { 16 + k * 3.2, 4.5 }, 1.2, (k % 2 ~= 0) and '#9fb04a' or '#b9c35a') end
  g.r(11.5, 18.5, 9, 3.2, WOOD, 1)
end
I.bones = function(g) bone(g, 7, 8, 25, 24); bone(g, 25, 8, 7, 24) end
I.hides = function(g)
  g.p({ { 8, 6 }, { 13, 9 }, { 19, 9 }, { 24, 6 }, { 23, 12 }, { 27, 17 }, { 23, 22 }, { 24, 27.5 }, { 19, 24.5 }, { 13, 24.5 }, { 8, 27.5 }, { 9, 22 }, { 5, 17 }, { 9, 12 } }, '#9a6a3a')
  g.dc(13, 14, 1.8, 'rgba(60,35,15,.5)'); g.dc(19, 17, 2.2, 'rgba(60,35,15,.5)'); g.dc(14, 20, 1.4, 'rgba(60,35,15,.5)'); g.hl(11, 12, 1.4)
end
I.ore = function(g)
  g.p({ { 4, 25 }, { 6, 15 }, { 13, 9 }, { 22, 10 }, { 28, 17 }, { 26, 26 }, { 14, 28 } }, '#77736c')
  for _, t in ipairs({ { { 11, 15 }, { 14, 13 }, { 15, 17 } }, { { 18, 19 }, { 22, 17 }, { 22, 22 } }, { { 9, 21 }, { 12, 20 }, { 11, 24 } } }) do g.p(t, '#e08a2a') end
  g.hl(9, 13.5, 1.4)
end
-- goods
I.tools = function(g) g.l({ { 8, 28 }, { 21, 10 } }, 2.2, WOOD); g.p({ { 18, 6 }, { 26, 8.5 }, { 24.5, 14 }, { 19.5, 11.5 } }, IRON); g.l({ { 25, 28 }, { 11, 11 } }, 2.2, WOODL); g.p({ { 5.5, 10.5 }, { 10.5, 5 }, { 15, 9.5 }, { 10, 14.5 } }, '#7f7a74') end
I.clothing = function(g)
  g.p({ { 10, 5.5 }, { 13.5, 7.5 }, { 18.5, 7.5 }, { 22, 5.5 }, { 28.5, 11 }, { 25, 15.5 }, { 22, 13 }, { 22, 27.5 }, { 10, 27.5 }, { 10, 13 }, { 7, 15.5 }, { 3.5, 11 } }, '#a6784a')
  g.dq({ 13.5, 7.5 }, { 16, 11 }, { 18.5, 7.5 }, 1, 'rgba(60,30,10,.7)'); g.dl({ { 10, 19 }, { 22, 19 } }, 1.4, '#6b4423'); g.hl(13, 12, 1.4)
end
I.pottery = function(g)
  g.q({ 11, 10 }, { 5.5, 13 }, { 11, 17 }, 1.4, '#a85c33'); g.q({ 21, 10 }, { 26.5, 13 }, { 21, 17 }, 1.4, '#a85c33')
  g.e(16, 19.5, 8, 9, CLAY); g.r(12.5, 5.5, 7, 6, '#b9673a', 1); g.e(16, 5.5, 4.6, 1.5, '#8f4c28')
  g.dl({ { 9, 18 }, { 23, 18 } }, 1.2, 'rgba(60,20,5,.55)'); g.dl({ { 9.5, 21.5 }, { 22.5, 21.5 } }, .8, 'rgba(255,220,180,.4)'); g.hl(12, 15.5, 1.6)
end
I.bricks = function(g) g.r(3.5, 20, 12, 7, '#a8432c', .8); g.r(16.5, 20, 12, 7, '#b04a30', .8); g.r(10, 12, 12, 7, '#b9533a', .8); g.r(6.5, 4.5, 10, 6.5, '#a8432c', .8); g.hl(6, 22, 1); g.hl(13, 14, 1) end
I.metal = function(g)
  g.p({ { 4, 26 }, { 8, 19.5 }, { 22, 19.5 }, { 26, 26 } }, '#7f8b97'); g.p({ { 9, 19 }, { 12, 13 }, { 24, 13 }, { 27, 19 } }, '#a3afba'); g.p({ { 7, 12.5 }, { 10, 7 }, { 20, 7 }, { 23, 12.5 } }, '#8e9aa6')
  g.dl({ { 11, 15 }, { 23, 15 } }, .8, 'rgba(255,255,255,.4)'); g.dl({ { 10, 9 }, { 19, 9 } }, .8, 'rgba(255,255,255,.35)')
end
I.fire = function(g) g.l({ { 6, 27 }, { 26, 22.5 } }, 3, '#6b4423'); g.l({ { 6, 22.5 }, { 26, 27 } }, 3, WOOD); flame(g, 16, 14.5, 1.6) end
I.corpses = function(g)
  g.e(16, 21, 13, 5.5, '#cfc8b6'); g.e(6, 19.5, 3.6, 3.4, '#c4bcaa')
  for _, x in ipairs({ 11, 16, 21 }) do g.dl({ { x, 16 }, { x + .8, 26 } }, 1, 'rgba(90,70,40,.7)') end
  g.hl(9, 18, 1.2)
end
-- essentials
I.insight = function(g) cloud(g, 15, 17, 1.2, '#bcd8ff'); star(g, 22, 9, 5, '#ffe27a'); g.hl(10, 14, 1.6) end
I.culture = function(g)
  g.p({ { 6, 7 }, { 26, 7 }, { 25, 18 }, { 16, 28 }, { 7, 18 } }, '#d96aa8')
  g.dp({ { 9, 12 }, { 14, 11 }, { 13.5, 15 }, { 9.5, 14.5 } }, '#2a1020'); g.dp({ { 23, 12 }, { 18, 11 }, { 18.5, 15 }, { 22.5, 14.5 } }, '#2a1020')
  g.dq({ 11, 19 }, { 16, 24 }, { 21, 19 }, 1.5, '#2a1020'); g.dl({ { 8, 9 }, { 24, 9 } }, 1, 'rgba(255,230,120,.8)'); g.hl(10, 10, 1.2)
end
I.faith = function(g)
  g.dc(16, 9, 8, 'rgba(255,210,90,.22)'); g.r(12, 14, 8, 14, '#efe4c8', 1.5); g.dq({ 12, 14 }, { 16, 16 }, { 20, 14 }, 1, 'rgba(160,140,100,.6)')
  g.l({ { 16, 14 }, { 16, 12 } }, .8, '#3a2a1a'); flame(g, 16, 8.5, 1); g.hl(14, 18, 1.1)
end
I.influence = function(g)
  g.p({ { 5, 24 }, { 5, 10.5 }, { 10.5, 17 }, { 16, 7.5 }, { 21.5, 17 }, { 27, 10.5 }, { 27, 24 } }, GOLD); g.r(5, 21.5, 22, 5, '#c9962c', 1)
  g.dc(16, 18, 1.8, '#c0392b'); g.dc(10, 20, 1.3, '#3f86d6'); g.dc(22, 20, 1.3, '#3f86d6'); g.hl(9, 14, 1.2)
end
-- people tiles
I['e.people'] = function(g) person(g, { x = -5.5, s = .78, tunic = '#8a6b45' }); person(g, { x = 5.5, s = .78, tunic = '#5f7491', hair = '#2e1d10' }) end
I['e.workers'] = function(g)
  local h = person(g, { tunic = '#3f6fb5', legs = '#2d3f5a' }).hand
  g.l({ { h[1] - 2, h[2] + 5 }, { h[1] + 2, h[2] - 12 } }, 1.8, WOOD); g.q({ h[1] - 3.5, h[2] - 11 }, { h[1] + 2.5, h[2] - 15.5 }, { h[1] + 7.5, h[2] - 10 }, 2, IRON)
end
I['e.health'] = function(g)
  local pts = {}
  for k = 0, 39 do local t = k / 40 * pi * 2; pts[#pts + 1] = { 16 + 16 * sin(t) ^ 3 * .72, 15 - (13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t)) * .72 } end
  g.p(pts, '#d23b3b'); g.hl(10.5, 10.5, 2)
end
I['e.land'] = function(g)
  g.p({ { 3, 17 }, { 16, 24 }, { 16, 28 }, { 3, 21 } }, '#7a5a33'); g.p({ { 16, 24 }, { 29, 17 }, { 29, 21 }, { 16, 28 } }, '#5e4428'); g.p({ { 16, 10 }, { 29, 17 }, { 16, 24 }, { 3, 17 } }, '#6f9a42')
  g.l({ { 20, 17 }, { 20, 12 } }, 1.5, '#6b4423'); g.b({ { 20, 9.5, 3.6 }, { 17.5, 11, 2.6 }, { 22.5, 11, 2.6 } }, '#3f7a34'); g.e(10, 18, 2.4, 1.6, STONE)
end
I['e.adults'] = function(g) person(g, { tunic = '#8a6b45' }) end
I['e.children'] = function(g) person(g, { s = .68, tunic = '#9a7a4a' }) end
I['e.elders'] = function(g) g.l({ { 7, 30 }, { 8.5, 21 } }, 1.5, WOOD); person(g, { tunic = '#7a7262', hair = '#d8d2c6' }) end
I['e.sick'] = function(g) person(g, { tunic = '#7a7262', skin = '#a9b77a' }); drop(g, 24.5, 6.5, .32, '#7fb6e8'); g.dl({ { 13, 13.5 }, { 19, 13.5 } }, .8, 'rgba(40,60,20,.7)') end
I['e.housing'] = function(g) hutArt(g) end
I['e.homeless'] = function(g) person(g, { tunic = '#7a6a55', y = 2 }); cloud(g, 16, 5, .7, '#8a9aaa'); for _, d in ipairs({ { 10, 11 }, { 16, 12.5 }, { 22, 11 } }) do g.dl({ { d[1], d[2] }, { d[1] - 1, d[2] + 3 } }, 1, '#7fb6e8') end end
-- jobs
I['u.gatherer'] = function(g)
  person(g, { tunic = '#7d8a3e' }); g.p({ { 20.5, 20 }, { 29.5, 20 }, { 28, 27 }, { 22, 27 } }, '#b5803f'); g.dl({ { 21.5, 23 }, { 28.6, 23 } }, .8, 'rgba(60,30,10,.6)')
  g.c(23, 19.5, 1.7, '#5a3592'); g.c(26.5, 19.3, 1.7, '#6a3fa8'); g.c(25, 18, 1.5, '#c0392b')
end
I['u.dreamer'] = function(g) person(g, { tunic = '#6a5aa8', eyes = 'closed' }); g.b({ { 25, 5.5, 3.3 }, { 28.5, 7.5, 2.5 }, { 22, 7.5, 2.4 } }, '#dfe9ff'); g.dc(21, 13, .9, '#dfe9ff'); g.dc(22.3, 11, 1.1, '#dfe9ff') end
I['u.wanderer'] = function(g) g.c(9, 14.5, 4.3, '#b39563'); person(g, { tunic = '#9a7a50' }); g.l({ { 25.5, 9 }, { 23.5, 30 } }, 1.8, WOOD) end
I['u.knapper'] = function(g) person(g, { tunic = '#8c7b62' }); g.p({ { 21.5, 18 }, { 28.8, 19.5 }, { 24.3, 25 } }, '#7d8794'); g.c(7.5, 22.5, 2.3, '#9b948a'); g.dc(27.5, 26.5, .8, '#9aa0a8'); g.dc(29.5, 23.5, .6, '#9aa0a8') end
I['u.firekeeper'] = function(g) person(g, { tunic = '#a0522d' }); g.l({ { 24, 24.5 }, { 25.6, 13.5 } }, 2, '#6b4423'); flame(g, 25.8, 10.5, 1) end
I['u.hunter'] = function(g) person(g, { tunic = '#8b5e34', belt = '#5a3a1a' }); spear(g, 23.5, 30, 26, 6.5) end
I['u.fisher'] = function(g) person(g, { tunic = '#4f7d8f' }); g.l({ { 22.5, 23 }, { 30, 3.5 } }, 1.2, WOODL); g.dl({ { 30, 3.5 }, { 30.4, 15 } }, .6, 'rgba(235,235,235,.85)'); g.e(29.8, 18.5, 2.4, 1.3, '#7fa8c9', 1.45) end
I['u.digger'] = function(g) person(g, { tunic = '#7a6a4a' }); g.l({ { 22, 7 }, { 24.5, 22 } }, 1.8, WOOD); g.p({ { 21.8, 21.5 }, { 27.2, 20.8 }, { 27.8, 27 }, { 24.8, 29.5 }, { 22, 27 } }, IRON) end
I['u.woodcutter'] = function(g) person(g, { tunic = '#5f7a3a' }); g.l({ { 23, 25 }, { 26.5, 6.5 } }, 1.8, WOOD); g.p({ { 25, 6.5 }, { 30.5, 4.5 }, { 31, 11 }, { 26, 10.5 } }, IRON) end
I['u.healer'] = function(g)
  person(g, { tunic = '#d9d0bc', robe = true }); g.dl({ { 11.5, 6.8 }, { 20.5, 6.8 } }, 1.2, '#4f8f34'); g.l({ { 24.5, 22 }, { 26.5, 14 } }, 1, '#4d7a2a')
  leaf(g, 25, 15.5, -1.2, 1, '#5fa03c'); leaf(g, 28, 17.5, -.5, 1, '#4f8f34'); leaf(g, 23, 17, -2.2, .9, '#6fb04a')
end
I['u.storyteller'] = function(g)
  person(g, { tunic = '#a8553a' }); g.r(21, 17, 8.5, 6.5, PARCH, 1); g.dl({ { 22.5, 19 }, { 28, 19 } }, .6, 'rgba(80,60,30,.6)'); g.dl({ { 22.5, 21 }, { 27, 21 } }, .6, 'rgba(80,60,30,.6)')
  g.dq({ 9.5, 6 }, { 8, 9 }, { 9.5, 12 }, .8, 'rgba(255,240,200,.8)'); g.dq({ 7.5, 5 }, { 5.5, 9 }, { 7.5, 13 }, .8, 'rgba(255,240,200,.6)')
end
I['u.soothsayer'] = function(g) person(g, { tunic = '#5b3f8a', robe = true, hair = '#45306a' }); g.dc(25, 19, 5, 'rgba(180,140,255,.3)'); g.c(25, 19, 3.2, '#9b6bdc'); g.hl(24, 18, 1.1) end
I['u.chieftain'] = function(g)
  for k, a in ipairs({ -1.1, -.55, 0, .55, 1.1 }) do g.e(16 + sin(a) * 6.5, 6.5 - cos(a) * 6.5, 1.4, 4.2, (k % 2 == 0) and '#c0392b' or '#efe8d8', a) end
  g.l({ { 25.5, 9 }, { 24.5, 30 } }, 1.6, '#8a5a2b'); person(g, { tunic = '#9a3b2a', belt = GOLD }); g.dc(25.5, 8.5, 1.4, GOLD)
end
I['u.scout'] = function(g) person(g, { tunic = '#5a6b3a', armR = false }); g.l({ { 20.8, 15.5 }, { 23, 10.5 } }, 2.6, SKIN); g.l({ { 18.5, 9 }, { 28, 6 } }, 2.4, '#c9962c'); g.e(28.6, 5.8, 1.3, 1.9, '#a87a24', -.3) end
I['u.tailor'] = function(g) person(g, { tunic = '#8a5a7a' }); g.l({ { 22, 24 }, { 28.5, 13.5 } }, 1, '#cfd6dd'); g.dq({ 28.5, 13.5 }, { 31.5, 20 }, { 26, 27.5 }, .8, '#d04a4a'); g.r(4, 20, 6, 6, '#a6784a', 1) end
I['u.potter'] = function(g) person(g, { tunic = '#9a6a40' }); g.e(25, 24.5, 4.4, 4.8, CLAY); g.r(23, 18.5, 4, 2.6, '#b9673a', .6); g.hl(23.5, 23, 1) end
I['u.weaver'] = function(g)
  person(g, { tunic = '#7a8a5a' }); g.dq({ 21, 25 }, { 14, 30 }, { 6, 27 }, .8, '#d8b44a'); g.c(25, 22, 4.2, '#c9a24a')
  g.dq({ 22, 20 }, { 25, 23 }, { 28, 20 }, .7, 'rgba(110,70,10,.7)'); g.dq({ 22, 24 }, { 25, 21 }, { 28, 24 }, .7, 'rgba(110,70,10,.7)')
end
I['u.farmer'] = function(g) person(g, { tunic = '#7c8a45' }); g.e(16, 6.6, 8.5, 2, '#d9b45a'); g.e(16, 4.6, 4.2, 2.8, '#d9b45a'); g.l({ { 23, 23.5 }, { 25, 19 } }, 1.8, WOOD); g.q({ 25, 19 }, { 31.5, 13 }, { 26, 7.5 }, 1.5, '#b5bcc4') end
I['u.herder'] = function(g)
  person(g, { tunic = '#9a8a5a' }); g.l({ { 25, 30 }, { 25, 9 } }, 1.6, WOOD); g.q({ 25, 9 }, { 25, 3.5 }, { 29, 5.8 }, 1.6, WOOD)
  g.b({ { 6, 27, 2.6 }, { 9, 26, 2.9 }, { 11.5, 27.2, 2.5 }, { 8.5, 28.6, 2.4 } }, '#f2eee4'); g.c(3.8, 26.3, 1.7, '#3a332c')
end
I['u.baker'] = function(g) person(g, { tunic = '#e2dac8' }); g.r(11.5, .8, 9, 5.5, '#f4f0e6', 2.4); g.e(25, 21.5, 4.8, 2.7, '#c98a3c', -.3); g.dl({ { 23.5, 21 }, { 24.5, 23 } }, .7, 'rgba(110,60,15,.75)'); g.dl({ { 26, 20 }, { 27, 22 } }, .7, 'rgba(110,60,15,.75)') end
I['u.mason'] = function(g) person(g, { tunic = '#8a6a5a' }); g.r(21.2, 18.8, 7.5, 4.4, '#a8432c', .8); g.hl(23, 20, .8); g.p({ { 4, 21 }, { 8.5, 19.5 }, { 9, 23 } }, '#9aa0a8') end
I['u.miner'] = function(g) person(g, { tunic = '#6a5a4a', hair = '#8a6a3a' }); g.dc(16, 4.5, 1.4, '#ffe27a'); g.l({ { 21, 26 }, { 26, 9 } }, 1.8, WOOD); g.q({ 20, 9.5 }, { 26, 4.5 }, { 31, 9.5 }, 2, IRON) end
I['u.smith'] = function(g) person(g, { tunic = '#5a4a3a', belt = '#3a2a1a' }); g.dl({ { 23, 22 }, { 26.5, 18.5 } }, 1, '#55606a'); g.dl({ { 24, 23 }, { 27.5, 19.5 } }, 1, '#55606a'); g.dc(28, 18, 3.6, 'rgba(255,150,60,.35)'); g.r(25.5, 16.5, 5.5, 3, '#f08a2a', .8) end
I['u.toolsmith'] = function(g) g.p({ { 1.5, 24 }, { 11, 24 }, { 10, 26 }, { 8, 26 }, { 8.5, 29.5 }, { 4, 29.5 }, { 4.5, 26 }, { 2.5, 26 } }, '#5d646c'); person(g, { tunic = '#4a5a6a' }); g.l({ { 22, 25 }, { 26, 12.5 } }, 1.8, WOOD); g.r(22.8, 8.2, 7.4, 4.6, '#8e98a2', 1) end
I['u.guard'] = function(g) person(g, { tunic = '#6b5a3a', belt = '#3a2a1a' }); spear(g, 24, 30, 25.5, 6.5); g.p({ { 2.5, 15 }, { 12.5, 15 }, { 12, 22 }, { 7.5, 27.5 }, { 3, 22 } }, '#8a3a2a'); g.dc(7.5, 19.5, 1.6, GOLD); g.dl({ { 7.5, 16 }, { 7.5, 26 } }, .8, 'rgba(255,220,150,.4)') end
I['u.scholar'] = function(g) person(g, { tunic = '#3f5a8a', robe = true }); g.r(3.5, 19, 6.5, 7.5, PARCH, 1); g.e(26, 15, 1.5, 5.5, '#f0ece2', .5); g.dl({ { 23.5, 20 }, { 28.4, 10 } }, .6, 'rgba(90,90,90,.7)') end
I['u.priest'] = function(g) person(g, { tunic = '#e3dccb', robe = true, hair = '#e3dccb' }); g.dl({ { 13.5, 15 }, { 12, 30 } }, 1.4, GOLD); g.dl({ { 18.5, 15 }, { 20, 30 } }, 1.4, GOLD); g.r(23.5, 15.5, 3, 6, '#efe4c8', .6); flame(g, 25, 12.5, .6) end
I['u.merchant'] = function(g) person(g, { tunic = '#7a3a6a', belt = GOLD, hair = '#c9962c' }); g.p({ { 21, 19.5 }, { 27, 19.5 }, { 29.5, 26.5 }, { 25, 28.5 }, { 19.5, 26.5 } }, '#b38a4a'); g.dl({ { 21.5, 21 }, { 26.5, 21 } }, 1, '#6b4423'); g.c(9, 27, 2.3, GOLD); g.hl(8.3, 26.3, .8) end
-- buildings
I['b.leanto'] = function(g)
  g.p({ { 4, 27.5 }, { 16, 7 }, { 28, 27.5 } }, '#6d8a3a'); g.p({ { 11, 27.5 }, { 16, 17 }, { 21, 27.5 } }, '#241a0e'); g.l({ { 3.5, 28 }, { 17.5, 5.5 } }, 1.6, WOOD); g.l({ { 28.5, 28 }, { 14.5, 5.5 } }, 1.6, WOODL)
  for _, d in ipairs({ { 9, 20 }, { 12, 15 }, { 22, 20 }, { 20, 14 } }) do g.dc(d[1], d[2], 1.2, 'rgba(160,200,90,.55)') end
end
I['b.mudhut'] = function(g)
  local pts = {}
  for k = 0, 16 do local a = pi + pi * k / 16; pts[#pts + 1] = { 16 + cos(a) * 12.5, 27.5 + sin(a) * 15 } end
  g.p(pts, '#9a6b3e'); g.r(12.8, 18.5, 6.4, 9, '#2a1d10', 3.2)
  for _, d in ipairs({ { 8, 20 }, { 22, 22 }, { 11, 15 }, { 20, 15 }, { 16, 11 } }) do g.dc(d[1], d[2], .9, 'rgba(60,35,15,.5)') end
  g.hl(10, 16, 1.4)
end
I['b.hut'] = function(g) hutArt(g) end
I['b.house'] = function(g) g.r(20.5, 5.5, 3.5, 7, '#8a8078', .4); g.r(6, 15, 20, 12.5, '#d9c9a3', 0); g.p({ { 3, 16.5 }, { 16, 5 }, { 29, 16.5 } }, '#a8432c'); g.r(14, 19, 4.6, 8.5, '#6b4423', .5); g.r(20, 18.5, 4, 4, '#3f6a8a', .4); g.r(8, 18.5, 4, 4, '#3f6a8a', .4) end
I['b.stockpile'] = function(g)
  g.r(4, 17, 11, 10.5, '#a87a44', 1); g.dl({ { 4.5, 17.5 }, { 14.5, 27 } }, .8, 'rgba(60,30,10,.6)'); g.dl({ { 14.5, 17.5 }, { 4.5, 27 } }, .8, 'rgba(60,30,10,.6)')
  g.r(15, 19.5, 9, 8, '#9b6a35', 1); g.b({ { 25.5, 23.5, 4.2 }, { 25.5, 19, 2.8 } }, '#c9b48a'); g.r(6.5, 9, 9, 8, '#b8894f', 1); g.dl({ { 7, 13 }, { 15, 13 } }, .8, 'rgba(60,30,10,.6)')
end
I['b.grave'] = function(g) g.e(16, 26.5, 12.5, 3.8, '#5e4a2c'); g.p({ { 10, 26 }, { 10, 12 }, { 13, 8 }, { 19, 8 }, { 22, 12 }, { 22, 26 } }, '#9a968e'); g.dl({ { 16, 12 }, { 16, 21 } }, 1.2, 'rgba(40,40,40,.6)'); g.dl({ { 13, 15 }, { 19, 15 } }, 1.2, 'rgba(40,40,40,.6)'); g.hl(12.5, 11.5, 1.2) end
I['b.shrine'] = function(g) g.r(5.5, 12, 5, 16, STONE, 1); g.r(21.5, 12, 5, 16, STONE, 1); g.r(3.5, 7.5, 25, 5, '#a19c94', 1); g.e(16, 25.5, 4, 1.8, '#5a4a3a'); flame(g, 16, 21, .9); g.hl(7, 14, 1) end
I['b.circle'] = function(g)
  local function st(k) return 16 + cos(k * pi / 4) * 12, 21 + sin(k * pi / 4) * 5.5 end
  for _, k in ipairs({ 5, 6, 7, 4, 0 }) do local x, y = st(k); g.e(x, y, 2.6, 2, '#9a968e') end
  g.l({ { 11, 22 }, { 21, 19.5 } }, 2.2, '#6b4423'); g.l({ { 11, 19.5 }, { 21, 22 } }, 2.2, WOOD); flame(g, 16, 15.5, 1.1)
  for _, k in ipairs({ 1, 2, 3 }) do local x, y = st(k); g.e(x, y, 2.6, 2, '#a7a39a') end
end
I['b.herbgarden'] = function(g)
  g.p({ { 3.5, 21 }, { 28.5, 21 }, { 26.5, 28.5 }, { 5.5, 28.5 } }, '#7a4e25'); g.e(16, 21, 12.5, 3, '#4a3420')
  for k, x in ipairs({ 9, 16, 23 }) do
    g.dl({ { x, 21 }, { x, 14 } }, .9, '#3f6a22'); leaf(g, x - 2.2, 16.5, -2.6, .95, k == 2 and '#6fb04a' or '#5fa03c'); leaf(g, x + 2.2, 15, -.5, .95, '#4f8f34'); leaf(g, x, 11.5, -1.57, .9, '#6fb04a')
  end
end
I['b.granary'] = function(g)
  for _, x in ipairs({ 10, 16, 22 }) do g.l({ { x, 22 }, { x, 29 } }, 1.6, WOOD) end
  g.r(6.5, 13, 19, 10, '#c9a06a', 2.5); g.p({ { 3.5, 14.5 }, { 16, 3 }, { 28.5, 14.5 } }, '#b38a3a')
  for k = 0, 4 do g.dl({ { 16, 4.5 }, { 6 + k * 5, 14 } }, .6, 'rgba(90,60,10,.55)') end
  g.r(14, 16, 4, 5, '#5a3a1a', .6)
end
I['b.well'] = function(g)
  g.l({ { 7.5, 22 }, { 7.5, 8 } }, 1.6, WOOD); g.l({ { 24.5, 22 }, { 24.5, 8 } }, 1.6, WOOD); g.p({ { 4.5, 9.5 }, { 16, 3 }, { 27.5, 9.5 } }, '#8a5a2b'); g.dl({ { 7.5, 10.5 }, { 24.5, 10.5 } }, 1.2, '#5a3a1a')
  g.dl({ { 16, 10.5 }, { 16, 14 } }, .7, '#d9c9a3'); g.r(14, 13.5, 4, 3.6, WOODL, .6); g.r(5, 18, 22, 9.5, STONE, 3); g.e(16, 18.6, 9, 1.6, '#2f5a7a')
  g.dl({ { 5.5, 22.5 }, { 26.5, 22.5 } }, .7, 'rgba(0,0,0,.3)'); g.dl({ { 11, 18.5 }, { 11, 27 } }, .7, 'rgba(0,0,0,.3)'); g.dl({ { 21, 18.5 }, { 21, 27 } }, .7, 'rgba(0,0,0,.3)')
end
I['b.warehouse'] = function(g)
  g.r(3, 12.5, 26, 15, '#a8532c', 0); g.p({ { 1.5, 13.5 }, { 8, 6 }, { 24, 6 }, { 30.5, 13.5 } }, '#6b4a33'); g.r(10.5, 17, 11, 10.5, '#4a3020', .5)
  g.dl({ { 16, 17.5 }, { 16, 27 } }, .8, 'rgba(0,0,0,.5)'); g.dl({ { 11, 22 }, { 21, 22 } }, .8, 'rgba(0,0,0,.4)'); g.dl({ { 3.5, 17 }, { 10, 17 } }, .6, 'rgba(0,0,0,.3)'); g.dl({ { 22, 21 }, { 28.5, 21 } }, .6, 'rgba(0,0,0,.3)')
end
I['b.palisade'] = function(g)
  for k, x in ipairs({ 4, 9, 14, 19, 24, 28.5 }) do
    local o = (k % 2 == 0) and 2 or 0
    g.p({ { x - 2.3, 28.5 }, { x - 2.3, 11 + o }, { x, 6.5 + o }, { x + 2.3, 11 + o }, { x + 2.3, 28.5 } }, (k % 2 == 0) and WOODL or WOOD)
  end
  g.dl({ { 2, 16 }, { 30.5, 16 } }, 1, '#3a2614'); g.dl({ { 2, 24 }, { 30.5, 24 } }, 1, '#3a2614')
end
I['b.library'] = function(g)
  g.r(4, 13, 24, 14.5, '#cfc6b0', 0); g.p({ { 2, 14 }, { 16, 4.5 }, { 30, 14 } }, '#8a7a66'); g.r(13, 18, 6, 9.5, '#4a3020', 3)
  for _, x in ipairs({ 7, 10, 22, 25 }) do g.dl({ { x, 15 }, { x, 27 } }, 1, 'rgba(90,80,60,.55)') end
  g.r(13.2, 8.6, 5.6, 3.6, '#3f5a8a', .5); g.dl({ { 16, 8.8 }, { 16, 12 } }, .6, '#d9c9a3')
end
I['b.temple'] = function(g)
  g.r(2.5, 25, 27, 3.5, '#bdb39c', .5)
  for _, x in ipairs({ 5, 10.5, 16, 21.5 }) do g.r(x + .5, 13, 3.6, 12, '#e3dccb', .4) end
  g.r(2.5, 10, 27, 3.5, '#d6ccb4', .4); g.p({ { 2, 10.5 }, { 16, 3 }, { 30, 10.5 } }, '#e3dccb'); g.dc(16, 7.5, 1.2, GOLD)
end
I['b.market'] = function(g)
  g.r(4, 19, 24, 8.5, '#9b6a35', 1); g.l({ { 5, 19 }, { 5, 11 } }, 1.4, WOOD); g.l({ { 27, 19 }, { 27, 11 } }, 1.4, WOOD); g.p({ { 2, 13 }, { 6, 6 }, { 26, 6 }, { 30, 13 } }, '#c0392b')
  for _, s in ipairs({ { 8.5, 6, 12, 13 }, { 16.5, 6, 20, 13 } }) do g.dp({ { s[1], s[2] }, { s[1] + 4, s[2] }, { s[3] + 4, s[4] }, { s[3], s[4] } }, 'rgba(255,245,225,.85)') end
  g.c(9, 17.5, 2, '#6a3fa8'); g.c(14, 17.5, 2, '#e08a2a'); g.c(19, 17.5, 2, '#c0392b'); g.c(24, 17.5, 2, '#7d9a3a')
end
I['b.monument'] = function(g)
  g.r(7, 25, 18, 4.5, '#9a968e', 1); g.p({ { 11.5, 25 }, { 13.5, 7.5 }, { 16, 3.5 }, { 18.5, 7.5 }, { 20.5, 25 } }, '#bdb6a6')
  g.dl({ { 16, 10 }, { 16, 13 } }, .9, 'rgba(60,50,40,.6)'); g.dc(16, 16, 1.1, 'rgba(60,50,40,.6)'); g.dl({ { 14.5, 19 }, { 17.5, 19 } }, .9, 'rgba(60,50,40,.6)'); g.hl(14, 12, 1)
end
I['b.aqueduct'] = function(g)
  for _, x in ipairs({ 3.5, 13.5, 23.5 }) do g.r(x, 12, 5, 16.5, '#b9ae96', 0) end
  g.r(1.5, 7, 29, 5.5, '#c9bea6', 0); g.dl({ { 2, 8.4 }, { 30, 8.4 } }, 1.3, '#3f86d6')
  g.dq({ 8.5, 28.5 }, { 11, 15 }, { 13.5, 28.5 }, .8, 'rgba(0,0,0,.45)'); g.dq({ 18.5, 28.5 }, { 21, 15 }, { 23.5, 28.5 }, .8, 'rgba(0,0,0,.45)')
end
-- wonders
I['b.hearth'] = function(g)
  g.dc(16, 15, 12, 'rgba(255,150,50,.18)')
  g.e(16, 25.5, 13.5, 4.8, '#6e665c')
  for _, p in ipairs({ { 4.5, 24 }, { 9, 21.5 }, { 16, 20.8 }, { 23, 21.5 }, { 27.5, 24 } }) do g.e(p[1], p[2], 2.8, 2.2, '#9a968e') end
  g.l({ { 9, 26.5 }, { 23, 23 } }, 2.6, '#6b4423'); g.l({ { 9, 23 }, { 23, 26.5 } }, 2.6, WOOD)
  flame(g, 16, 14.5, 2.2, '#e8671f', '#ffd34d')
  for _, p in ipairs({ { 5, 29 }, { 11, 28.6 }, { 21, 28.6 }, { 27, 29 } }) do g.e(p[1], p[2], 2.9, 2.2, '#a7a39a') end
  g.dc(7, 7, .9, '#ffd34d'); g.dc(25, 5, .8, '#ffb04d'); g.dc(22, 9, .6, '#ffd34d')
end
I['b.totem'] = function(g)
  g.e(16, 29, 8.5, 2.2, '#5e4a2c')
  g.p({ { 12, 6.5 }, { 3, 3.5 }, { 5.5, 10.5 }, { 12, 11.5 } }, '#c0392b'); g.p({ { 20, 6.5 }, { 29, 3.5 }, { 26.5, 10.5 }, { 20, 11.5 } }, '#2f8a8a')
  g.r(11.5, 4, 9, 25.5, '#9a6a35', 1.5)
  for k, y in ipairs({ 8, 15.5, 23 }) do
    g.dc(14, y, 1.2, '#1d140c'); g.dc(18, y, 1.2, '#1d140c')
    g.dq({ 13.5, y + 3 }, { 16, y + (k == 2 and 1.6 or 4.6) }, { 18.5, y + 3 }, 1, '#1d140c')
    g.dl({ { 11.8, y + 5.2 }, { 20.2, y + 5.2 } }, .8, 'rgba(40,20,5,.6)')
  end
  g.dp({ { 13, 4.2 }, { 16, 1.2 }, { 19, 4.2 } }, '#e2b23c'); g.hl(13.5, 6.5, 1.1)
end
I['b.stones'] = function(g)
  g.c(16, 9, 6.5, '#ffd34d'); g.hl(13.5, 6.8, 1.6)
  g.e(16, 27, 14.5, 3.6, '#5d7a3a')
  for _, p in ipairs({ { 7, 14, 3, 9 }, { 12, 12.5, 2.8, 9.5 }, { 20, 12.5, 2.8, 9.5 }, { 25, 14, 3, 9 } }) do g.r(p[1] - p[3] / 2, p[2], p[3], p[4], '#a7a39a', .6) end
  g.r(3, 15.5, 5, 13, '#8e8a84', .8); g.r(24, 15.5, 5, 13, '#8e8a84', .8)
  g.r(10.5, 17, 4.6, 11.5, '#9a968e', .8); g.r(17, 17, 4.6, 11.5, '#9a968e', .8); g.r(9.5, 14.5, 12.5, 3.2, '#b3aea4', .6)
  g.hl(5, 18, 1); g.hl(12, 19, .9)
end
I['b.gardens'] = function(g)
  g.p({ { 3, 29 }, { 29, 29 }, { 27, 22 }, { 5, 22 } }, '#a8532c'); g.p({ { 6, 22 }, { 26, 22 }, { 24.5, 15.5 }, { 7.5, 15.5 } }, '#b9633a'); g.p({ { 9, 15.5 }, { 23, 15.5 }, { 21.5, 9.5 }, { 10.5, 9.5 } }, '#c9734a')
  for _, row in ipairs({ { 22, 5, 27, 5 }, { 15.5, 8, 24, 4 }, { 9.5, 11, 21, 3 } }) do
    for k = 0, row[4] - 1 do local x = row[2] + k * (row[3] - row[2]) / max(1, row[4] - 1); g.b({ { x, row[1] - 1.5, 2.6 }, { x + 1.6, row[1] - 2.6, 1.8 } }, k % 2 == 0 and '#5fa03c' or '#4f8f34') end
  end
  g.dl({ { 25, 10 }, { 25.5, 16 }, { 27, 22 }, { 28, 28 } }, 1.4, '#5aa6e8'); g.b({ { 16, 6.5, 3.4 }, { 13.5, 7.5, 2.2 }, { 18.5, 7.5, 2.2 } }, '#6fb04a')
  g.l({ { 16, 9.5 }, { 16, 7 } }, 1, '#6b4423')
end
I['b.archive'] = function(g)
  g.r(2.5, 25.5, 27, 3.2, '#bdb39c', .5)
  for _, x in ipairs({ 4, 9, 19.5, 24.5 }) do g.r(x, 14, 3.4, 11.5, '#e3dccb', .4) end
  g.r(2.5, 11, 27, 3.4, '#d6ccb4', .4)
  local pts = {}
  for k = 0, 16 do local a = pi + pi * k / 16; pts[#pts + 1] = { 16 + cos(a) * 8, 11 + sin(a) * 7.5 } end
  g.p(pts, '#c9a24a'); g.dl({ { 16, 3.5 }, { 16, 11 } }, .7, 'rgba(110,70,10,.55)'); g.dc(16, 2.6, 1.1, GOLD)
  g.r(12.5, 15, 7, 10.5, '#4a3020', 3.4); g.r(13.8, 17.5, 4.4, 4, PARCH, .6); g.dl({ { 14.5, 19 }, { 17.5, 19 } }, .5, 'rgba(80,60,30,.7)')
  g.hl(11, 7, 1.2)
end
I['b.wall'] = function(g)
  g.p({ { 1.5, 27.5 }, { 1.5, 17 }, { 11, 15 }, { 11, 26 } }, '#9a968e'); g.p({ { 21, 26 }, { 21, 15 }, { 30.5, 17 }, { 30.5, 27.5 } }, '#8e8a84')
  for _, x in ipairs({ 2, 5.5, 8.5 }) do g.r(x, 14.5 + (x - 2) * -.2, 2.4, 3, '#9a968e', .3) end
  for _, x in ipairs({ 22, 25.5, 28.5 }) do g.r(x, 13.5 + (x - 22) * .3, 2.4, 3, '#8e8a84', .3) end
  g.r(10, 9, 12, 19, '#b3aea4', .5)
  for _, x in ipairs({ 10, 13.2, 16.4, 19.6 }) do g.r(x, 6, 2.4, 3.4, '#b3aea4', .3) end
  g.r(13, 18, 6, 10, '#3a2614', 3); g.dl({ { 10.5, 14 }, { 21.5, 14 } }, .7, 'rgba(0,0,0,.3)'); g.dl({ { 2, 21.5 }, { 10.5, 20.5 } }, .7, 'rgba(0,0,0,.3)'); g.dl({ { 21.5, 20.5 }, { 30, 22 } }, .7, 'rgba(0,0,0,.3)')
  g.hl(12, 11, 1)
end
I['b.colossus'] = function(g)
  g.r(8, 26, 16, 4.5, '#8e8a84', 1); g.r(10, 23.5, 12, 3, '#a7a39a', .8)
  local P = person(g, { s = .78, y = -6.5, tunic = '#b87333', skin = '#c88a4a', hair = '#8a5a2b', legs = '#9a5f2a', armR = false })
  g.l({ { 19.2, 11.2 }, { 22.5, 3.5 } }, 2.1, '#c88a4a'); flame(g, 22.8, 2.6, .55)
  g.dc(9, 6, .7, '#ffd34d'); g.hl(13, 11, 1)
end
I['u.builder'] = function(g)
  g.p({ { 1.5, 27.5 }, { 11.5, 23.5 }, { 12.5, 26 }, { 2.5, 30 } }, WOODL); g.dl({ { 3, 28 }, { 11.5, 24.8 } }, .6, 'rgba(60,30,10,.6)')
  person(g, { tunic = '#a07a40', belt = '#5a3a1a' })
  g.l({ { 22.5, 24 }, { 26, 11.5 } }, 1.8, WOOD); g.p({ { 22.6, 9.8 }, { 29.4, 8 }, { 30.4, 11.6 }, { 23.6, 13.4 } }, IRON)
end
-- legacy
I['x.ember'] = function(g)
  g.dc(16, 18, 13, 'rgba(255,120,30,.2)')
  g.b({ { 16, 19, 8.5 }, { 10, 21.5, 5.5 }, { 22, 21.5, 5.5 } }, '#5a2412')
  g.dl({ { 10, 20 }, { 14, 18 }, { 17, 21 }, { 21, 17.5 } }, 1.3, '#ff9a3a'); g.dl({ { 13, 24 }, { 16, 22.5 }, { 20, 24.5 } }, 1, '#ffb04d')
  flame(g, 16, 10.5, .95); g.dc(9, 9, .8, '#ffd34d'); g.dc(23, 7, .7, '#ffb04d')
end
I['x.medal'] = function(g)
  g.p({ { 9, 20 }, { 14, 20 }, { 11, 30 }, { 8.5, 27.5 }, { 5.5, 29 } }, '#c0392b'); g.p({ { 18, 20 }, { 23, 20 }, { 26.5, 29 }, { 23.5, 27.5 }, { 21, 30 } }, '#3f6fb5')
  g.c(16, 14, 10, '#d9a83a'); g.c(16, 14, 7, '#e9c45a'); star(g, 16, 14, 5.2, '#fff1a8'); g.hl(12, 9.5, 1.4)
end
I['x.lock'] = function(g)
  g.q({ 10.5, 15 }, { 10, 3 }, { 16, 3.5 }, 2.6, '#9aa3ad'); g.q({ 16, 3.5 }, { 22, 3 }, { 21.5, 15 }, 2.6, '#9aa3ad')
  g.r(7.5, 14, 17, 14, '#c9a24a', 2); g.dc(16, 19.5, 2, '#3a2410'); g.dl({ { 16, 20 }, { 16, 24.5 } }, 1.6, '#3a2410'); g.hl(11, 17, 1.2)
end
-- rites
I['ri.hunt'] = function(g) g.q({ 5, 27 }, { 20, 28 }, { 26, 12 }, 3.4, '#f0e8d4'); spear(g, 5, 9, 25, 24); spear(g, 27, 9, 7, 24) end
I['ri.bonfire'] = function(g) g.l({ { 5, 28 }, { 27, 23 } }, 3, '#6b4423'); g.l({ { 5, 23 }, { 27, 28 } }, 3, WOOD); flame(g, 16, 14, 2.1); g.dc(7, 9, 1, '#ffd34d'); g.dc(26, 7, .9, '#ffd34d'); g.dc(24, 13, .7, '#ffb04d') end
I['ri.rain'] = function(g) cloud(g, 16, 11, 1.25, '#9db3c9'); for _, d in ipairs({ { 9, 22 }, { 16, 24 }, { 23, 22 } }) do drop(g, d[1], d[2], .38, '#3f86d6') end end
I['ri.vision'] = function(g)
  local pts = {}
  for k = 0, 12 do local t = k / 12; pts[#pts + 1] = { 3 + 26 * t, 16 - sin(pi * t) * 9 } end
  for k = 11, 1, -1 do local t = k / 12; pts[#pts + 1] = { 3 + 26 * t, 16 + sin(pi * t) * 9 } end
  g.p(pts, '#efe9dc'); g.c(16, 16, 5.8, '#4f8ed0'); g.dc(16, 16, 2.6, '#10131a'); g.hl(14, 14, 1.4)
  for _, r in ipairs({ { 16, 2.5, 16, 5 }, { 6, 5, 8, 7.5 }, { 26, 5, 24, 7.5 } }) do g.dl({ { r[1], r[2] }, { r[3], r[4] } }, 1.2, '#ffe27a') end
end
I['ri.festival'] = function(g)
  g.l({ { 22, 9 }, { 29, 3 } }, 1.4, WOODL); g.l({ { 10, 9 }, { 3, 3 } }, 1.4, WOODL); g.r(8, 12, 16, 14, '#b5803f', 2); g.e(16, 12, 8, 2.8, '#e8dcc0')
  g.dl({ { 8.5, 15 }, { 12, 25 }, { 16, 15 }, { 20, 25 }, { 23.5, 15 } }, .8, '#7a3a2a'); g.e(16, 26, 8, 2.4, '#8a5a2b')
end
I['ri.worksong'] = function(g) g.e(10, 24, 3.4, 2.5, GOLD, -.4); g.e(22, 21, 3.4, 2.5, GOLD, -.4); g.l({ { 13, 23 }, { 13, 8 } }, 1.4, GOLD); g.l({ { 25, 20 }, { 25, 5 } }, 1.4, GOLD); g.p({ { 13, 7.5 }, { 25, 4.5 }, { 25, 8.5 }, { 13, 11.5 } }, GOLD) end
I['ri.expedition'] = function(g)
  g.r(3.5, 6, 25, 20, PARCH, 1.5); g.dp({ { 6, 20 }, { 9, 14 }, { 12, 20 } }, '#8e8a84'); g.dp({ { 10, 20 }, { 13, 15 }, { 16, 20 } }, '#a19c94')
  g.dl({ { 8, 23 }, { 13, 22 }, { 17, 17 }, { 21, 15 }, { 24, 11 } }, 1, 'rgba(180,40,30,.9)'); g.dl({ { 22.5, 9.5 }, { 25.5, 12.5 } }, 1.4, '#b02a1e'); g.dl({ { 25.5, 9.5 }, { 22.5, 12.5 } }, 1.4, '#b02a1e')
end
I['ri.healrite'] = function(g) g.q({ 14, 30 }, { 13, 18 }, { 16, 8 }, 1.4, '#4d7a2a'); for _, l in ipairs({ { 10, 22, -2.4 }, { 18, 20, -.8 }, { 10, 14, -2.5 }, { 18, 12.5, -.7 } }) do leaf(g, l[1], l[2], l[3], 1.2, '#5fa03c') end; star(g, 23.5, 8, 5.5, '#fff1a8'); star(g, 25.5, 21, 3.2, '#fff1a8') end
I['ri.blessing'] = function(g) g.de(16, 13, 8, 2.2, 'rgba(255,220,120,.35)'); person(g, { s = .7, tunic = '#e3dccb' }); star(g, 6, 8, 3.6); star(g, 26, 11, 3); star(g, 24, 3.5, 2.2) end
I['ri.council'] = function(g) person(g, { x = -8, s = .62, tunic = '#7a6a55', hair = '#d8d2c6' }); person(g, { x = 8, s = .62, tunic = '#5f7491' }); person(g, { s = .72, tunic = '#9a3b2a', hair = '#d8d2c6' }) end
I['ri.harvest'] = function(g)
  local pts = {}
  for k = 0, 16 do local a = -2.2 + 4.4 * k / 16; pts[#pts + 1] = { 21 + cos(a) * 8, 10 + sin(a) * 8 } end
  for k = 16, 0, -1 do local a = -1.9 + 3.8 * k / 16; pts[#pts + 1] = { 24.5 + cos(a) * 6.5, 8.5 + sin(a) * 6.5 } end
  g.p(pts, '#f2e6b0'); grainStalk(g, 9, 14, -.3); grainStalk(g, 15, 17, .15)
end
I['ri.arms'] = function(g) spear(g, 4, 29, 25, 5); spear(g, 28, 29, 7, 5); g.p({ { 9, 13 }, { 23, 13 }, { 22, 21 }, { 16, 27.5 }, { 10, 21 } }, '#8a3a2a'); g.dc(16, 18.5, 2, GOLD) end
I['ri.pilgrimage'] = function(g)
  g.p({ { 1.5, 28 }, { 13, 7 }, { 18.5, 15 }, { 22.5, 11 }, { 30.5, 28 } }, '#8e8a84'); g.dp({ { 10.5, 11.5 }, { 13, 7 }, { 15.6, 11.3 }, { 13.8, 12.6 }, { 12.3, 11.2 } }, '#efe9dc')
  g.dl({ { 8, 28 }, { 13, 25 }, { 11, 22 }, { 16, 19 }, { 14, 16 } }, 1.2, '#e3c98a'); g.dc(25, 5.5, 2.6, '#ffd34d')
end
I['ri.caravan'] = function(g)
  g.l({ { 24, 17.5 }, { 30.5, 21 } }, 1.6, WOOD); g.r(4.5, 13, 20, 8.5, '#9b6a35', 1); g.b({ { 10, 10.5, 3.6 }, { 16.5, 10, 3.9 }, { 21, 11, 3 } }, '#c9b48a')
  for _, x in ipairs({ 10, 20 }) do g.c(x, 23.5, 4.2, '#6b4423'); g.dl({ { x - 3.5, 23.5 }, { x + 3.5, 23.5 } }, .7, '#3a2614'); g.dl({ { x, 20 }, { x, 27 } }, .7, '#3a2614'); g.dc(x, 23.5, 1, '#3a2614') end
end
I['ri.migrants'] = function(g) g.p({ { 2.5, 27.5 }, { 16, 5.5 }, { 29.5, 27.5 } }, '#c9a24a'); g.p({ { 12, 27.5 }, { 16, 15 }, { 20, 27.5 } }, '#3a2614'); g.dl({ { 9, 16.5 }, { 23, 16.5 } }, 1, 'rgba(140,60,30,.8)'); g.dl({ { 6, 22 }, { 26, 22 } }, 1, 'rgba(140,60,30,.8)'); g.l({ { 16, 6 }, { 16, 2 } }, 1.2, WOOD) end
I['ri.symposium'] = function(g) I['b.temple'](g); g.r(10, 17, 12, 7, PARCH, 1); g.dl({ { 12, 19.5 }, { 20, 19.5 } }, .6, 'rgba(80,60,30,.6)'); g.dl({ { 12, 21.5 }, { 18, 21.5 } }, .6, 'rgba(80,60,30,.6)') end
-- seasons
I['x.spring'] = function(g)
  g.q({ 16, 29 }, { 15, 20 }, { 16, 12 }, 1.6, '#4d7a2a'); leaf(g, 11, 19, -2.6, 1.3, '#6fb04a'); leaf(g, 21, 16, -.6, 1.3, '#5fa03c')
  for k = 0, 4 do local a = k / 5 * pi * 2; g.c(16 + cos(a) * 3.2, 9 + sin(a) * 3.2, 2.3, '#f29ac2') end
  g.c(16, 9, 1.9, '#ffd34d')
end
I['x.summer'] = function(g)
  for k = 0, 7 do local a = k / 8 * pi * 2; g.l({ { 16 + cos(a) * 9.5, 16 + sin(a) * 9.5 }, { 16 + cos(a) * 13.5, 16 + sin(a) * 13.5 } }, 1.8, '#f6c13a') end
  g.c(16, 16, 7.5, '#f6c13a'); g.hl(13.5, 13.5, 1.8)
end
I['x.autumn'] = function(g)
  g.l({ { 16, 29 }, { 16, 20 } }, 1.4, '#6b4423')
  g.p({ { 16, 3 }, { 19, 9 }, { 25, 7 }, { 23, 13 }, { 29, 15 }, { 23, 19 }, { 24, 23 }, { 16, 20.5 }, { 8, 23 }, { 9, 19 }, { 3, 15 }, { 9, 13 }, { 7, 7 }, { 13, 9 } }, '#d9752a')
  g.dl({ { 16, 6 }, { 16, 20 } }, .8, 'rgba(90,40,10,.6)'); g.dl({ { 16, 14 }, { 24, 10 } }, .7, 'rgba(90,40,10,.5)'); g.dl({ { 16, 14 }, { 8, 10 } }, .7, 'rgba(90,40,10,.5)')
end
I['x.winter'] = function(g)
  for k = 0, 2 do local a = k * pi / 3; local dx, dy = cos(a) * 12, sin(a) * 12; g.l({ { 16 - dx, 16 - dy }, { 16 + dx, 16 + dy } }, 1.8, '#cfe6ff') end
  for k = 0, 5 do
    local a = k * pi / 3; local x0, y0 = 16 + cos(a) * 8, 16 + sin(a) * 8
    g.dl({ { x0, y0 }, { x0 + cos(a + .7) * 3.2, y0 + sin(a + .7) * 3.2 } }, 1.2, '#eaf4ff'); g.dl({ { x0, y0 }, { x0 + cos(a - .7) * 3.2, y0 + sin(a - .7) * 3.2 } }, 1.2, '#eaf4ff')
  end
  g.c(16, 16, 2.2, '#eaf4ff')
end
-- odds and ends
I['x.food'] = function(g) g.b({ { 11, 14, 3.6 }, { 16, 12, 4.2 }, { 21, 14, 3.6 } }, '#b8322a'); g.c(12.5, 12, 1.8, '#6a3fa8'); g.p({ { 4, 15 }, { 28, 15 }, { 24, 25.5 }, { 8, 25.5 } }, '#8a5a2b'); g.e(16, 15, 12, 2.2, '#a8743c') end
I['x.scroll'] = function(g) g.r(7, 8.5, 18, 15.5, PARCH, 1); g.e(7, 16.3, 2.6, 8.2, '#cdb880'); g.e(25, 16.3, 2.6, 8.2, '#cdb880'); for _, y in ipairs({ 12, 15, 18, 21 }) do g.dl({ { 10.5, y }, { 21.5, y } }, .7, 'rgba(80,60,30,.55)') end end
I['x.warn'] = function(g) g.p({ { 16, 4 }, { 29, 27 }, { 3, 27 } }, '#e0862a'); g.dl({ { 16, 11 }, { 16, 19.5 } }, 2.6, '#2a1606'); g.dc(16, 23.5, 1.6, '#2a1606'); g.hl(13, 12, 1.2) end
I['x.good'] = function(g) star(g, 16, 16, 12, '#ffe27a'); star(g, 26, 6, 3.6, '#fff1a8'); g.hl(13, 12, 1.4) end
I['x.bad'] = function(g)
  g.c(16, 13.5, 9.5, '#e9e2cf'); g.r(10.5, 18.5, 11, 8, '#e9e2cf', 2); g.dc(12.4, 14, 2.6, '#1d140c'); g.dc(19.6, 14, 2.6, '#1d140c'); g.dp({ { 16, 17 }, { 14.6, 20 }, { 17.4, 20 } }, '#1d140c')
  for _, x in ipairs({ 13, 16, 19 }) do g.dl({ { x, 22.5 }, { x, 26 } }, .8, 'rgba(60,50,40,.7)') end
end
for k = 0, 4 do I['mood' .. k] = function(g) face(g, k) end end
I['e.mood'] = I.mood2
Art.ICONS = I

---------------------------------------------------------------- loading and drawing
Art.img = {}
function Art.load()
  bodyCanvas = lg.newCanvas(Art.RES, Art.RES, { msaa = 8, dpiscale = 1 })
  for id, fn in pairs(I) do
    local ok, cv = pcall(Art.paint, fn)
    if ok then Art.img[id] = cv else print('icon failed: ' .. id .. ' ' .. tostring(cv)) end
  end
  bodyCanvas:release(); bodyCanvas = nil
end
-- Draws an icon with its top-left at x, y and the given size.
function Art.draw(id, x, y, size, alpha)
  local im = Art.img[id] or Art.img['x.scroll']
  if not im then return end
  local r, g, b, a = lg.getColor()
  local mode, amode = lg.getBlendMode()
  lg.setBlendMode('alpha', 'premultiplied')
  local al = alpha or 1
  lg.setColor(al, al, al, al)
  lg.draw(im, x, y, 0, size / Art.RES, size / Art.RES)
  lg.setBlendMode(mode, amode)
  lg.setColor(r, g, b, a)
end

return Art
