-- Hearthfire Chronicle: sound effects and music, all synthesized in code (no audio files).
-- Effects are built once at start-up. Music is composed phrase by phrase in a background thread (musicthread.lua).
local Audio = {}
local RATE = 44100
local sin, exp, pi, floor, max, min = math.sin, math.exp, math.pi, math.floor, math.max, math.min
local TAU = 2 * pi
local sfx, pools, last = {}, {}, {}
local vol = { music = .5, sound = .7 }
local music, reqCh, outCh, ctlCh, thread
local pending, fade, lastParams = 0, 0, ''
Audio.ok = false

local function noise() return love.math.random() * 2 - 1 end
-- Renders dur seconds by calling fn(t) for every sample.
local function make(dur, fn)
  local n = floor(dur * RATE)
  local sd = love.sound.newSoundData(n, RATE, 16, 1)
  for i = 0, n - 1 do
    local v = fn(i / RATE)
    if v > 1 then v = 1 elseif v < -1 then v = -1 end
    sd:setSample(i, v)
  end
  return sd
end
-- A struck bell: a few inharmonic partials that fade at different speeds.
local function bell(t, f, decay)
  if t < 0 then return 0 end
  local a = math.min(1, t * 400)
  return a * exp(-t * (decay or 3.2)) * (sin(TAU * f * t) + .35 * sin(TAU * f * 2.76 * t) * exp(-t * 5) + .15 * sin(TAU * f * 5.4 * t) * exp(-t * 9))
end
-- A hand drum: a low tone that drops in pitch, with a short slap of noise.
local function drum(t, lo, hi, decay)
  if t < 0 then return 0 end
  local ph = TAU * (lo * t + (hi - lo) * (1 - exp(-t * 22)) / 22)
  return sin(ph) * exp(-t * (decay or 7)) + noise() * exp(-t * 70) * .3
end

local function build()
  local lp = 0
  sfx.click = make(.07, function(t)
    local ph = TAU * (520 * t + 900 * (1 - exp(-t * 40)) / 40)
    return (sin(ph) * exp(-t * 70) * .45 + noise() * exp(-t * 300) * .12)
  end)
  sfx.place = make(.32, function(t)
    lp = lp * .85 + noise() * .15
    return drum(t, 70, 190, 13) * .55 + lp * exp(-t * 25) * .9
  end)
  sfx.done = make(1.1, function(t) return (drum(t, 90, 220, 16) * .25 + bell(t - .06, 880, 3.5) * .22 + bell(t - .16, 1318.5, 3.5) * .18) end)
  sfx.tech = make(1.6, function(t)
    local v = 0
    for k, f in ipairs({ 587.3, 740, 880, 1174.7 }) do v = v + bell(t - (k - 1) * .09, f, 2.8) * (.2 - k * .02) end
    return v
  end)
  sfx.trait = make(1.2, function(t) return bell(t, 659.3, 3) * .2 + bell(t - .14, 987.8, 3) * .16 end)
  sfx.rite = make(1.4, function(t)
    local sw = t < 1.3 and sin(pi * t / 1.3) or 0
    return drum(t, 58, 120, 6) * .45 + drum(t - .24, 62, 130, 8) * (t > .24 and .3 or 0) + (sin(TAU * 146.8 * t) + .6 * sin(TAU * 220 * t)) * sw * .1
  end)
  sfx.bad = make(.7, function(t) return drum(t, 48, 95, 6) * .55 + (t > .2 and drum(t - .2, 45, 85, 6) * .45 or 0) end)
  sfx.death = make(1.1, function(t)
    local a = min(1, t * 12) * exp(-t * 2.6)
    return a * (sin(TAU * (196 - 8 * t) * t) * .2 + sin(TAU * 130.8 * t) * .12)
  end)
  sfx.story = make(1.5, function(t)
    local f = t < .4 and 293.7 or 440
    local tt = t < .4 and t or t - .4
    local a = min(1, tt * 14) * (t < .4 and (1 - tt / .45) or exp(-tt * 1.4))
    local v = 0
    for k = 1, 6 do v = v + sin(TAU * f * k * t) / (k * 1.6) end
    return v * a * .13
  end)
  sfx.milestone = make(2, function(t)
    local v = 0
    for k, f in ipairs({ 587.3, 740, 880, 1174.7, 1480 }) do v = v + bell(t - (k - 1) * .11, f, 2.2) * .15 end
    return v + bell(t - .5, 2349, 2) * .05
  end)
  local w = 0
  sfx.season = make(1.8, function(t)
    local cut = .03 + .05 * (1 + sin(t * 3.3)) / 2
    w = w + (noise() - w) * cut
    return w * sin(pi * t / 1.8) * .55
  end)
  sfx.wonder = make(2.6, function(t)
    local v = drum(t, 50, 110, 4) * .4
    for k, f in ipairs({ 293.7, 440, 587.3, 880 }) do v = v + bell(t - .1 - (k - 1) * .16, f, 1.6) * .14 end
    return v
  end)
  sfx.toast = make(.6, function(t) return bell(t, 1046.5, 5) * .14 end)
  for name, sd in pairs(sfx) do
    local src = love.audio.newSource(sd, 'static')
    pools[name] = { src, src:clone(), src:clone() }
  end
end

local GAP = { click = .05, death = 2.5, bad = 1, season = 3, toast = .3, place = .06 }
function Audio.play(name, volume)
  if not Audio.ok or vol.sound <= 0 or not pools[name] then return end
  local now = love.timer.getTime()
  if last[name] and now - last[name] < (GAP[name] or .4) then return end
  last[name] = now
  for _, src in ipairs(pools[name]) do
    if not src:isPlaying() then src:setVolume(vol.sound * (volume or 1)); src:play(); return end
  end
end

function Audio.init()
  if not love.audio or not love.sound then return end
  local ok, err = pcall(build)
  if not ok then print('sound effects failed: ' .. tostring(err)); return end
  Audio.ok = true
  local ok2, err2 = pcall(function()
    music = love.audio.newQueueableSource(22050, 16, 1, 6)
    reqCh, outCh, ctlCh = love.thread.getChannel('hf_music_req'), love.thread.getChannel('hf_music_out'), love.thread.getChannel('hf_music_ctl')
    reqCh:clear(); outCh:clear(); ctlCh:clear()
    thread = love.thread.newThread('musicthread.lua')
    thread:start()
  end)
  if not ok2 then print('music failed: ' .. tostring(err2)); music = nil end
end
function Audio.setVolumes(m, s) vol.music, vol.sound = m, s end

-- params: season (1-4), level (0-3, grows with discoveries), mood, title (true on the title screen)
function Audio.update(dt, params)
  if not music then return end
  local key = params.season .. '|' .. params.level .. '|' .. (params.title and 1 or 0) .. '|' .. (params.mood > -20 and 1 or 0)
  if key ~= lastParams then lastParams = key; ctlCh:clear(); ctlCh:push({ season = params.season, level = params.level, title = params.title and true or false, mood = params.mood }) end
  while true do
    local sd = outCh:pop()
    if not sd then break end
    music:queue(sd); pending = max(0, pending - 1)
  end
  local queued = 6 - music:getFreeBufferCount()
  if vol.music > 0 then
    if queued + pending < 2 then reqCh:push(1); pending = pending + 1 end
    if not music:isPlaying() and queued > 0 then music:play() end
  elseif music:isPlaying() then music:pause() end
  fade = min(1, fade + dt / 4)
  music:setVolume(vol.music * .8 * fade)
end
function Audio.status()
  if not music then return 'music off' end
  return string.format('music %s, %d phrases queued, %d pending, volume %.2f', music:isPlaying() and 'playing' or 'stopped', 6 - music:getFreeBufferCount(), pending, music:getVolume())
end
function Audio.threadError(msg) print('music thread: ' .. tostring(msg)); if music then music:stop() end; music = nil end

return Audio
