-- Hearthfire Chronicle: story events.
-- Every few seasons the tribe faces a choice. The game pauses until the player decides; each choice has its own outcome.
local Sim = require('sim')
local Story = {}
local floor, max, min = math.floor, math.max, math.min
local function rand() return love.math.random() end
local function S() return Sim.S end
local fmt = Sim.fmt
Story.enabled = true

---------------------------------------------------------------- helpers used by the events
local function buff(id, name, days, fx, icon)
  local s = S()
  local keep = {}
  for _, b in ipairs(s.buffs) do if b.id ~= 's.' .. id then keep[#keep + 1] = b end end
  keep[#keep + 1] = { id = 's.' .. id, n = name, fx = fx, ['end'] = s.day + days, i = icon }
  s.buffs = keep
  Sim.rebuildFX()
end
local function add(r, v) local s = S(); s.res[r] = max(0, s.res[r] + v) end
local function insight(days, least) local g = floor(max(least, (S().rate.insight or 0) * days) + .5); add('insight', g); return g end
local function trait(id)
  local s = S()
  if Sim.hasTrait(id) then return end
  s.traits[#s.traits + 1] = id
  Sim.rebuildFX()
  Sim.emit('trait', Sim.TRM[id])
end
local function chance(p) return rand() < p end
local function explore(k) local got = 0; for _ = 1, k do if Sim.exploreOne() then got = got + 1 end end; return got end
local function knows(biome) local s = S(); for i = 1, Sim.N do if s.exp[i] == 1 and s.map[i] == biome then return true end end; return false end
local function shelters() local s = S(); return (s.blds.leanto or 0) + (s.blds.mudhut or 0) + (s.blds.hut or 0) + (s.blds.house or 0) end
local function burnShelters(k)
  local s = S()
  local lost = 0
  for _ = 1, k do
    local opts = {}
    for _, id in ipairs({ 'leanto', 'mudhut', 'hut', 'house' }) do if (s.blds[id] or 0) > 0 then opts[#opts + 1] = id end end
    if #opts == 0 then break end
    local id = opts[love.math.random(1, #opts)]
    s.blds[id] = s.blds[id] - 1; lost = lost + 1
  end
  return lost
end
local function lose(frac, keys)
  local s = S()
  for _, k in ipairs(keys) do s.res[k] = s.res[k] * (1 - frac) end
end
local STORES = { 'fruit', 'meat', 'fish', 'cooked', 'grain', 'bread', 'wood', 'stone', 'tools', 'clothing', 'metal', 'bricks', 'pottery', 'hides' }
local function people(k) return k == 1 and '1 person' or (k .. ' people') end

---------------------------------------------------------------- the events
-- Each event: id, title, icon, text, cond (when it can happen), again (days before it may repeat; once per tribe if absent)
-- and choices: t (label), d (what it will do), cost, req (extra condition), why (shown when req fails), fn (returns the outcome text).
local E = {}
Story.EVENTS = E

E[#E + 1] = { id = 'stranger', title = 'A stranger at the fire', icon = 'u.wanderer',
  text = 'A lone traveller stumbles into camp at dusk, half-starved. She carries a pouch of strange seeds and speaks with an accent nobody knows.',
  cond = function(s) return s.day > 30 end,
  choices = {
    { t = 'Welcome her to the fire', d = 'She joins the tribe and shares what she knows.', fn = function()
      local s = S(); s.pop.adults = s.pop.adults + 1
      local g = insight(15, 10)
      if s.happy > 15 and chance(.5) then trait('openHearth'); return 'She stays. Her tales of far places give the dreamers much to think about (+1 adult, +' .. g .. ' insight). A new custom takes hold: Open hearth.' end
      return 'She stays. Her tales of far places give the dreamers much to think about (+1 adult, +' .. g .. ' insight).' end },
    { t = 'Feed her and send her on', d = 'Costs 10 food.', cost = { food = 10 }, fn = function() add('culture', 6); return 'She leaves at dawn, and the tale of the seed-woman is told for years (+6 culture).' end },
    { t = 'Turn her away', d = 'Nothing is lost, but some will be ashamed.', fn = function() buff('coldWelcome', 'A cold welcome', 20, { { 'happy', 'a', -3 } }, 'x.bad'); return 'She walks back into the dark. Many in the tribe are ashamed (mood \u{2212}3 for 20 days).' end },
  } }

E[#E + 1] = { id = 'wolfpup', title = 'The wolf pup', icon = 'u.hunter',
  text = 'Hunters come back with a wolf pup they found alone in a den, its mother killed by a bear. It snaps at anyone who comes close.',
  cond = function() return Sim.known('hunting') end,
  choices = {
    { t = 'Raise it in camp', d = 'It may grow into a friend.', fn = function() trait('wolfkin'); return 'The pup grows up by the fire, and its litters after it. A new custom takes hold: Wolf companions (hunters +15%, defense +2).' end },
    { t = 'Return it to the forest', d = 'A kindness the spirits may remember.', fn = function() add('faith', 5); return 'It is left at the forest edge. The soothsayers call it a good deed (+5 faith).' end },
    { t = 'Take its pelt', d = 'A little meat and a soft hide.', fn = function() add('hides', 2); add('meat', 4); return 'A small, warm pelt and a little meat (+2 hides, +4 meat).' end },
  } }

E[#E + 1] = { id = 'fever', title = 'The strange fever', icon = 'e.sick',
  text = 'An elder burns with a fever nobody has seen before. Her breath rattles, and the healers argue over what to do.',
  cond = function(s) return Sim.popTotal() >= 15 and s.pop.elders >= 1 end,
  choices = {
    { t = 'Carry her away from camp', d = 'She will die alone, but the fever may not spread.', fn = function()
      Sim.kill(1, 'of the strange fever', 'elders')
      buff('quarantine', 'Quarantine', 30, { { 'sick', 'm', .6 } }, 'e.health')
      return 'She dies in a hut far from the fire, but the fever goes no further (sickness \u{2212}40% for 30 days).' end },
    { t = 'Nurse her at the fire', d = 'She may recover, or the fever may spread.', fn = function()
      local s = S()
      if chance(.55) then add('faith', 8); return 'After nine days the fever breaks. Her recovery is taken as a sign (+8 faith).' end
      local k = math.ceil(max(1, s.pop.adults - s.pop.sick) * .15); s.pop.sick = min(s.pop.adults, s.pop.sick + k)
      return 'The fever spreads through the camp. ' .. people(k) .. ' fall sick.' end },
    { t = 'Ask the spirits for help', d = 'Costs 15 faith.', cost = { faith = 15 }, req = function() return Sim.known('ritualism') end, why = 'Needs Ritualism.', fn = function()
      buff('spirits', 'The spirits listened', 15, { { 'happy', 'a', 4 } }, 'faith'); return 'Smoke and chanting go on for three nights. At dawn her fever breaks (mood +4 for 15 days).' end },
  } }

E[#E + 1] = { id = 'herd', title = 'The great herd', icon = 'meat',
  text = 'Scouts run in breathless: a vast herd of grazing beasts is moving through the valley, so many that the ground shakes.',
  cond = function() return Sim.known('hunting') and (Sim.season() == 2 or Sim.season() == 3) end, again = 300,
  choices = {
    { t = 'Send every hunter', d = 'A great haul, but a dangerous one.', fn = function()
      buff('herd', 'The great herd', 8, { { 'u.hunter', 'm', 2.5 }, { 'huntRisk', 'm', 2 } }, 'u.hunter')
      return 'For 8 days hunters bring in two and a half times as much, but the stampede makes accidents twice as likely.' end },
    { t = 'Follow the herd and learn its paths', d = 'Trackers chart new land.', fn = function()
      local k = explore(2); local g = insight(5, 8)
      return 'Trackers follow the herd for days, charting ' .. k .. ' new ' .. (k == 1 and 'tile' or 'tiles') .. ' (+' .. g .. ' insight).' end },
    { t = 'Let them pass', d = 'Nothing happens.', fn = function() return 'The herd moves on over the hills.' end },
  } }

E[#E + 1] = { id = 'flint', title = 'Black flint', icon = 'stone',
  text = 'A child digging by the stream turns up a seam of fine black flint, sharper than any stone the knappers have worked.',
  cond = function() return Sim.known('knapping') end,
  choices = {
    { t = 'Quarry it', d = 'Stone and ready-made tools.', fn = function() add('stone', 40); add('tools', 8); return 'The seam yields well (+40 stone, +8 tools).' end },
    { t = 'Make it a sacred place', d = 'Faith and a lighter heart.', fn = function() add('faith', 12); buff('flintSpring', 'The sacred seam', 30, { { 'happy', 'a', 3 } }, 'faith'); return 'The seam is left untouched and visited at every full moon (+12 faith, mood +3 for 30 days).' end },
  } }

E[#E + 1] = { id = 'feud', title = 'A feud between families', icon = 'x.warn',
  text = 'Two families quarrel over the best berry thicket. Every meal ends in shouting, and others are starting to take sides.',
  cond = function() return Sim.popTotal() >= 20 end,
  choices = {
    { t = 'Divide the thicket', d = 'Fair, if nobody is pleased.', fn = function() add('culture', 4); return 'Each family takes half. Neither is happy, but the shouting stops (+4 culture).' end },
    { t = 'Let the chieftain decide', d = 'Authority grows; the losers sulk.', req = function() return Sim.known('chieftains') end, why = 'Needs Chieftains.', fn = function()
      add('influence', 8); buff('feudLost', 'Sulking family', 20, { { 'happy', 'a', -2 } }, 'x.bad'); return 'The chieftain rules, and the ruling holds (+8 influence, mood \u{2212}2 for 20 days).' end },
    { t = 'Let them settle it themselves', d = 'It might end in peace, or in blood.', fn = function()
      if chance(.35) then Sim.kill(1, 'in a feud between families'); buff('feud', 'Bad blood', 20, { { 'happy', 'a', -6 } }, 'x.bad'); return 'A fight breaks out and one person dies (mood \u{2212}6 for 20 days).' end
      add('culture', 10); return 'After a long night of talk they make peace, and the story becomes a lesson for the young (+10 culture).' end },
  } }

E[#E + 1] = { id = 'eclipse', title = 'The sun goes dark', icon = 'x.summer',
  text = 'At midday the sun goes dark. Birds fall silent, dogs howl, and people cry out that the world is ending.',
  cond = function(s) return s.day > 250 end,
  choices = {
    { t = 'Call it a sign of favour', d = 'Faith and courage.', req = function() return Sim.known('ritualism') end, why = 'Needs Ritualism.', fn = function()
      add('faith', 25); buff('favour', 'A sign of favour', 15, { { 'happy', 'a', 5 } }, 'faith'); return 'The soothsayers dance as the light returns (+25 faith, mood +5 for 15 days).' end },
    { t = 'Hide until it passes', d = 'Fear lingers.', fn = function() buff('fear', 'Lingering fear', 10, { { 'happy', 'a', -5 } }, 'x.bad'); return 'Most hide in the shelters until the sun comes back (mood \u{2212}5 for 10 days).' end },
    { t = 'Watch, and remember', d = 'The dreamers learn something.', fn = function()
      local g = insight(Sim.known('astronomy') and 50 or 25, 15); return 'The dreamers watch the shadow cross the sun and argue about it for weeks (+' .. g .. ' insight).' end },
  } }

E[#E + 1] = { id = 'wreck', title = 'Wreckage on the beach', icon = 'wood',
  text = 'A storm throws a tangle of driftwood onto the beach. Among it lies the broken hull of a boat larger than any the tribe has seen.',
  cond = function() return knows('coast') end,
  choices = {
    { t = 'Haul in the timber', d = 'Logs and sticks.', fn = function() add('wood', 60); add('sticks', 40); return 'Everyone hauls driftwood for two days (+60 logs, +40 sticks).' end },
    { t = 'Search the wreck', d = 'Who knows what is inside.', fn = function()
      if chance(.6) then add('tools', 10); add('pottery', 6); add('culture', 6); return 'Inside: tools of strange make, sealed pots, and a carved figure nobody can explain (+10 tools, +6 pottery, +6 culture).' end
      return 'Nothing but rotten rope and gull feathers.' end },
  } }

E[#E + 1] = { id = 'drought', title = 'Drought', icon = 'x.summer',
  text = 'No rain has fallen for weeks. Streams shrink to trickles and the berry bushes droop in the heat.',
  cond = function(s) return Sim.season() == 2 and s.day > 150 end, again = 400,
  choices = {
    { t = 'Dig deep water holes', d = 'Costs 20 sticks. Softens the drought.', cost = { sticks = 20 }, fn = function()
      buff('drought', 'Drought', 15, { { 'g.water', 'm', .8 }, { 'g.fruit', 'm', .85 } }, 'x.summer'); return 'The holes help. Water gathering \u{2212}20% and fruit \u{2212}15% for 15 days.' end },
    { t = 'Dance for rain', d = 'Costs 15 faith. Ends it sooner.', cost = { faith = 15 }, req = function() return Sim.known('ritualism') end, why = 'Needs Ritualism.', fn = function()
      buff('drought', 'Drought', 5, { { 'g.water', 'm', .6 } }, 'x.summer'); return 'On the fifth night the rain comes (water gathering \u{2212}40% for 5 days).' end },
    { t = 'Wait it out', d = 'A long, hard dry spell.', fn = function()
      buff('drought', 'Drought', 20, { { 'g.water', 'm', .55 }, { 'g.fruit', 'm', .7 } }, 'x.summer'); return 'The drought drags on. Water gathering \u{2212}45% and fruit \u{2212}30% for 20 days.' end },
  } }

E[#E + 1] = { id = 'ruins', title = 'The old ruins', icon = 'b.monument',
  text = 'Explorers find tumbled walls overgrown with vines, and stones carved with signs nobody can read. Someone lived here long ago.',
  cond = function(s) return s.explored >= 30 end,
  choices = {
    { t = 'Study the carvings', d = 'Insight.', fn = function() local g = insight(30, 40); return 'The carvings are copied onto hides and puzzled over for a season (+' .. g .. ' insight).' end },
    { t = 'Take the stones', d = 'Building stone.', fn = function() add('stone', 120); return 'The old walls become new ones (+120 stone).' end },
    { t = 'Leave them in peace', d = 'Faith and calm.', fn = function() add('faith', 15); buff('ruins', 'Respect for the old ones', 20, { { 'happy', 'a', 3 } }, 'faith'); return 'The ruins are left to the vines (+15 faith, mood +3 for 20 days).' end },
  } }

E[#E + 1] = { id = 'traders', title = 'Traders from the coast', icon = 'ri.caravan',
  text = 'Traders from the far coast walk into camp with laden packs and a string of pack animals. They want hides and tools.',
  cond = function(s) return Sim.popTotal() >= 25 and s.day > 300 end, again = 500,
  choices = {
    { t = 'Trade with them', d = 'Costs 10 hides and 5 tools. Two kinds of goods in return.', cost = { hides = 10, tools = 5 }, fn = function()
      local pool = { 'pottery', 'clothing', 'metal', 'bricks', 'herbs', 'ore' }
      local got = {}
      for _ = 1, 2 do local r = table.remove(pool, love.math.random(1, #pool)); local a = 25 + floor(rand() * 36); add(r, a); got[#got + 1] = '+' .. a .. ' ' .. Sim.R[r].n:lower() end
      return 'A fair trade (' .. table.concat(got, ', ') .. ').' end },
    { t = 'Hold a feast for them', d = 'Costs 40 food. Friendship and fame.', cost = { food = 40 }, fn = function()
      add('influence', 10); add('culture', 6); buff('feast', 'Feast with the traders', 10, { { 'happy', 'a', 5 } }, 'x.food')
      return 'Songs and stories are traded long into the night (+10 influence, +6 culture, mood +5 for 10 days).' end },
    { t = 'Send them away', d = 'Nothing happens.', fn = function() return 'They shrug and walk on.' end },
  } }

E[#E + 1] = { id = 'knapper', title = 'The old knapper', icon = 'u.knapper',
  text = 'The oldest knapper wants to pass on her secrets before her hands fail. She will teach, but only if the young stop all other work to learn.',
  cond = function() return Sim.known('knapping') and Sim.n('knapper') >= 1 end,
  choices = {
    { t = 'Let them learn', d = 'Work slows for 10 days; knapping improves for good.', fn = function()
      trait('flintMasters'); buff('lessons', 'Lessons in flint', 10, { { 'all', 'm', .9 } }, 'u.knapper')
      return 'For ten days work slows (production \u{2212}10%), but a new custom takes hold: Flint masters (knappers +50%).' end },
    { t = 'There is no time', d = 'Nothing changes.', fn = function() return 'Her secrets die with her.' end },
  } }

E[#E + 1] = { id = 'bumper', title = 'A bumper harvest', icon = 'grain',
  text = 'The fields are heavy with grain, more than the farmers can bring in before the rains.',
  cond = function() return Sim.known('agriculture') and Sim.season() == 3 and Sim.n('farmer') >= 3 end, again = 400,
  choices = {
    { t = 'Everyone to the fields', d = 'Farmers +80% for 10 days; other work \u{2212}15%.', fn = function()
      buff('bumper', 'Everyone to the fields', 10, { { 'u.farmer', 'm', 1.8 / .85 }, { 'all', 'm', .85 } }, 'grain'); return 'Young and old work the fields from dawn to dusk (farmers +80%, other work \u{2212}15% for 10 days).' end },
    { t = 'Take what the farmers can carry', d = 'Nothing changes.', fn = function() return 'Some of the grain rots in the fields.' end },
  } }

E[#E + 1] = { id = 'blight', title = 'Blight', icon = 'grain',
  text = 'Black spots creep across the young grain. Each morning more stalks have withered.',
  cond = function() return Sim.known('agriculture') and Sim.season() == 2 and Sim.n('farmer') >= 3 end, again = 500,
  choices = {
    { t = 'Burn the sick fields', d = 'Farmers \u{2212}50% for 15 days.', fn = function() buff('blight', 'Blight', 15, { { 'u.farmer', 'm', .5 } }, 'grain'); return 'The smoke hangs over the fields for days (farmers \u{2212}50% for 15 days).' end },
    { t = 'Treat it with herbs', d = 'Costs 20 herbs. Farmers \u{2212}20% for 10 days.', cost = { herbs = 20 }, fn = function() buff('blight', 'Blight', 10, { { 'u.farmer', 'm', .8 } }, 'grain'); return 'The herb wash slows the blight (farmers \u{2212}20% for 10 days).' end },
    { t = 'Hope it passes', d = 'It might, or it might ruin the year.', fn = function()
      if chance(.5) then buff('blight', 'Blight', 30, { { 'u.farmer', 'm', .35 } }, 'grain'); return 'It spreads to every field (farmers \u{2212}65% for 30 days).' end
      return 'A week of rain washes the blight away.' end },
  } }

E[#E + 1] = { id = 'curious', title = 'The curious child', icon = 'u.scholar',
  text = 'A girl of twelve asks why the stars move but the mountains do not, and will not stop asking. She has already worn out two scholars.',
  cond = function() return Sim.known('writing') end,
  choices = {
    { t = 'Apprentice her to the scholars', d = 'Insight +20% for 40 days.', fn = function() buff('curious', 'A sharp young mind', 40, { { 'insight', 'm', 1.2 } }, 'u.scholar'); return 'She takes to the tablets at once (insight +20% for 40 days).' end },
    { t = 'Tell her to fetch water', d = 'Nothing changes.', fn = function() return 'She fetches water. She keeps asking.' end },
  } }

E[#E + 1] = { id = 'tribute', title = 'Riders on the ridge', icon = 'u.guard',
  text = 'Armed riders appear on the ridge. Their messenger says: pay tribute, or they will take what they want.',
  cond = function() return Sim.popTotal() >= 40 and Sim.known('chieftains') end, again = 600,
  choices = {
    { t = 'Pay the tribute', d = 'Lose 15% of food and stores.', fn = function() lose(.15, STORES); return 'They load their animals and ride off without a word.' end },
    { t = 'Fight them', d = 'Strong defense wins glory; weak defense costs lives.', fn = function()
      local pop = Sim.popTotal()
      if Sim.defense() >= pop / 10 then add('influence', 20); buff('victory', 'Victory song', 15, { { 'happy', 'a', 6 } }, 'u.guard'); return 'The guards drive them off. Songs are sung about it (+20 influence, mood +6 for 15 days).' end
      local k = 2 + floor(rand() * 3); Sim.kill(k, 'fighting the riders'); lose(.2, STORES)
      return 'The riders break through. ' .. people(k) .. ' die and a fifth of the stores are taken. Defense ' .. fmt(Sim.defense()) .. ' was not enough; ' .. fmt(pop / 10) .. ' was needed.' end },
    { t = 'Offer a marriage alliance', d = 'Costs 20 influence. Peace, and new kin.', cost = { influence = 20 }, fn = function() local s = S(); s.pop.adults = s.pop.adults + 3; return 'A wedding ends the threat, and three of their people join the tribe.' end },
  } }

E[#E + 1] = { id = 'blaze', title = 'Fire in the camp', icon = 'fire',
  text = 'Sparks from a fire pit catch the dry thatch. Flames leap from roof to roof while people scream for water.',
  cond = function() return Sim.known('fire') and Sim.popTotal() >= 20 and shelters() >= 4 end, again = 600,
  choices = {
    { t = 'Form a water line', d = 'Costs 30 water. One shelter is lost.', cost = { water = 30 }, fn = function() local k = burnShelters(1); return 'Bucket by bucket the fire is beaten back. ' .. (k == 1 and 'One shelter burns down.' or 'No shelter is lost.') end },
    { t = 'Save the stores first', d = 'Two shelters are lost.', fn = function() local k = burnShelters(2); return 'The stores are carried out safely, but ' .. (k == 1 and 'a shelter burns' or (k .. ' shelters burn')) .. ' to the ground.' end },
  } }

E[#E + 1] = { id = 'poet', title = 'The wandering poet', icon = 'u.storyteller',
  text = 'A wandering poet asks to spend the season by your fire. In return he offers songs nobody here has ever heard.',
  cond = function() return Sim.known('oral') end,
  choices = {
    { t = 'Let him stay', d = 'Costs 25 food. Culture +50% for 40 days.', cost = { food = 25 }, fn = function() buff('poet', 'The poet\'s songs', 40, { { 'culture', 'm', 1.5 }, { 'happy', 'a', 3 } }, 'u.storyteller'); return 'His songs fill the evenings (culture +50% and mood +3 for 40 days).' end },
    { t = 'One song, then he goes', d = 'Costs 5 food.', cost = { food = 5 }, fn = function() add('culture', 10); return 'He sings once, beautifully, and walks on (+10 culture).' end },
  } }

E[#E + 1] = { id = 'lost', title = 'A child is missing', icon = 'e.children',
  text = 'A child has wandered off into the woods. The light is fading, and wolves have been heard nearby.',
  cond = function(s) return s.pop.children >= 2 end,
  choices = {
    { t = 'Everyone searches', d = 'Work stops for 3 days.', fn = function()
      buff('search', 'The search', 3, { { 'all', 'm', .5 } }, 'e.children'); buff('found', 'The child came home', 10, { { 'happy', 'a', 4 } }, 'e.children')
      return 'The child is found asleep under a fallen tree. Work halves for 3 days, and the tribe celebrates (mood +4 for 10 days).' end },
    { t = 'Send the wanderers', d = 'Likely, but not certain, to find the child.', fn = function()
      if chance(.65) then local k = explore(1); return 'The wanderers find the child by a stream ' .. (k > 0 and 'nobody had seen before (+1 tile).' or 'at the edge of the woods.') end
      Sim.kill(1, 'lost in the woods', 'children'); return 'They search all night but find only tracks.' end },
    { t = 'Wait until morning', d = 'Safer for the searchers.', fn = function()
      if chance(.3) then return 'At dawn the child walks back into camp, cold and hungry.' end
      Sim.kill(1, 'lost in the woods', 'children'); return 'The child is never found.' end },
  } }

E[#E + 1] = { id = 'honey', title = 'The honey tree', icon = 'fruit',
  text = 'Gatherers find a hollow tree humming with bees, its trunk heavy with honey.',
  cond = function(s) return s.day > 60 and Sim.season() < 4 end, again = 500,
  choices = {
    { t = 'Smoke them out', d = 'A sweet, safe haul.', req = function() return Sim.known('fire') end, why = 'Needs Fire-making.', fn = function() add('fruit', 40); buff('honey', 'Honey', 10, { { 'happy', 'a', 3 } }, 'fruit'); return 'The bees drowse in the smoke (+40 food, mood +3 for 10 days).' end },
    { t = 'Brave the stings', d = 'Some honey, some pain.', fn = function() add('fruit', 25); buff('stung', 'Stung', 5, { { 'happy', 'a', -2 } }, 'x.bad'); return 'Swollen hands, but sweet ones (+25 food, mood \u{2212}2 for 5 days).' end },
    { t = 'Leave the bees be', d = 'Nothing happens.', fn = function() return 'The tree hums on.' end },
  } }

E[#E + 1] = { id = 'prophet', title = 'The prophet', icon = 'u.priest',
  text = 'A woman claims the gods speak through her. Crowds gather at her hut each night, and the priests are uneasy.',
  cond = function() return Sim.known('religion') end,
  choices = {
    { t = 'Make her a priest', d = 'Faith +40%, influence \u{2212}15% for 50 days.', fn = function() buff('prophet', 'The prophet', 50, { { 'faith', 'm', 1.4 }, { 'influence', 'm', .85 } }, 'u.priest'); return 'Her words fill the temple (faith +40%, influence \u{2212}15% for 50 days).' end },
    { t = 'Declare her mad', d = 'Order is kept; her followers grieve.', fn = function() add('influence', 10); buff('silenced', 'The silenced prophet', 20, { { 'happy', 'a', -4 } }, 'x.bad'); return 'She is sent away (+10 influence, mood \u{2212}4 for 20 days).' end },
    { t = 'Let her speak', d = 'Culture and faith.', fn = function() add('culture', 20); add('faith', 20); return 'Her visions are argued over at every fire (+20 culture, +20 faith).' end },
  } }

E[#E + 1] = { id = 'collapse', title = 'Cave-in', icon = 'u.miner',
  text = 'A tunnel collapses with miners inside. Their families claw at the rubble with bare hands.',
  cond = function() return Sim.n('miner') >= 3 end, again = 600,
  choices = {
    { t = 'Dig them out at once', d = 'Work slows for 4 days.', fn = function()
      buff('dig', 'Digging out the miners', 4, { { 'all', 'm', .75 } }, 'u.miner')
      if chance(.3) then Sim.kill(1, 'in a mine collapse'); return 'They are dug out after two days. One did not survive (production \u{2212}25% for 4 days).' end
      return 'Every miner comes out alive (production \u{2212}25% for 4 days).' end },
    { t = 'Seal the tunnel', d = 'No more lives risked.', fn = function() local k = 1 + floor(rand() * 2); Sim.kill(k, 'in a mine collapse'); buff('tomb', 'The sealed tunnel', 20, { { 'happy', 'a', -5 } }, 'x.bad'); return 'The tunnel becomes a tomb for ' .. people(k) .. ' (mood \u{2212}5 for 20 days).' end },
  } }

E[#E + 1] = { id = 'farShore', title = 'The far shore', icon = 'u.fisher',
  text = 'Fishers return with tales of a far shore, glimpsed through the mist on a clear morning.',
  cond = function() return Sim.known('canoes') and knows('coast') end,
  choices = {
    { t = 'Send an expedition', d = 'Costs 30 food and 30 water. Charts new land.', cost = { food = 30, water = 30 }, fn = function() local k = explore(4); return 'The canoes return after a month with maps of ' .. k .. ' new ' .. (k == 1 and 'tile' or 'tiles') .. '.' end },
    { t = 'The sea is too wide', d = 'Nothing happens.', fn = function() return 'The far shore stays a story.' end },
  } }

E[#E + 1] = { id = 'hardWinter', title = 'Signs of a hard winter', icon = 'x.winter',
  text = 'The old ones read the signs: thick fur on the beasts, geese flying south early. They say the hardest winter in memory is coming.',
  cond = function(s) return Sim.season() == 3 and s.day % 100 >= 60 and s.day > 300 end, again = 500,
  choices = {
    { t = 'Gather fuel', d = '+50 sticks; fires burn faster all winter.', fn = function()
      add('sticks', 50); buff('bitter', 'Bitter winter', 45, { { 'firedecay', 'm', 1.5 } }, 'x.winter'); return 'Everyone gathers sticks (+50). The winter is bitter: fire pits burn out 50% faster for 45 days.' end },
    { t = 'Sew warm furs', d = 'Costs 10 hides. +12 clothing.', cost = { hides = 10 }, fn = function()
      add('clothing', 12); buff('bitter', 'Bitter winter', 45, { { 'firedecay', 'm', 1.5 } }, 'x.winter'); return 'Furs are sewn by every fire (+12 clothing). The winter is bitter: fire pits burn out 50% faster for 45 days.' end },
    { t = 'Trust in luck', d = 'The old ones are often wrong.', fn = function()
      if chance(.5) then buff('bitter', 'Bitter winter', 45, { { 'firedecay', 'm', 1.5 }, { 'cold', 'm', 1.5 } }, 'x.winter'); return 'The old ones were right. The cold bites 50% harder and fires burn out 50% faster for 45 days.' end
      return 'The winter is no worse than any other.' end },
  } }

E[#E + 1] = { id = 'refugees', title = 'People of the flood', icon = 'ri.migrants',
  text = 'A band of twelve people, driven from their land by floods, asks to join the tribe. They are tired and very hungry.',
  cond = function(s) return s.day > 150 and s.happy > 0 end, again = 500,
  choices = {
    { t = 'Take them all in', d = 'Costs 40 food. 8 adults and 4 children join.', cost = { food = 40 }, fn = function() local s = S(); s.pop.adults = s.pop.adults + 8; s.pop.children = s.pop.children + 4; return 'Twelve new faces at the fire.' end },
    { t = 'Take only the strong', d = '5 adults join; the rest are turned away.', fn = function() local s = S(); s.pop.adults = s.pop.adults + 5; buff('harsh', 'A harsh choice', 15, { { 'happy', 'a', -2 } }, 'x.bad'); return 'Five stay. The others walk on, and the choice weighs on people (mood \u{2212}2 for 15 days).' end },
    { t = 'Turn them away', d = 'Nothing is spent.', fn = function() return 'They walk on toward the hills.' end },
  } }

local EM = {}
for _, e in ipairs(E) do EM[e.id] = e end
Story.EM = EM

---------------------------------------------------------------- running events
function Story.current() local s = S(); return s.story and EM[s.story.id] or nil end
function Story.canChoose(c)
  if c.req and not c.req() then return false, c.why end
  if c.cost and not Sim.payable(c.cost) then return false, 'Cannot afford it.' end
  return true
end
-- Called once a day: maybe starts an event.
function Story.daily()
  local s = S()
  if not Story.enabled or s.story or s.over then return end
  if s.day < (s.nextStory or 0) or rand() > .08 then return end
  local pool, total = {}, 0
  for _, e in ipairs(E) do
    local last = s.storySeen[e.id]
    local fresh = last == nil or (e.again and s.day - last >= e.again)
    if fresh then
      local ok, yes = pcall(e.cond, s)
      if ok and yes then pool[#pool + 1] = e; total = total + (e.w or 1) end
    end
  end
  if #pool == 0 then s.nextStory = s.day + 30; return end
  local r, pick = rand() * total, pool[1]
  for _, e in ipairs(pool) do r = r - (e.w or 1); if r <= 0 then pick = e; break end end
  s.story = { id = pick.id, day = s.day }
  s.storySeen[pick.id] = s.day
  s.nextStory = s.day + 70 + floor(rand() * 60)
  Sim.emit('story', pick)
end
-- Resolves the current event with choice k; returns the outcome text, or nil if that choice is not possible.
function Story.choose(k)
  local s = S()
  local e = Story.current()
  if not e then s.story = nil; return nil end
  local c = e.choices[k]
  if not c or not Story.canChoose(c) then return nil end
  if c.cost then Sim.pay(c.cost) end
  local out = c.fn() or ''
  s.story = nil
  s.storiesDone = (s.storiesDone or 0) + 1
  Sim.rebuildFX()
  Sim.logm(e.title .. '. ' .. out, 'story', e.icon)
  return out
end
-- For scripted test players: picks any affordable choice at random.
function Story.autoChoose()
  local e = Story.current()
  if not e then return end
  local ok = {}
  for k, c in ipairs(e.choices) do if Story.canChoose(c) then ok[#ok + 1] = k end end
  if #ok == 0 then S().story = nil; return end
  return Story.choose(ok[love.math.random(1, #ok)])
end

return Story
