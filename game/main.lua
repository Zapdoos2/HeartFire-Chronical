-- Hearthfire Chronicle: a tribe game in the style of NeverEnding Legacy, written in Lua for the LÖVE engine.
-- Runs on macOS and Windows. Saves live in the player's application-data folder.
local Sim = require('sim')
local Art = require('art')
local UI = require('ui')
local Screens = require('screens')
local Title = require('title')
local Story = require('story')
local Legacy = require('legacy')
local Settings = require('settings')
local Audio = require('audio')
local DPI = require('dpi')
local json = require('json')

local SAVE = 'save.json'
local acc, saveTimer = 0, 0
local test = {}     -- options for self-test and snapshot runs
local mode = 'title'
local quiet = false -- true while a scripted player runs, so it makes no sound and no notices

local function save(silent)
  if test.noSave or not Sim.S then return end
  local ok = love.filesystem.write(SAVE, json.encode(Sim.S))
  if ok and not silent then Screens.saveNoteT = love.timer.getTime() end
end

local function loadSave()
  if love.filesystem.getInfo(SAVE) then
    local d = json.decode(love.filesystem.read(SAVE) or '')
    if d and pcall(Sim.loadState, d) then return true end
  end
  -- bring over a tribe from the earlier Mac app, which stored its save in storage.json in this same folder
  if love.filesystem.getInfo('storage.json') then
    local outer = json.decode(love.filesystem.read('storage.json') or '')
    local inner = outer and outer['hearthfire-v1'] and json.decode(outer['hearthfire-v1'])
    if inner and pcall(Sim.loadState, inner) then
      Sim.logm('The chronicle continues in a new home.', 'era', 'x.scroll')
      return true
    end
  end
  return false
end

local function resetBoard()
  Screens.tab = 'production'
  for _, sc in pairs(UI.scroll) do sc.y = 0; sc.stick = nil end
  Screens.storyResult, Screens.toasts, Screens.lastEmbers, Screens.reveal = nil, {}, nil, {}
end
local function living() local s = Sim.S; return s and not s.over and not s.legacyDone end
-- Founds a new tribe; the one being played, if any, is retired into the legacy first.
local function found(name)
  if living() then Legacy.endTribe('retired') end
  Legacy.founded()
  Sim.newGame(Legacy.startOptions(name))
  resetBoard()
  save(true)
  mode = 'game'
  Screens.help = Legacy.D.founded == 1 and not test.snapshot
end

local function exportCode()
  local data = json.encode(Sim.S)
  love.system.setClipboardText(love.data.encode('string', 'base64', data))
  return 'Save code copied to the clipboard.'
end
local function importCode()
  local text = (love.system.getClipboardText() or ''):gsub('%s', '')
  if text == '' then return 'The clipboard is empty. Copy a save code first.' end
  local ok, raw = pcall(love.data.decode, 'string', 'base64', text)
  local d = ok and json.decode(raw)
  if not d or not pcall(Sim.loadState, d) then return 'That is not a save code. Copy the whole code with nothing around it.' end
  resetBoard()
  save(true)
  return 'Save code loaded.'
end

---------------------------------------------------------------- sounds and notices for notable moments
local BAD = { beasts = true, fire = true, flood = true, plague = true, raiders = true, harsh = true }
local function onEmit(kind, d)
  if kind == 'over' then Screens.lastEmbers = Legacy.endTribe('died out'); save(true) end
  if quiet then return end
  local T = Screens.toast
  if kind == 'tech' then Audio.play('tech'); T('Discovery: ' .. d.n, Sim.TECH_ICON[d.id], 'tech')
  elseif kind == 'trait' then Audio.play('trait'); T('A new custom: ' .. d.n, Sim.TRAIT_ICON[d.id], 'trait')
  elseif kind == 'built' then Audio.play('done', .7)
  elseif kind == 'wonder' then Audio.play('wonder'); T('A wonder is finished: the ' .. d.n, 'b.' .. d.id, 'wonder')
  elseif kind == 'era' then Audio.play('milestone'); T('A new age begins: the ' .. d, 'b.monument', 'era')
  elseif kind == 'rite' then Audio.play('rite')
  elseif kind == 'death' then Audio.play('death', .8)
  elseif kind == 'season' then Audio.play('season', d == 'Winter' and 1 or .6)
  elseif kind == 'story' then Audio.play('story')
  elseif kind == 'milestone' then Audio.play('milestone'); T('Milestone: ' .. d.n .. '  (+' .. d.e .. (d.e == 1 and ' ember)' or ' embers)'), d.icon, 'milestone')
  elseif kind == 'event' then Audio.play(BAD[d] and 'bad' or 'toast') end
end

---------------------------------------------------------------- self-test (no game save is touched)
-- A simple scripted player used by the self-test and by test snapshots.
local function botStep(S, d)
  if S.story then Story.autoChoose() end
  if d % 5 == 1 then
    local W = Sim.assignCap()
    local eat = (S.pop.adults + S.pop.elders + S.pop.children * .5) * .6
    local crisis = S.foodShort > .01 or S.waterShort > .01 or Sim.foodTotal() < eat * 8 or S.res.water < eat * 8
    local builders = (Sim.known('shelter') and #S.queue > 0) and math.max(1, math.ceil(W / 18)) or 0
    local want = crisis and { dreamer = W >= 6 and 1 or 0, wanderer = #Sim.frontier() > 0 and 1 or 0, builder = math.min(builders, 1) } or {
      dreamer = math.max(1, math.floor(W * .12 + .5)), wanderer = #Sim.frontier() > 0 and 1 or 0, builder = builders,
      knapper = Sim.known('knapping') and math.ceil(W / 20) or 0, firekeeper = Sim.known('fire') and math.ceil(W / 20) or 0,
      storyteller = Sim.known('oral') and 1 + math.floor(W / 40) or 0, soothsayer = Sim.known('ritualism') and 1 + math.floor(W / 40) or 0,
      chieftain = Sim.known('chieftains') and math.min(2, Sim.UM.chieftain.max()) or 0, woodcutter = Sim.known('woodcutting') and math.ceil(W / 15) or 0,
      digger = Sim.known('digging') and math.ceil(W / 20) or 0, healer = (Sim.known('healing') and S.pop.sick > 2) and 2 or 0, mason = Sim.known('masonry') and 1 or 0,
      scholar = Sim.known('writing') and Sim.UM.scholar.max() or 0, farmer = (Sim.known('agriculture') and Sim.season() < 4) and math.ceil(W / 5) or 0,
      fisher = Sim.known('fishing') and math.ceil(W / 10) or 0 }
    local order = { 'dreamer', 'wanderer', 'builder', 'knapper', 'firekeeper', 'storyteller', 'soothsayer', 'chieftain', 'woodcutter', 'digger', 'healer', 'mason', 'scholar', 'farmer', 'fisher' }
    S.units = {}
    local left = W
    for _, id in ipairs(order) do local k = math.min(want[id] or 0, left); S.units[id] = k; left = left - k end
    S.units.gatherer = (S.units.gatherer or 0) + left
  end
  local best
  for _, t in ipairs(Sim.TECHS) do if not Sim.known(t.id) and Sim.reqMet(t) and Sim.payable(t.cost) and (not best or t.cost.insight < best.cost.insight) then best = t end end
  if best then Sim.research(best.id) end
  local planned = 0
  for _, q in ipairs(S.queue) do planned = planned + (Sim.BM[q.id].house or 0) end
  for _, id in ipairs({ 'house', 'hut', 'mudhut', 'leanto' }) do
    if Sim.homeless() - planned > 0 and Sim.known(Sim.BM[id].tech) and Sim.payable(Sim.BM[id].cost) then Sim.build(id, 1); break end
  end
  -- a wonder in reach takes priority over everything but graves and housing
  local saving = false
  for _, b in ipairs(Sim.BLDS) do
    if b.wonder and Sim.bldAvail(b) and Sim.bld(b.id) == 0 and Sim.queued(b.id) == 0 then
      if Sim.payable(b.cost) then Sim.build(b.id, 1) else saving = true end
      break
    end
  end
  for _, id in ipairs({ 'grave', 'stockpile', 'granary', 'warehouse', 'well', 'shrine', 'circle', 'library', 'temple', 'market' }) do
    local want = id == 'grave' and math.ceil(Sim.popTotal() / 8) or math.ceil(Sim.popTotal() / 30)
    if (not saving or id == 'grave' or id == 'stockpile' or id == 'warehouse') and Sim.known(Sim.BM[id].tech) and Sim.payable(Sim.BM[id].cost) and Sim.bld(id) + Sim.queued(id) < want then Sim.build(id, 1) end
  end
  for _, r in ipairs(Sim.RITES) do if love.math.random() < .05 then Sim.doRite(r.id) end end
end

local function selfTest()
  local out = {}
  local function say(...) local t = table.concat({ ... }, ' '); out[#out + 1] = t; print(t) end
  local ok, err = pcall(function()
    local runs, overs, nan = tonumber(test.runs) or 5, 0, 0
    local wonders, stories, built, errs = 0, 0, 0, 0
    for run = 1, runs do
      Sim.newGame()
      local S = Sim.S
      for d = 1, tonumber(test.days) or 3000 do
        if S.over then break end
        botStep(S, d)
        Sim.simDay()
        for _, k in ipairs(Sim.RKEYS) do if S.res[k] ~= S.res[k] then nan = nan + 1 end end
        if test.trace and (S.day % 100 == 0 or S.over) then
          local hb = Sim.BM.hearth
          say(string.format('  y%d pop %d food %d water %d short %.2f/%.2f homeless %d queue %d rate %.1f techs %d | hearth avail %s stone %d/%d wood %d clay %d | sick %d corpses %.0f',
            S.day / 100, Sim.popTotal(), Sim.foodTotal(), S.res.water, S.foodShort, S.waterShort, Sim.homeless(), #S.queue, S._buildRate or 0, #S.techs,
            tostring(Sim.bldAvail(hb)), S.res.stone, Sim.cap('stone'), S.res.wood, S.res.clay, S.pop.sick, S.res.corpses))
        end
      end
      if S.over then overs = overs + 1 end
      wonders, stories, built = wonders + Sim.wondersBuilt(), stories + S.storiesDone, built + S.built
      say(string.format('run %d: year %d, %d people (peak %d), %d discoveries, %d traits, %d buildings raised, %d wonders, %d stories, %s', run, math.floor(S.day / 100) + 1, Sim.popTotal(), S.peak,
        #S.techs, #S.traits, S.built, Sim.wondersBuilt(), S.storiesDone, S.over and 'DIED OUT' or 'alive'))
    end
    say('died out: ' .. overs .. ' of ' .. runs .. ', broken numbers: ' .. nan .. ', wonders: ' .. wonders .. ', stories: ' .. stories)
    -- every rite, policy and story choice at least once, in a rich sandbox
    Sim.newGame()
    local S = Sim.S
    for _, t in ipairs(Sim.TECHS) do S.techs[#S.techs + 1] = t.id end
    Sim.rebuildFX()
    for _, k in ipairs(Sim.RKEYS) do S.res[k] = 500 end
    S.pop.adults, S.pop.elders, S.pop.children = 120, 10, 10
    S.day = 1000
    for _, b in ipairs(Sim.BLDS) do if not b.wonder then S.blds[b.id] = 3 end end
    S.units.miner, S.units.knapper, S.units.farmer = 4, 2, 5
    local riteFails = {}
    for _, r in ipairs(Sim.RITES) do if not Sim.doRite(r.id) then riteFails[#riteFails + 1] = r.id end end
    for _, p in ipairs(Sim.POLICIES) do S.res.influence = 100; Sim.setPolicy(p.id, p.opts and 'plenty' or true) end
    for _, t in ipairs(Sim.TRAITS) do if t.story then S.traits[#S.traits + 1] = t.id end end
    for _, b in ipairs(Sim.BLDS) do if b.wonder then S.res.stone, S.res.bricks, S.res.wood, S.res.metal, S.res.clay, S.res.pottery, S.res.hides, S.res.culture, S.res.faith = 2000, 2000, 2000, 2000, 2000, 2000, 2000, 2000, 2000; Sim.build(b.id, 1) end end
    S.units.builder = 100
    for _ = 1, 60 do Sim.simDay() end
    say('wonders raised in the sandbox: ' .. Sim.wondersBuilt() .. ' of 7, queue left: ' .. #S.queue)
    local storyFails = {}
    for _, e in ipairs(Story.EVENTS) do
      for k, c in ipairs(e.choices) do
        for _, kk in ipairs(Sim.RKEYS) do S.res[kk] = math.max(S.res[kk], 300) end
        S.pop.adults, S.pop.elders, S.pop.children = math.max(S.pop.adults, 60), math.max(S.pop.elders, 4), math.max(S.pop.children, 6)
        S.story = { id = e.id, day = S.day }
        local okc, res = pcall(Story.choose, k)
        if not okc or not res then storyFails[#storyFails + 1] = e.id .. ':' .. k .. (okc and '' or (' ' .. tostring(res))) end
        S.story = nil
      end
      local okc = pcall(e.cond, S)
      if not okc then storyFails[#storyFails + 1] = e.id .. ':cond' end
    end
    for _ = 1, 40 do Sim.simDay() end
    for _ = 1, 300 do Sim.randomEvent() end
    say('rites that would not run: ' .. (#riteFails > 0 and table.concat(riteFails, ', ') or 'none'))
    local miss = require('flavor').missing()
    say('flavor lines missing: ' .. (#miss > 0 and table.concat(miss, ', ') or 'none'))
    say('story choices that failed: ' .. (#storyFails > 0 and table.concat(storyFails, ', ') or 'none') .. ' (' .. #Story.EVENTS .. ' events)')
    -- legacy: scoring and perks
    local e = Legacy.score(S)
    for _, p in ipairs(Legacy.PERKS) do Legacy.D.embers = 999; while Legacy.buy(p.id) do end end
    local o = Legacy.startOptions('Testers')
    Sim.newGame(o)
    say('legacy: sandbox tribe scores ' .. e .. ' embers; fully perked tribe starts with ' .. Sim.popTotal() .. ' people and ' .. #Sim.S.techs .. ' discoveries; ' .. #Sim.perkFX .. ' perk effects')
    -- window sizes for common Windows displays (screen size and display scale): each must fit the screen and
    -- leave at least the smallest board the layout is designed for (1000 x 640 units)
    do
      local keep, bad, list = DPI.scale, 0, {}
      for _, c in ipairs({ { 1280, 720, 1 }, { 1366, 768, 1 }, { 1366, 768, 1.25 }, { 1920, 1080, 1 }, { 1920, 1080, 1.25 }, { 1920, 1080, 1.5 }, { 1920, 1200, 1.5 },
        { 2560, 1440, 1.25 }, { 2560, 1440, 1.5 }, { 2560, 1600, 2 }, { 2880, 1800, 2 }, { 3840, 2160, 1.5 }, { 3840, 2160, 2 } }) do
        DPI.scale = c[3]
        local w, h, minw, minh = DPI.windowSize(c[1], c[2])
        local ui = math.min(c[3], w / 1000, h / 640)
        if w > c[1] or h > c[2] - 60 * c[3] or w / ui < 999.5 or h / ui < 639.5 or minw > w or minh > h then bad = bad + 1 end
        list[#list + 1] = string.format('%dx%d at %d%% -> window %dx%d, interface %d%%', c[1], c[2], c[3] * 100, w, h, math.floor(ui * 100 + .5))
      end
      DPI.scale = keep
      say('window on common Windows displays: ' .. (bad == 0 and 'all fit' or (bad .. ' DO NOT FIT')))
      if test.trace or bad > 0 then for _, l in ipairs(list) do say('  ' .. l) end end
    end
    -- save round trip
    for d = 1, 400 do botStep(Sim.S, d); Sim.simDay() end
    local before = json.encode(Sim.S)
    Sim.loadState(json.decode(before))
    local after = json.encode(Sim.S)
    say('save round trip: ' .. (#before > 1000 and math.abs(#before - #after) < 50 and 'ok' or ('MISMATCH ' .. #before .. ' vs ' .. #after)))
    if test.migrate then
      local f = io.open(test.migrate, 'r')
      local raw = f:read('*a'); f:close()
      local d = json.decode(raw)
      if d['hearthfire-v1'] then d = json.decode(d['hearthfire-v1']) end
      Sim.loadState(d)
      say('loaded tribe: ' .. Sim.S.name .. ', day ' .. Sim.S.day .. ', ' .. #Sim.S.techs .. ' discoveries, ' .. Sim.popTotal() .. ' people, home tile ' .. Sim.BIOME[Sim.S.map[Sim.S.home]].n .. ', explored ' .. Sim.S.explored)
      for _ = 1, 50 do Sim.simDay() end
      say('after 50 more days: ' .. Sim.popTotal() .. ' people, day ' .. Sim.S.day .. ', story pending: ' .. tostring(Sim.S.story and Sim.S.story.id))
    end
  end)
  if not ok then say('SELFTEST ERROR: ' .. tostring(err)) end
  love.filesystem.write('selftest.txt', table.concat(out, '\n'))
end

---------------------------------------------------------------- settings
local function applyScale(pref)
  if UI.fitScale(pref) or pref then
    UI.loadFonts()
    Sim.mapDirty = true
    if Sim.S then for _, e in ipairs(Sim.S.log) do e._w = nil end end
  end
end
Settings.onChange = function(k, v)
  if k == 'music' or k == 'sound' then Audio.setVolumes(Settings.get('music'), Settings.get('sound'))
  elseif k == 'ui' then applyScale(v)
  elseif k == 'fullscreen' then love.window.setFullscreen(v, 'desktop'); applyScale()
  elseif k == 'stories' then Story.enabled = v end
end

---------------------------------------------------------------- LÖVE callbacks
function love.load(arg)
  for i = 1, #arg do
    local a = arg[i]
    if a:sub(1, 2) == '--' then
      local nxt = arg[i + 1]
      if nxt and nxt:sub(1, 2) ~= '--' then test[a:sub(3)] = nxt else test[a:sub(3)] = true end
    end
  end
  if test.selftest or test.snapshot then
    love.filesystem.setIdentity('Hearthfire Chronicle test')
    test.noSave = not test.keep
    Legacy.noSave, Settings.noSave = not test.keep, true
    love.window.setTitle('Hearthfire Chronicle \u{2014} test run')
  end
  Settings.load()
  if test.scale then Settings.data.ui = tonumber(test.scale) end
  if Settings.get('fullscreen') and not test.snapshot then love.window.setFullscreen(true, 'desktop') end
  -- The window opened at the design size times the display scale (conf.lua). On a small screen, shrink it to fit.
  UI.os = DPI.scale
  local dw, dh = love.window.getDesktopDimensions()
  local ww, wh, flags = love.window.getMode()
  if dw and dh and not love.window.getFullscreen() then
    local w, h, minw, minh = DPI.windowSize(dw, dh)
    if ww > w or wh > h then
      flags.minwidth, flags.minheight = minw, minh
      love.window.setMode(math.min(ww, w), math.min(wh, h), flags)
    end
  end
  if test.size then local w, h = test.size:match('(%d+)x(%d+)'); local _, _, fl = love.window.getMode(); fl.minwidth, fl.minheight = 400, 300; love.window.setMode(tonumber(w), tonumber(h), fl) end
  love.graphics.setDefaultFilter('linear', 'linear')
  love.keyboard.setKeyRepeat(true)
  UI.fitScale(Settings.get('ui'))
  UI.loadFonts()
  UI.loadTextures()
  Art.load()
  Legacy.load()
  Story.enabled = Settings.get('stories')
  Sim.emit = onEmit
  Sim.onDay = function() Story.daily(); Legacy.check() end
  UI.onClick = function() Audio.play('click', .55) end
  Screens.sfx = function(n) Audio.play(n) end
  Screens.onSave = function() save() end
  Screens.onExport = exportCode
  Screens.onImport = importCode
  Screens.onOpenFolder = function() love.system.openURL('file://' .. love.filesystem.getSaveDirectory()) end
  Screens.onNewGame = function() mode = 'title'; Title.page = 'new'; Title.name = Sim.tribeName() end
  Screens.onRetire = function() Legacy.endTribe('retired'); save(true); mode = 'title'; Title.page = 'new'; Title.name = Sim.tribeName() end
  Screens.onTitle = function() save(true); mode = 'title'; Title.page = 'main' end
  Screens.onLegacy = function() save(true); mode = 'title'; Title.page = 'legacy'; Title.back = 'game' end
  Title.onBackToGame = function() mode = 'game' end
  Title.onContinue = function() mode = 'game' end
  Title.onFound = found
  Title.onQuit = function() love.event.quit() end
  Title.hasGame = function()
    if not living() then return nil end
    local s = Sim.S
    return 'The ' .. s.name .. ' tribe  \u{00b7}  ' .. Sim.dateStr(s.day) .. '  \u{00b7}  ' .. Sim.popTotal() .. ' people'
  end

  if test.selftest then quiet = true; selfTest(); love.event.quit(); return end
  if not test.mute then Audio.init() end
  Audio.setVolumes(Settings.get('music'), Settings.get('sound'))

  local loaded = not test.fresh and loadSave()
  if test.state then
    local f = io.open(test.state, 'r')
    local raw = f:read('*a'); f:close()
    local d = json.decode(raw)
    if d and d['hearthfire-v1'] then d = json.decode(d['hearthfire-v1']) end
    Sim.loadState(d); loaded = true
  end
  if loaded then Legacy.check() end
  if test.snapshot then
    if not loaded then Sim.newGame(Legacy.startOptions(test.name)) end
    mode = test.title and 'title' or 'game'
    if test.page then Title.page = test.page; Title.name = 'Ashvale' end
    if test.ltab then Title.legacyTab = test.ltab end
  end
  if test.tab then Screens.tab = test.tab end
  if test.days then local S = Sim.S; for _ = 1, tonumber(test.days) do if not S.over then Sim.simDay() end end end
  if test.botdays then
    quiet = true
    local S = Sim.S
    for d = 1, tonumber(test.botdays) do if S.over then break end; botStep(S, d); Sim.simDay() end
    quiet = false
    if S.story then Story.autoChoose() end
  end
  if test.techs then
    local k = tonumber(test.techs) or #Sim.TECHS
    for i = 1, math.min(k, #Sim.TECHS) do local t = Sim.TECHS[i]; if not Sim.known(t.id) then Sim.S.techs[#Sim.S.techs + 1] = t.id end end
    Sim.rebuildFX()
  end
  if test.rich then for _, k in ipairs(Sim.RKEYS) do Sim.S.res[k] = math.max(Sim.S.res[k], math.min(Sim.cap(k), 400)) end end
  if test.plan then for id in test.plan:gmatch('[%a]+') do Sim.build(id, 1) end end
  if test.story then Sim.S.story = { id = test.story, day = Sim.S.day } end
  if test.help then Screens.help = true end
  if test.hover then test.hoverX, test.hoverY = test.hover:match('(%d+),(%d+)') end
  if test.snapshot then Sim.S.speed = 0 end
  if test.toast then Screens.toast('Milestone: A growing camp  (+1 ember)', 'e.people', 'milestone'); Screens.toast('Discovery: Fire-making', 'fire', 'tech') end
end

function love.resize() applyScale() end

local function audioParams()
  local s = Sim.S
  local k = s and #s.techs or 0
  return { season = (s and mode == 'game') and Sim.season() or 4, level = k >= 30 and 3 or k >= 15 and 2 or k >= 5 and 1 or 0, mood = s and s.happy or 0, title = mode == 'title' }
end

---------------------------------------------------------------- hover sweep (test only)
-- Moves the mouse over a grid of points on the board and holds it still at each for a few frames. If the hovered
-- item, the info box or the tiles move while the mouse stands still, something is bouncing under the cursor.
-- With --sweep click it also clicks at every point, alternating left and right clicks, like a player adding and
-- removing workers; --sweepscroll max runs it with the production list scrolled to the bottom (the buildings).
local sweep
local function boardSignature()
  local top, ib = math.huge, -1
  for _, h in ipairs(UI.hits) do
    if type(h.id) == 'string' and h.id:sub(1, 5) == 'tile:' and h.y < top then top = h.y end
    if h.id == 'infobox' then ib = h.h end
  end
  return tostring(Screens.infoKey) .. '|' .. math.floor(top * 10 + .5) .. '|' .. math.floor(ib * 10 + .5) / 10
end
local function sweepStep()
  if not sweep then
    sweep = { pts = {}, i = 1, osc = {}, shifts = {}, heights = {}, clicks = 0 }
    if test.sweepscroll then local sc = UI.scrollState('prod'); sc.y = sc.max end
    for y = 140, UI.H - 12, tonumber(test.sweepstep) or 7 do
      for x = 262, UI.W - 322, tonumber(test.sweepstep) or 7 do sweep.pts[#sweep.pts + 1] = { x, y } end
    end
  end
  -- each point: hold the mouse there for seven drawn frames (drawn straight away, without waiting for the screen)
  for _ = 1, 60 do
    local p = sweep.pts[sweep.i]
    if not p then
      UI.forceMouse = nil
      local hs = {}
      for hgt in pairs(sweep.heights) do hs[#hs + 1] = hgt end
      table.sort(hs)
      print(string.format('sweep: %d points, %d clicks, %d bouncing, %d one-off shifts, info box heights seen: %s', #sweep.pts, sweep.clicks, #sweep.osc, #sweep.shifts, table.concat(hs, ' ')))
      if #sweep.osc > 0 then print('bouncing at: ' .. table.concat(sweep.osc, '; ', 1, math.min(8, #sweep.osc))) end
      if #sweep.shifts > 0 then print('shifts at: ' .. table.concat(sweep.shifts, '; ', 1, math.min(8, #sweep.shifts))) end
      love.event.quit()
      return
    end
    UI.forceMouse = p
    local g = {}
    for f = 1, 7 do
      Screens.draw(0)
      if f == 2 and test.sweep == 'click' then UI.click(p[1], p[2], sweep.i % 2 == 0 and 2 or 1); sweep.clicks = sweep.clicks + 1 end
      if f >= 3 then local sig = boardSignature(); g[#g + 1] = sig; sweep.heights[sig:match('|([^|]*)$')] = true end
    end
    local changes = 0
    for k = 2, #g do if g[k] ~= g[k - 1] then changes = changes + 1 end end
    local where = p[1] .. ',' .. p[2] .. ' (' .. tostring(Screens.infoKey) .. ')'
    if changes >= 2 then sweep.osc[#sweep.osc + 1] = where elseif changes == 1 then sweep.shifts[#sweep.shifts + 1] = where end
    sweep.i = sweep.i + 1
  end
end

function love.update(dt)
  dt = math.min(dt, 1)
  local S = Sim.S
  if mode == 'game' and S and not S.over and not Screens.overlayOpen() then
    acc = acc + dt * (S.speed or 0)
    local k = 0
    while acc >= 1 and k < 12 do
      acc = acc - 1; Sim.simDay(); k = k + 1
      if Screens.overlayOpen() then acc = 0; break end
    end
    if k >= 12 then acc = 0 end
  end
  saveTimer = saveTimer + dt
  if saveTimer > 30 then saveTimer = 0; if mode == 'game' then save() end end
  Audio.update(dt, audioParams())
  if test.snapshot then
    test.t = (test.t or 0) + dt
    if test.sweep and test.t > .5 then sweepStep(); return end
    if test.rtest and test.t > .5 and not test.rdone then
      -- right-click test: a right-click on a job removes workers when the chosen action is "Add 1"
      test.rdone = true
      Screens.modeIdx = 1
      for _, h in ipairs(UI.hits) do
        if h.id == 'tile:u:gatherer' then
          local before = Sim.n('gatherer')
          UI.click(h.x + h.w / 2, h.y + h.h / 2, 2)
          local mid = Sim.n('gatherer')
          UI.click(h.x + h.w / 2, h.y + h.h / 2, 1)
          print(string.format('right-click test: gatherers %d -> %d after a right-click -> %d after a left-click', before, mid, Sim.n('gatherer')))
        end
      end
    end
    if test.hoverX then love.mouse.setPosition(tonumber(test.hoverX) * UI.scale, tonumber(test.hoverY) * UI.scale) end
    if test.clicks and test.t > .4 then
      test.queue = test.queue or {}
      if not test.queued then test.queued = true; for cx, cy in test.clicks:gmatch('(%d+),(%d+)') do test.queue[#test.queue + 1] = { tonumber(cx), tonumber(cy) } end end
      local c = table.remove(test.queue, 1)
      if c then UI.click(c[1], c[2], 1); test.t = .41 end
    end
    if test.fps then test.frames = (test.frames or 0) + 1; test.ft = (test.ft or 0) + dt end
    if test.t > (test.fps and 4 or (tonumber(test.wait) or 1.5)) and not test.shot then
      if test.fps then print(string.format('average frame: %.1f ms (%d frames)', test.ft / test.frames * 1000, test.frames)); print(Audio.status()) end
      test.shot = true
      love.graphics.captureScreenshot(function(img)
        img:encode('png', 'snapshot.png')
        print('snapshot: ' .. love.filesystem.getSaveDirectory() .. '/snapshot.png')
        love.event.quit()
      end)
    end
  end
end

local lastDt = 0
function love.draw()
  if mode == 'title' then Title.draw(lastDt) else Screens.draw(lastDt) end
  lastDt = love.timer.getDelta()
end

local isMac = love.system.getOS() == 'OS X'
function love.mousepressed(x, y, button)
  -- a Ctrl-click on a Mac counts as a right-click, as it does everywhere else on macOS
  if button == 1 and isMac and love.keyboard.isDown('lctrl', 'rctrl') then button = 2 end
  if button == 1 or button == 2 then UI.click(x / UI.scale, y / UI.scale, button) end
end
function love.mousereleased() UI.released() end
function love.mousemoved(x, y) UI.moved(x / UI.scale, y / UI.scale) end
function love.wheelmoved(_, y) UI.wheel(y) end
function love.textinput(t) if mode == 'title' then Title.textinput(t) end end
function love.keypressed(key, _, isRepeat)
  if key == 'f11' or (key == 'f' and love.keyboard.isDown('lgui', 'rgui') and love.keyboard.isDown('lctrl', 'rctrl')) then
    Settings.set('fullscreen', not love.window.getFullscreen()); return
  end
  if mode == 'title' then Title.keypressed(key); return end
  if isRepeat then return end
  local S = Sim.S
  if S.story and not Screens.storyResult and key:match('^%d$') then Screens.chooseStory(tonumber(key)); return end
  if Screens.storyResult and (key == 'return' or key == 'space' or key == 'escape') then Screens.storyResult = nil; return end
  if key == 'space' then S.speed = (S.speed or 0) > 0 and 0 or 1
  elseif key == 'escape' then
    if Screens.help then Screens.help = false elseif Sim.known('history') and not S.wonSeen then S.wonSeen = true end
  elseif key == 'h' or key == 'f1' then Screens.help = not Screens.help
  elseif key:match('^%d$') and tonumber(key) >= 1 and tonumber(key) <= #Screens.TABS then Screens.setTab(Screens.TABS[tonumber(key)][1])
  end
end
function love.focus(f) if not f and mode == 'game' then save(true) end end
function love.quit() save(true); return false end
function love.threaderror(_, err) Audio.threadError(err) end

-- In a test run (--selftest or --snapshot) an error is printed to the terminal and the run ends at once,
-- so a failed test never leaves an error window open on the player's screen. Normal play keeps LÖVE's usual error screen.
local defaultErrorHandler = love.errorhandler
function love.errorhandler(msg)
  if test.selftest or test.snapshot then
    print('TEST RUN ERROR: ' .. tostring(msg) .. '\n' .. debug.traceback('', 2))
    return function() return 1 end
  end
  return defaultErrorHandler(msg)
end
