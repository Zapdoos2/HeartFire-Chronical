function love.conf(t)
  -- the window opens at the design size times the display scale (see dpi.lua; the scale is 1 on a Mac)
  local DPI = require('dpi')
  local w, h, minw, minh = DPI.windowSize(DPI.screenW, DPI.screenH)

  t.identity = 'Hearthfire Chronicle'
  t.appendidentity = false
  t.version = '11.5'
  t.console = false

  t.window.title = 'Hearthfire Chronicle'
  t.window.icon = 'icon.png'
  t.window.width = w
  t.window.height = h
  t.window.minwidth = minw
  t.window.minheight = minh
  t.window.resizable = true
  t.window.highdpi = true
  -- Test option: --lowdpi draws at standard pixel density (one pixel per unit), which is how the game is drawn
  -- on Windows and on non-Retina screens. It lets a Retina Mac preview that look.
  for _, a in ipairs(arg or {}) do if a == '--lowdpi' then t.window.highdpi = false end end
  t.window.msaa = 4
  t.window.vsync = 1

  t.modules.audio = true
  t.modules.sound = true
  t.modules.thread = true
  t.modules.joystick = false
  t.modules.physics = false
  t.modules.video = false
  t.modules.touch = false
end
