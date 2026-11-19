-- Hearthfire Chronicle: the music, composed live in a background thread.
-- Each request yields one phrase of four bars: a drone that follows a slow chord pattern, a plucked melody,
-- and, as the tribe grows, a hand drum, a flute and a second plucked voice. Notes that ring past the end of a
-- phrase carry over into the next one, so phrases join without seams.
require('love.sound')
require('love.math')
local ffi = require('ffi')
local reqCh = love.thread.getChannel('hf_music_req')
local outCh = love.thread.getChannel('hf_music_out')
local ctlCh = love.thread.getChannel('hf_music_ctl')

local sin, exp, pi, floor, max, min, abs = math.sin, math.exp, math.pi, math.floor, math.max, math.min, math.abs
local TAU = 2 * pi
local RATE = 22050
local BPM = 66
local BEAT = 60 / BPM
local BAR = BEAT * 4
local PH = floor(BAR * 4 * RATE)
local TAIL = floor(5 * RATE)
local N = PH + TAIL
local buf = ffi.new('float[?]', N)
local carry = ffi.new('float[?]', TAIL)
local rng = love.math.newRandomGenerator(os.time())
local function rnd() return rng:random() end
local params = { season = 1, level = 0, mood = 0, title = true }

local function freq(semis) return 146.83 * 2 ^ (semis / 12) end    -- semitones above D3
local MAJOR = { 0, 2, 4, 7, 9 }
local MINOR = { 0, 3, 5, 7, 10 }
local PROG_MAJOR = { { 0, -3, 2, 7 }, { 0, 7, -3, 0 }, { 0, 2, 7, 0 }, { -3, 2, 0, 7 } }
local PROG_MINOR = { { 0, -2, 3, -5 }, { 0, 3, -2, 0 }, { 0, -5, -2, 0 }, { 3, -2, 0, -5 } }

-- scale degree index -> semitones above D3 (degree 1 = D3)
local function degree(scale, d)
  local oct = floor((d - 1) / #scale)
  local k = (d - 1) % #scale + 1
  return scale[k] + 12 * oct
end

---------------------------------------------------------------- voices
local function pluck(start, semis, amp, dur)
  local f = freq(semis)
  local L = max(2, floor(RATE / f + .5))
  local line = ffi.new('float[?]', L)
  local prev = 0
  for i = 0, L - 1 do prev = prev * .45 + (rnd() * 2 - 1) * .55; line[i] = prev end
  local n = floor(dur * RATE)
  local idx = 0
  for i = 0, n - 1 do
    local j = start + i
    if j >= N then break end
    local nx = idx + 1; if nx >= L then nx = 0 end
    local a = line[idx]
    line[idx] = (a + line[nx]) * .4985
    local env = i < 40 and i / 40 or 1
    buf[j] = buf[j] + a * amp * env
    idx = nx
  end
end
local function pad(start, len, semis, amp)
  local f1 = freq(semis)
  local f2 = f1 * 1.0028
  local att, rel = floor(.9 * RATE), floor(1.1 * RATE)
  local total = len + rel
  for i = 0, total - 1 do
    local j = start + i
    if j >= N then break end
    local env = i < att and (i / att) or (i > len and (1 - (i - len) / rel) or 1)
    local t = i / RATE
    local v = sin(TAU * f1 * t) + .7 * sin(TAU * f2 * t) + .22 * sin(TAU * 2 * f1 * t)
    buf[j] = buf[j] + v * env * env * amp
  end
end
local function drum(start, amp)
  local n = floor(.6 * RATE)
  local ph = 0
  for i = 0, n - 1 do
    local j = start + i
    if j >= N then break end
    local t = i / RATE
    local f = 52 + 70 * exp(-t * 24)
    ph = ph + TAU * f / RATE
    buf[j] = buf[j] + (sin(ph) * exp(-t * 6.5) + (rnd() * 2 - 1) * exp(-t * 90) * .25) * amp
  end
end
local function flute(start, len, semis, amp)
  local f = freq(semis)
  local att, rel = floor(.14 * RATE), floor(.35 * RATE)
  local ph, br = 0, 0
  for i = 0, len + rel - 1 do
    local j = start + i
    if j >= N then break end
    local t = i / RATE
    local env = i < att and (i / att) or (i > len and (1 - (i - len) / rel) or 1)
    local vib = 1 + (t > .3 and .0045 * sin(TAU * 5.2 * t) or 0)
    ph = ph + TAU * f * vib / RATE
    br = br * .9 + (rnd() * 2 - 1) * .1
    buf[j] = buf[j] + (sin(ph) + .22 * sin(2 * ph) + .07 * sin(3 * ph) + br * .5) * env * amp
  end
end

---------------------------------------------------------------- reverb (state carries from phrase to phrase)
local COMBS, ALLS = { 557, 593, 641, 677 }, { 277, 211 }
local combBuf, combIdx, combLp, allBuf, allIdx = {}, {}, {}, {}, {}
for k, d in ipairs(COMBS) do combBuf[k] = ffi.new('float[?]', d); combIdx[k] = 0; combLp[k] = 0 end
for k, d in ipairs(ALLS) do allBuf[k] = ffi.new('float[?]', d); allIdx[k] = 0 end
local function reverb(x)
  local acc = 0
  for k = 1, 4 do
    local b, i = combBuf[k], combIdx[k]
    local y = b[i]
    combLp[k] = y * .7 + combLp[k] * .3
    b[i] = x + combLp[k] * .8
    i = i + 1; if i >= COMBS[k] then i = 0 end
    combIdx[k] = i
    acc = acc + y
  end
  acc = acc * .25
  for k = 1, 2 do
    local b, i = allBuf[k], allIdx[k]
    local y = b[i]
    local o = -acc + y
    b[i] = acc + y * .5
    i = i + 1; if i >= ALLS[k] then i = 0 end
    allIdx[k] = i
    acc = o
  end
  return acc
end

---------------------------------------------------------------- a phrase
local melodyDeg = 8
local function phrase()
  for i = 0, N - 1 do buf[i] = 0 end
  for i = 0, TAIL - 1 do buf[i] = carry[i] end
  local season, level, title = params.season or 1, params.level or 0, params.title
  local bright = (season <= 2) and (params.mood or 0) > -20 and not title
  local scale = bright and MAJOR or MINOR
  local progs = bright and PROG_MAJOR or PROG_MINOR
  local prog = progs[floor(rnd() * #progs) + 1]
  local winter = season == 4
  local density = (title and .32 or .42 + .06 * level) * (winter and .65 or 1)
  local barS = floor(BAR * RATE)
  local beatS = floor(BEAT * RATE)
  for b = 0, 3 do
    local root = prog[b + 1]
    local s0 = b * barS
    pad(s0, barS, root - 12, .028)
    pad(s0, barS, root - 5, .02)
    pad(s0, barS, root, .016)
    -- hand drum
    if level >= 1 or title then
      local amp = title and .16 or .22
      drum(s0, amp)
      if not winter then drum(s0 + 2 * beatS, amp * .6) end
      if level >= 2 and rnd() < .4 then drum(s0 + floor(3.5 * beatS), amp * .45) end
    end
    -- flute: one long note over the chord
    if (level >= 2 or (title and b == 2)) and rnd() < .55 then
      local st = s0 + (rnd() < .5 and 0 or beatS)
      local len = floor(beatS * (1.5 + rnd() * 1.5))
      local tones = { root + 12, root + 19, root + 24 }
      flute(st, len, tones[floor(rnd() * 3) + 1], .045)
    end
    -- plucked melody: a gentle random walk over the scale
    for beat = 0, 3 do
      for half = 0, 1 do
        local p = half == 0 and density or density * .35
        if rnd() < p then
          local step = floor(rnd() * 5) - 2
          if step == 0 and rnd() < .6 then step = 1 end
          melodyDeg = min(15, max(6, melodyDeg + step))
          local semis = degree(scale, melodyDeg)
          local st = s0 + beat * beatS + half * floor(beatS / 2) + floor(rnd() * 300)
          pluck(st, semis, .2, 2.6)
          if level >= 3 and rnd() < .3 then pluck(st + 40, degree(scale, melodyDeg - 2), .1, 2.2) end
        end
      end
    end
  end
  -- mix down: reverb, gentle limiting, and keep the tail for the next phrase
  local sd = love.sound.newSoundData(PH, RATE, 16, 1)
  local out = ffi.cast('int16_t*', sd:getFFIPointer())
  for i = 0, PH - 1 do
    local x = buf[i]
    local v = x + reverb(x) * .55
    v = math.tanh(v * 1.8) * .88
    out[i] = floor(v * 32000)
  end
  for i = 0, TAIL - 1 do carry[i] = buf[PH + i] end
  return sd
end

while true do
  local r = reqCh:demand()
  if r == 'quit' then break end
  local p = ctlCh:pop()
  while p ~= nil do params = p; p = ctlCh:pop() end
  outCh:push(phrase())
end
