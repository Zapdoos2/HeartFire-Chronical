-- Hearthfire Chronicle: the legacy that outlives each tribe.
-- Embers are earned from milestones and from every tribe's story when it ends. They buy perks that help all later tribes.
local json = require('json')
local Sim = require('sim')
local Legacy = {}
local floor, max, min = math.floor, math.max, math.min
local FILE = 'legacy.json'
Legacy.noSave = false

local function fresh() return { embers = 0, earned = 0, perks = {}, miles = {}, tribes = {}, founded = 0 } end
Legacy.D = fresh()

---------------------------------------------------------------- perks
local function mul(key, per) return function(l) return { { key, 'm', 1 + per * l } } end end
Legacy.PERKS = {
  { id = 'band', n = 'A larger band', icon = 'e.people', cost = { 4, 8, 14 }, d = 'Each new tribe starts with 2 more adults per level.' },
  { id = 'stores', n = 'Provisions', icon = 'x.food', cost = { 2, 5, 9 }, d = 'Each new tribe starts with 30 more fruit, water and sticks per level.' },
  { id = 'memory', n = 'Ancestral memory', icon = 'x.scroll', cost = { 6, 12 }, d = 'New tribes start knowing Language and Stone-knapping; at level 2, also Shelter and Fire-making.' },
  { id = 'songs', n = 'Old songs', icon = 'insight', cost = { 3, 6, 10 }, d = 'Insight +10% per level.', fx = mul('insight', .1) },
  { id = 'gather', n = 'Gathering lore', icon = 'u.gatherer', cost = { 3, 6, 10 }, d = 'Gatherers bring in 10% more per level.', fx = mul('u.gatherer', .1) },
  { id = 'paths', n = 'Pathfinders', icon = 'u.wanderer', cost = { 3, 7 }, d = 'Exploring +25% per level.', fx = mul('explore', .25) },
  { id = 'hands', n = 'Sturdy hands', icon = 'u.builder', cost = { 3, 7 }, d = 'Construction +25% per level.', fx = mul('build', .25) },
  { id = 'hardy', n = 'Hardy folk', icon = 'e.health', cost = { 4, 8 }, d = 'Sickness \u{2212}15% per level.', fx = function(l) return { { 'sick', 'm', .85 ^ l } } end },
  { id = 'kin', n = 'Kinship', icon = 'e.children', cost = { 4, 8 }, d = 'Births +15% per level.', fx = mul('birth', .15) },
  { id = 'keepers', n = 'Keepers of the flame', icon = 'fire', cost = { 4 }, d = 'Fire pits last 30% longer and the cold hurts 20% less.', fx = function() return { { 'firedecay', 'm', .7 }, { 'cold', 'm', .8 } } end },
  { id = 'lore', n = 'Storykeepers', icon = 'culture', cost = { 4, 8 }, d = 'Culture and faith +15% per level.', fx = function(l) return { { 'culture', 'm', 1 + .15 * l }, { 'faith', 'm', 1 + .15 * l } } end },
  { id = 'voice', n = 'A voice that carries', icon = 'influence', cost = { 5, 10 }, d = 'Influence +15% per level.', fx = mul('influence', .15) },
}
local PM = {}
for _, p in ipairs(Legacy.PERKS) do PM[p.id] = p end
Legacy.PM = PM
function Legacy.level(id) return Legacy.D.perks[id] or 0 end
function Legacy.nextCost(id) local p = PM[id]; local l = Legacy.level(id); return p.cost[l + 1] end
function Legacy.applyFX()
  local list = {}
  for _, p in ipairs(Legacy.PERKS) do
    local l = Legacy.level(p.id)
    if l > 0 and p.fx then for _, e in ipairs(p.fx(l)) do list[#list + 1] = e end end
  end
  Sim.perkFX = list
  if Sim.S then Sim.rebuildFX() end
end
function Legacy.buy(id)
  local c = Legacy.nextCost(id)
  if not c or Legacy.D.embers < c then return false end
  Legacy.D.embers = Legacy.D.embers - c
  Legacy.D.perks[id] = Legacy.level(id) + 1
  Legacy.applyFX(); Legacy.save()
  return true
end
-- Options for Sim.newGame that come from perks.
function Legacy.startOptions(name)
  local o = { name = name, gen = Legacy.D.founded + 1, adults = 2 * Legacy.level('band'), res = {}, techs = {} }
  local st = Legacy.level('stores')
  if st > 0 then o.res = { fruit = 30 * st, water = 30 * st, sticks = 30 * st } end
  local m = Legacy.level('memory')
  if m >= 1 then o.techs = { 'language', 'knapping' } end
  if m >= 2 then o.techs[#o.techs + 1] = 'shelter'; o.techs[#o.techs + 1] = 'fire' end
  return o
end

---------------------------------------------------------------- milestones
local function M(id, n, d, e, icon, check) return { id = id, n = n, d = d, e = e, icon = icon, check = check } end
Legacy.MILES = {
  M('idea1', 'The first idea', 'Make a discovery.', 1, 'insight', function(s) return #s.techs >= 1 end),
  M('idea10', 'Heads full of ideas', 'Know 10 discoveries.', 2, 'u.dreamer', function(s) return #s.techs >= 10 end),
  M('idea25', 'Keepers of knowledge', 'Know 25 discoveries.', 3, 'u.scholar', function(s) return #s.techs >= 25 end),
  M('ideaAll', 'Nothing left unknown', 'Make every discovery.', 5, 'b.library', function(s) return #s.techs >= #Sim.TECHS end),
  M('winter', 'Through the dark', 'Survive a first winter.', 1, 'x.winter', function(s) return s.day >= 100 end),
  M('year10', 'Ten summers', 'Reach year 10 with one tribe.', 2, 'x.summer', function(s) return s.day >= 900 end),
  M('year25', 'A long memory', 'Reach year 25 with one tribe.', 3, 'x.scroll', function(s) return s.day >= 2400 end),
  M('year50', 'Half a hundred years', 'Reach year 50 with one tribe.', 4, 'b.monument', function(s) return s.day >= 4900 end),
  M('pop25', 'A growing camp', 'Grow to 25 people.', 1, 'e.people', function(s) return s.peak >= 25 end),
  M('pop50', 'A village', 'Grow to 50 people.', 2, 'b.hut', function(s) return s.peak >= 50 end),
  M('pop100', 'A town', 'Grow to 100 people.', 3, 'b.house', function(s) return s.peak >= 100 end),
  M('pop250', 'A city', 'Grow to 250 people.', 5, 'b.aqueduct', function(s) return s.peak >= 250 end),
  M('built1', 'Raised by hand', 'Finish a building.', 1, 'u.builder', function(s) return (s.built or 0) >= 1 end),
  M('wonder1', 'A wonder of the world', 'Finish a wonder.', 3, 'b.hearth', function() return Sim.wondersBuilt() >= 1 end),
  M('wonder3', 'Builders of wonders', 'Finish 3 wonders with one tribe.', 4, 'b.totem', function() return Sim.wondersBuilt() >= 3 end),
  M('wonderAll', 'Nothing is impossible', 'Finish every wonder with one tribe.', 6, 'b.colossus', function() return Sim.wondersBuilt() >= 7 end),
  M('land50', 'Wide horizons', 'Explore 50 tiles.', 2, 'e.land', function(s) return s.explored >= 50 end),
  M('land150', 'The known world', 'Explore 150 tiles.', 3, 'ri.expedition', function(s) return s.explored >= 150 end),
  M('custom5', 'A way of life', 'Have 5 customs at once.', 2, 'culture', function(s) return #s.traits >= 5 end),
  M('custom12', 'A people apart', 'Have 12 customs at once.', 3, 'ri.festival', function(s) return #s.traits >= 12 end),
  M('rites10', 'Keepers of rites', 'Perform 10 rites.', 1, 'faith', function(s) return (s.ritesDone or 0) >= 10 end),
  M('tales10', 'Many tales to tell', 'Face 10 story events.', 2, 'u.storyteller', function(s) return (s.storiesDone or 0) >= 10 end),
  M('joy', 'Joy around the fire', 'Reach a mood of 60%.', 2, 'mood4', function(s) return s.happy >= 60 end),
  M('history', 'A civilization remembers', 'Discover Written history.', 5, 'x.medal', function() return Sim.known('history') end),
  M('lineage', 'A long line', 'Found 3 tribes.', 2, 'x.ember', function() return Legacy.D.founded >= 3 end),
}
function Legacy.milesDone() local k = 0; for _, m in ipairs(Legacy.MILES) do if Legacy.D.miles[m.id] then k = k + 1 end end; return k end
-- Called every day and after loading: awards milestones the current tribe has reached.
function Legacy.check()
  local s = Sim.S
  if not s or s.over then return end
  local any = false
  for _, m in ipairs(Legacy.MILES) do
    if not Legacy.D.miles[m.id] then
      local ok, yes = pcall(m.check, s)
      if ok and yes then
        Legacy.D.miles[m.id] = { tribe = s.name, day = s.day }
        Legacy.D.embers = Legacy.D.embers + m.e; Legacy.D.earned = Legacy.D.earned + m.e
        Sim.logm('Milestone: ' .. m.n .. '. ' .. m.d .. ' (+' .. m.e .. (m.e == 1 and ' ember' or ' embers') .. ' for your legacy)', 'era', m.icon)
        Sim.emit('milestone', m)
        any = true
      end
    end
  end
  if any then Legacy.save() end
end

---------------------------------------------------------------- the end of a tribe
function Legacy.score(s)
  local years = floor(s.day / 100)
  local parts = {
    { 'Discoveries', floor(#s.techs / 3) },
    { 'Most people at once', floor((s.peak or 0) / 15) },
    { 'Years lived', floor(years / 3) },
    { 'Wonders', 2 * Sim.wondersBuilt() },
  }
  if Sim.known('history') then parts[#parts + 1] = { 'A civilization', 5 } end
  local total = 0
  for _, p in ipairs(parts) do total = total + p[2] end
  return total, parts
end
local function spark(list, k)
  local out = {}
  if #list == 0 then return out end
  for i = 1, k do out[i] = list[max(1, min(#list, floor((i - 1) / max(1, k - 1) * (#list - 1) + 1.5)))] end
  return out
end
-- Records the current tribe in the legacy (once) and returns the embers it earned.
function Legacy.endTribe(reason)
  local s = Sim.S
  if not s or s.legacyDone then return 0 end
  local e = Legacy.score(s)
  s.legacyDone = true
  local D = Legacy.D
  D.embers = D.embers + e; D.earned = D.earned + e
  table.insert(D.tribes, 1, { name = s.name, gen = s.gen or 1, day = s.day, peak = s.peak or Sim.popTotal(), techs = #s.techs, traits = #s.traits, wonders = Sim.wondersBuilt(),
    born = s.born, deaths = s.deaths, era = Sim.era(), reason = reason, embers = e, spark = spark(s.hist and s.hist.pop or {}, 40) })
  while #D.tribes > 40 do table.remove(D.tribes) end
  Legacy.save()
  return e
end
function Legacy.founded() Legacy.D.founded = Legacy.D.founded + 1; Legacy.save() end

---------------------------------------------------------------- saving
function Legacy.load()
  Legacy.D = fresh()
  if love.filesystem.getInfo(FILE) then
    local d = json.decode(love.filesystem.read(FILE) or '')
    if type(d) == 'table' then
      local D = Legacy.D
      D.embers = max(0, floor(tonumber(d.embers) or 0)); D.earned = max(0, floor(tonumber(d.earned) or 0)); D.founded = max(0, floor(tonumber(d.founded) or 0))
      if type(d.perks) == 'table' then for id, l in pairs(d.perks) do if PM[id] then D.perks[id] = min(#PM[id].cost, max(0, floor(tonumber(l) or 0))) end end end
      if type(d.miles) == 'table' then for id, v in pairs(d.miles) do D.miles[id] = v end end
      if type(d.tribes) == 'table' then for _, t in ipairs(d.tribes) do if type(t) == 'table' then D.tribes[#D.tribes + 1] = t end end end
    end
  end
  Legacy.applyFX()
end
function Legacy.save()
  if Legacy.noSave then return end
  love.filesystem.write(FILE, json.encode(Legacy.D))
end

return Legacy
