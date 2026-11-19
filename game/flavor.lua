-- Hearthfire Chronicle: flavor text.
-- One dry line for nearly everything in the game, shown in italics under the plain description.
-- The lines are attached to the game data (as the field q) when this file is first required.
local Sim = require('sim')
local Legacy = require('legacy')
local Flavor = {}

local RES = {
  fruit = 'Sweet, plentiful, and only occasionally the wrong kind of berry.',
  meat = 'Until recently, this was running away.',
  fish = 'Slippery while alive, and not much easier afterwards.',
  cooked = 'The same meat as before, now with far fewer complaints.',
  grain = 'Not much to look at, but it keeps for ages and leads, eventually, to bread.',
  bread = 'Grain that has been ground, kneaded and baked into a reason to get up in the morning.',
  water = 'Clear, cold and essential. Nobody has yet found a way to make it more exciting.',
  muddy = 'Technically water. The rest is best not thought about.',
  sticks = 'The building block of early civilization, and of most of its fires.',
  wood = 'Sticks, but larger and considerably more stubborn.',
  stone = 'Hard, heavy and everywhere. The tribe has high hopes for it.',
  clay = 'Mud with ambitions.',
  herbs = 'Some heal, some season the stew, and a few are best saved for enemies.',
  fiber = 'Stringy plants that can be twisted into nearly anything, given patience.',
  bones = 'Whatever is left once dinner has been thoroughly enjoyed.',
  hides = 'Warm, tough, and previously worn by someone else.',
  ore = 'Rock with something shiny trapped inside, waiting for a very hot fire.',
  tools = 'A sharp edge on a stick changes everything. Mind your fingers.',
  clothing = 'Fashion is still some years away; for now, warmth is the only style.',
  pottery = 'Holds food, water and, in time, a great deal of decorative pride.',
  bricks = 'Clay, fired until it stops arguing.',
  metal = 'Melted rock that cooled into something far more useful than rock.',
  fire = 'Warm, bright and always hungry. Not to be left alone with children or thatch.',
  corpses = 'The departed deserve a resting place, and the living deserve fresh air.',
  insight = 'Ideas, hunches and the occasional good one.',
  culture = 'The stories, songs and habits that convince a tribe it is better than the one over the hill.',
  faith = 'Belief in something greater. Usually the weather.',
  influence = 'The art of getting others to do things, and letting them think it was their idea.',
}
-- the tiles in the Essentials and Demographics groups
Flavor.ESS = {
  people = 'Everyone you are responsible for, whether they like it or not.',
  workers = 'Hard at work, or at least standing near the work.',
  health = 'Feeling fine, mostly.',
  land = 'Everything your explorers have seen and lived to describe.',
  adults = 'Old enough to work, and young enough to complain about it.',
  children = 'Small, loud and always hungry, which is how you know they are healthy.',
  elders = 'Full of advice, much of it unasked for.',
  sick = 'Coughing, sneezing and looking for sympathy.',
  housing = 'A roof for everyone who has one.',
  homeless = 'Sleeping under the stars sounds lovely until it rains.',
}
local UNITS = {
  gatherer = 'Spends the day picking things up, and the evening deciding which ones were edible.',
  dreamer = 'Looks at clouds for a living. Somehow, this works.',
  wanderer = 'Goes for very long walks and comes back with news, or occasionally not at all.',
  builder = 'Measures twice, cuts once, and blames the stone for everything.',
  knapper = 'Hits rocks with other rocks, with a precision that is frankly alarming.',
  firekeeper = 'Guardian of the flame, and of the tribe\'s eyebrows.',
  hunter = 'Brave, patient and quick, in roughly that order, until something charges.',
  fisher = 'Sits by the water all day and calls it work. Now and then, it is.',
  digger = 'Finds the ground surprisingly full of useful things, and worms.',
  woodcutter = 'Has strong opinions about trees, most of them final.',
  healer = 'Knows which leaf to chew for a headache, and which one causes them.',
  storyteller = 'Every story is true, at least the way they tell it.',
  soothsayer = 'Reads the future in smoke, bones and the faces of whoever is listening.',
  chieftain = 'Wears the biggest feathers and gets the blame for the weather.',
  scout = 'Travels light, moves fast and always knows the way back. Usually.',
  tailor = 'Turns animal skins into something you would be happy to be seen in.',
  potter = 'Turns mud into vessels, and is a little smug about it.',
  weaver = 'Can make cloth out of nearly any plant, and patience out of nothing.',
  farmer = 'Puts seeds in the ground and waits. Then worries. Then waits some more.',
  herder = 'Keeps the animals close, because walking after them was getting tiring.',
  baker = 'Rises early so the bread can rise later.',
  mason = 'Fires clay into bricks, and builds a reputation along with them.',
  miner = 'Goes deep into the hills for ore and comes back wearing most of the hill.',
  smith = 'Coaxes metal out of rock with fire, sweat and a great deal of shouting.',
  toolsmith = 'Makes the tools that make everything else, very loudly.',
  guard = 'Stands very still, looking very serious, until it matters.',
  scholar = 'Writes things down so nobody ever has to think them twice.',
  priest = 'Speaks to the gods on everyone\'s behalf, and now and then on theirs.',
  merchant = 'Could sell sand to a desert tribe, and has.',
}
local BLDS = {
  leanto = 'Keeps off most of the rain and some of the wind, on a good day.',
  mudhut = 'Cozy, cheap, and best not leaned on.',
  hut = 'Four walls and a roof, which is two more walls than last year.',
  house = 'Room for the whole family, the in-laws, and their disagreements.',
  stockpile = 'A very organized heap.',
  grave = 'A quiet place for those who have gone on ahead.',
  shrine = 'A small place for big prayers.',
  circle = 'Where the same stories are told every night, and somehow get better.',
  herbgarden = 'Medicine, seasoning and one mystery weed, all in neat rows.',
  granary = 'Raised up on stilts, so the mice have to really want it.',
  well = 'A hole in the ground that gives back more than you put in.',
  warehouse = 'Holds more than anyone can remember owning.',
  palisade = 'Sharpened logs standing in a line, looking unfriendly on your behalf.',
  library = 'Every tablet in its place, and a scholar to tell you to be quiet.',
  temple = 'Built for the gods, who have yet to complain about the draughts.',
  market = 'Everything here has a price, including the advice.',
  monument = 'A great deal of stone, arranged to make the tribe feel important.',
  aqueduct = 'Water that walks to you, on legs of stone.',
  hearth = 'Many hands keep it burning, and nobody remembers who lit it.',
  totem = 'Each family carved its own face. The argument over who goes on top continues.',
  stones = 'Nobody agrees what the stones are for, which may be the point.',
  gardens = 'Green in every season, and the best place in the land to get pleasantly lost.',
  archive = 'Everything the tribe has ever learned, in one place, slightly out of order.',
  wall = 'Keeps the raiders out, and the tribe\'s pride in.',
  colossus = 'Visible for miles, and very proud of it.',
}
local TECHS = {
  language = 'The first word was probably "food". The second was "mine".',
  knapping = 'Two rocks go in; one sharper rock comes out.',
  shelter = 'Sleeping under something turns out to be much better than sleeping under nothing.',
  fire = 'Hot, bright and dangerous. Everyone wants one.',
  hunting = 'Find the animal, chase the animal, and hope the animal does not chase back.',
  fishing = 'Requires a stick, a line, and more patience than anyone knew they had.',
  herbalism = 'Every remedy in the tribe was first tried on somebody\'s uncle.',
  digging = 'The ground goes down a lot further than anyone expected.',
  woodcutting = 'Trees, it turns out, can be persuaded to fall over.',
  stockpiling = 'Keeping some for later: a radical idea at the time.',
  oral = 'Stories passed from mouth to ear, and improved at every step.',
  ritualism = 'If dancing brought the rain once, it may well do so again.',
  scouting = 'Someone has to see what is over the hill, and it is usually whoever asked.',
  healing = 'Rest, warm water and a strong-smelling poultice. Results may vary.',
  sewing = 'A bone needle, a strip of sinew, and suddenly winter seems less personal.',
  spears = 'A pointed stick, held at a respectful distance.',
  building = 'Putting things on top of other things, carefully.',
  chieftains = 'Someone has to be in charge, so that everyone else has someone to blame.',
  burial = 'The dead are laid to rest, and the living sleep better for it.',
  pottery = 'Mud, shaped and baked until it holds water and stops being mud.',
  wells = 'If the water will not come to the tribe, the tribe will dig until it does.',
  canoes = 'A hollow log, and the courage to sit in it.',
  weaving = 'Over, under, over, under, for a very long time.',
  agriculture = 'Food that stays where you put it. A revolution, and a great deal of back pain.',
  husbandry = 'Why chase dinner when it can be persuaded to follow you home?',
  masonry = 'Stone, cut square and stacked straight, which is harder than it sounds.',
  baking = 'Hot stones, ground grain, and the first smell anyone would call delicious.',
  astronomy = 'The stars move in patterns, and the patterns tell the farmers when to worry.',
  carpentry = 'Wood that fits together on purpose.',
  defense = 'Being ready for a fight, mostly so you never have to have one.',
  writing = 'Now nobody can claim they never said it.',
  mining = 'Digging, but with ambition.',
  irrigation = 'Telling the river where to go, politely, by means of ditches.',
  smelting = 'Heat a rock enough, and some of them give up their secrets.',
  medicine = 'Cures that mostly work, written down so the ones that do not can be avoided.',
  religion = 'Gods, temples, and strong opinions about both.',
  trade = 'Swapping what you have too much of for what you lack. Everyone wins, supposedly.',
  law = 'Rules for everybody, written where everybody can argue about them.',
  mathematics = 'Counting past ten without running out of fingers.',
  metalTools = 'An axe that does not shatter is a very good axe indeed.',
  architecture = 'Big buildings that stay up. The second part is the hard part.',
  philosophy = 'Asking questions that have no answers, at great length, over dinner.',
  currency = 'Small shiny tokens that everyone has agreed to want.',
  ironWorking = 'Harder than bronze, stronger than stone, and much louder to make.',
  cityPlanning = 'Streets that go somewhere, on purpose.',
  science = 'Try something, write down what happened, and try again. Repeat forever.',
  history = 'The story of the tribe, written down so it can finally be disputed properly.',
}
local TRAITS = {
  insects = 'Crunchy, plentiful, and full of goodness. Nobody asks what is in the stew anymore.',
  necro = 'Desperate times. Nobody talks about it afterwards.',
  fearDeath = 'Every shadow looks like an omen, and every omen looks bad.',
  afterlife = 'Somewhere past the hills, the departed are surely having a lovely time.',
  ancestors = 'The old ones are always watching, so the young ones behave. Mostly.',
  sedentism = 'Why wander? The view is perfectly fine from here.',
  nomad = 'Packing up is easy when you own very little.',
  kin = 'Everybody is somebody\'s cousin, which makes arguments very complicated.',
  fireRev = 'Let the fire go out and you will have a lot of explaining to do.',
  stories = 'Every evening ends with a story, and most stories end with a lesson.',
  hunterPride = 'The biggest catch earns the best seat by the fire, and a story that grows each year.',
  sea = 'Salt in the air, and sand in absolutely everything.',
  herbLore = 'Grandmother\'s remedies, now with slightly fewer side effects.',
  toolcraft = 'A tool well made is a tool handed down, and argued over.',
  wanderlust = 'The grass is always greener on the next hill, and the one after that.',
  feasts = 'Any excuse for a feast is a good excuse.',
  stoic = 'Death comes for everyone. In the meantime, there is work to do.',
  martial = 'Disagreements are settled the traditional way, which takes a lot of bandages.',
  craftPride = 'Every pot is signed, and every potter thinks theirs is the best.',
  stars = 'The night sky is full of hunters, rivers, and a surprising number of goats.',
  poly = 'A god for every hill, every river and every particularly stubborn rock.',
  mono = 'One god, one temple, and many opinions about the details.',
  agrarian = 'Life follows the seasons, and the seasons follow the farmers\' complaints.',
  merchantSpirit = 'Everything is for sale, and the price is always open to discussion.',
  clean = 'Washing hands before eating: an idea whose time has finally come.',
  wolfkin = 'The wolves get the scraps, and the tribe gets the credit.',
  flintMasters = 'The sharpest edges in the land, and the bandaged fingers to prove it.',
  openHearth = 'There is always room for one more by the fire, and one more bowl in the pot.',
  hospitality = 'Strangers become guests, and guests become family, eventually.',
}
local RITES = {
  hunt = 'The whole tribe goes out together, so that at least the animals are outnumbered.',
  bonfire = 'A fire big enough to be seen from the next valley, which is partly the point.',
  rain = 'It works every time, provided you keep dancing until it rains.',
  vision = 'Days alone in the wild without food produce remarkable ideas, and a remarkable appetite.',
  festival = 'Music, dancing and far too much food. Nobody works the next morning.',
  worksong = 'The work goes amazingly fast when everyone is trying to stay in tune.',
  expedition = 'Pack food, pack water, and try to bring everyone back.',
  healrite = 'Smoke, chanting and herbs. The herbs do most of the work.',
  blessing = 'The ancestors look kindly on new life, and on the sleepless nights that follow.',
  council = 'The elders gather to share their wisdom, and their complaints about the young.',
  harvest = 'The moon is full, the fields are ripe, and nobody is allowed to rest.',
  arms = 'Everyone gets a spear, and a stern talk about which end to point away.',
  pilgrimage = 'A long walk to a holy place, and a longer one back.',
  caravan = 'Leaves with goods, and comes back with different goods and a great many stories.',
  migrants = 'Word goes out that there is food and a warm fire. Word travels fast.',
  symposium = 'Everyone gets to speak. Nobody gets to finish.',
}
local POLICIES = {
  food = 'Nobody has ever complained that their portion was too large.',
  water = 'Drink up, or do not. The river is not going anywhere.',
  eatRaw = 'Cooking is a luxury, and luxuries can wait.',
  muddy = 'It is wet. That is the main thing.',
  childLabor = 'They have small hands and endless energy. They also have opinions about this.',
  elderWork = 'Seventy winters of experience, and now one more chore.',
  longHours = 'The sun goes down, but the work does not.',
  festDays = 'Every few days nobody works, and everybody is happier for it.',
}
local BIOME = {
  ocean = 'A great deal of water, none of it for drinking.',
  coast = 'Sand, shells and fish, if you are quick.',
  grass = 'Wide, open and full of things to eat, and things that eat.',
  forest = 'Plenty of wood, plenty of game, and plenty of places to get lost.',
  jungle = 'Lush, loud and full of fruit, and of creatures that also want the fruit.',
  hills = 'Good stone, fine views and very tired legs.',
  mountain = 'Impressive to look at, exhausting to climb, and mostly rock.',
  river = 'Fresh water, rich soil and the occasional flood, all in one handy place.',
  lake = 'A calm, deep store of water and fish, minding its own business.',
  desert = 'Sand, sun and very little else. At least the view is honest.',
  swamp = 'Damp, muddy and buzzing. Excellent clay; regrettable smell.',
  tundra = 'Cold, flat and quiet, apart from the wind.',
}
local PERKS = {
  band = 'More hands at the first fire, and more opinions about where to put it.',
  stores = 'The last tribe packed a lunch. Several, in fact.',
  memory = 'Some lessons stick, like which end of the rock is sharp.',
  songs = 'The tunes are old, but the ideas they inspire are new.',
  gather = 'Grandmother always knew where the best berries grew. Now everyone does.',
  paths = 'Old trails, remembered, lead to new places.',
  hands = 'Stronger arms, steadier hands, and fewer walls falling over.',
  hardy = 'Tough as old roots, and only slightly less cheerful.',
  kin = 'Bigger families, and bigger dinners.',
  keepers = 'A flame that was never allowed to go out, carried from tribe to tribe.',
  lore = 'The stories outlive their tellers, and improve with every telling.',
  voice = 'Your people\'s name is spoken with respect, or at least loudly.',
}
local MILES = {
  idea1 = 'Somebody thought of something. Everyone else is still catching up.',
  idea10 = 'The tribe is now officially full of ideas, some of them good.',
  idea25 = 'Far too much to remember, which is roughly why writing was invented.',
  ideaAll = 'There is nothing left to learn. Probably.',
  winter = 'Cold, hungry, and still here.',
  year10 = 'Old enough to have traditions, and young enough to break them.',
  year25 = 'The old stories now have old stories of their own.',
  year50 = 'Nobody remembers the first fire, but everybody claims to.',
  pop25 = 'Too many to remember everyone\'s name, though not for lack of trying.',
  pop50 = 'Big enough to need rules, and someone to ignore them.',
  pop100 = 'A hundred people, and a hundred opinions on everything.',
  pop250 = 'Crowded, noisy and very, very proud of it.',
  built1 = 'It is standing. That counts.',
  wonder1 = 'People walk from far away just to stare at it.',
  wonder3 = 'At this point it is less an achievement than a habit.',
  wonderAll = 'The neighbors have stopped trying to keep up.',
  land50 = 'There is a lot more world than anyone thought.',
  land150 = 'The maps are getting very large, and the mapmakers very tired.',
  custom5 = 'This is simply how things are done around here.',
  custom12 = 'Visitors are thoroughly confused, which is how you know it is culture.',
  rites10 = 'The gods know the tribe by name now.',
  tales10 = 'Every one of them retold by the fire, and never the same way twice.',
  joy = 'Laughter by the fire, and nobody is even pretending.',
  history = 'Now the whole story is written down, mistakes and all.',
  lineage = 'The fire goes out, and someone, somewhere, lights another.',
}

-- Quiet lines for the corner of the title screen, one picked at each visit.
Flavor.TITLE = {
  'Now with fire.', 'Mostly survivable.', 'Founded before history began.', 'Nine people, one fire, no plan.',
  'The world is large, and largely unexplored.', 'Contains winter.', 'No dinosaurs were harmed. There were no dinosaurs.',
  'Ideas sold separately: see Dreamers.', 'Mind the wolves.', 'The fire is warm. The rest is up to you.',
}

local function attach(list, lines)
  for _, item in ipairs(list) do if lines[item.id] then item.q = lines[item.id] end end
end
for id, line in pairs(RES) do if Sim.R[id] then Sim.R[id].q = line end end
for id, line in pairs(BIOME) do if Sim.BIOME[id] then Sim.BIOME[id].q = line end end
attach(Sim.UNITS, UNITS); attach(Sim.BLDS, BLDS); attach(Sim.TECHS, TECHS); attach(Sim.TRAITS, TRAITS)
attach(Sim.RITES, RITES); attach(Sim.POLICIES, POLICIES); attach(Legacy.PERKS, PERKS); attach(Legacy.MILES, MILES)

-- Everything that should have a line and does not (used by the self-test).
function Flavor.missing()
  local out = {}
  local function check(list, kind) for _, item in ipairs(list) do if not item.q then out[#out + 1] = kind .. ':' .. item.id end end end
  for _, k in ipairs(Sim.RKEYS) do if not Sim.R[k].q then out[#out + 1] = 'res:' .. k end end
  for k, b in pairs(Sim.BIOME) do if not b.q then out[#out + 1] = 'land:' .. k end end
  check(Sim.UNITS, 'job'); check(Sim.BLDS, 'building'); check(Sim.TECHS, 'tech'); check(Sim.TRAITS, 'trait')
  check(Sim.RITES, 'rite'); check(Sim.POLICIES, 'policy'); check(Legacy.PERKS, 'perk'); check(Legacy.MILES, 'milestone')
  return out
end
-- A flavor paragraph for a doc, or nil.
function Flavor.p(line, font)
  local UI = require('ui')
  if not line then return { t = 'gap', h = 0 } end
  return { t = 'p', text = line, font = font or UI.F.smallI, col = UI.C.muted }
end

return Flavor
