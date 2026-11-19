-- Hearthfire Chronicle: the board. Layout, the seven tabs, the map, the chronicle and the overlays.
local Sim = require('sim')
local Art = require('art')
local UI = require('ui')
local Story = require('story')
local Legacy = require('legacy')
local Settings = require('settings')
local Flavor = require('flavor')
local Screens = {}
local lg = love.graphics
local floor, max, min, abs = math.floor, math.max, math.min, math.abs
local C, F = UI.C, nil
local fmt, fmtD = Sim.fmt, Sim.fmtD

Screens.tab = 'production'
Screens.modeIdx = 1
Screens.infoKey = nil
Screens.help = false
Screens.saveNoteT = -10
Screens.wipeArm = -10
Screens.settingsMsg, Screens.settingsMsgT = '', -10
Screens.onSave = function() end      -- set by main.lua
Screens.onExport = function() end
Screens.onImport = function() end
Screens.onOpenFolder = function() end
Screens.onNewGame = function() end
Screens.onRetire = function() end
Screens.onTitle = function() end
Screens.onLegacy = function() end
Screens.toasts = {}
Screens.reveal = {}

local TABS = { { 'production', 'Production' }, { 'territory', 'Territory' }, { 'policies', 'Policies' }, { 'traits', 'Traits' }, { 'research', 'Research' }, { 'rites', 'Rites' },
  { 'history', 'History' }, { 'settings', 'Settings' } }
Screens.TABS = TABS
local MODES = { { 'add', 1 }, { 'add', 5 }, { 'add', 10 }, { 'add', 100 }, { 'add', math.huge }, { 'rem', 1 }, { 'rem', 5 }, { 'rem', 10 }, { 'rem', 100 }, { 'rem', math.huge } }
local function modeLabel(i)
  local m = MODES[i]
  if m[1] == 'add' then return m[2] == math.huge and 'Add as many as possible' or ('Add ' .. m[2]) end
  return m[2] == math.huge and 'Remove all' or ('Remove ' .. m[2])
end
-- the action a right-click performs: the opposite of the chosen one, with the same amount
local function oppositeMode(i)
  local m = MODES[i]
  for k, o in ipairs(MODES) do if o[1] ~= m[1] and o[2] == m[2] then return k end end
  return i
end
local function S() return Sim.S end
local function rname(r) return r == 'food' and 'food' or Sim.R[r].n:lower() end
local function ricon(r) return r == 'food' and 'x.food' or r end

---------------------------------------------------------------- small text helpers
local function moodWord(h) return h > 50 and 'Joyful' or h > 20 and 'Happy' or h > -10 and 'Content' or h > -35 and 'Unhappy' or h > -60 and 'Miserable' or 'Despairing' end
local function moodFace(h) return h > 50 and 4 or h > 20 and 3 or h > -10 and 2 or h > -35 and 1 or 0 end
local function fmtK(v) if v >= 1000 then return string.format(v >= 10000 and '%.0fK' or '%.1fK', v / 1000) end return tostring(v) end
local function fmtDays(x)
  if x >= 200 then return string.format('%.1f years', x / 100) end
  local d = max(1, math.ceil(x)); return d .. (d == 1 and ' day' or ' days')
end
local function forecast(id)
  local s = S()
  local d, v, c = s.rate[id] or 0, s.res[id], Sim.cap(id)
  if c ~= math.huge and v >= c * .99 and (Sim.FLOW[id] or {})['Lost: storage full'] then return 'Storage is full and the extra is lost. Build more storage.', true end
  if d < -.01 and v > .5 then return 'At this rate it runs out in about ' .. fmtDays(v / -d) .. '.', true end
  if d > .01 and c ~= math.huge and v < c * .99 then return 'Storage fills in about ' .. fmtDays((c - v) / d) .. '.' end
  return nil
end
local function flowRows(id, maxN)
  local o = Sim.FLOW[id]
  if not o then return nil end
  local pos, neg = {}, {}
  for k, v in pairs(o) do if abs(v) >= .005 then if v > 0 then pos[#pos + 1] = { k, v } else neg[#neg + 1] = { k, v } end end end
  table.sort(pos, function(a, b) return a[2] > b[2] end)
  table.sort(neg, function(a, b) return a[2] < b[2] end)
  local rows = {}
  for k = 1, min(maxN, #pos) do rows[#rows + 1] = { pos[k][1], fmtD(pos[k][2]), C.good } end
  for k = 1, min(maxN, #neg) do rows[#rows + 1] = { neg[k][1], fmtD(neg[k][2]), C.bad } end
  return #rows > 0 and rows or nil
end
local function costItems(cost)
  local items = {}
  local keys = {}
  for k in pairs(cost) do keys[#keys + 1] = k end
  local order = { insight = 1, culture = 2, faith = 3, influence = 4 }
  table.sort(keys, function(a, b) return (order[a] or 9) .. a < (order[b] or 9) .. b end)
  for _, r in ipairs(keys) do
    local v = cost[r]
    local have = r == 'food' and Sim.foodTotal() or S().res[r]
    items[#items + 1] = { icon = ricon(r) }
    items[#items + 1] = { text = fmt(v) .. ' ' .. rname(r) .. '    ', col = have < v and C.bad or C.text, font = UI.F.smallB }
  end
  return items
end
local function unitSummaryItems(u)
  local it = {}
  if u.prod then
    for _, p in ipairs(u.prod) do it[#it + 1] = { text = '+' .. p[2] .. ' ' }; it[#it + 1] = { icon = p[1] }; it[#it + 1] = { text = '  ' } end
  elseif u.rin then
    local first = true
    for _, r in ipairs(Sim.orderedKeys(u.rin)) do
      if not first then it[#it + 1] = { text = ' + ' } end
      it[#it + 1] = { text = u.rin[r] .. ' ' }; it[#it + 1] = { icon = r }; first = false
    end
    it[#it + 1] = { text = '  \u{2192}  ' }
    for _, r in ipairs(Sim.orderedKeys(u.rout)) do it[#it + 1] = { text = u.rout[r] .. ' ' }; it[#it + 1] = { icon = r } end
  elseif u.explore then it[#it + 1] = { text = 'explores about one tile every ' .. floor(1 / u.explore + .5) .. ' days' }
  elseif u.special == 'fire' then
    it = { { text = '1.5 ' }, { icon = 'sticks' }, { text = '  \u{2192}  0.38 ' }, { icon = 'fire' }, { text = ', and cooks 4 ' }, { icon = 'meat' }, { icon = 'fish' } }
  elseif u.special == 'heal' then it = { { text = 'cures 0.3 sick, using ' }, { icon = 'herbs' } }
  elseif u.special == 'guard' then it = { { text = '+1 defense' } }
  elseif u.special == 'build' then it = { { text = 'one day of construction work on the first planned building' } } end
  return it
end
local function unlocksOf(id)
  local out = {}
  for _, u in ipairs(Sim.UNITS) do if u.tech == id then out[#out + 1] = { 'u.' .. u.id, u.n } end end
  for _, b in ipairs(Sim.BLDS) do if b.tech == id then out[#out + 1] = { 'b.' .. b.id, b.n } end end
  for _, r in ipairs(Sim.RITES) do if r.tech == id then out[#out + 1] = { 'ri.' .. r.id, r.n .. ' rite' } end end
  for _, p in ipairs(Sim.POLICIES) do if p.tech == id then out[#out + 1] = { Sim.POLICY_ICON[p.id], p.n .. ' policy' } end end
  return out
end
local function tipLine()
  local s, p = S(), S().pop
  if s.waterShort > .02 then return 'Your people are thirsty. Add gatherers, explore land with rivers or lakes, or allow muddy water in Policies. They will not thank you for it.' end
  if s.foodShort > .02 then return 'Your people are hungry. Add gatherers, hunters or fishers, or set meager rations in Policies and brace for complaints.' end
  if s.explored < 15 and Sim.n('wanderer') == 0 and Sim.n('scout') == 0 then return 'Send someone exploring: a Wanderer finds new land, and more land means more food and water for your gatherers. The wanderer will be fine. Probably.' end
  if #s.techs == 0 then return 'Dreamers produce insight; yes, staring at clouds counts as work. Spend it in the Research tab. Wanderers find new land, which lets gatherers bring in more.' end
  if #s.queue > 0 and (s._buildRate or 0) < .01 then return 'Nothing is being built. Put people to work as Builders (under Construction), or leave a few idle to lend a hand.' end
  if Sim.homeless() > 0 and Sim.known('shelter') and #s.queue == 0 then return Sim.homeless() .. ' people have no shelter. Plan lean-tos or huts below and put a Builder to work, especially before winter. Winter does not knock.' end
  if Sim.homeless() > 0 then return 'Research Shelter so your people can sleep under a roof instead of under the weather.' end
  if s.res.corpses >= 1 and not Sim.known('digging') then return 'The dead lie unburied, spreading grief and sickness. Research Digging to build graves.' end
  if s.res.corpses >= 1 then return 'The dead lie unburied. Build more graves; they deserve better, and the smell is not improving.' end
  if p.sick > p.adults * .1 and not Sim.known('healing') then return 'Many are sick. Research Healing, avoid muddy water and raw meat, and bury the dead.' end
  if Sim.idle() > 0 then return Sim.idle() .. ' adults have no job. Click a job below to put them to work before they start making up dances.' end
  if Sim.season() == 3 then return 'Winter is coming. Stock up on sticks for firekeepers, make clothing, and build shelter. The cold does not accept excuses.' end
  return 'Try the Rites tab: powers the whole tribe can call on, usually with some chanting involved.'
end

---------------------------------------------------------------- the stores column
local EINFO = {
  people = { n = 'Population', v = function() return tostring(Sim.popTotal()) end, d = function() local p = S().pop; return p.adults .. ' adults, ' .. p.children .. ' children and ' .. p.elders .. ' elders. ' .. S().born .. ' born and ' .. S().deaths .. ' dead so far.' end },
  workers = { n = 'Workers', v = function() return fmtK(Sim.assigned()) .. '/' .. fmtK(Sim.assignCap()) end, d = function() return Sim.assigned() .. ' people have jobs and ' .. Sim.idle() .. ' are idle. Sick people cannot work, so jobs go slower when many are ill.' end },
  mood = { n = 'Mood', v = function() return floor(S().happy + .5) .. '%' end },
  health = { n = 'Health', v = function() local p = S().pop; return floor(100 * (1 - p.sick / max(1, p.adults)) + .5) .. '%' end, d = function() return S().pop.sick .. ' adults are sick. Muddy water, raw meat, unburied dead, crowding and cold all spread sickness. Healers and herbs cure it.' end },
  land = { n = 'Explored land', v = function() return tostring(S().explored) end, d = function() return S().explored .. ' of ' .. Sim.N .. ' tiles explored. More land means more wild resources for gatherers. See the Territory tab.' end },
  adults = { n = 'Adults', v = function() return tostring(S().pop.adults) end, d = function() return 'The ones who can work. Adults slowly become elders.' end },
  children = { n = 'Children', v = function() return tostring(S().pop.children) end, d = function() return 'They eat half as much and grow up in about 140 days.' end },
  elders = { n = 'Elders', v = function() return tostring(S().pop.elders) end, d = function() return 'Too old to work unless the Elder workforce policy is on. They die of old age over time.' end },
  sick = { n = 'Sick', v = function() return tostring(S().pop.sick) end, d = function() return 'Sick adults cannot work and some die. Healers use herbs to cure them.' end },
  housing = { n = 'Housing', v = function() return tostring(Sim.housing()) end, d = function() return 'Places to sleep. Build lean-tos, huts and houses in the Production tab.' end },
  homeless = { n = 'Without shelter', v = function() return tostring(Sim.homeless()) end, d = function() return 'People without shelter are unhappy, get sick more often and suffer in winter.' end },
}
local LEFT = {
  { 'Essentials', { 'e:people', 'e:workers', 'e:mood', 'e:health', 'e:land', 'r:insight', 'r:culture', 'r:faith', 'r:influence' } },
  { 'Demographics', { 'e:adults', 'e:children', 'e:elders', 'e:sick', 'e:housing', 'e:homeless' } },
  { 'Food & Water', { 'r:fruit', 'r:meat', 'r:fish', 'r:cooked', 'r:grain', 'r:bread', 'r:water', 'r:muddy' } },
  { 'Crafting & Construction', { 'r:sticks', 'r:wood', 'r:stone', 'r:clay', 'r:herbs', 'r:fiber', 'r:bones', 'r:hides', 'r:ore' } },
  { 'Goods', { 'r:tools', 'r:clothing', 'r:pottery', 'r:bricks', 'r:metal', 'r:fire', 'r:corpses' } },
}
local NOTES = { fire = 'Fire pits keep about 10 people warm in winter and let firekeepers cook. They burn out over time.', corpses = 'The unburied dead spread sickness and grief. Build graves.',
  tools = 'Many jobs need one tool per worker. Tools wear out.', clothing = 'Each piece keeps one person warm in winter.', muddy = 'Drinking it spreads sickness.', pottery = 'Each pot adds a little food and water storage.' }

local function moodDoc()
  local s = S()
  local f = Sim.moodFactors()
  local tg = 0; for _, e in ipairs(f) do tg = tg + e[2] end
  tg = floor(Sim.clamp(tg, -100, 100) + .5)
  local trend = abs(tg - s.happy) > 3 and (' Mood changes slowly; right now it is ' .. (tg > s.happy and 'rising' or 'falling') .. ' toward ' .. tg .. '%.') or ''
  local rows = {}
  for _, e in ipairs(f) do rows[#rows + 1] = { e[1], (e[2] > 0 and '+' or '') .. e[2], e[2] > 0 and C.good or C.bad } end
  return { { t = 'title', icon = 'mood' .. moodFace(s.happy), text = 'Mood: ' .. floor(s.happy + .5) .. '%' }, { t = 'p', text = moodWord(s.happy) .. '. Happy people have more children and work harder.' .. trend }, { t = 'rows', rows = rows } }
end
local function storeDoc(key)
  local kind, id = key:match('^(%a):(.+)$')
  if kind == 'e' then
    if id == 'mood' then return moodDoc() end
    local e = EINFO[id]
    return { { t = 'title', icon = 'e.' .. id, text = e.n .. ': ' .. e.v() }, { t = 'p', text = e.d() }, Flavor.p(Flavor.ESS[id]) }
  end
  local s, r = S(), Sim.R[id]
  local c, d = Sim.cap(id), s.rate[id] or 0
  local doc = { { t = 'title', icon = id, text = r.n } }
  doc[#doc + 1] = { t = 'flow', items = { { text = fmt(s.res[id]) .. (c ~= math.huge and (' / ' .. fmt(c) .. ' stored') or '') .. '  \u{00b7}  ' }, { text = fmtD(d) .. ' per day', col = d > .005 and C.good or d < -.005 and C.bad or C.muted, font = UI.F.smallB } } }
  local fc, warn = forecast(id)
  if fc then doc[#doc + 1] = { t = 'p', text = fc, col = warn and C.warn or C.muted } end
  local rows = flowRows(id, 6)
  if rows then doc[#doc + 1] = { t = 'h', text = 'Where it comes from and goes' }; doc[#doc + 1] = { t = 'rows', rows = rows } end
  local note = NOTES[id] or (r.c == 'food' and ('Food. ' .. (r.raw and 'Eating it raw can cause sickness. ' or '') .. 'Spoils over time; granaries slow that down.'))
  if note then doc[#doc + 1] = { t = 'p', text = note, col = C.muted } end
  if r.q then doc[#doc + 1] = Flavor.p(r.q) end
  return doc
end

local function drawStores(x, y, w, h)
  UI.panel(x, y, w, h)
  local sc = UI.scrollState('left')
  sc.x, sc.yTop, sc.w, sc.h = x, y, w, h
  UI.pushClip(x + 3, y + 3, w - 6, h - 6)
  local s = S()
  local cy = y + 10 - sc.y
  local ts, gap = 44, 4
  for _, grp in ipairs(LEFT) do
    local visible = {}
    for _, key in ipairs(grp[2]) do
      local kind, id = key:match('^(%a):(.+)$')
      local show
      if kind == 'e' then show = (id ~= 'homeless' or Sim.homeless() > 0) and (id ~= 'sick' or s.pop.sick > 0 or s.deaths > 0)
      else show = s.seen[id] or s.res[id] > .05 or Sim.R[id].c == 'ess' end
      if show then visible[#visible + 1] = key end
    end
    if #visible > 0 then
      local title = grp[1]
      local tw = UI.F.d16:getWidth(title)
      UI.shadowText(title, x + (w - tw) / 2, cy, UI.F.d16, C.text)
      cy = cy + UI.F.d16:getHeight() + 1
      UI.rect(x + 20, cy, w - 40, 1, C.frameHi, .25)
      cy = cy + 6
      local perRow = max(1, floor((w - 16 + gap) / (ts + gap)))
      local rows = math.ceil(#visible / perRow)
      for rI = 1, rows do
        local count = min(perRow, #visible - (rI - 1) * perRow)
        local rx = x + (w - (count * ts + (count - 1) * gap)) / 2
        for k = 1, count do
          local key = visible[(rI - 1) * perRow + k]
          local kind, id = key:match('^(%a):(.+)$')
          local tx, ty = rx + (k - 1) * (ts + gap), cy
          local hot = UI.hit('left:' .. key, tx, ty, ts, ts, { tip = function() return storeDoc(key) end })
          UI.tile(tx, ty, ts, hot)
          local icon = kind == 'r' and id or (id == 'mood' and ('mood' .. moodFace(s.happy)) or ('e.' .. id))
          Art.draw(icon, tx + 7, ty + 1, 30)
          local val = kind == 'r' and fmt(s.res[id]) or EINFO[id].v()
          local font = #val > 5 and UI.F.micro or UI.F.tinyB
          local vw = font:getWidth(val)
          UI.shadowText(val, tx + (ts - vw) / 2, ty + ts - font:getHeight() - 1, font, C.text)
          if kind == 'r' then
            local dlt, c = s.rate[id] or 0, Sim.cap(id)
            if dlt > .005 then UI.text('\u{25b2}', tx + ts - 10, ty + 1, UI.F.micro, C.good) elseif dlt < -.005 then UI.text('\u{25bc}', tx + ts - 10, ty + 1, UI.F.micro, C.bad) end
            if c ~= math.huge and s.res[id] >= c * .99 then UI.border(tx + 1, ty + 1, ts - 2, ts - 2, C.warn, 1, 1, 2)
            elseif (Sim.R[id].c == 'food' or id == 'water') and dlt < -.005 and s.res[id] < abs(dlt) * 10 then UI.border(tx + 1, ty + 1, ts - 2, ts - 2, C.bad, 1, 1, 2) end
          end
        end
        cy = cy + ts + gap
      end
      cy = cy + 6
    end
  end
  sc.max = max(0, cy + sc.y - y - h + 8)
  UI.popClip()
  UI.scrollbar(sc)
end

---------------------------------------------------------------- production
local UGROUPS = {
  { 'Gathering', { 'gatherer', 'hunter', 'fisher', 'digger', 'woodcutter', 'miner', 'farmer', 'herder' } },
  { 'Discovery', { 'dreamer', 'scholar' } }, { 'Exploration', { 'wanderer', 'scout' } }, { 'Construction', { 'builder' } },
  { 'Crafting', { 'knapper', 'firekeeper', 'tailor', 'weaver', 'potter', 'baker', 'mason', 'smith', 'toolsmith' } },
  { 'Culture & faith', { 'storyteller', 'soothsayer', 'priest', 'healer' } }, { 'Leadership', { 'chieftain', 'merchant', 'guard' } },
}
local BGROUPS = {
  { 'Housing', { 'leanto', 'mudhut', 'hut', 'house' } }, { 'Storage', { 'stockpile', 'granary', 'warehouse' } },
  { 'Settlement', { 'grave', 'well', 'herbgarden', 'palisade', 'aqueduct' } }, { 'Sacred & civic', { 'shrine', 'circle', 'library', 'temple', 'market', 'monument' } },
  { 'Wonders', { 'hearth', 'totem', 'stones', 'gardens', 'archive', 'wall', 'colossus' }, true },
}
local function bldSummary(b)
  if b.house then return 'All shelter together: ' .. Sim.housing() .. ' beds for ' .. Sim.popTotal() .. ' people' .. (Sim.homeless() > 0 and ('; ' .. Sim.homeless() .. ' sleep outside') or '') .. '.' end
  if b.id == 'stockpile' or b.id == 'warehouse' or b.id == 'granary' then return 'Storage now: ' .. fmt(Sim.cap('fruit')) .. ' of each food, ' .. fmt(Sim.cap('wood')) .. ' of each material.' end
  if b.id == 'well' or b.id == 'aqueduct' then return 'Water from wells and aqueducts: +' .. fmt(5 * Sim.bld('well') + 25 * Sim.bld('aqueduct')) .. ' a day.' end
  if b.id == 'palisade' then return 'Defense now: ' .. fmt(Sim.defense()) .. '.' end
  return nil
end
local function infoDoc(key)
  local s = S()
  local m = MODES[Screens.modeIdx]
  if not key then
    local doc = { { t = 'title', icon = 'fire', text = 'The ' .. s.name .. ' tribe' }, { t = 'p', text = modeLabel(Screens.modeIdx) .. '  \u{00b7}  ' .. Sim.idle() .. ' idle workers', col = C.blueHi },
      { t = 'p', text = tipLine(), font = UI.F.body } }
    local act = Screens.activeEffects()
    if #act > 0 then doc[#doc + 1] = { t = 'chips', label = 'In effect', items = act }
    else doc[#doc + 1] = { t = 'p', text = 'Hover over any icon to learn about it. Use the arrows above to choose what a click does; a right-click does the opposite.', col = C.muted } end
    return doc
  end
  local kind, id = key:match('^(%a):(.+)$')
  if kind == 'u' then
    local u = Sim.UM[id]
    local c = Sim.n(id)
    local mx = u.max and u.max() or nil
    local doc = { { t = 'title', icon = 'u.' .. id, text = u.n },
      { t = 'p', text = 'Click to ' .. modeLabel(Screens.modeIdx):lower() .. ', right-click to ' .. modeLabel(oppositeMode(Screens.modeIdx)):lower() .. '  \u{00b7}  ' .. c .. ' working' .. (mx and ('  \u{00b7}  room for ' .. mx) or '') .. '  \u{00b7}  ' .. Sim.idle() .. ' idle', col = C.blueHi },
      { t = 'p', text = u.d, font = UI.F.body }, Flavor.p(u.q) }
    local items = { { text = 'Each worker, per day:  ', col = C.muted } }
    for _, it in ipairs(unitSummaryItems(u)) do items[#items + 1] = it end
    if u.tools then items[#items + 1] = { text = ' \u{00b7}  needs a tool', col = C.muted } end
    doc[#doc + 1] = { t = 'flow', items = items }
    if c > 0 then
      local label, now = u.n .. 's', { { text = 'All ' .. c .. ' together, right now:  ', col = C.muted } }
      local any = false
      for _, r in ipairs(Sim.RKEYS) do
        local v = (Sim.FLOW[r] or {})[label]
        if v and abs(v) >= .01 then any = true; now[#now + 1] = { text = fmtD(v) .. ' ', col = v > 0 and C.good or C.bad, font = UI.F.smallB }; now[#now + 1] = { icon = r }; now[#now + 1] = { text = '  ' } end
      end
      if any then doc[#doc + 1] = { t = 'flow', items = now } end
      local lu = s._landUse
      if lu and u.prod then
        for _, p in ipairs(u.prod) do
          local lk = p[3]
          if lk and lu.ratio[lk] and lu.ratio[lk] < .7 then
            doc[#doc + 1] = { t = 'p', text = 'The land is crowded: each worker brings in only ' .. floor(lu.ratio[lk] * 100 + .5) .. '% of the usual ' .. Sim.R[p[1]].n:lower() .. '. Explore more land.', col = C.warn }
            break
          end
        end
      end
      if u.tools then
        local need = 0; for _, x in ipairs(Sim.UNITS) do if x.tools then need = need + Sim.n(x.id) end end
        if s.res.tools < need then doc[#doc + 1] = { t = 'p', text = 'Not enough tools. Workers without one manage only 30%.', col = C.warn } end
      end
    end
    return doc
  end
  local b = Sim.BM[id]
  local q = Sim.queued(id)
  if b.wonder and not Sim.bldAvail(b) then
    return { { t = 'title', icon = 'b.' .. id, text = b.n .. ' (wonder)', col = C.muted }, { t = 'p', text = 'Unlocked by the discovery of ' .. Sim.TM[b.tech].n .. '.', col = C.warn },
      { t = 'p', text = b.d, font = UI.F.body }, Flavor.p(b.q), { t = 'flow', items = costItems(b.cost) }, { t = 'p', text = 'Takes ' .. b.work .. ' days of building work.', col = C.muted } }
  end
  local status
  if b.wonder then
    status = Sim.bld(id) > 0 and 'Standing. Wonders are built once and last forever.' or (q > 0 and 'Being built now.' or 'Click to begin building it. Only one can ever be built.')
  else
    local function phrase(add)
      local amount = m[2] == math.huge and (add and 'as many as you can afford' or 'all of them') or tostring(m[2])
      return (add and 'plan ' or 'cancel or tear down ') .. amount
    end
    status = 'Click to ' .. phrase(m[1] == 'add') .. ', right-click to ' .. phrase(m[1] ~= 'add') .. '  \u{00b7}  ' .. Sim.bld(id) .. ' built' .. (q > 0 and ('  \u{00b7}  ' .. q .. ' planned') or '')
  end
  local doc = { { t = 'title', icon = 'b.' .. id, text = b.n .. (b.wonder and ' (wonder)' or ''), col = b.wonder and C.gold or nil }, { t = 'p', text = status, col = C.blueHi },
    { t = 'p', text = b.d .. (id == 'grave' and (' ' .. math.ceil(s.buried) .. ' of ' .. Sim.bld('grave') * 10 .. ' plots used.') or ''), font = UI.F.body }, Flavor.p(b.q),
    { t = 'flow', items = costItems(b.cost) } }
  if not (b.wonder and Sim.bld(id) > 0) then
    local rate = s._buildRate or 0
    local ahead = 0
    for _, qq in ipairs(s.queue) do ahead = ahead + Sim.BM[qq.id].work - qq.done end
    local line = 'Takes ' .. fmt(b.work) .. ' days of building work.'
    if rate > .01 then
      doc[#doc + 1] = { t = 'p', text = line .. ' At the current pace' .. (ahead > 0 and ', after what is already planned,' or '') .. ' one more would be done in about ' .. fmtDays((ahead + (q > 0 and 0 or b.work)) / rate) .. '.', col = C.muted }
    else doc[#doc + 1] = { t = 'p', text = line .. ' Nobody is building right now: assign Builders, or leave people idle to lend a hand.', col = C.warn } end
  end
  local sm = bldSummary(b)
  if sm then doc[#doc + 1] = { t = 'p', text = sm, col = C.muted } end
  return doc
end

-- invert is true for a right-click, which does the opposite of the chosen action with the same amount
local function actTile(kind, id, tx, ty, ts, invert)
  local m = MODES[Screens.modeIdx]
  local add, count = m[1] == 'add', m[2]
  if invert then add = not add end
  local msg, col
  if kind == 'u' then
    local before = Sim.n(id)
    Sim.assign(id, add and count or -count)
    local d = Sim.n(id) - before
    if d > 0 then msg, col = '+' .. d, C.good elseif d < 0 then msg, col = '\u{2212}' .. (-d), C.text
    else col = C.warn; msg = not add and 'None to remove' or (Sim.idle() > 0 and 'No room for more' or 'No idle workers') end
  else
    local b = Sim.BM[id]
    if add then
      local d = Sim.build(id, b.wonder and 1 or min(count, 1000))
      if d > 0 then msg, col = b.wonder and 'Work begins' or ('+' .. d .. ' planned'), C.good; Screens.sfx('place')
      else
        col = C.warn
        if not Sim.bldAvail(b) then msg = 'Needs ' .. Sim.TM[b.tech].n
        elseif b.wonder and Sim.bld(id) > 0 then msg = 'Already standing'
        elseif b.wonder and Sim.queued(id) > 0 then msg = 'Already being built'
        else msg = 'Not enough materials' end
      end
    else
      local k = 0
      for _ = 1, min(count, 1000) do
        local found
        for j = #Sim.S.queue, 1, -1 do if Sim.S.queue[j].id == id then found = j; break end end
        if found then Sim.cancel(found); k = k + 1
        elseif Sim.bld(id) > 0 and not b.wonder then Sim.demolish(id); k = k + 1
        else break end
      end
      if k > 0 then msg, col = '\u{2212}' .. k, C.text else msg, col = b.wonder and 'Wonders stand forever' or 'None to remove', C.warn end
    end
  end
  UI.floatText(msg, tx + ts / 2, ty, col)
  Screens.flash = { key = kind .. ':' .. id, t = love.timer.getTime() }
end

local function drawTileGroups(groups, kind, x, y, w)
  local ts, gap, ggap = 48, 4, 26
  local blocks = {}
  for _, g in ipairs(groups) do
    local ids = {}
    local anyW = false
    if g[3] then for _, id in ipairs(g[2]) do if Sim.bldAvail(Sim.BM[id]) then anyW = true end end end
    for _, id in ipairs(g[2]) do
      local ok = kind == 'u' and Sim.unitAvail(Sim.UM[id]) or (kind == 'b' and (Sim.bldAvail(Sim.BM[id]) or anyW))
      if ok then ids[#ids + 1] = id end
    end
    if #ids > 0 then
      local perRow = math.ceil(#ids / math.ceil(#ids / 6))
      local bw = max(perRow * (ts + gap) - gap, UI.F.small:getWidth(g[1]))
      local rows = math.ceil(#ids / perRow)
      blocks[#blocks + 1] = { title = g[1], ids = ids, w = bw, h = 20 + rows * (ts + gap), perRow = perRow }
    end
  end
  -- arrange blocks in centered rows
  local rowsList, cur, curW = {}, {}, 0
  for _, b in ipairs(blocks) do
    if #cur > 0 and curW + ggap + b.w > w then rowsList[#rowsList + 1] = cur; cur, curW = {}, 0 end
    cur[#cur + 1] = b; curW = curW + (#cur > 1 and ggap or 0) + b.w
  end
  if #cur > 0 then rowsList[#rowsList + 1] = cur end
  local need = 0
  for _, x2 in ipairs(Sim.UNITS) do if x2.tools then need = need + Sim.n(x2.id) end end
  local s = S()
  local m = MODES[Screens.modeIdx]
  local cy = y
  for _, row in ipairs(rowsList) do
    local rw, rh = 0, 0
    for k, b in ipairs(row) do rw = rw + b.w + (k > 1 and ggap or 0); rh = max(rh, b.h) end
    local bx = x + (w - rw) / 2
    for _, b in ipairs(row) do
      local tw = UI.F.small:getWidth(b.title)
      UI.shadowText(b.title, bx + (b.w - tw) / 2, cy, UI.F.small, C.text)
      for k, id in ipairs(b.ids) do
        local col, rI = (k - 1) % b.perRow, floor((k - 1) / b.perRow)
        local rowCount = min(b.perRow, #b.ids - rI * b.perRow)
        local rowStart = bx + (b.w - (rowCount * (ts + gap) - gap)) / 2
        local tx, ty = rowStart + col * (ts + gap), cy + 20 + rI * (ts + gap)
        local key = kind .. ':' .. id
        local hot = UI.hit('tile:' .. key, tx, ty, ts, ts, { info = key, click = function() actTile(kind, id, tx, ty, ts) end, rclick = function() actTile(kind, id, tx, ty, ts, true) end })
        local fl = Screens.flash and Screens.flash.key == key and love.timer.getTime() - Screens.flash.t < .25
        local pad = fl and 2 or 0
        local B = kind == 'b' and Sim.BM[id]
        UI.tile(tx + pad, ty + pad, ts - pad * 2, hot or fl, kind == 'b')
        if B and B.wonder then UI.border(tx + pad + 1, ty + pad + 1, ts - pad * 2 - 2, ts - pad * 2 - 2, C.gold, Sim.bld(id) > 0 and .9 or .45, 1, 2) end
        local count = kind == 'u' and Sim.n(id) or Sim.bld(id)
        local locked = B and not Sim.bldAvail(B)
        local cant = B and m[1] == 'add' and (locked or not Sim.payable(B.cost))
        Art.draw((kind == 'u' and 'u.' or 'b.') .. id, tx + 6, ty + 6, 36, locked and .25 or (cant and .45 or 1))
        if locked then Art.draw('x.lock', tx + ts - 19, ty + ts - 19, 16) end
        if B and B.wonder then
          if count > 0 then UI.shadowText('\u{2713}', tx + 4, ty + 1, UI.F.smallB, C.gold) end
        else UI.shadowText(fmtK(count), tx + 4, ty + 2, UI.F.tinyB, kind == 'b' and Art.color('#cfe0ff') or C.text) end
        if B then
          local q = Sim.queued(id)
          if q > 0 then
            local qs = '+' .. fmtK(q)
            UI.rect(tx + ts - UI.F.micro:getWidth(qs) - 7, ty + ts - 15, UI.F.micro:getWidth(qs) + 5, 13, Art.color('#1c3963'), .95, 3)
            UI.text(qs, tx + ts - UI.F.micro:getWidth(qs) - 4.5, ty + ts - 15, UI.F.micro, Art.color('#cfe0ff'))
          end
        end
        if kind == 'u' and Sim.UM[id].tools and count > 0 and s.res.tools < need then UI.shadowText('!', tx + ts - 9, ty + ts - 17, UI.F.bodyB, C.warn) end
      end
      bx = bx + b.w + ggap
    end
    cy = cy + rh + 10
  end
  return cy - y
end

-- The info box keeps one height whatever is hovered, so the tiles below never move under the mouse.
-- It is sized for the tallest text any visible job or building can show, grows if a longer one appears
-- (a warning, say), and only shrinks when the window size changes.
local infoH = { t = -1, key = '', h = 0 }
local function infoBoxHeight(iw, h)
  local key = floor(iw) .. '|' .. floor(h) .. '|' .. UI.scale
  if key ~= infoH.key then infoH.key, infoH.h = key, 0 end
  local now = love.timer.getTime()
  if now - infoH.t > .5 or infoH.h == 0 then
    infoH.t = now
    local need = UI.docHeight(infoDoc(nil), iw - 24)
    for _, u in ipairs(Sim.UNITS) do if Sim.unitAvail(u) then need = max(need, UI.docHeight(infoDoc('u:' .. u.id), iw - 24)) end end
    local anyW = false
    for _, b in ipairs(Sim.BLDS) do if b.wonder and Sim.bldAvail(b) then anyW = true end end
    for _, b in ipairs(Sim.BLDS) do if Sim.bldAvail(b) or (b.wonder and anyW) then need = max(need, UI.docHeight(infoDoc('b:' .. b.id), iw - 24)) end end
    local cap = max(200, min(260, floor((h - 42) * .45)))
    infoH.h = max(infoH.h, max(118, min(cap, need + 20)))
  end
  return infoH.h
end

local function drawProduction(x, y, w, h)
  -- picker
  local lw = 230
  local lx = x + (w - lw) / 2
  local function arrow(dx, dir)
    local ax = dir < 0 and lx - 30 or lx + lw + 6
    local hot = UI.hit('mode' .. dir, ax, y + 8, 24, 24, { click = function() Screens.modeIdx = (Screens.modeIdx - 1 + dir) % #MODES + 1 end })
    UI.blue(ax, y + 8, 24, 24, hot and 'hot' or nil)
    lg.setColor(1, 1, 1, 1)
    local cx, cy = ax + 12, y + 20
    if dir < 0 then lg.polygon('fill', cx + 4, cy - 6, cx - 5, cy, cx + 4, cy + 6) else lg.polygon('fill', cx - 4, cy - 6, cx + 5, cy, cx - 4, cy + 6) end
  end
  arrow(0, -1); arrow(0, 1)
  UI.plaque(lx, y + 8, lw, 24)
  local label = modeLabel(Screens.modeIdx)
  UI.shadowText(label, lx + (lw - UI.F.smallB:getWidth(label)) / 2, y + 10, UI.F.smallB, C.text)
  -- info box
  local iw = min(w - 20, 600)
  local ix = x + (w - iw) / 2
  local doc = infoDoc(Screens.infoKey)
  local ih = infoBoxHeight(iw, h)
  UI.hit('infobox', ix, y + 42, iw, ih, {})
  UI.plaque(ix, y + 42, iw, ih)
  UI.pushClip(ix + 2, y + 44, iw - 4, ih - 4)
  UI.doc(doc, ix + 12, y + 52, iw - 24)
  UI.popClip()
  -- tiles
  local top = y + 42 + ih + 8
  local sc = UI.scrollState('prod')
  sc.x, sc.yTop, sc.w, sc.h = x, top, w, y + h - top
  UI.pushClip(x, top, w, y + h - top)
  local cy = top + 4 - sc.y
  cy = cy + Screens.drawQueue(x + 10, cy, w - 20)
  cy = cy + drawTileGroups(UGROUPS, 'u', x + 10, cy, w - 20)
  local anyB = false
  for _, b in ipairs(Sim.BLDS) do if Sim.bldAvail(b) then anyB = true end end
  if anyB then
    local t = 'Buildings'
    UI.shadowText(t, x + (w - UI.F.d18:getWidth(t)) / 2, cy + 6, UI.F.d18, C.gold)
    cy = cy + 34
    cy = cy + drawTileGroups(BGROUPS, 'b', x + 10, cy, w - 20)
  end
  local lu, lb = 0, 0
  for _, u in ipairs(Sim.UNITS) do if not Sim.unitAvail(u) then lu = lu + 1 end end
  for _, b in ipairs(Sim.BLDS) do if not Sim.bldAvail(b) then lb = lb + 1 end end
  if lu + lb > 0 then
    local t = lu .. ' more jobs and ' .. lb .. ' more buildings will be unlocked through research.'
    UI.para(t, x + 10, cy + 4, w - 20, UI.F.small, C.muted, 'center')
    cy = cy + 30
  end
  sc.max = max(0, cy + sc.y - top - (y + h - top) + 10)
  UI.popClip()
  UI.scrollbar(sc)
end

-- The construction queue: what is being built, how far along it is, and a button to cancel each project.
-- Once any building can be built the strip is always there, one row high, so planning or finishing
-- a building never moves the tiles below it.
function Screens.drawQueue(x, y, w)
  local s = S()
  local any = false
  for _, b in ipairs(Sim.BLDS) do if Sim.bldAvail(b) then any = true; break end end
  if not any then return 0 end
  local ts, gap, LW, moreW = 40, 6, 166, 64
  local h = 8 + ts + 6 + 8
  UI.plaque(x, y, w, h)
  -- left: what this strip is and how fast building goes
  local rate = s._buildRate or 0
  UI.shadowText('Under construction', x + 12, y + 7, UI.F.smallB, C.gold)
  local n = #s.queue
  UI.text(n == 0 and 'Nothing planned' or (n .. (n == 1 and ' project' or ' projects')), x + 12, y + 26, UI.F.tiny, C.text)
  local sub = rate > .01 and (fmt(rate) .. ' days of work a day') or (n > 0 and 'Nobody is building' or nil)
  if sub then UI.text(sub, x + 12, y + 41, UI.F.tiny, rate > .01 and C.muted or C.warn) end
  -- right: the projects in order, the first one being worked on
  local x0 = x + LW
  local perRow = max(1, floor((w - LW - 12 - moreW + gap) / (ts + gap)))
  local shown = min(n, perRow)
  if n == 0 then
    local hint = 'Click a building below to plan it. Builders raise it; idle people lend a hand.'
    local hh = UI.wrapH(hint, UI.F.small, w - LW - 12)
    UI.para(hint, x0, y + (h - hh) / 2, w - LW - 12, UI.F.small, C.muted)
  end
  for k = 1, shown do
    local q = s.queue[k]
    local b = Sim.BM[q.id]
    local tx, ty = x0 + (k - 1) * (ts + gap), y + 8
    local hot = UI.hit('queue:' .. k, tx, ty, ts, ts + 6, { tip = function()
      local eta = Sim.queueEta(k)
      return { { t = 'title', icon = 'b.' .. q.id, text = b.n }, { t = 'p', text = fmt(q.done) .. ' of ' .. fmt(b.work) .. ' days of work done.' },
        { t = 'p', text = eta and ('Finished in about ' .. fmtDays(eta) .. '.') or 'Waiting for builders.', col = eta and C.muted or C.warn },
        { t = 'p', text = 'Click the cross, or right-click, to cancel and get every material back.', col = C.muted } }
    end, rclick = function() Sim.cancel(k); UI.floatText('Cancelled', tx + ts / 2, ty, C.text) end })
    UI.tile(tx, ty, ts, hot, true)
    if b.wonder then UI.border(tx + 1, ty + 1, ts - 2, ts - 2, C.gold, .8, 1, 2) end
    Art.draw('b.' .. q.id, tx + 4, ty + 3, 32, k == 1 and 1 or .7)
    UI.rect(tx, ty + ts + 2, ts, 4, C.black, .7, 2)
    UI.rect(tx, ty + ts + 2, ts * min(1, q.done / b.work), 4, k == 1 and C.good or C.blueHi, 1, 2)
    local cx, cy2 = tx + ts - 13, ty - 1
    local xh = UI.hit('cancel:' .. k, cx - 1, cy2 - 1, 16, 16, { click = function() Sim.cancel(k); UI.floatText('Cancelled', tx + ts / 2, ty, C.text) end, tip = function() return { { t = 'p', text = 'Cancel and return the materials' } } end })
    if hot or xh then
      UI.rect(cx, cy2, 14, 14, xh and C.bad or C.black, xh and 1 or .75, 7)
      lg.setColor(1, 1, 1, 1); lg.setLineWidth(1.6); lg.line(cx + 4, cy2 + 4, cx + 10, cy2 + 10); lg.line(cx + 10, cy2 + 4, cx + 4, cy2 + 10)
    end
  end
  if n > shown then UI.text('+' .. (n - shown) .. ' more', x0 + shown * (ts + gap) + 4, y + 8 + (ts - UI.F.small:getHeight()) / 2, UI.F.small, C.muted) end
  return h + 10
end
-- Everything in effect for a limited time (rites and story outcomes), as chips for the info box.
function Screens.activeEffects()
  local s = S()
  local out = {}
  for _, b in ipairs(s.buffs) do
    local r = Sim.RM[b.id]
    local left = b['end'] - s.day
    out[#out + 1] = { r and ('ri.' .. b.id) or (b.i or 'x.scroll'), (r and r.n or b.n or 'Effect') .. '  ' .. left .. (left == 1 and ' day' or ' days') }
  end
  return out
end

---------------------------------------------------------------- territory map
local mapCanvas, mapKey = nil, ''
local WATERY = { river = true, lake = true, ocean = true }
local function tileRng(seed, i) return love.math.newRandomGenerator(seed * 7 + i * 131) end
local function hgrad(x, y, w, h, left, right)
  local m = lg.newMesh({ { x, y, 0, 0, left[1], left[2], left[3], left[4] }, { x + w, y, 0, 0, right[1], right[2], right[3], right[4] },
    { x + w, y + h, 0, 0, right[1], right[2], right[3], right[4] }, { x, y + h, 0, 0, left[1], left[2], left[3], left[4] } }, 'fan', 'stream')
  lg.setColor(1, 1, 1, 1); lg.draw(m)
end
local function paintTile(i, x, y, ts, rng)
  local s = S()
  local t = s.map[i]
  local b = Sim.BIOME[t]
  local cx, cy, u = x + ts / 2, y + ts / 2, ts / 20
  local base = Art.color(t == 'river' and Sim.BIOME.grass.col or b.col)
  UI.setc(base); lg.rectangle('fill', x, y, ts + .6, ts + .6)
  local L, D = Art.tone(base, .1), Art.tone(base, -.18)
  local mesh = lg.newMesh({ { x, y, 0, 0, L[1], L[2], L[3], 1 }, { x + ts, y, 0, 0, base[1], base[2], base[3], 1 }, { x + ts, y + ts, 0, 0, D[1], D[2], D[3], 1 }, { x, y + ts, 0, 0, base[1], base[2], base[3], 1 } }, 'fan', 'stream')
  lg.setColor(1, 1, 1, 1); lg.draw(mesh)
  lg.setColor(0, 0, 0, .12)
  for _ = 1, 4 do lg.rectangle('fill', x + rng:random() * ts, y + rng:random() * ts, u * 1.2, u * 1.2) end
  lg.setLineJoin('bevel')
  local function line(pts, w, col) UI.setc(Art.color(col)); lg.setLineWidth(w); lg.line(pts) end
  local function tree(tx, ty, r, col)
    lg.setColor(.29, .19, .09, 1); lg.rectangle('fill', tx - u * .6, ty, u * 1.2, r * .9)
    lg.setColor(0, 0, 0, .35); lg.circle('fill', tx, ty, r, 16)
    UI.setc(Art.color(col)); lg.circle('fill', tx - r * .08, ty - r * .1, r * .88, 16)
    lg.setColor(1, 1, 1, .18); lg.circle('fill', tx - r * .35, ty - r * .35, r * .3, 10)
  end
  if t == 'forest' then
    for _, p in ipairs({ { .3, .42 }, { .68, .36 }, { .5, .7 } }) do tree(x + ts * (p[1] + (rng:random() - .5) * .1), y + ts * (p[2] + (rng:random() - .5) * .1), ts * .17, rng:random() < .5 and '#2f5e2c' or '#386b32') end
  elseif t == 'jungle' then
    for _, p in ipairs({ { .25, .3 }, { .7, .28 }, { .45, .55 }, { .78, .72 }, { .22, .74 } }) do tree(x + ts * p[1], y + ts * p[2], ts * .14, rng:random() < .5 and '#2a8a52' or '#1f7444') end
  elseif t == 'hills' then
    for _, h in ipairs({ { .3, .66, .26 }, { .66, .58, .3 } }) do
      local pts = {}
      for k = 0, 16 do local a = math.pi + math.pi * k / 16; pts[#pts + 1] = x + ts * h[1] + math.cos(a) * ts * h[3]; pts[#pts + 1] = y + ts * h[2] + math.sin(a) * ts * h[3] * .62 end
      lg.setColor(.49, .42, .28, 1); lg.polygon('fill', pts)
      lg.setColor(.16, .11, .05, .55); lg.setLineWidth(u * .8); lg.line(pts)
      lg.setColor(1, .94, .8, .18); lg.ellipse('fill', x + ts * h[1] - ts * h[3] * .25, y + ts * h[2] - ts * h[3] * .3, ts * h[3] * .3, ts * h[3] * .14)
    end
  elseif t == 'mountain' then
    for _, m in ipairs({ { .36, .8, .3, .62 }, { .66, .82, .26, .5 } }) do
      local px, py = x + ts * m[1], y + ts * m[2]
      local top = py - ts * m[4]
      lg.setColor(.55, .53, .49, 1); lg.polygon('fill', px - ts * m[3], py, px, top, px + ts * m[3], py)
      lg.setColor(.12, .09, .07, .7); lg.setLineWidth(u * .8); lg.polygon('line', px - ts * m[3], py, px, top, px + ts * m[3], py)
      lg.setColor(0, 0, 0, .22); lg.polygon('fill', px, top, px + ts * m[3], py, px, py)
      lg.setColor(.94, .93, .89, 1); lg.polygon('fill', px - ts * m[3] * .32, top + ts * m[4] * .3, px, top, px + ts * m[3] * .32, top + ts * m[4] * .3, px, top + ts * m[4] * .22)
    end
  elseif t == 'ocean' or t == 'lake' then
    for k = 0, (t == 'ocean' and 2 or 1) do
      local wx, wy = x + ts * (.2 + rng:random() * .5), y + ts * (.25 + k * .25 + rng:random() * .08)
      if t == 'ocean' then lg.setColor(.67, .82, .94, .45) else lg.setColor(.78, .9, .98, .55) end
      lg.setLineWidth(u * .9)
      lg.arc('line', 'open', wx, wy, ts * .09, math.pi * 1.1, math.pi * 1.9, 8)
      lg.arc('line', 'open', wx + ts * .16, wy, ts * .09, math.pi * 1.1, math.pi * 1.9, 8)
    end
  elseif t == 'coast' then
    lg.setColor(.47, .35, .2, .35)
    for _ = 1, 5 do lg.rectangle('fill', x + rng:random() * ts, y + rng:random() * ts, u, u) end
    local X, Y = Sim.xy(i)
    for _, d in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
      local nx, ny = X + d[1], Y + d[2]
      if nx >= 0 and ny >= 0 and nx < Sim.MW and ny < Sim.MH and s.map[Sim.idx(nx, ny)] == 'ocean' then
        local pts
        if d[1] ~= 0 then local lx = d[1] > 0 and x + ts - u or x + u; pts = { lx, y + u, lx, y + ts - u }
        else local ly = d[2] > 0 and y + ts - u or y + u; pts = { x + u, ly, x + ts - u, ly } end
        line(pts, u * 1.6, 'rgba(240,250,255,.6)')
      end
    end
  elseif t == 'desert' then
    for k = 0, 1 do
      local dy = y + ts * (.38 + k * .3)
      local p1 = Art.quadPts({ x + ts * .12, dy }, { x + ts * .4, dy - ts * .14 }, { x + ts * .62, dy }, 8)
      local p2 = Art.quadPts({ x + ts * .62, dy }, { x + ts * .78, dy + ts * .08 }, { x + ts * .9, dy - ts * .02 }, 6)
      for k2 = 3, #p2 do p1[#p1 + 1] = p2[k2] end
      line(p1, u * .9, 'rgba(140,100,40,.55)')
    end
  elseif t == 'swamp' then
    lg.setColor(.24, .35, .39, .65)
    for _, e in ipairs({ { .32, .4, .2 }, { .66, .66, .16 } }) do lg.ellipse('fill', x + ts * e[1], y + ts * e[2], ts * e[3], ts * e[3] * .45) end
    for _ = 1, 5 do local rx, ry = x + ts * (.12 + rng:random() * .76), y + ts * (.3 + rng:random() * .55); line({ rx, ry, rx + u * .4, ry - ts * .2 }, u * .7, '#8a9a4a') end
  elseif t == 'tundra' then
    lg.setColor(1, 1, 1, .55)
    for _ = 1, 6 do lg.circle('fill', x + rng:random() * ts, y + rng:random() * ts, u * .9, 8) end
  end
  if t == 'grass' or t == 'river' then
    for _ = 1, 4 do
      local gx, gy = x + ts * (.15 + rng:random() * .7), y + ts * (.2 + rng:random() * .65)
      line({ gx - u * .9, gy - u * 1.4, gx, gy, gx + u * .9, gy - u * 1.4 }, u * .6, 'rgba(40,70,20,.55)')
    end
  end
  if t == 'river' then
    local X, Y = Sim.xy(i)
    local ends = {}
    for _, d in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
      local nx, ny = X + d[1], Y + d[2]
      if nx >= 0 and ny >= 0 and nx < Sim.MW and ny < Sim.MH then
        local nb = s.map[Sim.idx(nx, ny)]
        if WATERY[nb] or nb == 'coast' then ends[#ends + 1] = { cx + d[1] * ts / 2, cy + d[2] * ts / 2 } end
      end
    end
    if #ends == 0 then ends = { { cx - ts * .35, cy - ts * .2 }, { cx + ts * .35, cy + ts * .2 } } end
    if #ends == 1 then ends[2] = { cx, cy } end
    for _, e in ipairs(ends) do
      local pts = Art.quadPts({ cx, cy }, { (cx + e[1]) / 2 + (rng:random() - .5) * ts * .2, (cy + e[2]) / 2 + (rng:random() - .5) * ts * .2 }, e, 10)
      lg.setColor(.18, .37, .51, 1); lg.setLineWidth(ts * .3); lg.line(pts)
      lg.setColor(.35, .61, .8, 1); lg.setLineWidth(ts * .2); lg.line(pts)
    end
    lg.setColor(.35, .61, .8, 1); lg.circle('fill', cx, cy, ts * .14, 12)
  end
end
local function buildMap(w)
  local s = S()
  local ts = w / Sim.MW
  local H = ts * Sim.MH
  local cv = lg.newCanvas(w, H, { msaa = 4, dpiscale = lg.getDPIScale() * UI.scale })
  lg.push('all')
  lg.setScissor()
  lg.setCanvas(cv)
  lg.setScissor()
  lg.clear(.04, .03, .024, 1)
  lg.origin()
  local fog = love.math.newRandomGenerator(s.seed + 99)
  for _ = 1, 220 do
    if fog:random() < .5 then lg.setColor(.76, .63, .42, .025) else lg.setColor(0, 0, 0, .2) end
    lg.circle('fill', fog:random() * w, fog:random() * H, ts * (.3 + fog:random() * 1.2), 16)
  end
  local fr = {}
  for _, i in ipairs(Sim.frontier()) do fr[i] = true end
  for i = 1, Sim.N do
    local X, Y = Sim.xy(i)
    local x, y = X * ts, Y * ts
    if s.exp[i] == 1 then paintTile(i, x, y, ts, tileRng(s.seed, i))
    elseif fr[i] then
      lg.push('all'); paintTile(i, x, y, ts, tileRng(s.seed, i)); lg.pop()
      lg.setColor(.04, .03, .024, .8); lg.rectangle('fill', x, y, ts + .6, ts + .6)
    end
  end
  for i = 1, Sim.N do
    if s.exp[i] == 1 then
      local X, Y = Sim.xy(i)
      local x, y = X * ts, Y * ts
      for _, d in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
        local nx, ny = X + d[1], Y + d[2]
        local open = nx < 0 or ny < 0 or nx >= Sim.MW or ny >= Sim.MH or s.exp[Sim.idx(nx, ny)] ~= 1
        if open then
          local dark, clear = { .04, .03, .024, .55 }, { .04, .03, .024, 0 }
          if d[1] == -1 then hgrad(x, y, ts * .3, ts, dark, clear) elseif d[1] == 1 then hgrad(x + ts * .7, y, ts * .3, ts, clear, dark)
          elseif d[2] == -1 then UI.vgrad(x, y, ts, ts * .3, dark, clear) else UI.vgrad(x, y + ts * .7, ts, ts * .3, clear, dark) end
        end
      end
      lg.setColor(0, 0, 0, .18); lg.setLineWidth(1); lg.rectangle('line', x + .5, y + .5, ts, ts)
    end
  end
  -- the settlement: shelters around the home fire, and each finished wonder on a tile nearby
  local hX, hY = Sim.xy(s.home)
  local land = {}
  for ring = 1, 3 do
    for dy = -ring, ring do for dx = -ring, ring do
      if math.max(math.abs(dx), math.abs(dy)) == ring then
        local X, Y = hX + dx, hY + dy
        if X >= 0 and Y >= 0 and X < Sim.MW and Y < Sim.MH then
          local i = Sim.idx(X, Y)
          if s.exp[i] == 1 and not WATERY[s.map[i]] then land[#land + 1] = { X, Y, ring } end
        end
      end
    end end
  end
  local wonders = {}
  for _, b in ipairs(Sim.BLDS) do if b.wonder and Sim.bld(b.id) > 0 then wonders[#wonders + 1] = b.id end end
  local homes = 0
  for _, id in ipairs({ 'leanto', 'mudhut', 'hut', 'house' }) do homes = homes + Sim.bld(id) end
  local best = Sim.bld('house') > 0 and 'b.house' or Sim.bld('hut') > 0 and 'b.hut' or 'b.mudhut'
  local slots = { { .05, .05 }, { .52, .1 }, { .1, .52 }, { .55, .55 } }
  local k, wi = 0, 1
  for li, L in ipairs(land) do
    local x, y = L[1] * ts, L[2] * ts
    if wi <= #wonders and L[3] >= 1 and (li % 2 == 0 or li > 8) then
      Art.draw('b.' .. wonders[wi], x + ts * .08, y + ts * .02, ts * .84); wi = wi + 1
    elseif L[3] == 1 then
      for _, sl in ipairs(slots) do
        if k < math.ceil(homes / 2) and k < 28 then Art.draw(best, x + ts * sl[1], y + ts * sl[2], ts * .44); k = k + 1 end
      end
    end
  end
  lg.pop()
  return cv
end
-- The map is painted into its own image before anything else is drawn in a frame, so no screen clipping leaks into it.
local lastExp, lastSeed
local function ensureMap(mw)
  local s = S()
  local homes = 0
  for _, id in ipairs({ 'leanto', 'mudhut', 'hut', 'house' }) do homes = homes + Sim.bld(id) end
  local key = s.explored .. '|' .. mw .. '|' .. s.seed .. '|' .. (Sim.known('canoes') and 1 or 0) .. '|' .. math.min(56, math.ceil(homes / 2)) .. '|' .. Sim.wondersBuilt() .. '|' .. UI.scale
    .. '|' .. (Sim.bld('house') > 0 and 4 or Sim.bld('hut') > 0 and 3 or Sim.bld('mudhut') > 0 and 2 or 1)
  if key ~= mapKey or not mapCanvas or Sim.mapDirty then
    -- tiles explored since the last picture fade in
    if lastExp and lastSeed == s.seed then
      local now = love.timer.getTime()
      for i = 1, Sim.N do if s.exp[i] == 1 and lastExp[i] ~= 1 then Screens.reveal[i] = now end end
    else Screens.reveal = {} end
    lastExp, lastSeed = {}, s.seed
    for i = 1, Sim.N do lastExp[i] = s.exp[i] end
    if mapCanvas then mapCanvas:release() end
    mapCanvas = buildMap(mw); mapKey = key; Sim.mapDirty = false
  end
end
-- Moving things on top of the map picture: the home fire, glints on water, newly found land, and the weather.
local weather = { kind = nil, list = {} }
local function drawMapLife(mx0, my0, mw, mh, ts)
  local s = S()
  local now = love.timer.getTime()
  local dt = Screens.dt or 0
  -- water glints
  for i = 1, Sim.N do
    local t = s.map[i]
    if s.exp[i] == 1 and WATERY[t] then
      local X, Y = Sim.xy(i)
      local ph = now * 1.3 + i * 1.7
      local a = .1 + .1 * math.sin(ph)
      if a > .05 then
        local gx, gy = mx0 + (X + .25 + .5 * ((i * 37) % 10) / 10) * ts, my0 + (Y + .3 + .4 * ((i * 53) % 10) / 10) * ts + math.sin(ph * .5) * ts * .04
        lg.setColor(.85, .95, 1, a); lg.setLineWidth(1.2)
        lg.line(gx - ts * .1, gy, gx + ts * .1, gy)
      end
    end
  end
  -- newly explored tiles fade in from the dark
  for i, t0 in pairs(Screens.reveal) do
    local age = now - t0
    if age > 1.4 then Screens.reveal[i] = nil
    else
      local X, Y = Sim.xy(i)
      local a = 1 - age / 1.4
      lg.setColor(.04, .03, .024, .85 * a * a); lg.rectangle('fill', mx0 + X * ts, my0 + Y * ts, ts + .5, ts + .5)
      UI.border(mx0 + X * ts, my0 + Y * ts, ts, ts, C.gold, a, 2)
    end
  end
  -- the home fire
  local hX, hY = Sim.xy(s.home)
  local hx, hy = mx0 + hX * ts + ts / 2, my0 + hY * ts + ts / 2
  local fl = .8 + .2 * math.sin(now * 7.3) * math.sin(now * 3.1 + 1)
  for r = ts * 1.5, 2, -ts * .12 do lg.setColor(1, .62, .22, .04 * fl); lg.circle('fill', hx, hy, r * (.95 + .05 * fl), 24) end
  local fs = ts * (.86 + .06 * fl)
  Art.draw('fire', hx - fs / 2, hy - fs * .55, fs)
  for k = 0, 5 do
    local life = (now * .7 + k / 6) % 1
    local sx = hx + math.sin(k * 2.3 + now * 1.7) * ts * .18 * life
    local sy = hy - ts * .25 - life * ts * .9
    lg.setColor(1, .75 + .2 * (1 - life), .3, (1 - life) * .9)
    lg.circle('fill', sx, sy, 1.4 * (1 - life) + .5, 6)
  end
  -- weather follows the season
  if not Settings.get('weather') then return end
  local se, dd = Sim.season(), s.day % 25
  local kind = se == 4 and 'snow' or se == 3 and 'leaves' or (se == 1 and dd >= 6 and dd <= 13) and 'rain' or se == 2 and 'motes' or nil
  if weather.kind ~= kind or weather.w ~= mw then
    weather = { kind = kind, w = mw, list = {} }
    local count = kind == 'snow' and 90 or kind == 'rain' and 110 or kind == 'leaves' and 26 or kind == 'motes' and 22 or 0
    for k = 1, count do weather.list[k] = { x = love.math.random() * mw, y = love.math.random() * mh, v = .5 + love.math.random(), p = love.math.random() * 6.28 } end
  end
  for _, f in ipairs(weather.list) do
    if kind == 'snow' then
      f.y = f.y + dt * 14 * f.v; f.x = f.x + math.sin(now + f.p) * dt * 8
      lg.setColor(1, 1, 1, .55 + .25 * f.v / 1.5); lg.circle('fill', mx0 + f.x % mw, my0 + f.y % mh, .9 + f.v * .8, 6)
    elseif kind == 'rain' then
      f.y = f.y + dt * 260 * f.v; f.x = f.x - dt * 40
      local x, y = mx0 + f.x % mw, my0 + f.y % mh
      lg.setColor(.75, .85, 1, .28); lg.setLineWidth(1); lg.line(x, y, x - 2, y + 7)
    elseif kind == 'leaves' then
      f.y = f.y + dt * 18 * f.v; f.x = f.x + (math.sin(now * 1.3 + f.p) * 18 - 8) * dt
      local x, y = mx0 + f.x % mw, my0 + f.y % mh
      lg.push(); lg.translate(x, y); lg.rotate(now * 2 * f.v + f.p)
      lg.setColor(f.v > 1 and .85 or .72, f.v > 1 and .42 or .3, .12, .85); lg.ellipse('fill', 0, 0, 3.2, 1.6, 8)
      lg.pop()
    elseif kind == 'motes' then
      f.x = f.x + math.sin(now * .6 + f.p) * dt * 10; f.y = f.y + math.cos(now * .5 + f.p) * dt * 6
      local a = .35 + .35 * math.sin(now * 2 + f.p)
      lg.setColor(1, .95, .6, a); lg.circle('fill', mx0 + f.x % mw, my0 + f.y % mh, 1.6, 8)
    end
  end
  if kind == 'snow' then lg.setColor(.85, .9, 1, .07); lg.rectangle('fill', mx0, my0, mw, mh) end
end
local hoverTile
local function drawTerritory(x, y, w, h)
  local s = S()
  local sc = UI.scrollState('terr')
  sc.x, sc.yTop, sc.w, sc.h = x, y, w, h
  UI.pushClip(x, y, w, h)
  local cy = y + 10 - sc.y
  local t = 'Territory'
  UI.shadowText(t, x + (w - UI.F.d22:getWidth(t)) / 2, cy, UI.F.d22, C.gold)
  cy = cy + 32
  cy = cy + UI.para(s.explored .. ' of ' .. Sim.N .. ' tiles explored. Each known tile adds wild resources your workers can harvest every day. The more workers share a resource, the less each brings in. Wanderers and scouts reveal more land.', x + 30, cy, w - 60, UI.F.small, C.muted, 'center') + 10
  local mw = floor(w - 24)
  if not mapCanvas then return end
  local mx0, my0 = x + 12, cy
  local ts = mw / Sim.MW
  local mh = ts * Sim.MH
  UI.border(mx0 - 2, my0 - 2, mw + 4, mh + 4, C.frame, 1, 2)
  lg.setColor(1, 1, 1, 1); lg.setBlendMode('alpha', 'premultiplied'); lg.draw(mapCanvas, mx0, my0); lg.setBlendMode('alpha')
  UI.pushClip(mx0, my0, mw, mh); drawMapLife(mx0, my0, mw, mh, ts); UI.popClip()
  hoverTile = nil
  if UI.hit('map', mx0, my0, mw, mh, {}) then
    local X, Y = floor((UI.mx - mx0) / ts), floor((UI.my - my0) / ts)
    if X >= 0 and Y >= 0 and X < Sim.MW and Y < Sim.MH then
      hoverTile = Sim.idx(X, Y)
      UI.border(mx0 + X * ts, my0 + Y * ts, ts, ts, C.gold, 1, 2)
    end
  end
  cy = cy + mh + 10
  local info, infoQ
  if hoverTile then
    if s.exp[hoverTile] ~= 1 then
      local fr = false
      for _, i in ipairs(Sim.frontier()) do if i == hoverTile then fr = true end end
      info = fr and 'Unexplored, at the edge of known land. Explorers may reach it soon.' or 'Unknown, beyond the reach of your explorers.'
    else
      local b = Sim.BIOME[s.map[hoverTile]]
      local parts = {}
      for _, k in ipairs(Sim.LANDKEYS) do if b.y[k] then parts[#parts + 1] = Sim.LAND[k] .. ' ' .. b.y[k] end end
      info = b.n .. (hoverTile == s.home and ', your home fire' or '') .. ':  ' .. table.concat(parts, '  \u{00b7}  ')
      infoQ = b.q
    end
  else info = 'Point at a tile to see what it offers.' end
  local ih0 = UI.wrapH(info, UI.F.small, w - 48)
  local ih = ih0 + 14 + (infoQ and (UI.wrapH(infoQ, UI.F.smallI, w - 48) + 2) or 0)
  UI.plaque(x + 12, cy, w - 24, ih)
  UI.para(info, x + 24, cy + 7, w - 48, UI.F.small, C.text)
  if infoQ then UI.para(infoQ, x + 24, cy + 9 + ih0, w - 48, UI.F.smallI, C.muted) end
  cy = cy + ih + 12
  -- land table
  local L = Sim.landCap()
  local use = s._landUse or { raw = {}, ratio = {} }
  local cols = { x + 16, x + 16 + (w - 32) * .38, x + 16 + (w - 32) * .6, x + 16 + (w - 32) * .8 }
  for k, hd in ipairs({ 'Resource', 'Land yields / day', 'Harvested / day', 'Use' }) do UI.text(hd, cols[k], cy, UI.F.tiny, C.muted) end
  cy = cy + 20
  UI.rect(x + 16, cy - 2, w - 32, 1, C.frameHi, .3)
  for _, k in ipairs(Sim.LANDKEYS) do
    if L[k] > 0 or use.raw[k] then
      local capv = k == 'water' and (L.water + L.muddy) or L[k]
      local got = (use.raw[k] or 0) * (use.ratio[k] or 0)
      UI.text(Sim.LAND[k], cols[1], cy + 2, UI.F.small, C.text)
      UI.text(fmt(capv), cols[2], cy + 2, UI.F.small, C.text)
      UI.text(fmt(got), cols[3], cy + 2, UI.F.small, C.text)
      local bw = (w - 32) * .18
      UI.rect(cols[4], cy + 8, bw, 6, C.black, .6)
      if capv > 0 then UI.vgrad(cols[4], cy + 8, bw * min(1, got / capv), 6, Art.color('#8fb6ea'), Art.color('#3a68a8')) end
      cy = cy + 22
      UI.rect(x + 16, cy, w - 32, 1, C.frameHi, .15)
    end
  end
  cy = cy + 8
  cy = cy + UI.para('This season: ' .. Sim.SEASONS[Sim.season()] .. '. Fruit, herbs, fiber, game, fish and farmland change with the seasons.', x + 30, cy, w - 60, UI.F.small, C.muted, 'center') + 10
  sc.max = max(0, cy + sc.y - y - h)
  UI.popClip()
  UI.scrollbar(sc)
end

---------------------------------------------------------------- cards (research, rites, traits)
-- cards: list of {doc = doc, buttons = {{label, onClick, enabled}}, note = text, active = bool}
local function drawCards(cards, x, y, w)
  local minW, gap = 260, 8
  local cols = max(1, floor((w + gap) / (minW + gap)))
  local cw = (w - (cols - 1) * gap) / cols
  local cy = y
  for start = 1, #cards, cols do
    local rowH = 0
    local hs = {}
    for k = start, min(#cards, start + cols - 1) do
      local c = cards[k]
      local h = UI.docHeight(c.doc, cw - 22) + 20 + (c.buttons and 32 or 0)
      hs[k] = h; rowH = max(rowH, h)
    end
    for k = start, min(#cards, start + cols - 1) do
      local c = cards[k]
      local cx = x + (k - start) * (cw + gap)
      UI.plaque(cx, cy, cw, rowH, c.active)
      if c.neg then UI.rect(cx + 1, cy + 1, 3, rowH - 2, C.bad, .8) end
      UI.doc(c.doc, cx + 11, cy + 10, cw - 22)
      if c.buttons then
        local bx = cx + 11
        local by = cy + rowH - 32
        for bi, b in ipairs(c.buttons) do
          local bw = UI.F.smallB:getWidth(b[1]) + 26
          local id = 'card:' .. (c.id or k) .. ':' .. bi
          local hot = UI.hit(id, bx, by, bw, 24, { click = b[3] and b[2] or nil, disabled = not b[3] })
          UI.blue(bx, by, bw, 24, not b[3] and 'disabled' or (hot and 'hot' or nil))
          UI.shadowText(b[1], bx + 13, by + 3, UI.F.smallB, b[3] and { 1, 1, 1, 1 } or C.muted)
          bx = bx + bw + 8
        end
        if c.note then UI.text(c.note, bx + 2, by + 4, UI.F.tiny, C.muted) end
      end
    end
    cy = cy + rowH + gap
  end
  return cy - y
end
local function sectionHeader(title, sub, x, y, w)
  UI.shadowText(title, x + (w - UI.F.d22:getWidth(title)) / 2, y, UI.F.d22, C.gold)
  local h = 32
  if sub then h = h + UI.para(sub, x + 30, y + h, w - 60, UI.F.small, C.muted, 'center') + 10 end
  return h
end
local function scrolled(name, x, y, w, h, fn)
  local sc = UI.scrollState(name)
  sc.x, sc.yTop, sc.w, sc.h = x, y, w, h
  UI.pushClip(x, y, w, h)
  local used = fn(y + 10 - sc.y)
  sc.max = max(0, used + 20 - h)
  sc.y = min(sc.y, sc.max)
  UI.popClip()
  UI.scrollbar(sc)
end

local function drawResearch(x, y, w, h)
  scrolled('research', x, y, w, h, function(top)
    local s = S()
    local cy = top
    cy = cy + sectionHeader('Research', 'Spend insight from dreamers and scholars to make discoveries. Later ones also need culture, faith or influence. Each discovery opens up new ones.', x, cy, w)
    local av, hidden = {}, 0
    for _, t in ipairs(Sim.TECHS) do
      if not Sim.known(t.id) then if Sim.reqMet(t) then av[#av + 1] = t else hidden = hidden + 1 end end
    end
    table.sort(av, function(a, b) return a.cost.insight < b.cost.insight end)
    local cards = {}
    for _, t in ipairs(av) do
      local un = unlocksOf(t.id)
      local lead = 0
      for _, x2 in ipairs(Sim.TECHS) do for _, r in ipairs(x2.req) do if r == t.id then lead = lead + 1 end end end
      local doc = { { t = 'title', icon = Sim.TECH_ICON[t.id], text = t.n, iconSize = 30 }, { t = 'p', text = t.d }, Flavor.p(t.q) }
      if #un > 0 then doc[#doc + 1] = { t = 'chips', label = 'Unlocks', items = un } end
      doc[#doc + 1] = { t = 'flow', items = costItems(t.cost) }
      cards[#cards + 1] = { id = t.id, doc = doc, buttons = { { 'Research', function() Sim.research(t.id) end, Sim.payable(t.cost) } },
        note = lead > 0 and ('Leads to ' .. lead .. ' more ' .. (lead == 1 and 'discovery' or 'discoveries')) or nil }
    end
    if #cards == 0 then cy = cy + UI.para('Every discovery is made. Your tribe has become a civilization.', x + 20, cy, w - 40, UI.F.body, C.muted, 'center') + 10
    else cy = cy + drawCards(cards, x + 12, cy, w - 24) end
    if hidden > 0 then cy = cy + UI.para(hidden .. ' discoveries lie further ahead.', x + 20, cy + 4, w - 40, UI.F.small, C.muted, 'center') + 14 end
    if #s.techs > 0 then
      local t = 'Known (' .. #s.techs .. ' of ' .. #Sim.TECHS .. ')'
      UI.shadowText(t, x + (w - UI.F.d18:getWidth(t)) / 2, cy + 6, UI.F.d18, C.text)
      cy = cy + 36
      -- chips with hover descriptions
      local cx0, cxx, lh = x + 16, x + 16, 26
      local rows, row = {}, {}
      local rowW = 0
      for _, id in ipairs(s.techs) do
        local tw = UI.F.small:getWidth(Sim.TM[id].n) + 34
        if #row > 0 and rowW + tw > w - 32 then rows[#rows + 1] = { row, rowW }; row, rowW = {}, 0 end
        row[#row + 1] = { id, tw }; rowW = rowW + tw + 5
      end
      if #row > 0 then rows[#rows + 1] = { row, rowW } end
      for _, rw in ipairs(rows) do
        cxx = x + (w - rw[2]) / 2
        for _, it in ipairs(rw[1]) do
          local id, tw = it[1], it[2]
          local hot = UI.hit('known:' .. id, cxx, cy, tw, lh - 3, { tip = function() local tt = Sim.TM[id]; return { { t = 'title', icon = Sim.TECH_ICON[id], text = tt.n }, { t = 'p', text = tt.d }, Flavor.p(tt.q) } end })
          UI.plaque(cxx, cy, tw, lh - 3, hot)
          Art.draw(Sim.TECH_ICON[id], cxx + 4, cy + 1, 20)
          UI.text(Sim.TM[id].n, cxx + 27, cy + 3, UI.F.small, C.text)
          cxx = cxx + tw + 5
        end
        cy = cy + lh + 2
      end
      cy = cy + 6
    end
    return cy - top
  end)
end

local function drawRites(x, y, w, h)
  scrolled('rites', x, y, w, h, function(top)
    local s = S()
    local cy = top
    cy = cy + sectionHeader('Rites', 'Powers the whole tribe can call on. Each has a price and must rest a while before it can be performed again. New rites come with new discoveries.', x, cy, w)
    local cards, locked = {}, 0
    for _, r in ipairs(Sim.RITES) do
      if Sim.riteAvail(r) then
        local ready = Sim.riteReady(r)
        local buff
        for _, b in ipairs(s.buffs) do if b.id == r.id then buff = b end end
        local status = (buff and ('Active: ' .. (buff['end'] - s.day) .. ' days left. ') or '') .. 'Rests ' .. r.cd .. ' days between uses.' .. (ready and '' or (' Ready in ' .. (s.rites[r.id] + r.cd - s.day) .. ' days.'))
        local doc = { { t = 'title', icon = 'ri.' .. r.id, text = r.n, iconSize = 30 }, { t = 'p', text = r.d }, Flavor.p(r.q), { t = 'flow', items = costItems(r.cost) }, { t = 'p', text = status, col = buff and C.warn or C.muted } }
        cards[#cards + 1] = { id = r.id, doc = doc, active = buff ~= nil, buttons = { { 'Perform', function() Sim.doRite(r.id) end, ready and Sim.payable(r.cost) } } }
      else locked = locked + 1 end
    end
    if #cards == 0 then cy = cy + UI.para('Your tribe knows no rites yet. Research Fire-making, Hunting, Ritualism or Oral tradition to learn the first ones.', x + 20, cy, w - 40, UI.F.body, C.muted, 'center') + 10
    else cy = cy + drawCards(cards, x + 12, cy, w - 24) end
    if locked > 0 then cy = cy + UI.para(locked .. ' more rites can be learned.', x + 20, cy + 4, w - 40, UI.F.small, C.muted, 'center') + 14 end
    return cy - top
  end)
end

local function drawTraits(x, y, w, h)
  scrolled('traits', x, y, w, h, function(top)
    local s = S()
    local cy = top
    cy = cy + sectionHeader('Traits', 'Traits are not chosen. They emerge on their own from how your tribe lives: hardship, plenty, and new ways of working. ' .. #s.traits .. ' of ' .. #Sim.TRAITS .. ' have appeared.', x, cy, w)
    local cards = {}
    for _, id in ipairs(s.traits) do
      local t = Sim.TRM[id]
      if t then cards[#cards + 1] = { id = id, neg = t.neg, doc = { { t = 'title', icon = Sim.TRAIT_ICON[id] or 'culture', text = t.n, iconSize = 30, col = t.neg and C.bad or nil }, { t = 'p', text = t.d }, Flavor.p(t.q) } } end
    end
    if #cards == 0 then cy = cy + UI.para('No traits yet. Keep your tribe alive and they will come.', x + 20, cy, w - 40, UI.F.body, C.muted, 'center') + 10
    else cy = cy + drawCards(cards, x + 12, cy, w - 24) end
    return cy - top
  end)
end

local function drawPolicies(x, y, w, h)
  scrolled('policies', x, y, w, h, function(top)
    local s = S()
    local cy = top
    cy = cy + sectionHeader('Policies', 'Choices you make for the tribe. Some cost influence each time you change them.', x, cy, w)
    local pw = min(w - 24, 680)
    local px = x + (w - pw) / 2
    for _, p in ipairs(Sim.POLICIES) do
      local lock = p.tech and not Sim.known(p.tech)
      local ctlW = p.opts and 270 or (p.cost and 124 or 70)
      local desc = lock and ('Unlocked by ' .. Sim.TM[p.tech].n .. '.') or (p.d .. (p.cost and (' Changing it costs ' .. p.cost .. ' influence.') or ''))
      local dh = UI.wrapH(desc, UI.F.tiny, pw - ctlW - 60)
      local pq = not lock and p.q or nil
      local qh = pq and UI.wrapH(pq, UI.F.tinyI, pw - ctlW - 60) + 2 or 0
      local rh = max(52, 26 + dh + qh + 8)
      UI.plaque(px, cy, pw, rh)
      local a = lock and .45 or 1
      Art.draw(Sim.POLICY_ICON[p.id], px + 10, cy + 8, 24, a)
      UI.shadowText(p.n, px + 40, cy + 9, UI.F.bodyB, C.gold, a)
      UI.para(desc, px + 40, cy + 29, pw - ctlW - 60, UI.F.tiny, C.muted)
      if pq then UI.para(pq, px + 40, cy + 31 + dh, pw - ctlW - 60, UI.F.tinyI, C.muted, nil) end
      if not lock then
        if p.opts then
          local bx = px + pw - ctlW - 10
          for oi, o in ipairs(p.opts) do
            local bw = 84
            local on = s.pol[p.id] == o[1]
            local hot = UI.hit('pol:' .. p.id .. ':' .. oi, bx, cy + (rh - 26) / 2, bw, 26, { click = function() Sim.setPolicy(p.id, o[1]) end })
            UI.blue(bx, cy + (rh - 26) / 2, bw, 26, on and 'on' or (hot and 'hot' or nil))
            UI.shadowText(o[2], bx + (bw - UI.F.smallB:getWidth(o[2])) / 2, cy + (rh - 26) / 2 + 4, UI.F.smallB, on and Art.color('#06121f') or { 1, 1, 1, 1 })
            bx = bx + bw + 3
          end
        else
          local on = s.pol[p.id]
          local can = not p.cost or s.res.influence >= p.cost
          local tw = 70
          local bx, by = px + pw - tw - 10, cy + (rh - 26) / 2
          -- a switch that costs influence shows its price beside it, in red when the tribe cannot pay
          if p.cost then
            local ct = tostring(p.cost)
            local cw = 20 + UI.F.smallB:getWidth(ct)
            local cx0 = bx - 10 - cw
            Art.draw('influence', cx0, by + 3, 20)
            UI.text(ct, cx0 + 22, by + 4, UI.F.smallB, can and C.text or C.bad)
          end
          local tip = p.cost and function()
            return { { t = 'p', text = 'Changing this costs ' .. p.cost .. ' influence. You have ' .. fmt(s.res.influence) .. '.' .. (can and '' or ' Chieftains produce influence.'), col = can and C.text or C.warn } }
          end or nil
          local hot = UI.hit('pol:' .. p.id, bx, by, tw, 26, { click = can and function() Sim.setPolicy(p.id, not on) end or nil, disabled = not can, tip = tip })
          if on then UI.vgrad(bx, by, tw, 26, Art.color('#a6e391'), Art.color('#4f9a3c')); UI.border(bx, by, tw, 26, Art.color('#0b182c'), 1, 1, 3)
          else UI.blue(bx, by, tw, 26, not can and 'disabled' or (hot and 'hot' or nil)) end
          local lbl = on and 'On' or 'Off'
          UI.shadowText(lbl, bx + (tw - UI.F.smallB:getWidth(lbl)) / 2, by + 4, UI.F.smallB, on and Art.color('#071205') or (can and { 1, 1, 1, 1 } or C.muted))
        end
      end
      cy = cy + rh + 6
    end
    return cy - top
  end)
end

---------------------------------------------------------------- history
-- One line chart for one measure. Charts never share an axis; each has its own scale and its title names it.
local function drawChart(id, x, y, w, h, title, data, step, col, opts)
  opts = opts or {}
  UI.plaque(x, y, w, h)
  UI.shadowText(title, x + 12, y + 7, UI.F.smallB, C.text)
  local n = #data
  if n > 0 then local t = 'now ' .. fmt(data[n]) .. (opts.unit or ''); UI.text(t, x + w - 12 - UI.F.small:getWidth(t), y + 8, UI.F.small, C.muted) end
  local px, py, pw, ph = x + 48, y + 34, w - 64, h - 58
  if n < 2 then UI.para('Not enough history yet. Come back in a few days.', px, py + ph / 2 - 8, pw, UI.F.small, C.muted, 'center'); return end
  local lo, hi = math.huge, -math.huge
  for _, v in ipairs(data) do lo = min(lo, v); hi = max(hi, v) end
  if opts.floor0 then lo = 0 end
  if opts.zero then lo = min(lo, 0); hi = max(hi, 0) end
  if hi - lo < (opts.minSpan or 4) then hi = lo + (opts.minSpan or 4) end
  local span = hi - lo
  hi = hi + span * .06
  if not opts.floor0 then lo = lo - span * .06 end
  local function Y(v) return py + ph - (v - lo) / (hi - lo) * ph end
  local function X(k) return px + (k - 1) / (n - 1) * pw end
  for g = 0, 2 do
    local v = lo + (hi - lo) * g / 2
    local gy = Y(v)
    UI.rect(px, gy, pw, 1, C.frameHi, .13)
    local lbl = fmt(v)
    UI.text(lbl, px - 6 - UI.F.micro:getWidth(lbl), gy - 7, UI.F.micro, C.muted)
  end
  local base = opts.zero and Y(0) or (py + ph)
  if opts.zero and lo < 0 and hi > 0 then UI.rect(px, Y(0), pw, 1, C.muted, .5) end
  local verts, pts = {}, {}
  for k, v in ipairs(data) do
    local vx, vy = X(k), Y(v)
    verts[#verts + 1] = { vx, vy, 0, 0, col[1], col[2], col[3], .22 }
    verts[#verts + 1] = { vx, base, 0, 0, col[1], col[2], col[3], .03 }
    pts[#pts + 1] = vx; pts[#pts + 1] = vy
  end
  lg.setColor(1, 1, 1, 1); lg.draw(lg.newMesh(verts, 'strip', 'stream'))
  UI.setc(col); lg.setLineWidth(2); lg.setLineJoin('bevel'); lg.line(pts)
  local function yearOf(k) return floor(k * step / 100) + 1 end
  UI.text('Year 1', px, py + ph + 5, UI.F.micro, C.muted)
  local last = 'Year ' .. yearOf(n)
  UI.text(last, px + pw - UI.F.micro:getWidth(last), py + ph + 5, UI.F.micro, C.muted)
  if UI.hit('chart:' .. id, px, py - 6, pw, ph + 12, {}) then
    local k = max(1, min(n, floor((UI.mx - px) / pw * (n - 1) + 1.5)))
    local vx, vy = X(k), Y(data[k])
    UI.rect(vx, py, 1, ph, C.text, .35)
    UI.setc(C.panel); lg.circle('fill', vx, vy, 6, 16)
    UI.setc(col); lg.circle('fill', vx, vy, 4, 16)
    local day = k * step
    local lbl = Sim.dateStr(day) .. ':  ' .. fmt(data[k]) .. (opts.unit or '')
    local lw = UI.F.smallB:getWidth(lbl) + 16
    local lx = vx + 10
    if lx + lw > px + pw then lx = vx - 10 - lw end
    UI.rect(lx, py, lw, 22, C.black, .8, 4); UI.border(lx, py, lw, 22, C.frameHi, .6, 1, 4)
    UI.text(lbl, lx + 8, py + 2, UI.F.smallB, C.text)
  end
end
local function dangerButton(label, id, bx, by, fn)
  local bw = UI.F.smallB:getWidth(label) + 30
  local hot = UI.hit(id, bx, by, bw, 28, { click = fn })
  UI.vgrad(bx, by, bw, 28, Art.color(hot and '#f09080' or '#e08070'), Art.color('#9a3424')); UI.border(bx, by, bw, 28, Art.color('#2a0a05'), 1, 1, 3)
  UI.shadowText(label, bx + 15, by + 5, UI.F.smallB, { 1, 1, 1, 1 })
  return bw
end
local function blueButton(label, id, bx, by, fn, on)
  local bw = UI.F.smallB:getWidth(label) + 30
  local hot = UI.hit(id, bx, by, bw, 28, { click = fn })
  UI.blue(bx, by, bw, 28, on and 'on' or (hot and 'hot' or nil))
  UI.shadowText(label, bx + 15, by + 5, UI.F.smallB, on and Art.color('#06121f') or { 1, 1, 1, 1 })
  return bw
end
Screens.blueButton, Screens.dangerButton = blueButton, dangerButton
Screens.retireArm = -10
local function drawHistory(x, y, w, h)
  scrolled('history', x, y, w, h, function(top)
    local s = S()
    local cy = top
    cy = cy + sectionHeader('History', 'The story of the ' .. s.name .. ' tribe' .. ((s.gen or 1) > 1 and (', generation ' .. s.gen .. ' of your legacy') or '') .. '.', x, cy, w)
    local ow = min(w - 24, 760)
    local ox = x + (w - ow) / 2
    local stats = { { 'Year', floor(s.day / 100) + 1 }, { 'People now', Sim.popTotal() }, { 'Most at once', s.peak or Sim.popTotal() }, { 'Born', s.born }, { 'Died', s.deaths },
      { 'Discoveries', #s.techs .. ' of ' .. #Sim.TECHS }, { 'Customs', #s.traits }, { 'Wonders', Sim.wondersBuilt() .. ' of 7' }, { 'Land known', s.explored .. ' tiles' }, { 'Age', Sim.era() } }
    local cols = max(2, floor((ow + 5) / 145))
    local bw = (ow - (cols - 1) * 5) / cols
    for k, st in ipairs(stats) do
      local col, row = (k - 1) % cols, floor((k - 1) / cols)
      local bx, by = ox + col * (bw + 5), cy + row * 50
      UI.plaque(bx, by, bw, 45)
      UI.text(st[1], bx + 9, by + 4, UI.F.tiny, C.muted)
      UI.shadowText(tostring(st[2]), bx + 9, by + 20, UI.F.smallB, C.gold)
    end
    cy = cy + math.ceil(#stats / cols) * 50 + 12
    local hst = s.hist
    drawChart('pop', ox, cy, ow, 170, 'Population', hst.pop, hst.step, C.blueHi, { floor0 = true, minSpan = 10 }); cy = cy + 178
    drawChart('food', ox, cy, ow, 150, 'Food in store', hst.food, hst.step, Art.color('#e3b64a'), { floor0 = true, minSpan = 20 }); cy = cy + 158
    drawChart('mood', ox, cy, ow, 150, 'Mood', hst.mood, hst.step, Art.color('#b9d98a'), { zero = true, unit = '%', minSpan = 20 }); cy = cy + 164
    -- legacy
    local t = 'Your legacy'
    UI.shadowText(t, ox + (ow - UI.F.d18:getWidth(t)) / 2, cy, UI.F.d18, C.gold)
    cy = cy + 30
    local total, parts = Legacy.score(s)
    local lead = 'You hold ' .. Legacy.D.embers .. (Legacy.D.embers == 1 and ' ember' or ' embers') .. ' and have reached ' .. Legacy.milesDone() .. ' of ' .. #Legacy.MILES .. ' milestones. '
      .. 'Embers buy perks that help every tribe after this one. When this tribe\'s story ends, it adds ' .. total .. (total == 1 and ' ember.' or ' embers.')
    cy = cy + UI.para(lead, ox, cy, ow, UI.F.small, C.text, 'center') + 8
    local rows = {}
    for _, p in ipairs(parts) do rows[#rows + 1] = { p[1], '+' .. p[2], p[2] > 0 and C.good or C.muted } end
    local rw = min(ow, 360)
    UI.doc({ { t = 'rows', rows = rows } }, ox + (ow - rw) / 2, cy, rw)
    cy = cy + UI.docHeight({ { t = 'rows', rows = rows } }, rw) + 14
    local armed = love.timer.getTime() - Screens.retireArm < 4
    local l1, l2 = 'Open the legacy', armed and 'Click again to retire' or 'Retire this tribe'
    local w1, w2 = UI.F.smallB:getWidth(l1) + 30, UI.F.smallB:getWidth(l2) + 30
    local bx = ox + (ow - w1 - w2 - 10) / 2
    blueButton(l1, 'hist:legacy', bx, cy, function() Screens.onLegacy() end)
    dangerButton(l2, 'hist:retire', bx + w1 + 10, cy, function()
      if love.timer.getTime() - Screens.retireArm < 4 then Screens.retireArm = -10; Screens.onRetire() else Screens.retireArm = love.timer.getTime() end
    end)
    cy = cy + 40
    cy = cy + UI.para('Retiring ends this tribe\'s story and records it in the legacy. You then found a new tribe on a new map.', ox, cy, ow, UI.F.tiny, C.muted, 'center') + 10
    return cy - top
  end)
end

---------------------------------------------------------------- options (shared by the Settings tab and the title screen)
local function toggle(id, bx, by, on, fn)
  local hot = UI.hit(id, bx, by, 70, 26, { click = fn })
  if on then UI.vgrad(bx, by, 70, 26, Art.color('#a6e391'), Art.color('#4f9a3c')); UI.border(bx, by, 70, 26, Art.color('#0b182c'), 1, 1, 3)
  else UI.blue(bx, by, 70, 26, hot and 'hot' or nil) end
  local lbl = on and 'On' or 'Off'
  UI.shadowText(lbl, bx + (70 - UI.F.smallB:getWidth(lbl)) / 2, by + 4, UI.F.smallB, on and Art.color('#071205') or { 1, 1, 1, 1 })
end
function Screens.drawOptions(x, y, w, idp)
  local cy = y
  local lw = 170
  local function row(label, sub, h)
    UI.plaque(x, cy, w, h)
    UI.shadowText(label, x + 14, cy + 8, UI.F.bodyB, C.gold)
    if sub then UI.text(sub, x + 14, cy + 28, UI.F.tiny, C.muted) end
  end
  for _, v in ipairs({ { 'music', 'Music', 'Composed as you play' }, { 'sound', 'Sound effects', 'Clicks, bells and drums' } }) do
    row(v[2], v[3], 50)
    local sw = w - lw - 80
    UI.slider(idp .. v[1], x + lw, cy + 14, sw, Settings.get(v[1]), function(val) Settings.set(v[1], floor(val * 20 + .5) / 20) end)
    local pct = floor(Settings.get(v[1]) * 100 + .5) .. '%'
    UI.text(pct, x + w - 14 - UI.F.smallB:getWidth(pct), cy + 15, UI.F.smallB, C.text)
    cy = cy + 56
  end
  local limited = UI.scale < UI.pref * UI.os - .005
  row('Interface size', limited and ('Limited to ' .. floor(UI.scale / UI.os * 100 + .5) .. '% by the window size') or 'Makes all text and icons larger', 50)
  local bx = x + w - 14 - 3 * 84 - 6
  for _, v in ipairs({ { 1, '100%' }, { 1.15, '115%' }, { 1.3, '130%' } }) do
    local on = math.abs(Settings.get('ui') - v[1]) < .01
    local hot = UI.hit(idp .. 'ui' .. v[2], bx, cy + 12, 84, 26, { click = function() Settings.set('ui', v[1]) end })
    UI.blue(bx, cy + 12, 84, 26, on and 'on' or (hot and 'hot' or nil))
    UI.shadowText(v[2], bx + (84 - UI.F.smallB:getWidth(v[2])) / 2, cy + 16, UI.F.smallB, on and Art.color('#06121f') or { 1, 1, 1, 1 })
    bx = bx + 87
  end
  cy = cy + 56
  for _, v in ipairs({ { 'fullscreen', 'Full screen', 'Also: F11, or Ctrl+Cmd+F on a Mac' }, { 'weather', 'Weather on the map', 'Snow, rain and falling leaves' }, { 'stories', 'Story events', 'Now and then the tribe faces a choice' } }) do
    row(v[2], v[3], 50)
    toggle(idp .. v[1], x + w - 14 - 70, cy + 12, Settings.get(v[1]), function() Settings.set(v[1], not Settings.get(v[1])) end)
    cy = cy + 56
  end
  return cy - y
end

local function drawSettings(x, y, w, h)
  scrolled('settings', x, y, w, h, function(top)
    local cy = top
    cy = cy + sectionHeader('Settings', nil, x, cy, w)
    local ow = min(w - 24, 620)
    local ox = x + (w - ow) / 2
    cy = cy + Screens.drawOptions(ox, cy, ow, 'opt:') + 10
    local function centered(btns)
      local tw = 0
      for k, b in ipairs(btns) do tw = tw + UI.F.smallB:getWidth(b[1]) + 30 + (k > 1 and 8 or 0) end
      local bx = ox + (ow - tw) / 2
      for _, b in ipairs(btns) do bx = bx + blueButton(b[1], b[2], bx, cy, b[3]) + 8 end
      cy = cy + 38
    end
    local t = 'Saving'
    UI.shadowText(t, ox + (ow - UI.F.d16:getWidth(t)) / 2, cy + 4, UI.F.d16, C.text)
    cy = cy + 30
    cy = cy + UI.para('The game saves on this computer every 30 seconds and whenever you quit. Time only passes while the game is open. A save code copies your tribe so you can back it up or move it to another computer; to load one, copy it first, then press Load.', ox, cy, ow, UI.F.small, C.muted, 'center') + 10
    centered({ { 'Save now', 'set:save', function() Screens.onSave(); Screens.settingsMsg = 'Saved.'; Screens.settingsMsgT = love.timer.getTime() end },
      { 'Open save folder', 'set:folder', function() Screens.onOpenFolder() end } })
    centered({ { 'Copy save code', 'set:copy', function() Screens.settingsMsg = Screens.onExport(); Screens.settingsMsgT = love.timer.getTime() end },
      { 'Load code from clipboard', 'set:paste', function() Screens.settingsMsg = Screens.onImport(); Screens.settingsMsgT = love.timer.getTime() end } })
    if love.timer.getTime() - Screens.settingsMsgT < 6 and Screens.settingsMsg ~= '' then
      cy = cy + UI.para(Screens.settingsMsg, ox, cy - 4, ow, UI.F.small, C.good, 'center') + 8
    end
    centered({ { 'Back to the title screen', 'set:title', function() Screens.onTitle() end } })
    cy = cy + UI.para('To start a new tribe, retire this one from the History tab, or choose New tribe on the title screen.', ox, cy, ow, UI.F.tiny, C.muted, 'center') + 10
    return cy - top
  end)
end

---------------------------------------------------------------- chronicle
local LOGI = { good = 'x.good', bad = 'x.warn', death = 'x.bad', tech = 'insight', trait = 'culture', rite = 'faith', era = 'b.monument', story = 'x.scroll' }
local LOGC = { bad = '#ffd9a8', death = '#ffc2b6', good = '#d9f2cf', tech = '#cfe6ff', trait = '#f1d6ff', rite = '#ffe9b8', era = '#e9c47a', story = '#f4e2c0' }
local function drawChronicle(x, y, w, h)
  UI.panel(x, y, w, h)
  local s = S()
  local sc = UI.scrollState('log')
  if sc.stick == nil then sc.stick = true end
  sc.x, sc.yTop, sc.w, sc.h = x, y, w, h
  local tw = w - 14 - 26 - 30 - 18
  local entries = {}
  for k = min(100, #s.log), 1, -1 do entries[#entries + 1] = s.log[k] end
  local total = 0
  for _, e in ipairs(entries) do
    local txt = e.t .. ((e.n and e.n > 1) and ('  \u{00d7}' .. e.n) or '')
    if e._w ~= tw or e._t ~= txt then e._w, e._t = tw, txt; e._h = max(34, UI.wrapH(txt, UI.F.small, tw) + 10) end
    total = total + e._h + 2
  end
  sc.max = max(0, total + 12 - h)
  if sc.stick then sc.y = sc.max end
  sc.y = min(sc.y, sc.max)
  UI.pushClip(x + 3, y + 3, w - 6, h - 6)
  local cy = y + h - 6 - total + sc.max - sc.y
  if total < h - 12 then cy = y + h - 6 - total end
  for _, e in ipairs(entries) do
    local eh = e._h
    if cy + eh > y and cy < y + h then
      UI.vgrad(x + 6, cy, w - 12, eh, { 0, 0, 0, .35 }, { 0, 0, 0, .15 })
      if e.c == 'era' then UI.rect(x + 6, cy, w - 12, eh, C.gold, .12) elseif e.c == 'story' then UI.rect(x + 6, cy, w - 12, eh, C.faith, .07) end
      UI.rect(x + 6, cy, w - 12, 1, C.frameHi, .15)
      local yl = 'Y:' .. (floor(e.d / 100) + 1)
      UI.text(yl, x + 10, cy + 4, UI.F.micro, C.blueHi)
      UI.rect(x + 10, cy + 4 + UI.F.micro:getHeight() - 1, UI.F.micro:getWidth(yl), 1, C.blueHi, .7)
      UI.tile(x + 38, cy + 4, 28, false)
      Art.draw((e.i and e.i ~= '') and e.i or (LOGI[e.c] or 'x.scroll'), x + 39, cy + 5, 26)
      UI.para(e._t, x + 74, cy + 5, tw, UI.F.small, LOGC[e.c] and Art.color(LOGC[e.c]) or C.text, nil, true)
      UI.hit('log:' .. tostring(e), x + 6, cy, w - 12, eh, { tip = function() return { { t = 'p', text = Sim.dateStr(e.d), col = C.muted } } end })
    end
    cy = cy + eh + 2
  end
  UI.popClip()
  UI.scrollbar(sc)
end

---------------------------------------------------------------- header, logo, strip
local function speedIcon(kind, cx, cy)
  lg.setColor(1, 1, 1, 1)
  if kind == 0 then lg.rectangle('fill', cx - 5, cy - 5, 3.5, 10); lg.rectangle('fill', cx + 1.5, cy - 5, 3.5, 10)
  else
    local n = kind == 1 and 1 or kind == 3 and 2 or 3
    local tw = 7
    local sx = cx - (n * tw) / 2
    for k = 0, n - 1 do lg.polygon('fill', sx + k * tw, cy - 5, sx + k * tw + tw, cy, sx + k * tw, cy + 5) end
  end
end
local function drawHeader(x, y, w)
  local s = S()
  local dd = s.day % 100
  local banner = 'Year ' .. (floor(s.day / 100) + 1) .. ', day ' .. (dd + 1) .. ' in ' .. s.name
  local bw = UI.F.d22:getWidth(banner) + 40
  UI.plaque(x + (w - bw) / 2, y, bw, 34)
  UI.shadowText(banner, x + (w - bw) / 2 + 20, y + 5, UI.F.d22, C.text)
  -- speed row
  local sy = y + 40
  local speeds = { 0, 1, 3, 10 }
  local rowW = 4 * 32
  local sx = x + (w - rowW) / 2
  local sn = Sim.SEASONS[Sim.season()]
  local snW = UI.F.small:getWidth(sn)
  Art.draw('x.' .. sn:lower(), sx - snW - 30, sy, 20)
  UI.text(sn, sx - snW - 8, sy + 1, UI.F.small, C.muted)
  for k, sp in ipairs(speeds) do
    local bx = sx + (k - 1) * 32
    local hot = UI.hit('speed' .. sp, bx, sy, 30, 20, { click = function() s.speed = sp end, tip = function() return { { t = 'p', text = ({ [0] = 'Pause (Space)', [1] = 'Normal speed', [3] = 'Fast', [10] = 'Very fast' })[sp] } } end })
    UI.blue(bx, sy, 30, 20, s.speed == sp and 'on' or (hot and 'hot' or nil))
    speedIcon(sp, bx + 15, sy + 10)
  end
  UI.text(Sim.popTotal() .. ' people', sx + rowW + 10, sy + 1, UI.F.small, C.muted)
  -- tabs
  local ty = sy + 28
  -- tabs that do not fit on one line are split into rows of nearly equal length (4 and 4, not 7 and 1)
  local rows
  local function split(perRow)
    local out, row, rw = {}, {}, 0
    for k, t in ipairs(TABS) do
      local tw = UI.F.small:getWidth(t[2]) + 26
      if #row >= perRow then out[#out + 1] = { row, rw }; row, rw = {}, 0 end
      row[#row + 1] = { t, tw, k }; rw = rw + tw + 4
    end
    if #row > 0 then out[#out + 1] = { row, rw } end
    return out
  end
  for n = 1, #TABS do
    rows = split(math.ceil(#TABS / n))
    local fits = true
    for _, r in ipairs(rows) do if r[2] - 4 > w then fits = false end end
    if fits then break end
  end
  local researchDot, riteDot = false, false
  for _, t in ipairs(Sim.TECHS) do if not Sim.known(t.id) and Sim.reqMet(t) and Sim.payable(t.cost) then researchDot = true; break end end
  for _, r in ipairs(Sim.RITES) do if Sim.riteAvail(r) and Sim.riteReady(r) and Sim.payable(r.cost) then riteDot = true; break end end
  for _, rr in ipairs(rows) do
    local tx = x + (w - rr[2] + 4) / 2
    for _, it in ipairs(rr[1]) do
      local t, tw, k = it[1], it[2], it[3]
      local sel = Screens.tab == t[1]
      local hot = UI.hit('tab:' .. t[1], tx, ty, tw, 26, { click = function() Screens.setTab(t[1]) end, tip = function() return { { t = 'p', text = t[2] .. ' (key ' .. k .. ')' } } end })
      if sel then UI.vgrad(tx, ty, tw, 26, Art.color('#5b4b35'), Art.color('#2e251a')); UI.border(tx - 1, ty - 1, tw + 2, 28, C.black); UI.border(tx, ty, tw, 26, C.gold)
      else UI.plaque(tx, ty, tw, 26, hot) end
      UI.shadowText(t[2], tx + 13, ty + 4, UI.F.small, sel and { 1, 1, 1, 1 } or C.text)
      if (t[1] == 'research' and researchDot) or (t[1] == 'rites' and riteDot) then
        UI.setc(C.warn); lg.circle('fill', tx + tw - 7, ty + 13, 3, 10)
      end
      tx = tx + tw + 4
    end
    ty = ty + 30
  end
  return ty - y
end
local function drawLogo(x, y, w, h)
  local l1, l2 = 'Hearthfire', 'CHRONICLE'
  local f1, f2 = UI.F.d26, UI.F.d36
  local cy = y
  UI.shadowText(l1, x + (w - f1:getWidth(l1)) / 2, cy, f1, Art.color('#cfc6b4'))
  local spacing = 3
  local tw = f2:getWidth(l2) + spacing * (#l2 - 1)
  local cx = x + (w - tw) / 2
  for k = 1, #l2 do
    local ch = l2:sub(k, k)
    UI.shadowText(ch, cx, cy + 24, f2, Art.color('#b9ae98'))
    cx = cx + f2:getWidth(ch) + spacing
  end
  local era = Sim.era()
  lg.push()
  lg.translate(x + w - 12, cy + 64)
  lg.rotate(-.14)
  local ew = UI.F.bodyB:getWidth(era)
  UI.shadowText(era, -ew, -8, UI.F.bodyB, Art.color('#ffb55a'))
  lg.pop()
end
local function drawStrip(W)
  UI.vgrad(0, 0, W, 24, Art.color('#2b2b2b'), Art.color('#141414'))
  UI.rect(0, 23, W, 1, C.black)
  UI.text('Hearthfire Chronicle', 16, 4, UI.F.smallB, { 1, 1, 1, 1 })
  local tag = 'a tribe game in the style of NeverEnding Legacy'
  UI.text(tag, 16 + UI.F.smallB:getWidth('Hearthfire Chronicle') + 12, 4, UI.F.small, Art.color('#cccccc'))
  local hw = UI.F.smallB:getWidth('How to play') + 22
  local hx = W - 16 - hw
  local hot = UI.hit('helpBtn', hx, 2, hw, 20, { click = function() Screens.help = not Screens.help end })
  UI.blue(hx, 2, hw, 20, hot and 'hot' or nil)
  UI.text('How to play', hx + 11, 3, UI.F.smallB, { 1, 1, 1, 1 })
  local mw = UI.F.smallB:getWidth('Menu') + 22
  hx = hx - mw - 6
  local mh = UI.hit('menuBtn', hx, 2, mw, 20, { click = function() Screens.onTitle() end, tip = function() return { { t = 'p', text = 'Back to the title screen. Your tribe is saved and waits for you.' } } end })
  UI.blue(hx, 2, mw, 20, mh and 'hot' or nil)
  UI.text('Menu', hx + 11, 3, UI.F.smallB, { 1, 1, 1, 1 })
  local et = tostring(Legacy.D.embers)
  local ew = UI.F.smallB:getWidth(et) + 26
  hx = hx - ew - 10
  UI.hit('embers', hx, 2, ew, 20, { tip = function() return { { t = 'title', icon = 'x.ember', text = 'Embers: ' .. Legacy.D.embers }, { t = 'p', text = 'The legacy of your tribes. Earn embers from milestones and when a tribe\'s story ends; spend them on perks in the Legacy, from the title screen or the History tab.' } } end })
  Art.draw('x.ember', hx, 1, 22)
  UI.text(et, hx + 23, 3, UI.F.smallB, Art.color('#ffb55a'))
  local hint = 'Space pauses  \u{00b7}  1\u{2013}8 switch tabs'
  local hiw = UI.F.small:getWidth(hint)
  UI.text(hint, hx - hiw - 14, 4, UI.F.small, Art.color('#999999'))
  local since = love.timer.getTime() - Screens.saveNoteT
  if since < 2.4 then
    local a = since < 1.7 and 1 or (2.4 - since) / .7
    local sw = UI.F.small:getWidth('Game saved')
    UI.text('Game saved', hx - hiw - 30 - sw, 4, UI.F.small, C.good, a)
  end
end

---------------------------------------------------------------- overlays
local HELP = {
  { 'Give people work', 'The Production tab shows every job. Use the arrows to pick an action (Add 1, Add 10\u{2026}), then click a job or building; a right-click (or Ctrl-click on a Mac) does the opposite. Idle adults do nothing.' },
  { 'Food and water first', 'Gatherers bring in fruit and water. In the stores column a red border means something is running out. Hover any tile to see where it comes from and goes.' },
  { 'Explore the land', 'Every tile you know adds wild food, water and materials. Crowded land gives less to each worker, so keep a Wanderer exploring. See the Territory tab.' },
  { 'Make discoveries', 'Dreamers produce insight. Spend it in Research to unlock jobs, buildings, rites and policies. Later discoveries also need culture, faith or influence.' },
  { 'Build and grow', 'Clicking a building plans it and pays for it. Builders then raise it over some days; idle people lend a hand at half speed. Wonders are huge projects that change your tribe for good.' },
  { 'Survive winter', 'Every fourth season is winter. Food grows scarce and the cold kills. Stock up, build shelter, keep firekeepers burning sticks, and make clothing.' },
  { 'Health and the dead', 'Muddy water, raw meat, crowding and unburied bodies spread sickness. Build graves, find clean water, and train healers.' },
  { 'Keep people happy', 'Mood speeds up work and births. Hover the face in Essentials to see what helps and what hurts.' },
  { 'Rites, traits and policies', 'Rites are powers you call on, with a price and a rest time. Policies are choices you make. Traits emerge on their own from how your tribe lives.' },
  { 'Stories and legacy', 'Now and then the tribe faces a choice, and the game waits for you. When a tribe ends, or you retire it, it earns embers that buy lasting perks for every tribe after it.' },
}
local function overlayBox(W, H, bw, bh)
  UI.hit('overlay', 0, 0, W, H, {})
  UI.rect(0, 0, W, H, C.black, .78)
  local bx, by = (W - bw) / 2, (H - bh) / 2
  UI.panel(bx, by, bw, bh)
  return bx, by
end
Screens.overlayBox = overlayBox
local function centerButton(label, id, x, y, w, fn)
  local bw = UI.F.smallB:getWidth(label) + 34
  local bx = x + (w - bw) / 2
  local hot = UI.hit(id, bx, y, bw, 30, { click = fn })
  UI.blue(bx, y, bw, 30, hot and 'hot' or nil)
  UI.shadowText(label, bx + 17, y + 6, UI.F.smallB, { 1, 1, 1, 1 })
end
Screens.centerButton = centerButton
local function drawHelp(W, H)
  local bw = min(W - 40, 860)
  local colW = (bw - 60) / 2
  local lead = 'Guide a camp of nine people through hunger, winter and discovery until they become a civilization. The game never ends; how far you take your tribe is up to you, and so is the blame.'
  local leadH = UI.wrapH(lead, UI.F.body, bw - 80)
  local secH = 0
  local hs = {}
  for k, sct in ipairs(HELP) do hs[k] = 22 + UI.wrapH(sct[2], UI.F.small, colW) + 8 end
  for k = 1, #HELP, 2 do secH = secH + max(hs[k], hs[k + 1] or 0) end
  local bh = min(H - 30, 56 + leadH + 12 + secH + 66)
  local bx, by = overlayBox(W, H, bw, bh)
  UI.shadowText('How to play', bx + (bw - UI.F.d30:getWidth('How to play')) / 2, by + 12, UI.F.d30, C.gold)
  local cy = by + 52
  cy = cy + UI.para(lead, bx + 40, cy, bw - 80, UI.F.body, C.text, 'center', true) + 12
  for k = 1, #HELP, 2 do
    for j = 0, 1 do
      local sct = HELP[k + j]
      if sct then
        local sx = bx + 20 + j * (colW + 20)
        UI.shadowText(sct[1], sx, cy, UI.F.d18, C.gold)
        UI.para(sct[2], sx, cy + 22, colW, UI.F.small, C.text, nil, true)
      end
    end
    cy = cy + max(hs[k], hs[k + 1] or 0)
  end
  UI.para('Space pauses  \u{00b7}  1\u{2013}8 switch tabs  \u{00b7}  H opens this guide  \u{00b7}  the game saves itself', bx, by + bh - 62, bw, UI.F.tiny, C.muted, 'center')
  centerButton('Begin', 'helpClose', bx, by + bh - 42, bw, function() Screens.help = false end)
end
local function drawEnd(W, H, title, text, label, fn)
  local bw = min(W - 40, 520)
  local th = UI.wrapH(text, UI.F.body, bw - 60)
  local bh = 60 + th + 70
  local bx, by = overlayBox(W, H, bw, bh)
  UI.shadowText(title, bx + (bw - UI.F.d30:getWidth(title)) / 2, by + 16, UI.F.d30, C.gold)
  UI.para(text, bx + 30, by + 62, bw - 60, UI.F.body, C.text, 'center', true)
  centerButton(label, 'endBtn', bx, by + bh - 46, bw, fn)
end

-- A story event: the tribe faces a choice and the game waits.
Screens.storyResult = nil
local function choiceRows(ev, w)
  local rows = {}
  for k, c in ipairs(ev.choices) do
    local ok, why = Story.canChoose(c)
    local d = c.cost and c.d:gsub('^Costs [^.]*%.%s*', '') or c.d
    local items = { { text = d, col = C.muted } }
    if c.cost then
      items[#items + 1] = { text = '    ' }
      for _, it in ipairs(costItems(c.cost)) do items[#items + 1] = it end
    end
    if not ok and why then items[#items + 1] = { text = '  ' .. why, col = C.warn, font = UI.F.smallB } end
    local doc = { { t = 'p', text = k .. '.  ' .. c.t, font = UI.F.bodyB, col = ok and C.text or C.muted }, { t = 'flow', items = items } }
    rows[k] = { doc = doc, h = UI.docHeight(doc, w - 28) + 16, ok = ok }
  end
  return rows
end
function Screens.chooseStory(k)
  local ev = Story.current()
  if not ev or Screens.storyResult then return end
  local title, icon = ev.title, ev.icon
  local out = Story.choose(k)
  if out then Screens.storyResult = { title = title, icon = icon, text = out }; Screens.sfx('click') end
end
local function drawStory(W, H)
  local bw = min(W - 40, 640)
  local res = Screens.storyResult
  local ev = Story.current()
  if res then
    local th = UI.wrapH(res.text, UI.F.body, bw - 60)
    local bh = 84 + th + 64
    local bx, by = overlayBox(W, H, bw, bh)
    UI.tile(bx + 24, by + 18, 48, false)
    Art.draw(res.icon, bx + 28, by + 22, 40)
    UI.shadowText(res.title, bx + 86, by + 28, UI.F.d26, C.gold)
    UI.para(res.text, bx + 30, by + 80, bw - 60, UI.F.body, C.text, nil, true)
    centerButton('Continue', 'storyDone', bx, by + bh - 46, bw, function() Screens.storyResult = nil end)
    return
  end
  if not ev then return end
  local th = UI.wrapH(ev.text, UI.F.body, bw - 60)
  local rows = choiceRows(ev, bw - 48)
  local ch = 0
  for _, r in ipairs(rows) do ch = ch + r.h + 8 end
  local bh = 84 + th + 16 + ch + 30
  local bx, by = overlayBox(W, H, bw, bh)
  UI.tile(bx + 24, by + 18, 48, false)
  Art.draw(ev.icon, bx + 28, by + 22, 40)
  UI.shadowText(ev.title, bx + 86, by + 22, UI.F.d26, C.gold)
  UI.text(Sim.dateStr(S().day), bx + 88, by + 54, UI.F.tiny, C.muted)
  UI.para(ev.text, bx + 30, by + 82, bw - 60, UI.F.body, C.text, nil, true)
  local cy = by + 82 + th + 16
  for k, r in ipairs(rows) do
    local rx, rw = bx + 24, bw - 48
    local hot = UI.hit('story:' .. k, rx, cy, rw, r.h, { click = r.ok and function() Screens.chooseStory(k) end or nil, disabled = not r.ok })
    UI.plaque(rx, cy, rw, r.h, hot and r.ok)
    if hot and r.ok then UI.rect(rx + 1, cy + 1, rw - 2, r.h - 2, C.gold, .08) end
    UI.doc(r.doc, rx + 14, cy + 8, rw - 28)
    cy = cy + r.h + 8
  end
  UI.para('Press 1\u{2013}' .. #rows .. ' or click a choice. The game waits for you.', bx, by + bh - 24, bw, UI.F.tiny, C.muted, 'center')
end

-- Notices: short messages that rise from the bottom of the board for the moments that matter.
local TOASTC = { milestone = C.gold, wonder = C.gold, tech = C.insight, trait = C.culture, era = C.gold, bad = C.warn, built = C.good, story = C.faith }
function Screens.toast(text, icon, kind)
  table.insert(Screens.toasts, { text = text, icon = icon, kind = kind, t = 0 })
  while #Screens.toasts > 4 do table.remove(Screens.toasts, 1) end
end
local function drawToasts(x, bottom, w, dt)
  local keep = {}
  local cy = bottom
  for k = #Screens.toasts, 1, -1 do
    local t = Screens.toasts[k]
    t.t = t.t + dt
    if t.t < 6 then
      local a = min(1, t.t / .25, (6 - t.t) / .7)
      local font = UI.F.smallB
      local tw = min(w - 20, font:getWidth(t.text) + 62)
      local lines = UI.wrapH(t.text, font, tw - 56)
      local th = max(40, lines + 16)
      local tx = x + (w - tw) / 2
      cy = cy - th - 6
      local y = cy + (1 - min(1, t.t / .25)) * 16
      local col = TOASTC[t.kind] or C.frameHi
      UI.hit('toast:' .. tostring(t), tx, y, tw, th, { click = function() t.t = 5.4 end })
      UI.rect(tx, y + 2, tw, th, C.black, .5 * a, 6)
      UI.vgrad(tx, y, tw, th, { .23, .19, .14, .96 * a }, { .13, .1, .07, .96 * a })
      UI.border(tx, y, tw, th, col, a, 1, 6)
      Art.draw(t.icon or 'x.good', tx + 8, y + (th - 32) / 2, 32, a)
      UI.setc(C.text, a); UI.printf(font, t.text, UI.snap(tx + 48), UI.snap(y + (th - lines) / 2), tw - 56, 'left')
      table.insert(keep, 1, t)
    end
  end
  Screens.toasts = keep
end

---------------------------------------------------------------- frame
Screens.sfx = function() end
function Screens.setTab(t) Screens.tab = t end
function Screens.draw(dt)
  F = UI.F
  Screens.dt = dt
  local W, H = UI.W, UI.H
  local s = S()
  UI.beginFrame()
  do
    local cwPre = W - 32 - 236 - 296 - 16
    if Screens.tab == 'territory' then ensureMap(floor(cwPre - 6 - 24)) end
  end
  lg.push()
  lg.scale(UI.scale)
  UI.rect(0, 0, W, H, C.page)
  drawStrip(W)
  local pad, gap = 16, 8
  local leftW, rightW = 236, 296
  local cx = pad + leftW + gap
  local cw = W - pad * 2 - leftW - rightW - gap * 2
  local top = 32
  local headH = drawHeader(cx, top, cw)
  drawLogo(cx + cw + gap, top, rightW, headH)
  local colTop = top + headH + 4
  local colH = H - colTop - 10
  drawStores(pad, colTop, leftW, colH)
  UI.panel(cx, colTop, cw, colH)
  UI.pushClip(cx + 3, colTop + 3, cw - 6, colH - 6)
  local tab = Screens.tab
  if tab == 'production' then drawProduction(cx + 3, colTop + 3, cw - 6, colH - 6)
  elseif tab == 'territory' then drawTerritory(cx + 3, colTop + 3, cw - 6, colH - 6)
  elseif tab == 'policies' then drawPolicies(cx + 3, colTop + 3, cw - 6, colH - 6)
  elseif tab == 'traits' then drawTraits(cx + 3, colTop + 3, cw - 6, colH - 6)
  elseif tab == 'research' then drawResearch(cx + 3, colTop + 3, cw - 6, colH - 6)
  elseif tab == 'rites' then drawRites(cx + 3, colTop + 3, cw - 6, colH - 6)
  elseif tab == 'history' then drawHistory(cx + 3, colTop + 3, cw - 6, colH - 6)
  elseif tab == 'settings' then drawSettings(cx + 3, colTop + 3, cw - 6, colH - 6) end
  UI.popClip()
  drawChronicle(cx + cw + gap, colTop, rightW, colH)
  drawToasts(cx, colTop + colH - 8, cw, dt)
  UI.drawFloats(dt)
  -- overlays
  local function count(k, one, many) return k .. ' ' .. (k == 1 and one or many) end
  if s.over then
    local e = Screens.lastEmbers
    drawEnd(W, H, 'The fire goes out', 'The ' .. s.name .. ' tribe lasted until ' .. Sim.dateStr(s.day) .. '. ' .. count(s.born, 'was born', 'were born') .. ', ' .. s.deaths .. ' died, and '
      .. count(#s.techs, 'discovery was', 'discoveries were') .. ' made.'
      .. (e and ('\n\nIts story adds ' .. count(e, 'ember', 'embers') .. ' to your legacy.') or ''), 'Return to the fire', function() Screens.onTitle() end)
  elseif Sim.known('history') and not s.wonSeen then
    drawEnd(W, H, 'A civilization remembers', 'In year ' .. (floor(s.day / 100) + 1) .. ', the ' .. s.name .. ' tribe set its history down in writing. What began as a few people around a fire is now ' .. Sim.popTotal() .. ' strong, with '
      .. count(#s.techs, 'discovery', 'discoveries') .. ', ' .. count(#s.traits, 'custom', 'customs') .. ' of its own, ' .. count(s.born, 'birth', 'births') .. ' and ' .. count(s.deaths, 'death', 'deaths')
      .. ' remembered. The chronicle goes on as long as you want it to.', 'Keep playing', function() s.wonSeen = true end)
  elseif s.story or Screens.storyResult then drawStory(W, H)
  elseif Screens.help then drawHelp(W, H) end
  UI.endFrame()
  -- info box follows the hovered job or building
  local hh = UI.hotHit
  if hh and hh.opts.info then Screens.infoKey = hh.opts.info
  elseif not (hh and hh.id == 'infobox') then Screens.infoKey = nil end
  -- tooltip for whatever is under the mouse
  if hh and hh.opts.tip then
    local ok, doc = pcall(hh.opts.tip)
    if ok and doc then UI.tooltip(doc, hh.x, hh.y, hh.w, hh.h) end
  end
  lg.pop()
end
function Screens.overlayOpen() local s = S(); return Screens.help or s.over or (Sim.known('history') and not s.wonSeen) or s.story ~= nil or Screens.storyResult ~= nil end

return Screens
