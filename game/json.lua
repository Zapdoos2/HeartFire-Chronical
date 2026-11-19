-- Minimal JSON encoder/decoder for save files.
-- Tables with keys 1..n are written as arrays; everything else as objects.
local json = {}
local hasUtf8, utf8 = pcall(require, 'utf8')
if not hasUtf8 then utf8 = nil end

local escapes = { ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }

local function isArray(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  for i = 1, n do if t[i] == nil then return false end end
  return true, n
end

local function encode(v, out)
  local tv = type(v)
  if tv == 'nil' then out[#out + 1] = 'null'
  elseif tv == 'boolean' then out[#out + 1] = v and 'true' or 'false'
  elseif tv == 'number' then
    if v ~= v or v == math.huge or v == -math.huge then out[#out + 1] = 'null'
    elseif v == math.floor(v) and math.abs(v) < 1e15 then out[#out + 1] = string.format('%d', v)
    else out[#out + 1] = string.format('%.10g', v) end
  elseif tv == 'string' then
    out[#out + 1] = '"' .. v:gsub('[%c"\\]', function(c) return escapes[c] or string.format('\\u%04x', c:byte()) end) .. '"'
  elseif tv == 'table' then
    local arr, n = isArray(v)
    if arr then
      out[#out + 1] = '['
      for i = 1, n do if i > 1 then out[#out + 1] = ',' end; encode(v[i], out) end
      out[#out + 1] = ']'
    else
      out[#out + 1] = '{'
      local first = true
      for k, val in pairs(v) do
        if type(val) ~= 'function' and not (type(k) == 'string' and k:sub(1, 1) == '_') then
          if not first then out[#out + 1] = ',' end
          first = false
          encode(tostring(k), out); out[#out + 1] = ':'; encode(val, out)
        end
      end
      out[#out + 1] = '}'
    end
  end
end

function json.encode(v)
  local out = {}
  encode(v, out)
  return table.concat(out)
end

local function decodeError(str, i, msg) error(string.format('JSON error at %d: %s', i, msg), 0) end

local function skip(str, i)
  local _, e = str:find('^[ \n\r\t]*', i)
  return e + 1
end

local parse

local function parseString(str, i)
  local out, j = {}, i + 1
  while true do
    local c = str:sub(j, j)
    if c == '' then decodeError(str, j, 'unterminated string') end
    if c == '"' then return table.concat(out), j + 1 end
    if c == '\\' then
      local e = str:sub(j + 1, j + 1)
      local map = { b = '\b', f = '\f', n = '\n', r = '\r', t = '\t', ['"'] = '"', ['\\'] = '\\', ['/'] = '/' }
      if map[e] then out[#out + 1] = map[e]; j = j + 2
      elseif e == 'u' then
        local code = tonumber(str:sub(j + 2, j + 5), 16) or 63
        j = j + 6
        if code >= 0xD800 and code <= 0xDBFF and str:sub(j, j + 1) == '\\u' then
          local lo = tonumber(str:sub(j + 2, j + 5), 16) or 0
          code = 0x10000 + (code - 0xD800) * 0x400 + (lo - 0xDC00); j = j + 6
        end
        out[#out + 1] = utf8 and utf8.char(code) or string.char(math.min(code, 255))
      else decodeError(str, j, 'bad escape') end
    else
      local s, e = str:find('^[^"\\]+', j)
      out[#out + 1] = str:sub(s, e); j = e + 1
    end
  end
end

parse = function(str, i)
  i = skip(str, i)
  local c = str:sub(i, i)
  if c == '{' then
    local obj = {}
    i = skip(str, i + 1)
    if str:sub(i, i) == '}' then return obj, i + 1 end
    while true do
      local key; key, i = parseString(str, skip(str, i))
      i = skip(str, i)
      if str:sub(i, i) ~= ':' then decodeError(str, i, 'expected :') end
      local val; val, i = parse(str, i + 1)
      obj[key] = val
      i = skip(str, i)
      local d = str:sub(i, i)
      if d == '}' then return obj, i + 1 end
      if d ~= ',' then decodeError(str, i, 'expected , or }') end
      i = i + 1
    end
  elseif c == '[' then
    local arr, n = {}, 0
    i = skip(str, i + 1)
    if str:sub(i, i) == ']' then return arr, i + 1 end
    while true do
      local val; val, i = parse(str, i)
      n = n + 1; arr[n] = val
      i = skip(str, i)
      local d = str:sub(i, i)
      if d == ']' then return arr, i + 1 end
      if d ~= ',' then decodeError(str, i, 'expected , or ]') end
      i = i + 1
    end
  elseif c == '"' then return parseString(str, i)
  elseif str:sub(i, i + 3) == 'true' then return true, i + 4
  elseif str:sub(i, i + 4) == 'false' then return false, i + 5
  elseif str:sub(i, i + 3) == 'null' then return nil, i + 4
  else
    local s, e = str:find('^-?%d+%.?%d*[eE]?[-+]?%d*', i)
    if not s then decodeError(str, i, 'unexpected character') end
    return tonumber(str:sub(s, e)), e + 1
  end
end

function json.decode(str)
  local ok, v = pcall(function() return (parse(str, 1)) end)
  if ok then return v end
  return nil, v
end

return json
