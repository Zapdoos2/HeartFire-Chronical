-- Hearthfire Chronicle: player preferences, kept in settings.json next to the save.
local json = require('json')
local Settings = {}
local FILE = 'settings.json'
Settings.noSave = false
Settings.data = { music = .5, sound = .7, ui = 1, fullscreen = false, stories = true, weather = true }
Settings.onChange = function() end

function Settings.load()
  if love.filesystem.getInfo(FILE) then
    local d = json.decode(love.filesystem.read(FILE) or '')
    if type(d) == 'table' then
      for k, v in pairs(d) do if Settings.data[k] ~= nil and type(v) == type(Settings.data[k]) then Settings.data[k] = v end end
    end
  end
  local D = Settings.data
  D.music = math.max(0, math.min(1, D.music)); D.sound = math.max(0, math.min(1, D.sound))
  if D.ui ~= 1 and D.ui ~= 1.15 and D.ui ~= 1.3 then D.ui = 1 end
  return D
end
function Settings.save()
  if Settings.noSave then return end
  love.filesystem.write(FILE, json.encode(Settings.data))
end
function Settings.set(k, v)
  if Settings.data[k] == v then return end
  Settings.data[k] = v
  Settings.save()
  Settings.onChange(k, v)
end
function Settings.get(k) return Settings.data[k] end

return Settings
