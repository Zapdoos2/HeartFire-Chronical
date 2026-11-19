-- Hearthfire Chronicle: the rules of the world.
-- Data tables, game state, map generation, the daily simulation, events and player actions.
local Sim = {}
local S              -- current game state (see fresh())
local FX = {}        -- active modifiers: key -> {m = multiplier, a = additive}
Sim.FLOW = {}        -- smoothed per-day sources and sinks of each resource
Sim.logDirty, Sim.mapDirty = true, true

local floor, max, min, abs, exp, sqrt = math.floor, math.max, math.min, math.abs, math.exp, math.sqrt
local function rand() return love.math.random() end
local flavorRng = love.math.newRandomGenerator(os.time())
local function pick(list) return list[flavorRng:random(1, #list)] end
Sim.pickFlavor = pick
local function clamp(x, a, b) return max(a, min(b, x)) end
local function sr(x) if not (x > 0) then return 0 end local f = floor(x); return f + ((rand() < x - f) and 1 or 0) end
Sim.clamp, Sim.sr = clamp, sr

local function fmt(n)
  if n ~= n then return '0' end
  if n == math.huge then return '∞' end
  local a = abs(n)
  if a < 10 then return tostring(floor(n * 10 + .5) / 10):gsub('%.0$', '') end
  if a < 1e4 then
    local s = tostring(floor(n + .5))
    local k
    repeat s, k = s:gsub('^(-?%d+)(%d%d%d)', '%1,%2') until k == 0
    return s
  end
  local units = { '', 'K', 'M', 'B', 'T' }
  local e = min(4, floor(math.log10(a) / 3))
  return string.format('%.1f%s', n / 1000 ^ e, units[e + 1])
end
Sim.fmt = fmt
function Sim.fmtD(n)
  if abs(n) < .005 then return '0' end
  local s = abs(n) < 10 and string.format('%.2f', abs(n)) or fmt(abs(n))
  return (n > 0 and '+' or '\u{2212}') .. s
end

---------------------------------------------------------------- resources
Sim.RKEYS = { 'fruit', 'meat', 'fish', 'cooked', 'grain', 'bread', 'water', 'muddy', 'sticks', 'wood', 'stone', 'clay', 'herbs', 'fiber', 'bones', 'hides', 'ore',
  'tools', 'clothing', 'pottery', 'bricks', 'metal', 'fire', 'corpses', 'insight', 'culture', 'faith', 'influence' }
local R = {
  fruit = { n = 'Berries & fruit', c = 'food', spoil = .01 }, meat = { n = 'Raw meat', c = 'food', spoil = .02, raw = true },
  fish = { n = 'Raw fish', c = 'food', spoil = .02, raw = true }, cooked = { n = 'Cooked food', c = 'food', spoil = .005 },
  grain = { n = 'Grain', c = 'food', spoil = .001 }, bread = { n = 'Bread', c = 'food', spoil = .004 },
  water = { n = 'Fresh water', c = 'water' }, muddy = { n = 'Muddy water', c = 'water' },
  sticks = { n = 'Sticks', c = 'mat' }, wood = { n = 'Logs', c = 'mat' }, stone = { n = 'Stone', c = 'mat' }, clay = { n = 'Clay', c = 'mat' },
  herbs = { n = 'Herbs', c = 'mat' }, fiber = { n = 'Plant fiber', c = 'mat' }, bones = { n = 'Bones', c = 'mat' }, hides = { n = 'Hides', c = 'mat' },
  ore = { n = 'Metal ore', c = 'mat' }, tools = { n = 'Tools', c = 'goods' }, clothing = { n = 'Clothing', c = 'goods' }, pottery = { n = 'Pottery', c = 'goods' },
  bricks = { n = 'Bricks', c = 'goods' }, metal = { n = 'Metal bars', c = 'goods' }, fire = { n = 'Fire pits', c = 'other' }, corpses = { n = 'Unburied dead', c = 'other' },
  insight = { n = 'Insight', c = 'ess' }, culture = { n = 'Culture', c = 'ess' }, faith = { n = 'Faith', c = 'ess' }, influence = { n = 'Influence', c = 'ess' },
}
Sim.R = R
local FOODS = { 'fruit', 'meat', 'fish', 'cooked', 'grain', 'bread' }
Sim.FOODS = FOODS

---------------------------------------------------------------- land
local MW, MH = 22, 14
Sim.MW, Sim.MH, Sim.N = MW, MH, MW * MH
local BIOME = {
  ocean = { n = 'Ocean', col = '#1d3b57', y = { fish = 3 } },
  coast = { n = 'Beach', col = '#c4ad78', y = { fish = 4, fruit = .6, stone = .6, sticks = .4, muddy = .3 } },
  grass = { n = 'Grassland', col = '#7c9b4a', y = { fruit = 3, water = 1.5, muddy = .5, sticks = .6, herbs = .4, stone = .3, game = 2.5, fiber = .8, farm = 4 } },
  forest = { n = 'Forest', col = '#3f6b3a', y = { fruit = 2.2, sticks = 2.2, wood = 4, game = 3, herbs = .7, water = 1.2, muddy = .4, fiber = .4 } },
  jungle = { n = 'Jungle', col = '#2a7a52', y = { fruit = 4, herbs = 1.2, wood = 3, game = 2, water = 2, muddy = .6, fiber = .6, sticks = 1.2 } },
  hills = { n = 'Hills', col = '#8b7a52', y = { stone = 2, clay = .6, ore = 1, game = 1.2, sticks = .4, fruit = 1, water = 1, muddy = .2, farm = 1.5 } },
  mountain = { n = 'Mountains', col = '#7a756d', y = { stone = 3.5, ore = 2, water = .8 } },
  river = { n = 'River', col = '#4c8fbb', y = { water = 6, fish = 3, clay = 2, fruit = 2, farm = 6, sticks = .5, herbs = .5, fiber = .7, game = 1.5 } },
  lake = { n = 'Lake', col = '#3a76a6', y = { water = 7, fish = 4, clay = 1.2 } },
  desert = { n = 'Desert', col = '#d0b16a', y = { stone = 1.2, fruit = .3, game = .4, water = .2 } },
  swamp = { n = 'Marsh', col = '#56693f', y = { clay = 3, herbs = 1.6, fish = 1, muddy = 2.5, fiber = 1.2, game = 1 } },
  tundra = { n = 'Tundra', col = '#a5ae9f', y = { game = 1.6, stone = .6, water = .5, muddy = .5, herbs = .2 } },
}
Sim.BIOME = BIOME
Sim.LANDKEYS = { 'fruit', 'water', 'muddy', 'sticks', 'wood', 'stone', 'clay', 'herbs', 'game', 'fish', 'ore', 'fiber', 'farm' }
Sim.LAND = { fruit = 'Wild fruit', water = 'Fresh water', muddy = 'Muddy water', sticks = 'Fallen sticks', wood = 'Timber', stone = 'Loose stone', clay = 'Clay beds',
  herbs = 'Wild herbs', game = 'Game animals', fish = 'Fish', ore = 'Ore veins', fiber = 'Fibrous plants', farm = 'Arable soil' }
local LANDRES = { fruit = 'fruit', water = 'water', sticks = 'sticks', wood = 'wood', stone = 'stone', clay = 'clay', herbs = 'herbs', game = 'meat', fish = 'fish', ore = 'ore', fiber = 'fiber', farm = 'grain' }
local SEAS = { fruit = { 1, 1.15, 1.3, .55 }, herbs = { 1, 1.1, 1, .3 }, farm = { .7, 1.1, 1.7, 0 }, game = { 1, 1, 1.1, .75 }, fish = { 1, 1.1, 1, .7 }, fiber = { 1, 1.1, 1, .4 } }
local SEASONS = { 'Spring', 'Summer', 'Autumn', 'Winter' }
local YEAR = 100
Sim.SEASONS, Sim.YEAR = SEASONS, YEAR

---------------------------------------------------------------- jobs
local n, bld, known, popTotal  -- forward declarations for data closures
local UNITS = {
  { id = 'gatherer', n = 'Gatherer', d = 'Forages the land for fruit, water, sticks, stone, herbs and fiber.',
    prod = { { 'fruit', 2, 'fruit' }, { 'water', 2, 'water' }, { 'sticks', .45, 'sticks' }, { 'stone', .15, 'stone' }, { 'herbs', .12, 'herbs' }, { 'fiber', .1, 'fiber' } } },
  { id = 'dreamer', n = 'Dreamer', d = 'Stares at the sky and has ideas. Produces insight.', prod = { { 'insight', .3 } } },
  { id = 'wanderer', n = 'Wanderer', d = 'Roams outward and slowly discovers new land.', explore = .03 },
  { id = 'builder', n = 'Builder', tech = 'shelter', d = 'Raises new buildings. Each builder does a day of construction work per day; idle people lend a hand at half speed.', special = 'build' },
  { id = 'knapper', n = 'Knapper', tech = 'knapping', d = 'Chips stone into simple tools. Many jobs need a tool per worker.', rin = { stone = 1, sticks = .5 }, rout = { tools = .35 } },
  { id = 'firekeeper', n = 'Firekeeper', tech = 'fire', d = 'Burns sticks into fire pits, which warm the tribe in winter and cook raw meat and fish.', special = 'fire' },
  { id = 'hunter', n = 'Hunter', tech = 'hunting', tools = true, risk = .0015, d = 'Hunts game for meat, bones and hides. A dangerous trade.', prod = { { 'meat', 2.2, 'game' }, { 'bones', .4, 'game' }, { 'hides', .35, 'game' } } },
  { id = 'fisher', n = 'Fisher', tech = 'fishing', tools = true, d = 'Catches fish from rivers, lakes and coasts.', prod = { { 'fish', 2.1, 'fish' } } },
  { id = 'digger', n = 'Digger', tech = 'digging', tools = true, d = 'Digs up clay and stone.', prod = { { 'clay', .8, 'clay' }, { 'stone', .7, 'stone' } } },
  { id = 'woodcutter', n = 'Woodcutter', tech = 'woodcutting', tools = true, d = 'Fells trees for logs.', prod = { { 'wood', 1.3, 'wood' }, { 'sticks', .3, 'sticks' } } },
  { id = 'healer', n = 'Healer', tech = 'healing', d = 'Uses herbs to cure the sick.', special = 'heal' },
  { id = 'storyteller', n = 'Storyteller', tech = 'oral', d = 'Keeps the tales of the tribe. Produces culture.', prod = { { 'culture', .15 } } },
  { id = 'soothsayer', n = 'Soothsayer', tech = 'ritualism', d = 'Reads omens and leads prayers. Produces faith.', prod = { { 'faith', .15 } } },
  { id = 'chieftain', n = 'Chieftain', tech = 'chieftains', d = 'Leads the tribe. Produces influence. One per 25 people.', prod = { { 'influence', .15 } },
    max = function() return 1 + floor(popTotal() / 25) + (known('law') and 2 or 0) end },
  { id = 'scout', n = 'Scout', tech = 'scouting', d = 'Explores land far faster than wanderers.', explore = .12 },
  { id = 'tailor', n = 'Tailor', tech = 'sewing', tools = true, d = 'Sews hides into clothing, which keeps people warm.', rin = { hides = .6 }, rout = { clothing = .35 } },
  { id = 'potter', n = 'Potter', tech = 'pottery', d = 'Shapes and fires clay into pottery.', rin = { clay = 1, fire = .02 }, rout = { pottery = .45 } },
  { id = 'weaver', n = 'Weaver', tech = 'weaving', d = 'Weaves plant fiber into clothing.', rin = { fiber = 1 }, rout = { clothing = .4 } },
  { id = 'farmer', n = 'Farmer', tech = 'agriculture', tools = true, d = 'Grows grain on arable land. Nothing grows in winter.', prod = { { 'grain', 3.2, 'farm' } } },
  { id = 'herder', n = 'Herder', tech = 'husbandry', d = 'Tends flocks for meat, hides and wool.', prod = { { 'meat', 1.3 }, { 'hides', .3 }, { 'fiber', .5 } } },
  { id = 'baker', n = 'Baker', tech = 'baking', d = 'Turns grain into bread, a hearty food.', rin = { grain = 2, fire = .01 }, rout = { bread = 2.4 } },
  { id = 'mason', n = 'Mason', tech = 'masonry', d = 'Fires clay into bricks.', rin = { clay = 1, fire = .02 }, rout = { bricks = .6 } },
  { id = 'miner', n = 'Miner', tech = 'mining', tools = true, d = 'Mines ore and stone from hills and mountains.', prod = { { 'ore', .7, 'ore' }, { 'stone', 1, 'stone' } } },
  { id = 'smith', n = 'Smelter', tech = 'smelting', d = 'Smelts ore into metal bars using logs as fuel.', rin = { ore = 1, wood = .6 }, rout = { metal = .35 } },
  { id = 'toolsmith', n = 'Toolsmith', tech = 'metalTools', d = 'Forges sturdy metal tools.', rin = { metal = .3, wood = .2 }, rout = { tools = .7 } },
  { id = 'guard', n = 'Guard', tech = 'defense', tools = true, d = 'Protects the tribe from beasts and raiders.', special = 'guard' },
  { id = 'scholar', n = 'Scholar', tech = 'writing', d = 'Studies and records. Produces insight. 5 per library.', prod = { { 'insight', .45 } }, max = function() return 5 * bld('library') end },
  { id = 'priest', n = 'Priest', tech = 'religion', d = 'Tends the temple. Produces faith. 5 per temple.', prod = { { 'faith', .45 } }, max = function() return 5 * bld('temple') end },
  { id = 'merchant', n = 'Merchant', tech = 'trade', d = 'Trades with distant peoples. Produces influence. 4 per market.', prod = { { 'influence', .2 } }, max = function() return 4 * bld('market') end },
}
local UM = {}
for _, u in ipairs(UNITS) do UM[u.id] = u end
Sim.UNITS, Sim.UM = UNITS, UM
-- the ingredient order matters for display, so recipes keep an ordered key list too
local RECIPE_ORDER = { 'stone', 'sticks', 'hides', 'clay', 'fiber', 'grain', 'ore', 'metal', 'wood', 'fire', 'tools', 'clothing', 'pottery', 'bread', 'bricks' }
local function orderedKeys(t)
  local out = {}
  for _, k in ipairs(RECIPE_ORDER) do if t[k] then out[#out + 1] = k end end
  for k in pairs(t) do local found = false; for _, o in ipairs(out) do if o == k then found = true end end; if not found then out[#out + 1] = k end end
  return out
end
Sim.orderedKeys = orderedKeys

---------------------------------------------------------------- buildings
local BLDS = {
  { id = 'leanto', n = 'Lean-to', tech = 'shelter', cost = { sticks = 15 }, work = 3, house = 3, d = 'A rough shelter of branches. Houses 3.' },
  { id = 'mudhut', n = 'Mud shelter', tech = 'building', cost = { clay = 25, sticks = 10 }, work = 6, house = 5, d = 'Packed mud walls. Houses 5.' },
  { id = 'hut', n = 'Hut', tech = 'building', cost = { wood = 30, stone = 20, hides = 4 }, work = 10, house = 6, d = 'A sturdy wooden hut. Houses 6.' },
  { id = 'house', n = 'House', tech = 'carpentry', cost = { wood = 60, bricks = 40 }, work = 18, house = 10, d = 'A proper home. Houses 10.' },
  { id = 'stockpile', n = 'Stockpile', tech = 'stockpiling', cost = { sticks = 20, stone = 10 }, work = 4, d = '+250 storage for materials and goods, +60 for each food.' },
  { id = 'grave', n = 'Grave', tech = 'digging', cost = { sticks = 5 }, work = 1.5, d = 'Holds 10 of the dead; old plots free up over time. Unburied bodies spread sickness and grief.' },
  { id = 'shrine', n = 'Shrine', tech = 'ritualism', cost = { stone = 30, sticks = 20 }, work = 8, d = '+0.1 faith per day. Lifts the mood a little.' },
  { id = 'circle', n = 'Story circle', tech = 'oral', cost = { stone = 20, wood = 10 }, work = 6, d = '+0.1 culture per day. Lifts the mood a little.' },
  { id = 'herbgarden', n = 'Herb garden', tech = 'healing', cost = { clay = 10, sticks = 20 }, work = 5, d = '+0.8 herbs per day.' },
  { id = 'granary', n = 'Granary', pl = 'granaries', tech = 'pottery', cost = { wood = 40, pottery = 10, clay = 20 }, work = 14, d = '+400 storage for each food. Food spoils 25% slower (stacks to 75%).' },
  { id = 'well', n = 'Well', tech = 'wells', cost = { stone = 40 }, work = 12, d = '+5 fresh water per day and +100 water storage.' },
  { id = 'warehouse', n = 'Warehouse', tech = 'masonry', cost = { bricks = 60, wood = 40 }, work = 22, d = '+1500 storage for materials and goods.' },
  { id = 'palisade', n = 'Palisade', tech = 'defense', cost = { wood = 100 }, work = 18, d = '+6 defense against beasts and raiders.' },
  { id = 'library', n = 'Library', pl = 'libraries', tech = 'writing', cost = { bricks = 50, wood = 50, pottery = 10 }, work = 30, d = '+0.3 insight per day. Room for 5 scholars.' },
  { id = 'temple', n = 'Temple', tech = 'religion', cost = { bricks = 120, stone = 100 }, work = 45, d = '+0.4 faith per day. Room for 5 priests. Lifts the mood.' },
  { id = 'market', n = 'Market', tech = 'trade', cost = { wood = 80, bricks = 40 }, work = 28, d = '+0.2 influence per day. Room for 4 merchants.' },
  { id = 'monument', n = 'Monument', tech = 'architecture', cost = { stone = 500, bricks = 300 }, work = 110, d = '+0.8 culture per day. Greatly lifts the mood.' },
  { id = 'aqueduct', n = 'Aqueduct', tech = 'cityPlanning', cost = { bricks = 200, stone = 200 }, work = 90, d = '+25 fresh water per day.' },
  -- wonders: one of each, slow to raise, and they change the tribe for good
  { id = 'hearth', n = 'Eternal Hearth', wonder = true, tech = 'building', cost = { stone = 150, wood = 100, clay = 60 }, work = 60,
    fx = { { 'firedecay', 'm', .5 }, { 'cold', 'm', .6 }, { 'happy', 'a', 4 } }, d = 'A great ring of stone around a fire that is never allowed to die. Fire pits last twice as long, the cold hurts 40% less, and mood +4.' },
  { id = 'totem', n = 'Great Totem', wonder = true, tech = 'chieftains', cost = { wood = 220, hides = 30, culture = 40 }, work = 80,
    fx = { { 'culture', 'm', 1.25 }, { 'influence', 'm', 1.2 }, { 'happy', 'a', 4 } }, d = 'A carved pole taller than ten people, one face for every family. Culture +25%, influence +20%, mood +4.' },
  { id = 'stones', n = 'Sky Stones', wonder = true, tech = 'astronomy', cost = { stone = 800, faith = 60 }, work = 160,
    fx = { { 'insight', 'm', 1.15 }, { 'faith', 'm', 1.3 }, { 'u.farmer', 'm', 1.1 } }, d = 'A ring of standing stones that marks the turning of the year. Insight +15%, faith +30%, farmers +10%.' },
  { id = 'gardens', n = 'Terraced Gardens', wonder = true, tech = 'irrigation', cost = { bricks = 300, clay = 300, wood = 200 }, work = 200,
    fx = { { 'g.fruit', 'm', 1.4 }, { 'g.herbs', 'm', 1.4 }, { 'birth', 'm', 1.15 }, { 'happy', 'a', 8 } }, d = 'Hillsides of watered steps, green all summer. Gathered fruit and herbs +40%, births +15%, mood +8.' },
  { id = 'archive', n = 'Hall of Memory', wonder = true, tech = 'mathematics', cost = { bricks = 500, pottery = 120, wood = 300 }, work = 260,
    fx = { { 'insight', 'm', 1.3 }, { 'u.scholar', 'm', 1.25 }, { 'culture', 'm', 1.15 } }, d = 'A domed hall where every tablet and tale is kept. Insight +30%, scholars +25%, culture +15%.' },
  { id = 'wall', n = 'Long Wall', wonder = true, tech = 'architecture', cost = { stone = 1200, bricks = 400 }, work = 320,
    fx = { { 'defense', 'a', 60 }, { 'happy', 'a', 3 } }, d = 'A wall of fitted stone around the whole settlement. Defense +60, mood +3.' },
  { id = 'colossus', n = 'Bronze Giant', wonder = true, tech = 'ironWorking', cost = { metal = 250, bricks = 300, stone = 500 }, work = 360,
    fx = { { 'all', 'm', 1.1 }, { 'influence', 'm', 1.5 }, { 'migrants', 'm', 2 } }, d = 'A towering figure of cast metal holding a flame over the harbour. All production +10%, influence +50%, newcomers twice as likely.' },
}
local BM = {}
for _, b in ipairs(BLDS) do BM[b.id] = b end
Sim.BLDS, Sim.BM = BLDS, BM

---------------------------------------------------------------- discoveries
local function T(id, nm, cost, req, d, fx) return { id = id, n = nm, cost = cost, req = req, d = d, fx = fx or {} } end
local TECHS = {
  T('language', 'Language', { insight = 10 }, {}, 'Words for things. Insight +20%.', { { 'insight', 'm', 1.2 } }),
  T('knapping', 'Stone-knapping', { insight = 12 }, {}, 'Unlocks Knappers, who make tools.'),
  T('shelter', 'Shelter', { insight = 15 }, {}, 'Unlocks the Lean-to and Builders.'),
  T('fire', 'Fire-making', { insight = 25 }, { 'knapping' }, 'Unlocks Firekeepers and the Bonfire Night rite. Fire warms and cooks.'),
  T('hunting', 'Hunting', { insight = 30 }, { 'knapping' }, 'Unlocks Hunters and the Great Hunt rite.'),
  T('fishing', 'Fishing', { insight = 30 }, { 'knapping' }, 'Unlocks Fishers.'),
  T('herbalism', 'Herbalism', { insight = 20 }, { 'language' }, 'Gatherers find 50% more herbs.', { { 'g.herbs', 'm', 1.5 } }),
  T('digging', 'Digging', { insight = 30 }, { 'knapping' }, 'Unlocks Diggers and graves.'),
  T('woodcutting', 'Woodcutting', { insight = 40 }, { 'knapping' }, 'Unlocks Woodcutters.'),
  T('stockpiling', 'Stockpiling', { insight = 30 }, { 'shelter' }, 'Unlocks the Stockpile.'),
  T('oral', 'Oral tradition', { insight = 40 }, { 'language' }, 'Unlocks Storytellers, the Story circle, and the Festival and Work Song rites.'),
  T('ritualism', 'Ritualism', { insight = 40 }, { 'language' }, 'Unlocks Soothsayers, the Shrine, and the Rain Dance and Vision Quest rites.'),
  T('scouting', 'Scouting', { insight = 50 }, { 'language' }, 'Unlocks Scouts and the Expedition rite.'),
  T('healing', 'Healing', { insight = 50 }, { 'herbalism' }, 'Unlocks Healers, the Herb garden and the Healing Rite.'),
  T('sewing', 'Sewing', { insight = 50 }, { 'hunting' }, 'Unlocks Tailors.'),
  T('spears', 'Spears', { insight = 60 }, { 'hunting' }, 'Hunters +50%, and half as many hunting accidents.', { { 'u.hunter', 'm', 1.5 }, { 'huntRisk', 'm', .5 } }),
  T('building', 'Building', { insight = 70, culture = 5 }, { 'woodcutting', 'digging', 'shelter' }, 'Unlocks Mud shelters and Huts.'),
  T('chieftains', 'Chieftains', { insight = 60, culture = 10 }, { 'oral' }, 'Unlocks Chieftains, policies that cost influence, and the Council of Elders rite.'),
  T('burial', 'Burial rites', { insight = 40, faith = 10 }, { 'ritualism', 'digging' }, 'Grief from deaths is halved. Unlocks the Ancestral Blessing rite.', { { 'grief', 'm', .5 } }),
  T('pottery', 'Pottery', { insight = 80 }, { 'fire', 'digging' }, 'Unlocks Potters and the Granary.'),
  T('wells', 'Well-digging', { insight = 80 }, { 'digging' }, 'Unlocks the Well.'),
  T('canoes', 'Canoes', { insight = 90 }, { 'woodcutting', 'fishing' }, 'Fishers +40%. Explorers can cross open water.', { { 'u.fisher', 'm', 1.4 } }),
  T('weaving', 'Weaving', { insight = 100 }, { 'sewing' }, 'Unlocks Weavers.'),
  T('agriculture', 'Agriculture', { insight = 160, culture = 20 }, { 'pottery' }, 'Unlocks Farmers and the Harvest Moon rite.'),
  T('husbandry', 'Animal husbandry', { insight = 150 }, { 'agriculture', 'spears' }, 'Unlocks Herders.'),
  T('masonry', 'Masonry', { insight = 160 }, { 'building' }, 'Unlocks Masons and the Warehouse.'),
  T('baking', 'Baking', { insight = 130 }, { 'agriculture' }, 'Unlocks Bakers.'),
  T('astronomy', 'Astronomy', { insight = 200, faith = 20 }, { 'ritualism', 'agriculture' }, 'Farmers +20%, insight +10%.', { { 'u.farmer', 'm', 1.2 }, { 'insight', 'm', 1.1 } }),
  T('carpentry', 'Carpentry', { insight = 200 }, { 'building' }, 'Woodcutters +25%. Unlocks the House.', { { 'u.woodcutter', 'm', 1.25 } }),
  T('defense', 'Warrior code', { insight = 180, influence = 10 }, { 'spears', 'chieftains' }, 'Unlocks Guards, the Palisade and the Call to Arms rite.'),
  T('writing', 'Writing', { insight = 260, culture = 30 }, { 'oral', 'pottery' }, 'Unlocks Scholars and the Library.'),
  T('mining', 'Mining', { insight = 220 }, { 'masonry' }, 'Unlocks Miners.'),
  T('irrigation', 'Irrigation', { insight = 350 }, { 'agriculture', 'wells' }, 'Farmers +50%.', { { 'u.farmer', 'm', 1.5 } }),
  T('smelting', 'Smelting', { insight = 320 }, { 'mining', 'pottery' }, 'Unlocks Smelters.'),
  T('medicine', 'Medicine', { insight = 320 }, { 'healing', 'writing' }, 'Healers twice as effective, and 40% less sickness.', { { 'u.healer', 'm', 2 }, { 'sick', 'm', .6 } }),
  T('religion', 'Organized religion', { insight = 300, faith = 60 }, { 'writing', 'burial' }, 'Unlocks Priests, the Temple and the Pilgrimage rite.'),
  T('trade', 'Trade', { insight = 300, influence = 40 }, { 'writing' }, 'Unlocks Merchants, the Market and the Trade Caravan rite.'),
  T('law', 'Code of laws', { insight = 400, influence = 80 }, { 'writing', 'chieftains' }, 'Two more chieftains. Unlocks the Long hours and Festival days policies, and the Call the Wanderers rite.'),
  T('mathematics', 'Mathematics', { insight = 450 }, { 'writing' }, 'Insight +20%, Scholars +50%.', { { 'insight', 'm', 1.2 }, { 'u.scholar', 'm', 1.5 } }),
  T('metalTools', 'Metal tools', { insight = 400 }, { 'smelting' }, 'Unlocks Toolsmiths. Tools wear out 65% slower, and workers with tools work 25% better.', { { 'toolwear', 'm', .35 }, { 'tooled', 'm', 1.25 } }),
  T('architecture', 'Architecture', { insight = 600 }, { 'masonry', 'mathematics' }, 'Unlocks the Monument.'),
  T('philosophy', 'Philosophy', { insight = 700, culture = 120 }, { 'mathematics', 'religion' }, 'Culture +50%, mood +5. Unlocks the Grand Symposium rite.', { { 'culture', 'm', 1.5 }, { 'happy', 'a', 5 } }),
  T('currency', 'Currency', { insight = 650 }, { 'trade', 'smelting' }, 'Merchants twice as effective.', { { 'u.merchant', 'm', 2 } }),
  T('ironWorking', 'Iron working', { insight = 900 }, { 'metalTools' }, 'Workers with tools work another 25% better.', { { 'tooled', 'm', 1.25 }, { 'toolwear', 'm', .6 } }),
  T('cityPlanning', 'City planning', { insight = 1100 }, { 'architecture', 'law' }, 'Housing +25%. Unlocks the Aqueduct.', { { 'housing', 'm', 1.25 } }),
  T('science', 'Natural philosophy', { insight = 1600, culture = 150 }, { 'philosophy', 'mathematics' }, 'Insight +50%.', { { 'insight', 'm', 1.5 } }),
  T('history', 'Written history', { insight = 2500, culture = 300, faith = 100, influence = 100 }, { 'science', 'cityPlanning' }, 'Your tribe becomes a civilization that remembers. All production +25%.', { { 'all', 'm', 1.25 } }),
}
-- Later discoveries cost progressively more: insight scales linearly with depth, the other essentials by its square root.
for i, t in ipairs(TECHS) do
  local f = 1 + max(0, (i - 1) - 8) / 6
  for k, v in pairs(t.cost) do t.cost[k] = max(v, floor(v * (k == 'insight' and f or sqrt(f)) / 5 + .5) * 5) end
end
local TM = {}
for _, t in ipairs(TECHS) do TM[t.id] = t end
Sim.TECHS, Sim.TM = TECHS, TM

---------------------------------------------------------------- traits
local hasTrait, housing, homeless
local TRAITS = {
  { id = 'insects', n = 'Insect-eating', d = 'Hungry times taught the tribe to eat grubs and beetles.', fx = { { 'g.fruit', 'm', 1.15 }, { 'happy', 'a', -2 } }, c = function() return S.hungerDays >= 3 end, p = .05 },
  { id = 'necro', n = 'Ritual necrophagy', d = 'In desperation, the dead feed the living. Unburied dead slowly become meat.', fx = { { 'happy', 'a', -6 } }, neg = true, c = function() return S.res.corpses >= 3 and S.hungerDays >= 6 end, p = .03 },
  { id = 'fearDeath', n = 'Fear of death', d = 'Loss weighs heavily on everyone. Grief +50%, faith +20%.', fx = { { 'grief', 'm', 1.5 }, { 'faith', 'm', 1.2 } }, neg = true, c = function() return S.grief >= 8 end, p = .03 },
  { id = 'afterlife', n = 'Belief in the afterlife', d = 'The dead walk on in another land. Grief \u{2212}40%, faith +25%.', fx = { { 'grief', 'm', .6 }, { 'faith', 'm', 1.25 } }, c = function() return known('ritualism') and S.deaths >= 3 end, p = .02 },
  { id = 'ancestors', n = 'Ancestor worship', d = 'The graves of the old ones are tended with care. Faith +30%, mood +3.', fx = { { 'faith', 'm', 1.3 }, { 'happy', 'a', 3 } }, c = function() return known('burial') and bld('grave') >= 3 end, p = .02 },
  { id = 'sedentism', n = 'Sedentism', d = 'The tribe prefers to stay put. Births +25%, exploring \u{2212}30%.', fx = { { 'birth', 'm', 1.25 }, { 'explore', 'm', .7 } }, c = function() return housing() >= popTotal() and S.day > 200 end, p = .01, x = 'nomad' },
  { id = 'nomad', n = 'Nomadism', d = 'Home is wherever the tribe sleeps tonight. Exploring +50%, births \u{2212}15%.', fx = { { 'explore', 'm', 1.5 }, { 'birth', 'm', .85 } }, c = function() return homeless() > popTotal() * .5 and S.day > 60 end, p = .015, x = 'sedentism' },
  { id = 'kin', n = 'Strong kin bonds', d = 'Families look after one another. Births +20%, mood +3.', fx = { { 'birth', 'm', 1.2 }, { 'happy', 'a', 3 } }, c = function() return S.happy > 30 end, p = .01 },
  { id = 'fireRev', n = 'Fire reverence', d = 'The flame is sacred. Faith +15%, fire pits last 20% longer.', fx = { { 'faith', 'm', 1.15 }, { 'firedecay', 'm', .8 } }, c = function() return n('firekeeper') >= 3 end, p = .01 },
  { id = 'stories', n = 'Storytelling culture', d = 'Every evening ends with a tale. Culture +25%.', fx = { { 'culture', 'm', 1.25 } }, c = function() return n('storyteller') >= 3 end, p = .012 },
  { id = 'hunterPride', n = "Hunter's pride", d = 'The best hunters are honoured. Hunters +15%, mood +2.', fx = { { 'u.hunter', 'm', 1.15 }, { 'happy', 'a', 2 } }, c = function() return n('hunter') >= 10 end, p = .012 },
  { id = 'sea', n = 'Love of the sea', d = 'Water calls to the tribe. Fishers +20%.', fx = { { 'u.fisher', 'm', 1.2 } }, c = function() return n('fisher') >= 8 end, p = .012 },
  { id = 'herbLore', n = 'Herb lore', d = 'Remedies pass from parent to child. Sickness \u{2212}15%, herbs +25%.', fx = { { 'sick', 'm', .85 }, { 'g.herbs', 'm', 1.25 } }, c = function() return n('healer') >= 3 end, p = .012 },
  { id = 'toolcraft', n = 'Toolcraft tradition', d = 'Tools are made with pride and care. Tools wear 30% slower.', fx = { { 'toolwear', 'm', .7 } }, c = function() return n('knapper') + n('toolsmith') >= 5 end, p = .012 },
  { id = 'wanderlust', n = 'Wanderlust', d = 'The horizon is never far enough. Exploring +30%.', fx = { { 'explore', 'm', 1.3 } }, c = function() return S.explored >= 25 end, p = .01 },
  { id = 'feasts', n = 'Ceremonial feasts', d = 'Meals are shared and varied. Mood +5, food eaten +5%.', fx = { { 'happy', 'a', 5 }, { 'eat', 'm', 1.05 } }, c = function() return S.variety >= 4 end, p = .015 },
  { id = 'stoic', n = 'Stoicism', d = 'Death is part of life. Grief \u{2212}30%.', fx = { { 'grief', 'm', .7 } }, c = function() return S.deaths >= 50 end, p = .01 },
  { id = 'martial', n = 'Martial tradition', d = 'Strength is admired above all. Defense +50%, mood \u{2212}2.', fx = { { 'defense', 'm', 1.5 }, { 'happy', 'a', -2 } }, c = function() return n('guard') >= 10 end, p = .012 },
  { id = 'craftPride', n = 'Craft pride', d = 'Makers sign their work. Crafting jobs +20%.', fx = { { 'craft', 'm', 1.2 } }, c = function() return n('potter') + n('tailor') + n('mason') + n('weaver') >= 10 end, p = .012 },
  { id = 'stars', n = 'Star-gazing', d = 'Nights are spent naming the stars. Insight +15%.', fx = { { 'insight', 'm', 1.15 } }, c = function() return known('astronomy') and n('dreamer') >= 8 end, p = .012 },
  { id = 'poly', n = 'Polytheism', d = 'A god for every hill and river. Faith +20%, culture +10%.', fx = { { 'faith', 'm', 1.2 }, { 'culture', 'm', 1.1 } }, c = function() return known('religion') end, p = .01, x = 'mono' },
  { id = 'mono', n = 'Monotheism', d = 'One god above all. Faith +40%, influence +10%.', fx = { { 'faith', 'm', 1.4 }, { 'influence', 'm', 1.1 } }, c = function() return known('religion') and n('priest') >= 5 end, p = .008, x = 'poly' },
  { id = 'agrarian', n = 'Agrarian ways', d = 'Life follows the planting season. Farmers +15%, exploring \u{2212}20%.', fx = { { 'u.farmer', 'm', 1.15 }, { 'explore', 'm', .8 } }, c = function() return n('farmer') >= 15 end, p = .012 },
  { id = 'merchantSpirit', n = 'Merchant spirit', d = 'Everything has a price. Influence +20%.', fx = { { 'influence', 'm', 1.2 } }, c = function() return n('merchant') >= 5 end, p = .012 },
  { id = 'clean', n = 'Cleanliness taboos', d = 'Sickness taught the tribe to wash. Sickness \u{2212}30%.', fx = { { 'sick', 'm', .7 } }, c = function() return S.pop.sick >= 3 and S.pop.sick > S.pop.adults * .15 end, p = .03 },
  { id = 'wolfkin', n = 'Wolf companions', story = true, d = 'Tame wolves run with the hunters and guard the camp at night. Hunters +15%, defense +2.', fx = { { 'u.hunter', 'm', 1.15 }, { 'defense', 'a', 2 } }, c = function() return false end, p = 0 },
  { id = 'flintMasters', n = 'Flint masters', story = true, d = 'The old knapper\'s secrets live on. Knappers +50%.', fx = { { 'u.knapper', 'm', 1.5 } }, c = function() return false end, p = 0 },
  { id = 'openHearth', n = 'Open hearth', story = true, d = 'No traveller is turned away from the fire. Newcomers +50%, mood +2.', fx = { { 'migrants', 'm', 1.5 }, { 'happy', 'a', 2 } }, c = function() return false end, p = 0 },
  { id = 'hospitality', n = 'Hospitality', d = 'Strangers are welcomed at the fire. Wanderers join far more often.', fx = { { 'migrants', 'm', 2 } }, c = function() return S.happy > 20 and popTotal() > 20 end, p = .008 },
}
local TRM = {}
for _, t in ipairs(TRAITS) do TRM[t.id] = t end
Sim.TRAITS, Sim.TRM = TRAITS, TRM

---------------------------------------------------------------- rites
local exploreOne
local RITES = {
  { id = 'hunt', n = 'Great Hunt', tech = 'hunting', cost = { sticks = 20, tools = 3 }, dur = 5, cd = 30, fx = { { 'u.hunter', 'm', 3 } }, d = 'Every hunter joins one great drive. Hunters \u{00d7}3 for 5 days.' },
  { id = 'bonfire', n = 'Bonfire Night', tech = 'fire', cost = { sticks = 40 }, dur = 5, cd = 30, fx = { { 'happy', 'a', 10 } }, d = 'A towering fire. +5 fire pits now, and mood +10 for 5 days.', now = function() S.res.fire = S.res.fire + 5 end },
  { id = 'rain', n = 'Rain Dance', tech = 'ritualism', cost = { faith = 8 }, dur = 10, cd = 40, fx = { { 'g.water', 'm', 2 }, { 'g.fruit', 'm', 1.2 }, { 'u.farmer', 'm', 1.3 } }, d = 'Water gathering \u{00d7}2, fruit +20%, farmers +30% for 10 days.' },
  { id = 'vision', n = 'Vision Quest', tech = 'ritualism', cost = { faith = 12, herbs = 10 }, cd = 30, d = 'A dreamer fasts in the wilds and returns with ideas: gain 20 days of insight at once (at least 8).',
    now = function() local g = max(8, (S.rate.insight or 0) * 20); S.res.insight = S.res.insight + g; return '+' .. fmt(g) .. ' insight' end },
  { id = 'festival', n = 'Festival', tech = 'oral', cost = { culture = 10, food = 30 }, dur = 10, cd = 40, fx = { { 'happy', 'a', 25 } }, d = 'Song, dance and a shared meal. Mood +25 for 10 days.' },
  { id = 'worksong', n = 'Work Song', tech = 'oral', cost = { culture = 15 }, dur = 10, cd = 50, fx = { { 'all', 'm', 1.25 } }, d = 'Everyone works to the same rhythm. All production +25% for 10 days.' },
  { id = 'expedition', n = 'Expedition', tech = 'scouting', cost = { food = 20, water = 20 }, cd = 25, d = 'A provisioned party sets out and charts 3 new tiles of land at once.',
    now = function() local k = 0; for _ = 1, 3 do if exploreOne() then k = k + 1 end end; return k > 0 and (k .. ' new tiles charted') or 'no reachable land left to chart' end },
  { id = 'healrite', n = 'Healing Rite', tech = 'healing', cost = { faith = 10, herbs = 15 }, cd = 30, d = 'Chants and smoke over the sick: 60% of them recover at once.',
    now = function()
      local c = floor(S.pop.sick * .6); S.pop.sick = S.pop.sick - c
      if c == 0 then return S.pop.sick > 0 and 'too few were sick for the chants to take hold' or 'nobody was sick, but everyone feels a little healthier' end
      return c .. ' cured'
    end },
  { id = 'blessing', n = 'Ancestral Blessing', tech = 'burial', cost = { faith = 25 }, dur = 15, cd = 60, fx = { { 'birth', 'm', 3 } }, d = 'The ancestors favour new life. Births \u{00d7}3 for 15 days.' },
  { id = 'council', n = 'Council of Elders', tech = 'chieftains', cost = { influence = 15 }, dur = 15, cd = 50, fx = { { 'insight', 'm', 1.6 } }, d = 'The wise gather to debate. Insight +60% for 15 days.' },
  { id = 'harvest', n = 'Harvest Moon', tech = 'agriculture', cost = { faith = 30 }, dur = 15, cd = 80, fx = { { 'u.farmer', 'm', 2 } }, d = 'Fields swell under a blessed moon. Farmers \u{00d7}2 for 15 days.' },
  { id = 'arms', n = 'Call to Arms', tech = 'defense', cost = { influence = 20 }, dur = 20, cd = 60, fx = { { 'defense', 'm', 3 } }, d = 'Everyone sharpens a spear. Defense \u{00d7}3 for 20 days.' },
  { id = 'pilgrimage', n = 'Pilgrimage', tech = 'religion', cost = { faith = 60, culture = 20 }, dur = 10, cd = 60, fx = { { 'happy', 'a', 10 } }, d = 'The faithful walk to sacred places. +40 influence now, mood +10 for 10 days.',
    now = function() S.res.influence = S.res.influence + 40; return '+40 influence' end },
  { id = 'caravan', n = 'Trade Caravan', tech = 'trade', cost = { influence = 30 }, cd = 40, d = 'Send goods far away and bring back three kinds of materials, 100\u{2013}300 of each.',
    now = function()
      local pool = { 'wood', 'stone', 'clay', 'hides', 'ore', 'herbs', 'fiber', 'bricks', 'metal', 'pottery', 'tools', 'clothing' }
      local got = {}
      for _ = 1, 3 do
        local r = table.remove(pool, love.math.random(1, #pool))
        local a = floor(100 + rand() * 200 + .5)
        S.res[r] = S.res[r] + a
        got[#got + 1] = a .. ' ' .. R[r].n:lower()
      end
      return table.concat(got, ', ')
    end },
  { id = 'migrants', n = 'Call the Wanderers', tech = 'law', cost = { influence = 40, food = 100 }, cd = 80, d = 'Messengers invite wandering families to join. 3\u{2013}8 adults arrive.',
    now = function() local k = 3 + floor(rand() * 6); S.pop.adults = S.pop.adults + k; return k .. ' newcomers' end },
  { id = 'symposium', n = 'Grand Symposium', tech = 'philosophy', cost = { culture = 80 }, dur = 20, cd = 100, fx = { { 'insight', 'm', 2 }, { 'culture', 'm', 1.5 } }, d = 'Thinkers from every family debate in public. Insight \u{00d7}2, culture +50% for 20 days.' },
}
local RM = {}
for _, r in ipairs(RITES) do RM[r.id] = r end
Sim.RITES, Sim.RM = RITES, RM

---------------------------------------------------------------- policies
local POLICIES = {
  { id = 'food', n = 'Food rations', d = 'How much each person eats. Less makes food last; more makes people happier.', opts = { { 'meager', 'Meager' }, { 'normal', 'Normal' }, { 'plenty', 'Plentiful' } } },
  { id = 'water', n = 'Water rations', d = 'How much each person drinks.', opts = { { 'meager', 'Meager' }, { 'normal', 'Normal' }, { 'plenty', 'Plentiful' } } },
  { id = 'eatRaw', n = 'Eat raw meat and fish', d = 'Raw meat feeds people but can make them sick. Firekeepers cook it safely.', toggle = true },
  { id = 'muddy', n = 'Drink muddy water', d = 'When fresh water runs out, drink muddy water. It spreads sickness.', toggle = true },
  { id = 'childLabor', n = 'Child labor', d = 'Children can be given jobs, working at half strength. Mood \u{2212}8.', toggle = true, tech = 'chieftains', cost = 5, fx = { { 'happy', 'a', -8 } } },
  { id = 'elderWork', n = 'Elder workforce', d = 'Elders can be given jobs, working at half strength. Mood \u{2212}4.', toggle = true, tech = 'chieftains', cost = 5, fx = { { 'happy', 'a', -4 } } },
  { id = 'longHours', n = 'Long hours', d = 'All production +20%, mood \u{2212}12.', toggle = true, tech = 'law', cost = 10, fx = { { 'all', 'm', 1.2 }, { 'happy', 'a', -12 } } },
  { id = 'festDays', n = 'Festival days', d = 'Regular days of rest. Production \u{2212}10%, mood +12, culture +30%.', toggle = true, tech = 'law', cost = 10, fx = { { 'all', 'm', .9 }, { 'happy', 'a', 12 }, { 'culture', 'm', 1.3 } } },
}
local PM = {}
for _, p in ipairs(POLICIES) do PM[p.id] = p end
Sim.POLICIES, Sim.PM = POLICIES, PM

---------------------------------------------------------------- icons for news and screens
Sim.TECH_ICON = { language = 'x.scroll', knapping = 'tools', shelter = 'b.leanto', fire = 'fire', hunting = 'u.hunter', fishing = 'fish', herbalism = 'herbs', digging = 'u.digger',
  woodcutting = 'wood', stockpiling = 'b.stockpile', oral = 'u.storyteller', ritualism = 'u.soothsayer', scouting = 'u.scout', healing = 'u.healer', sewing = 'clothing', spears = 'ri.arms',
  building = 'b.hut', chieftains = 'u.chieftain', burial = 'b.grave', pottery = 'pottery', wells = 'b.well', canoes = 'u.fisher', weaving = 'u.weaver', agriculture = 'grain', husbandry = 'u.herder',
  masonry = 'bricks', baking = 'bread', astronomy = 'ri.harvest', carpentry = 'b.house', defense = 'u.guard', writing = 'u.scholar', mining = 'ore', irrigation = 'water', smelting = 'metal',
  medicine = 'e.health', religion = 'b.temple', trade = 'b.market', law = 'influence', mathematics = 'insight', metalTools = 'u.toolsmith', architecture = 'b.monument', philosophy = 'ri.symposium',
  currency = 'u.merchant', ironWorking = 'tools', cityPlanning = 'b.aqueduct', science = 'ri.vision', history = 'b.library' }
Sim.TRAIT_ICON = { insects = 'herbs', necro = 'x.bad', fearDeath = 'x.bad', afterlife = 'faith', ancestors = 'b.grave', sedentism = 'b.hut', nomad = 'u.wanderer', kin = 'e.people', fireRev = 'fire',
  stories = 'u.storyteller', hunterPride = 'u.hunter', sea = 'fish', herbLore = 'herbs', toolcraft = 'tools', wanderlust = 'u.scout', feasts = 'x.food', stoic = 'b.monument', martial = 'u.guard',
  craftPride = 'pottery', stars = 'insight', poly = 'b.temple', mono = 'b.shrine', agrarian = 'grain', merchantSpirit = 'u.merchant', clean = 'water', hospitality = 'ri.migrants',
  wolfkin = 'u.hunter', flintMasters = 'u.knapper', openHearth = 'ri.migrants' }
Sim.POLICY_ICON = { food = 'x.food', water = 'water', eatRaw = 'meat', muddy = 'muddy', childLabor = 'e.children', elderWork = 'e.elders', longHours = 'tools', festDays = 'ri.festival' }

---------------------------------------------------------------- state
local SYL = { 'ka', 'ru', 'ma', 'tu', 'shi', 'na', 'lo', 'vey', 'dra', 'ish', 'om', 'ten', 'bar', 'el', 'go', 'ya', 'zun', 'ha', 'ri', 'kel' }
local function tribeName()
  local s = ''
  for _ = 1, 2 + floor(rand() * 2) do s = s .. SYL[love.math.random(1, #SYL)] end
  return s:sub(1, 1):upper() .. s:sub(2)
end
local function fresh()
  local res = {}
  for _, k in ipairs(Sim.RKEYS) do res[k] = 0 end
  res.fruit, res.water, res.sticks, res.stone = 40, 40, 6, 2
  return { fmt = 'love1', name = tribeName(), day = 0, seed = love.math.random(1, 999999999), res = res,
    pop = { children = 2, adults = 6, elders = 1, sick = 0 }, units = { gatherer = 4, dreamer = 1, wanderer = 1 }, blds = {}, techs = {}, traits = {}, rites = {}, buffs = {},
    pol = { food = 'normal', water = 'normal', eatRaw = true, muddy = true, childLabor = false, elderWork = false, longHours = false, festDays = false },
    happy = 0, grief = 0, deaths = 0, born = 0, hungerDays = 0, buried = 0, variety = 1, explored = 0, rate = {}, log = {}, seen = {}, speed = 1, over = false, wonSeen = false,
    foodShort = 0, waterShort = 0, cold = 0, surplus = 0,
    queue = {}, built = 0, peak = 9, ritesDone = 0, storiesDone = 0, storySeen = {}, nextStory = 45, gen = 1,
    hist = { step = 5, pop = {}, food = {}, mood = {}, know = {} } }
end

function n(id) return S.units[id] or 0 end
function bld(id) return S.blds[id] or 0 end
function known(id) for _, t in ipairs(S.techs) do if t == id then return true end end return false end
function hasTrait(id) for _, t in ipairs(S.traits) do if t == id then return true end end return false end
local function M(k) return FX[k] and FX[k].m or 1 end
local function A(k) return FX[k] and FX[k].a or 0 end
function popTotal() return S.pop.children + S.pop.adults + S.pop.elders end
function housing() local h = 0; for _, b in ipairs(BLDS) do h = h + (b.house or 0) * bld(b.id) end; return floor(h * M('housing')) end
function homeless() return max(0, popTotal() - housing()) end
local function assigned() local a = 0; for _, v in pairs(S.units) do a = a + v end; return a end
local function assignCap() return S.pop.adults + (S.pol.childLabor and S.pop.children or 0) + (S.pol.elderWork and S.pop.elders or 0) end
local function idle() return max(0, assignCap() - assigned()) end
local function season() return floor((S.day % YEAR) / (YEAR / 4)) + 1 end
local function unitAvail(u) return not u.tech or known(u.tech) end
local function bldAvail(b) return known(b.tech) end
local function riteAvail(r) return known(r.tech) end
local function reqMet(t) for _, r in ipairs(t.req) do if not known(r) then return false end end return true end
Sim.n, Sim.bld, Sim.known, Sim.hasTrait, Sim.M, Sim.A = n, bld, known, hasTrait, M, A
Sim.popTotal, Sim.housing, Sim.homeless, Sim.assigned, Sim.assignCap, Sim.idle, Sim.season = popTotal, housing, homeless, assigned, assignCap, idle, season
Sim.unitAvail, Sim.bldAvail, Sim.riteAvail, Sim.reqMet = unitAvail, bldAvail, riteAvail, reqMet

Sim.perkFX = {}     -- bonuses from the legacy of earlier tribes, set by legacy.lua
Sim.emit = function() end   -- notifies the game of notable moments (sound, notices); set by main.lua
local function rebuildFX()
  FX = {}
  local function add(list)
    for _, e in ipairs(list or {}) do
      local f = FX[e[1]]; if not f then f = { m = 1, a = 0 }; FX[e[1]] = f end
      if e[2] == 'm' then f.m = f.m * e[3] else f.a = f.a + e[3] end
    end
  end
  for _, id in ipairs(S.techs) do if TM[id] then add(TM[id].fx) end end
  for _, id in ipairs(S.traits) do if TRM[id] then add(TRM[id].fx) end end
  for _, b in ipairs(S.buffs) do if b.fx then add(b.fx) elseif RM[b.id] then add(RM[b.id].fx) end end
  for _, p in ipairs(POLICIES) do if p.toggle and S.pol[p.id] and p.fx then add(p.fx) end end
  for _, b in ipairs(BLDS) do if b.fx and bld(b.id) > 0 then add(b.fx) end end
  add(Sim.perkFX)
end
Sim.rebuildFX = rebuildFX

function Sim.era()
  local k = #S.techs
  if known('history') then return 'Age of History' end
  if k >= 35 then return 'Age of Iron' elseif k >= 25 then return 'Age of Bronze' elseif k >= 15 then return 'Age of Fire and Clay' elseif k >= 5 then return 'Stone Age' end
  return 'Age of Wanderers'
end

local function cap(r)
  local c = R[r].c
  if c == 'food' then return 300 + 400 * bld('granary') + 60 * bld('stockpile') + 2 * S.res.pottery end
  if c == 'water' then return 150 + 100 * bld('well') + 5 * S.res.pottery + 300 * bld('aqueduct') end
  if c == 'mat' or c == 'goods' then return 100 + 250 * bld('stockpile') + 1500 * bld('warehouse') end
  if r == 'fire' then return 60 end
  return math.huge
end
Sim.cap = cap

---------------------------------------------------------------- map
local function xy(i) return (i - 1) % MW, floor((i - 1) / MW) end
local function idx(x, y) return y * MW + x + 1 end
Sim.xy, Sim.idx = xy, idx
local function nb4(i)
  local x, y = xy(i); local r = {}
  if x > 0 then r[#r + 1] = i - 1 end; if x < MW - 1 then r[#r + 1] = i + 1 end
  if y > 0 then r[#r + 1] = i - MW end; if y < MH - 1 then r[#r + 1] = i + MW end
  return r
end
local function nb8(i)
  local x, y = xy(i); local r = {}
  for dy = -1, 1 do for dx = -1, 1 do
    if dx ~= 0 or dy ~= 0 then local X, Y = x + dx, y + dy; if X >= 0 and Y >= 0 and X < MW and Y < MH then r[#r + 1] = idx(X, Y) end end
  end end
  return r
end
Sim.nb4, Sim.nb8 = nb4, nb8

local function genMap(seed)
  local rng = love.math.newRandomGenerator(seed)
  local function noise(sc)
    local gw, gh = math.ceil(MW / sc) + 2, math.ceil(MH / sc) + 2
    local g = {}
    for k = 1, gw * gh do g[k] = rng:random() end
    local function sm(t) return t * t * (3 - 2 * t) end
    local function v(i, j) return g[j * gw + i + 1] end
    return function(x, y)
      local fx, fy = x / sc, y / sc
      local x0, y0 = floor(fx), floor(fy)
      local tx, ty = sm(fx - x0), sm(fy - y0)
      local a = v(x0, y0) + (v(x0 + 1, y0) - v(x0, y0)) * tx
      local b = v(x0, y0 + 1) + (v(x0 + 1, y0 + 1) - v(x0, y0 + 1)) * tx
      return a + (b - a) * ty
    end
  end
  local e1, e2, m1, m2 = noise(5), noise(2.2), noise(4.5), noise(2)
  local E, Mo, t = {}, {}, {}
  for y = 0, MH - 1 do for x = 0, MW - 1 do
    local dx, dy = (x - MW / 2) / (MW / 2), (y - MH / 2) / (MH / 2)
    local d = sqrt(dx * dx + dy * dy)
    E[#E + 1] = .65 * e1(x, y) + .35 * e2(x, y) - .45 * max(0, d - .55) + .08
    Mo[#Mo + 1] = .6 * m1(x, y) + .4 * m2(x, y)
  end end
  for i = 1, MW * MH do
    local e, m = E[i], Mo[i]
    local _, y = xy(i)
    local b
    if e < .36 then b = 'ocean' elseif e > .76 then b = 'mountain' elseif e > .64 then b = 'hills'
    elseif m < .3 then b = 'desert' elseif m < .5 then b = 'grass' elseif m < .7 then b = 'forest'
    else b = (y > MH * .35 and y < MH * .65) and 'jungle' or 'swamp' end
    if b ~= 'ocean' and (y == 0 or y == MH - 1) and rng:random() < .7 then b = 'tundra' end
    t[i] = b
  end
  for i = 1, #t do
    if t[i] ~= 'ocean' and E[i] < .41 then
      for _, j in ipairs(nb4(i)) do if t[j] == 'ocean' then t[i] = 'coast'; break end end
    end
  end
  local highs = {}
  for i, b in ipairs(t) do if b == 'mountain' or b == 'hills' then highs[#highs + 1] = i end end
  for _ = 1, 4 do
    if #highs == 0 then break end
    local cur = table.remove(highs, floor(rng:random() * #highs) + 1)
    local seen = { [cur] = true }
    for _ = 1, 40 do
      local opts = {}
      for _, j in ipairs(nb4(cur)) do if not seen[j] then opts[#opts + 1] = j end end
      if #opts == 0 then break end
      table.sort(opts, function(a, b) return E[a] < E[b] end)
      local nx = opts[1]
      if t[nx] == 'ocean' or t[nx] == 'lake' then break end
      if E[nx] > E[cur] + .02 then if t[cur] ~= 'mountain' then t[cur] = 'lake' end; break end
      if t[nx] ~= 'mountain' then t[nx] = 'river' end
      seen[nx] = true; cur = nx
    end
  end
  local best, bs = 1, -1e9
  local okStart = { grass = true, forest = true, river = true, coast = true, jungle = true }
  for i = 1, #t do
    if okStart[t[i]] then
      local x, y = xy(i)
      local w, f = 0, 0
      local around = nb8(i); around[#around + 1] = i
      for _, j in ipairs(around) do local yy = BIOME[t[j]].y; w = w + (yy.water or 0); f = f + (yy.fruit or 0) end
      local s = min(w, 14) * 1.2 + min(f, 18) * .5 - sqrt((x - MW / 2) ^ 2 + (y - MH / 2) ^ 2) * .4 + rng:random()
      if s > bs then bs = s; best = i end
    end
  end
  return t, best
end

local function initMap()
  local t, home = genMap(S.seed)
  S.map, S.home, S.exp = t, home, {}
  for i = 1, MW * MH do S.exp[i] = 0 end
  S.exp[home] = 1
  for _, i in ipairs(nb8(home)) do if S.map[i] ~= 'ocean' then S.exp[i] = 1 end end
  local c = 0; for i = 1, MW * MH do if S.exp[i] == 1 then c = c + 1 end end
  S.explored = c
end

local function frontier()
  local f = {}
  local canoes = known('canoes')
  for i = 1, MW * MH do
    if S.exp[i] ~= 1 and (S.map[i] ~= 'ocean' or canoes) then
      for _, j in ipairs(nb8(i)) do if S.exp[j] == 1 then f[#f + 1] = i; break end end
    end
  end
  return f
end
Sim.frontier = frontier

local logm
function exploreOne()
  local f = frontier()
  if #f == 0 then return false end
  local i = f[love.math.random(1, #f)]
  S.exp[i] = 1; S.explored = S.explored + 1
  Sim.mapDirty = true
  local b = S.map[i]
  if S.explored % 5 == 0 or b == 'river' or b == 'lake' or b == 'mountain' then
    logm('Explorers discover ' .. BIOME[b].n:lower() .. ' land. ' .. S.explored .. ' tiles are now known.' .. pick({ '', ' The world keeps getting bigger.', ' Nobody has fallen off the edge yet.', ' The wanderers would like a rest.' }), 'good', 'e.land')
  end
  return true
end
Sim.exploreOne = exploreOne

local function landCap()
  local L = {}
  for _, k in ipairs(Sim.LANDKEYS) do L[k] = 0 end
  for i = 1, MW * MH do
    if S.exp[i] == 1 then for k, v in pairs(BIOME[S.map[i]].y) do L[k] = L[k] + v end end
  end
  L.water = L.water + 6; L.fruit = L.fruit + 1
  local se = season()
  for k, s in pairs(SEAS) do L[k] = L[k] * s[se] end
  return L
end
Sim.landCap = landCap

---------------------------------------------------------------- news
-- Repeated news within a season merges into one entry: the same line (shown xN) or a running total.
function logm(t, cls, icon, grp)
  local key = grp and grp.key or ('t:' .. t)
  local found
  for k = 1, min(8, #S.log) do
    local l = S.log[k]
    if (l.g or ('t:' .. l.t)) == key and S.day - l.d < 25 then found = k; break end
  end
  if found then
    local e = table.remove(S.log, found)
    if grp then e.k = (e.k or 0) + grp.add; e.t = grp.fmt(e.k) else e.n = (e.n or 1) + 1 end
    e.d = S.day; e._h = nil
    table.insert(S.log, 1, e)
  else
    table.insert(S.log, 1, { d = S.day, t = t, c = cls or '', i = icon or '', g = grp and grp.key or nil, k = grp and grp.add or nil })
    while #S.log > 160 do table.remove(S.log) end
  end
  Sim.logDirty = true
end
Sim.logm = logm
function Sim.dateStr(d)
  local y, dd = floor(d / YEAR) + 1, d % YEAR
  return SEASONS[floor(dd / 25) + 1] .. ' ' .. (dd % 25 + 1) .. ', year ' .. y
end

local function foodTotal() local s = 0; for _, f in ipairs(FOODS) do s = s + S.res[f] end; return s end
Sim.foodTotal = foodTotal
local function payable(cost)
  for r, v in pairs(cost) do
    if r == 'food' then if foodTotal() < v then return false end
    elseif S.res[r] < v then return false end
  end
  return true
end
local function pay(cost)
  for r, v in pairs(cost) do
    if r == 'food' then
      local tot = foodTotal()
      for _, f in ipairs(FOODS) do S.res[f] = S.res[f] - S.res[f] / tot * v end
    else S.res[r] = S.res[r] - v end
  end
end
Sim.payable, Sim.pay = payable, pay

local function fixAssign()
  local capN = assignCap()
  while assigned() > capN do
    local top
    for id, v in pairs(S.units) do if v > 0 and (not top or v > S.units[top]) then top = id end end
    if not top then break end
    S.units[top] = S.units[top] - 1
  end
end

local function kill(k, cause, group)
  k = min(k, group and S.pop[group] or popTotal())
  if k <= 0 then return end
  local p = S.pop
  for _ = 1, k do
    local tot = p.children + p.adults + p.elders
    if tot <= 0 then break end
    local r = rand() * tot
    if group then p[group] = p[group] - 1; if p.sick > p.adults then p.sick = p.adults end
    elseif r < p.elders then p.elders = p.elders - 1
    elseif r < p.elders + p.children then p.children = p.children - 1
    else p.adults = p.adults - 1; if p.sick > p.adults then p.sick = p.adults end end
  end
  S.res.corpses = S.res.corpses + k; S.deaths = S.deaths + k
  S.grief = S.grief + k * M('grief') * 20 / max(20, popTotal() + k)
  local function say(tot) return (tot == 1 and 'A person dies' or (tot .. ' people die')) .. ' ' .. cause .. '.' end
  logm(say(k), 'death', '', { key = 'd:' .. cause, add = k, fmt = say })
  Sim.emit('death', k)
  fixAssign()
end
Sim.kill = kill

local effNow = {}
local function defense() return ((effNow.guard or n('guard')) + 6 * bld('palisade')) * M('defense') + A('defense') end
Sim.defense = defense

---------------------------------------------------------------- mood
local function moodFactors()
  local f = { { 'Life together', 5 } }
  local pt, p = max(1, popTotal()), S.pop
  local rf = ({ meager = -15, normal = 0, plenty = 10 })[S.pol.food]
  local rw = ({ meager = -10, normal = 0, plenty = 5 })[S.pol.water]
  if rf ~= 0 then f[#f + 1] = { 'Food rations', rf } end
  if rw ~= 0 then f[#f + 1] = { 'Water rations', rw } end
  if S.variety > 1 then f[#f + 1] = { 'Varied meals', min(16, (S.variety - 1) * 4) } end
  if S.foodShort > .02 then f[#f + 1] = { 'Hunger', -40 * S.foodShort } end
  if S.waterShort > .02 then f[#f + 1] = { 'Thirst', -45 * S.waterShort } end
  local hl = homeless() / pt
  if hl > 0 then f[#f + 1] = { 'No shelter', -(known('shelter') and 15 or 5) * hl } end
  local sk = p.sick / max(1, p.adults)
  if sk > .02 then f[#f + 1] = { 'Sickness', -25 * sk } end
  if S.res.corpses >= 1 then f[#f + 1] = { 'Unburied dead', -min(20, S.res.corpses * 40 / max(20, pt)) } end
  if S.grief > .5 then f[#f + 1] = { 'Grief', -min(20, S.grief * 2) } end
  if S.cold > 0 then f[#f + 1] = { 'Cold', -min(25, S.cold / pt * 40) } end
  local sp = bld('shrine') + bld('circle') + 3 * bld('temple') + 5 * bld('monument')
  if sp > 0 then f[#f + 1] = { 'Sacred and gathering places', min(20, floor(sp * 30 / pt * 10 + .5) / 10 + min(6, sp)) } end
  local cult = (S.rate.culture or 0) + (S.rate.faith or 0)
  if cult > .05 then f[#f + 1] = { 'Stories and prayer', min(10, cult * 20) } end
  local extra = A('happy')
  if extra ~= 0 then f[#f + 1] = { 'Customs, rites and policies', extra } end
  for _, e in ipairs(f) do e[2] = floor(e[2] + .5) end
  return f
end
Sim.moodFactors = moodFactors

---------------------------------------------------------------- events
local function randomEvent()
  local pop, se = popTotal(), season()
  local ev = {}
  local function push(k, w) ev[#ev + 1] = { k, w } end
  if pop > 8 then push('beasts', 3) end
  if se == 2 and S.res.sticks + S.res.wood > 30 then push('fire', 2) end
  if se == 1 then for i = 1, MW * MH do if S.exp[i] == 1 and S.map[i] == 'river' then push('flood', 2); break end end end
  if pop > 25 and (S.res.corpses > 1 or homeless() > 5) then push('plague', 2) end
  if S.happy > 5 then push('migrants', 3 * M('migrants')) end
  push('bounty', 3); push('idea', 3)
  if pop > 40 then push('raiders', 2) end
  if se == 4 then push('harsh', 2) end
  if known('ritualism') then push('omen', 1.5) end
  push('twins', 1)
  local total = 0; for _, e in ipairs(ev) do total = total + e[2] end
  local r, pick = rand() * total, ev[1][1]
  for _, e in ipairs(ev) do r = r - e[2]; if r <= 0 then pick = e[1]; break end end
  local def = defense()
  if pick == 'beasts' then
    if def >= pop / 12 and def > 0 then logm('Wolves circle the camp at night, but the guards drive them off. The wolves seem disappointed.', 'good', 'u.guard')
    elseif pop <= 15 or rand() < .5 then
      for _, k in ipairs({ 'meat', 'fish', 'cooked', 'fruit' }) do S.res[k] = S.res[k] * .8 end
      logm('Wolves raid the camp at night and carry off a fifth of the food. They did not ask first.', 'bad', 'meat')
    else kill(1, 'in an attack by wild beasts') end
  elseif pick == 'fire' then
    S.res.sticks = S.res.sticks * .7; S.res.wood = S.res.wood * .7
    logm('A wildfire sweeps through the dry brush. A third of the sticks and logs are lost, though everyone is very warm.', 'bad', 'fire')
  elseif pick == 'flood' then
    for _, f in ipairs(FOODS) do S.res[f] = S.res[f] * .75 end
    logm('Spring floods swamp the food stores. A quarter of the food is ruined, and the rest is damp.', 'bad', 'water')
  elseif pick == 'plague' then
    local k = math.ceil((S.pop.adults - S.pop.sick) * .15); S.pop.sick = S.pop.sick + k
    logm('A plague spreads through the crowded camp. ' .. k .. ' fall sick, and everyone else keeps their distance.', 'bad', 'e.sick')
  elseif pick == 'migrants' then
    local k = 2 + floor(rand() * 4); S.pop.adults = S.pop.adults + k
    logm(k .. ' wanderers ask to join the tribe and are welcomed.', 'good', 'ri.migrants')
  elseif pick == 'bounty' then
    local k = 20 + floor(popTotal() * 2 + .5); S.res.fruit = S.res.fruit + k
    logm('Gatherers find a valley heavy with ripe fruit (+' .. k .. '). Nobody will say where it is.', 'good', 'fruit')
  elseif pick == 'idea' then
    local k = max(3, floor((S.rate.insight or 0) * 15 + .5)); S.res.insight = S.res.insight + k
    logm('A child asks a question nobody can answer. The tribe thinks hard about it (+' .. k .. ' insight).', 'good', 'insight')
  elseif pick == 'raiders' then
    if def >= pop / 8 then logm('Raiders test the palisade and guards, then slip away to bother someone else.', 'good', 'b.palisade')
    else
      local list = { 'wood', 'stone', 'tools', 'clothing', 'metal', 'bricks' }
      for _, f in ipairs(FOODS) do list[#list + 1] = f end
      for _, k in ipairs(list) do S.res[k] = S.res[k] * .8 end
      kill(floor(rand() * 3), 'defending the camp from raiders')
      logm('Raiders strike the camp and carry off a fifth of the stores. Rude.', 'bad')
    end
  elseif pick == 'harsh' then
    S.res.fire = S.res.fire * .5
    logm('A bitter storm blows through and smothers half the fire pits. Everyone huddles a little closer.', 'bad', 'x.winter')
  elseif pick == 'omen' then
    local k = 5 + floor(rand() * 10 + .5); S.res.faith = S.res.faith + k
    logm('A comet streaks across the sky. Soothsayers call it a good omen (+' .. k .. ' faith), as they do with most things.', 'good', 'faith')
  elseif pick == 'twins' then
    S.pop.children = S.pop.children + 2; S.born = S.born + 2
    logm('Twins are born under a full moon. Their parents will not sleep for years.', 'good', 'e.children')
  end
  Sim.emit('event', pick)
  return pick
end
Sim.randomEvent = randomEvent

---------------------------------------------------------------- one day
function Sim.simDay()
  local p, res, se = S.pop, S.res, season()
  local before = {}
  for k, v in pairs(res) do before[k] = v end
  local F = {}
  local function fl(r, label, v)
    if not v or v == 0 then return end
    local o = F[r]; if not o then o = {}; F[r] = o end
    o[label] = (o[label] or 0) + v
  end
  local function plural(id) return UM[id].n .. 's' end
  rebuildFX()
  local pop = popTotal()
  -- workforce
  local workforce = max(0, p.adults - p.sick) + (S.pol.childLabor and p.children * .5 or 0) + (S.pol.elderWork and p.elders * .5 or 0)
  local asg = assigned()
  local staff = asg > 0 and min(1, workforce / asg) or 1
  local happyEff = 1 + clamp(S.happy, -100, 100) / 400
  local toolNeed = 0
  for _, u in ipairs(UNITS) do if u.tools then toolNeed = toolNeed + n(u.id) end end
  local toolCov = toolNeed > 0 and min(1, res.tools / toolNeed) or 1
  local eff = {}
  for _, u in ipairs(UNITS) do
    local k = n(u.id)
    if k == 0 then eff[u.id] = 0 else
      local e = k * staff * happyEff * M('u.' .. u.id) * M('all')
      if u.tools then e = e * (.3 + .7 * toolCov) * M('tooled') end
      if u.rin then e = e * M('craft') end
      eff[u.id] = e
    end
  end
  effNow = eff
  -- gathering from land
  local L = landCap()
  local raw, outs = {}, {}
  for _, u in ipairs(UNITS) do
    if u.prod and eff[u.id] > 0 then
      for _, pr in ipairs(u.prod) do
        local r, amt, lk = pr[1], pr[2], pr[3]
        local v = eff[u.id] * amt
        if lk then
          v = v * M('g.' .. lk) * (SEAS[lk] and SEAS[lk][se] or 1)
          if LANDRES[lk] == r then raw[lk] = (raw[lk] or 0) + v end
        elseif R[r].c == 'ess' then v = v * M(r) end
        outs[#outs + 1] = { r, v, lk, u.id }
      end
    end
  end
  local ratio = {}
  for lk, rv in pairs(raw) do
    local cap0 = lk == 'water' and (L.water + L.muddy) or L[lk]
    ratio[lk] = (rv > 0 and cap0 > 0) and cap0 * (1 - exp(-rv / cap0)) / rv or 0
  end
  S._landUse = { raw = raw, ratio = ratio, L = L }
  local cleanFrac = (L.water + L.muddy) > 0 and L.water / (L.water + L.muddy) or 0
  for _, o in ipairs(outs) do
    local r, v, lk, uid = o[1], o[2], o[3], o[4]
    if lk then v = v * (ratio[lk] or 0) end
    if r == 'water' then
      res.water = res.water + v * cleanFrac; res.muddy = res.muddy + v * (1 - cleanFrac)
      fl('water', plural(uid), v * cleanFrac); fl('muddy', plural(uid), v * (1 - cleanFrac))
    else res[r] = res[r] + v; fl(r, plural(uid), v) end
  end
  -- recipes
  for _, u in ipairs(UNITS) do
    if u.rin and eff[u.id] > 0 then
      local f = eff[u.id]
      for r, a in pairs(u.rin) do if a > 0 then f = min(f, res[r] / a) end end
      if f > 0 then
        for r, a in pairs(u.rin) do res[r] = res[r] - a * f; fl(r, plural(u.id), -a * f) end
        for r, a in pairs(u.rout) do res[r] = res[r] + a * f; fl(r, plural(u.id), a * f) end
      end
    end
  end
  -- firekeepers
  if eff.firekeeper > 0 then
    local burn = min(eff.firekeeper * 1.5, res.sticks)
    res.sticks = res.sticks - burn; res.fire = res.fire + burn * .25
    fl('sticks', 'Firekeepers', -burn); fl('fire', 'Firekeepers', burn * .25)
    if res.fire >= .5 then
      local cook = eff.firekeeper * 4
      for _, r in ipairs({ 'meat', 'fish' }) do
        local c = min(cook, res[r])
        res[r] = res[r] - c; res.cooked = res.cooked + c; cook = cook - c
        fl(r, 'Cooked by firekeepers', -c); fl('cooked', 'Firekeepers', c)
      end
    end
  end
  -- healers
  if eff.healer > 0 and p.sick > 0 then
    local cure = min(p.sick, eff.healer * .3, res.herbs)
    res.herbs = res.herbs - cure; p.sick = max(0, p.sick - sr(cure)); fl('herbs', 'Healers', -cure)
  end
  -- construction: builders work on the first project in the queue; extra work flows on to the next
  do
    local work = ((eff.builder or 0) + idle() * .5 * staff * happyEff * M('all')) * M('build')
    S._buildRate = work
    while work > 1e-9 and #S.queue > 0 do
      local q = S.queue[1]
      local b = BM[q.id]
      local use = min(work, b.work - q.done)
      q.done = q.done + use; work = work - use
      if q.done >= b.work - 1e-6 then
        table.remove(S.queue, 1)
        S.blds[q.id] = bld(q.id) + 1; S.built = (S.built or 0) + 1
        if b.wonder then
          logm('A wonder is finished: the ' .. b.n .. '. ' .. b.d, 'era', 'b.' .. b.id)
          Sim.emit('wonder', b)
        else
          local function say(k) return 'Builders finish ' .. (k == 1 and ('a' .. (b.n:match('^[AEIOUaeiou]') and 'n ' or ' ') .. b.n:lower()) or (k .. ' ' .. Sim.plural(b))) .. '.' end
          logm(say(1), 'good', 'b.' .. b.id, { key = 'built:' .. b.id, add = 1, fmt = say })
          Sim.emit('built', b)
        end
      end
    end
  end
  -- explorers
  local ex = ((eff.wanderer or 0) * UM.wanderer.explore + (eff.scout or 0) * UM.scout.explore) * M('explore')
  for _ = 1, min(3, sr(ex)) do exploreOne() end
  if n('wanderer') > 0 and rand() < n('wanderer') * .0004 then
    S.units.wanderer = S.units.wanderer - 1; p.adults = p.adults - 1
    if p.sick > p.adults then p.sick = p.adults end
    logm('A wanderer never returns from the wilds.', 'death', 'u.wanderer')
  end
  -- buildings
  for _, b in ipairs({ { 'faith', 'shrine', .1, 'Shrines' }, { 'faith', 'temple', .4, 'Temples' }, { 'culture', 'circle', .1, 'Story circles' }, { 'culture', 'monument', .8, 'Monuments' },
    { 'insight', 'library', .3, 'Libraries' }, { 'influence', 'market', .2, 'Markets' }, { 'herbs', 'herbgarden', .8, 'Herb gardens' }, { 'water', 'well', 5, 'Wells' }, { 'water', 'aqueduct', 25, 'Aqueducts' } }) do
    local v = b[3] * bld(b[2]) * (R[b[1]].c == 'ess' and M(b[1]) or 1)
    if v > 0 then res[b[1]] = res[b[1]] + v; fl(b[1], b[4], v) end
  end
  -- eating and drinking
  local eaters = (p.adults + p.elders + p.children * .5) * .6
  local rf = ({ meager = .7, normal = 1, plenty = 1.4 })[S.pol.food]
  local rw = ({ meager = .7, normal = 1, plenty = 1.3 })[S.pol.water]
  local needF = eaters * rf * M('eat')
  local edible = {}
  for _, f in ipairs(FOODS) do if S.pol.eatRaw or not R[f].raw then edible[#edible + 1] = f end end
  local totF = 0; for _, f in ipairs(edible) do totF = totF + res[f] end
  local ate = min(needF, totF)
  local rawAte = 0
  if totF > 0 then
    for _, f in ipairs(edible) do
      local take = res[f] / totF * ate
      res[f] = res[f] - take; fl(f, 'Eaten', -take)
      if R[f].raw then rawAte = rawAte + take end
    end
  end
  local variety = 0; for _, f in ipairs(edible) do if res[f] >= 1 then variety = variety + 1 end end
  S.variety = variety
  local foodShort = needF > 0 and 1 - ate / needF or 0
  local needW = eaters * rw
  local drank = min(needW, res.water); res.water = res.water - drank; fl('water', 'Drunk', -drank)
  local mud = 0
  if drank < needW and S.pol.muddy then mud = min(needW - drank, res.muddy); res.muddy = res.muddy - mud; drank = drank + mud; fl('muddy', 'Drunk', -mud) end
  local waterShort = needW > 0 and 1 - drank / needW or 0
  S.foodShort, S.waterShort = foodShort, waterShort
  if foodShort > .02 or waterShort > .02 then S.hungerDays = S.hungerDays + 1 else S.hungerDays = max(0, S.hungerDays - .5) end
  if hasTrait('necro') and res.corpses > 0 then
    local c = min(res.corpses, .5); res.corpses = res.corpses - c; res.meat = res.meat + c * 15; fl('meat', 'Ritual necrophagy', c * 15)
  end
  -- decay and wear
  local spoilM = max(.25, 1 - .25 * bld('granary'))
  for _, f in ipairs(FOODS) do local sp = res[f] * R[f].spoil * spoilM; res[f] = res[f] - sp; fl(f, 'Spoiled', -sp) end
  do local v = min(res.fire, (res.fire * .04 + .02) * M('firedecay')); res.fire = res.fire - v; fl('fire', 'Burned out', -v) end
  do local v = min(res.tools, toolNeed) * .006 * M('toolwear'); res.tools = max(0, res.tools - v); fl('tools', 'Worn out', -v) end
  do local v = res.clothing * .003; res.clothing = res.clothing - v; fl('clothing', 'Worn out', -v) end
  -- winter cold
  local cold = 0
  if se == 4 then cold = max(0, pop - (res.fire * 10 + res.clothing + min(housing(), pop) * .8)) * M('cold') end
  S.cold = cold
  -- deaths
  if foodShort > .02 then kill(sr(pop * .035 * foodShort), 'of hunger') end
  if waterShort > .02 then kill(sr(pop * .06 * waterShort), 'of thirst') end
  if cold > 0 then kill(sr(cold * .004), 'from the cold') end
  if p.elders > 0 then kill(sr(p.elders * .004), 'of old age') end
  if p.sick > 0 then kill(min(p.sick, sr(p.sick * .006 * (known('medicine') and .5 or 1))), 'of sickness') end
  if eff.hunter > 0 then
    local acc = sr(n('hunter') * UM.hunter.risk * M('huntRisk'))
    if acc > 0 then kill(min(acc, n('hunter')), 'in a hunting accident') end
  end
  -- sickness
  local healthy = max(0, p.adults - p.sick)
  local pt = max(1, popTotal())
  local sickRate = .0008 + .03 * (needW > 0 and mud / needW or 0) + .012 * (needF > 0 and rawAte / needF or 0) + .02 * min(1, res.corpses / pt) + .004 * (homeless() / pt) + .012 * (cold / pt)
  sickRate = sickRate * M('sick')
  p.sick = p.sick + min(healthy, sr(healthy * sickRate))
  p.sick = max(0, p.sick - sr(p.sick * .07))
  -- births and aging
  local edTot = 0; for _, f in ipairs(edible) do edTot = edTot + res[f] end
  local fDays = edTot / max(.1, needF)
  local wDays = (res.water + (S.pol.muddy and res.muddy or 0)) / max(.1, needW)
  S.surplus = clamp((min(fDays, wDays) - 3) / 15, 0, 1)
  if foodShort < .02 and waterShort < .02 and p.adults >= 2 and S.surplus > 0 then
    local hf = clamp(1 + S.happy / 100, .3, 2)
    local b = sr(p.adults * .007 * S.surplus * M('birth') * hf * (homeless() > 0 and .4 or 1))
    if b > 0 then
      p.children = p.children + b; S.born = S.born + b
      local function say(tot) return tot == 1 and 'A child is born.' or (tot .. ' children are born.') end
      logm(say(b), 'good', 'e.children', { key = 'births', add = b, fmt = say })
    end
  end
  local grow = sr(p.children * .007); p.children = p.children - grow; p.adults = p.adults + grow
  local old = min(max(0, p.adults - p.sick), sr(p.adults * .0007)); p.adults = p.adults - old; p.elders = p.elders + old
  fixAssign()
  -- the dead
  local graveRoom = bld('grave') * 10 - S.buried
  if graveRoom > 0 and res.corpses > 0 then
    local b = min(graveRoom, math.ceil(res.corpses))
    fl('corpses', 'Buried', -min(b, res.corpses))
    res.corpses = max(0, res.corpses - b); S.buried = S.buried + b
  end
  res.corpses = max(0, res.corpses * .97 - .01)
  S.buried = S.buried * .98
  S.grief = S.grief * .96
  -- storage limits
  for _, r in ipairs(Sim.RKEYS) do
    if res[r] < 0 then res[r] = 0 end
    local c = cap(r)
    if res[r] > c then fl(r, 'Lost: storage full', c - res[r]); res[r] = c end
  end
  -- mood
  local target = 0; for _, f in ipairs(moodFactors()) do target = target + f[2] end
  S.happy = S.happy + (clamp(target, -100, 100) - S.happy) * .1
  -- traits, events, rites ending
  for _, t in ipairs(TRAITS) do
    if not hasTrait(t.id) and not (t.x and hasTrait(t.x)) and t.c() and rand() < t.p then
      S.traits[#S.traits + 1] = t.id
      logm('A new custom takes hold: ' .. t.n .. '. ' .. t.d, 'trait', Sim.TRAIT_ICON[t.id])
      Sim.emit('trait', t)
    end
  end
  if rand() < .02 then randomEvent() end
  local keep = {}
  for _, b in ipairs(S.buffs) do
    if b['end'] <= S.day then
      if RM[b.id] then logm(RM[b.id].n .. ' comes to an end.', 'rite', 'ri.' .. b.id) end
    else keep[#keep + 1] = b end
  end
  S.buffs = keep
  -- daily rates and where things came from
  for _, r in ipairs(Sim.RKEYS) do
    local d = res[r] - before[r]
    S.rate[r] = S.rate[r] == nil and d or S.rate[r] * .6 + d * .4
    if res[r] > .5 then S.seen[r] = true end
    local tracked = 0; for _, v in pairs(F[r] or {}) do tracked = tracked + v end
    local other = d - tracked
    if abs(other) > .005 then fl(r, r == 'corpses' and 'New dead' or 'Other (events)', other) end
  end
  local FLOW = Sim.FLOW
  for _, r in ipairs(Sim.RKEYS) do
    local o, nw = FLOW[r], F[r]
    if o or nw then
      o = o or {}; FLOW[r] = o; nw = nw or {}
      local keys = {}
      for k in pairs(o) do keys[k] = true end
      for k in pairs(nw) do keys[k] = true end
      for k in pairs(keys) do
        o[k] = (o[k] or 0) * .6 + (nw[k] or 0) * .4
        if abs(o[k]) < .002 then o[k] = nil end
      end
    end
  end
  S.day = S.day + 1
  S.peak = max(S.peak or 0, popTotal())
  local h = S.hist
  if S.day % h.step == 0 then
    h.pop[#h.pop + 1] = popTotal(); h.food[#h.food + 1] = floor(foodTotal() + .5); h.mood[#h.mood + 1] = floor(S.happy + .5); h.know[#h.know + 1] = #S.techs
    if #h.pop > 400 then
      for _, key in ipairs({ 'pop', 'food', 'mood', 'know' }) do
        local a, o = h[key], {}
        for k = 1, #a - 1, 2 do o[#o + 1] = key == 'know' and a[k + 1] or floor((a[k] + a[k + 1]) / 2 + .5) end
        h[key] = o
      end
      h.step = h.step * 2
    end
  end
  if S.day % YEAR == 0 then
    logm('Year ' .. (S.day / YEAR + 1) .. ' begins. The tribe numbers ' .. popTotal() .. '.' .. pick({ '', '', ' Nobody remembers the old year fondly.', ' The elders say it was better in their day.',
      ' Another notch is cut in the counting stick.', ' Everyone is a year older, and the children a lot louder.' }), '', 'e.people')
  elseif S.day % 25 == 0 then
    local sn = SEASONS[season()]
    Sim.emit('season', sn)
    local extra = ({
      { '', ' The snow melts and the mud returns.', ' Everything that bites wakes up.', ' The birds have opinions again.' },
      { '', ' Long days, warm nights, and flies.', ' The fruit ripens and the gatherers stop complaining.', ' It is too hot to argue, almost.' },
      { '', ' The leaves fall and the old ones start talking about winter.', ' Time to gather everything that is not tied down.', ' The geese are leaving. The geese know something.' },
      { ' Fire pits, clothing and shelter keep people warm.', ' Fire pits, clothing and shelter keep people warm. Complaining does not.', ' Fire pits, clothing and shelter keep people warm. Huddling also helps.' },
    })[season()]
    logm(sn .. ' arrives.' .. pick(extra), '', 'x.' .. sn:lower())
  end
  if popTotal() <= 0 and not S.over then S.over = true; logm('The last of the tribe is gone.', 'death'); Sim.emit('over') end
  if Sim.onDay and not S.over then Sim.onDay() end
end

---------------------------------------------------------------- player actions
function Sim.assign(id, d)
  local u = UM[id]
  if not u or not unitAvail(u) then return end
  if d > 0 then
    local k = min(d, idle())
    if u.max then k = min(k, max(0, u.max() - n(id))) end
    S.units[id] = n(id) + max(0, k)
  else S.units[id] = max(0, n(id) + d) end
end
function Sim.research(id)
  local t = TM[id]
  if not t or known(id) or not reqMet(t) or not payable(t.cost) then return false end
  local before = Sim.era()
  pay(t.cost); S.techs[#S.techs + 1] = id; rebuildFX()
  logm('Discovery: ' .. t.n .. '. ' .. t.d, 'tech', Sim.TECH_ICON[id])
  Sim.emit('tech', t)
  if Sim.era() ~= before then logm('A new age begins: the ' .. S.name .. ' tribe enters the ' .. Sim.era() .. '.', 'era', 'b.monument'); Sim.emit('era', Sim.era()) end
  return true
end
function Sim.plural(b) return b.pl or (b.n:lower() .. 's') end
function Sim.queued(id) local k = 0; for _, q in ipairs(S.queue) do if q.id == id then k = k + 1 end end; return k end
-- Pays for k buildings and adds them to the construction queue. Wonders can only be raised once.
function Sim.build(id, k)
  local b = BM[id]
  if not b or not bldAvail(b) then return 0 end
  local done = 0
  for _ = 1, k do
    if b.wonder and (bld(id) > 0 or Sim.queued(id) > 0) then break end
    if not payable(b.cost) then break end
    pay(b.cost); S.queue[#S.queue + 1] = { id = id, done = 0 }; done = done + 1
  end
  return done
end
-- Cancels a project in the queue and returns everything that was paid for it.
function Sim.cancel(k)
  local q = S.queue[k]
  if not q then return end
  table.remove(S.queue, k)
  for r, v in pairs(BM[q.id].cost) do S.res[r] = S.res[r] + v end
end
-- Days until queue item k is finished at the current building rate, or nil when nobody is building.
function Sim.queueEta(k)
  local rate = S._buildRate or 0
  if rate <= 1e-6 then return nil end
  local w = 0
  for j = 1, min(k, #S.queue) do local q = S.queue[j]; w = w + BM[q.id].work - q.done end
  return w / rate
end
function Sim.wondersBuilt() local k = 0; for _, b in ipairs(BLDS) do if b.wonder and bld(b.id) > 0 then k = k + 1 end end; return k end
function Sim.demolish(id)
  if BM[id] and BM[id].wonder then return end
  if bld(id) > 0 then
    S.blds[id] = S.blds[id] - 1
    if id == 'grave' then S.buried = min(S.buried, bld('grave') * 10) end
  end
end
function Sim.riteReady(r) local last = S.rites[r.id]; return last == nil or last + r.cd <= S.day end
function Sim.doRite(id)
  local r = RM[id]
  if not r or not riteAvail(r) or not Sim.riteReady(r) or not payable(r.cost) then return false end
  pay(r.cost); S.rites[id] = S.day; S.ritesDone = (S.ritesDone or 0) + 1
  Sim.emit('rite', r)
  local extra = r.now and r.now() or ''
  if r.dur then
    local keep = {}
    for _, b in ipairs(S.buffs) do if b.id ~= id then keep[#keep + 1] = b end end
    keep[#keep + 1] = { id = id, ['end'] = S.day + r.dur }
    S.buffs = keep
  end
  rebuildFX()
  logm('Rite performed: ' .. r.n .. '.' .. (extra ~= '' and (' ' .. extra:sub(1, 1):upper() .. extra:sub(2) .. '.') or ''), 'rite', 'ri.' .. id)
  return true
end
function Sim.setPolicy(id, v)
  local p = PM[id]
  if not p or (p.tech and not known(p.tech)) then return false end
  if p.cost then
    if S.res.influence < p.cost then return false end
    S.res.influence = S.res.influence - p.cost
  end
  S.pol[id] = v; rebuildFX(); fixAssign()
  return true
end

---------------------------------------------------------------- new game, saving, loading
function Sim.useState(s) S = s; Sim.S = s; rebuildFX(); Sim.logDirty, Sim.mapDirty = true, true end
-- opts (all optional): name, gen (how many tribes came before, plus one), adults, res = {key = amount}, techs = {ids}
function Sim.newGame(opts)
  opts = opts or {}
  local s = fresh()
  if opts.name and opts.name ~= '' then s.name = opts.name end
  s.gen = opts.gen or 1
  s.pop.adults = s.pop.adults + (opts.adults or 0)
  for r, v in pairs(opts.res or {}) do s.res[r] = s.res[r] + v end
  for _, t in ipairs(opts.techs or {}) do if TM[t] then s.techs[#s.techs + 1] = t end end
  if (opts.adults or 0) > 0 then s.units.gatherer = s.units.gatherer + opts.adults end
  s.peak = s.pop.children + s.pop.adults + s.pop.elders
  Sim.useState(s)
  Sim.FLOW = {}
  initMap()
  local count = popTotal()
  local words = { [9] = 'Nine', [11] = 'Eleven', [13] = 'Thirteen', [15] = 'Fifteen' }
  logm('The ' .. S.name .. ' tribe gathers around its first fire. ' .. (words[count] or tostring(count)) .. ' people, a little food, and the whole world unexplored.', 'good', 'fire')
end
Sim.tribeName = tribeName

-- Accepts saves from this version and from the earlier web version (which counted map tiles from 0).
function Sim.loadState(d)
  if type(d) ~= 'table' or type(d.pop) ~= 'table' or type(d.res) ~= 'table' then error('not a save') end
  local s = fresh()
  for k, v in pairs(d) do s[k] = v end
  s.res = {}
  for _, k in ipairs(Sim.RKEYS) do local v = tonumber(d.res[k]) or 0; s.res[k] = (v == v and v > 0) and v or 0 end
  s.pop = {}
  for _, k in ipairs({ 'children', 'adults', 'elders', 'sick' }) do s.pop[k] = max(0, floor(tonumber(d.pop[k]) or 0)) end
  local pol = fresh().pol
  for k, v in pairs(d.pol or {}) do pol[k] = v end
  s.pol = pol
  for _, k in ipairs({ 'units', 'blds', 'rites', 'rate', 'seen' }) do if type(s[k]) ~= 'table' then s[k] = {} end end
  for _, k in ipairs({ 'techs', 'traits', 'buffs', 'log' }) do if type(s[k]) ~= 'table' then s[k] = {} end end
  for _, k in ipairs({ 'happy', 'grief', 'deaths', 'born', 'hungerDays', 'buried', 'variety', 'explored', 'day', 'foodShort', 'waterShort', 'cold', 'surplus',
    'built', 'peak', 'ritesDone', 'storiesDone', 'nextStory', 'gen' }) do
    local v = tonumber(s[k]) or 0; s[k] = (v == v) and v or 0
  end
  if s.gen < 1 then s.gen = 1 end
  -- construction queue and history (added in the second edition; older saves start empty)
  local queue = {}
  if type(s.queue) == 'table' then
    for _, q in ipairs(s.queue) do if type(q) == 'table' and BM[q.id] then queue[#queue + 1] = { id = q.id, done = max(0, tonumber(q.done) or 0) } end end
  end
  s.queue = queue
  if type(s.storySeen) ~= 'table' then s.storySeen = {} end
  local h = s.hist
  if type(h) ~= 'table' or type(h.pop) ~= 'table' or type(h.food) ~= 'table' or type(h.mood) ~= 'table' or type(h.know) ~= 'table' then
    s.hist = { step = 5, pop = {}, food = {}, mood = {}, know = {} }
  else h.step = max(5, tonumber(h.step) or 5) end
  if s.nextStory == 0 then s.nextStory = s.day + 30 end
  local buffs = {}
  for _, b in ipairs(s.buffs) do if type(b) == 'table' and (RM[b.id] or type(b.fx) == 'table') and tonumber(b['end']) then buffs[#buffs + 1] = b end end
  s.buffs = buffs
  if s.fmt ~= 'love1' then
    if type(s.home) == 'number' then s.home = s.home + 1 end
    s.fmt = 'love1'
  end
  s._eff, s.landUse, s._landUse = nil, nil, nil
  for _, e in ipairs(s.log) do e._h = nil end
  if type(s.map) ~= 'table' or #s.map ~= MW * MH or type(s.exp) ~= 'table' then
    Sim.useState(s); initMap()
  else
    for i = 1, MW * MH do s.exp[i] = (s.exp[i] == 1 or s.exp[i] == true) and 1 or 0 end
    Sim.useState(s)
  end
  S.peak = max(S.peak, popTotal())
  Sim.FLOW = {}
end

return Sim
