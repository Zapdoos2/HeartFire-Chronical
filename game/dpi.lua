-- Hearthfire Chronicle: the display scale of the operating system.
--
-- A Retina Mac needs nothing here: LÖVE draws at the screen's real resolution by itself. Windows is different
-- (with LÖVE 11): unless a program says it can draw at the real resolution, Windows draws it at 100% and stretches
-- the picture, which blurs the whole game on displays set to 125%, 150% and so on (most laptops). So on Windows
-- this file says so, and reads the display's scale. The game then opens its window that much larger and draws its
-- interface that much larger (UI.os in ui.lua), so everything is the size the player expects, and sharp.
--
-- If any of the Windows calls fail, the scale stays 1 and the game behaves as it did before: stretched by Windows.
local DPI = { scale = 1 }

if jit and jit.os == 'Windows' then
  pcall(function()
    local ffi = require('ffi')
    ffi.cdef [[
      int SetProcessDPIAware(void);
      void* GetDC(void* window);
      int GetDeviceCaps(void* dc, int index);
      int ReleaseDC(void* window, void* dc);
      int GetSystemMetrics(int index);
    ]]
    local C = ffi.C                                   -- on Windows this includes user32.dll and gdi32.dll
    C.SetProcessDPIAware()
    local dc = C.GetDC(nil)
    if dc ~= nil then
      local dpi = C.GetDeviceCaps(dc, 88)             -- LOGPIXELSX: dots per inch of the main display; 96 means 100%
      C.ReleaseDC(nil, dc)
      if dpi >= 96 and dpi <= 480 then DPI.scale = dpi / 96 end
    end
    local sw, sh = C.GetSystemMetrics(0), C.GetSystemMetrics(1)   -- size of the main display in real pixels
    if sw > 0 and sh > 0 then DPI.screenW, DPI.screenH = sw, sh end
  end)
end

-- Test option: --osscale 1.5 pretends the display is set to 150%. With --lowdpi (see conf.lua) this previews on a
-- Mac what a Windows screen at that setting shows.
for i, a in ipairs(arg or {}) do
  if a == '--osscale' then DPI.scale = math.max(1, math.min(4, tonumber(arg[i + 1]) or 1)) end
end

-- The size to open the window with: the design size (1280 x 820 units) times the display scale, shrunk to fit a
-- screen of sw x sh pixels with room left for the title bar and the taskbar. Also returns the smallest size the
-- window may be resized to. Without a screen size nothing is shrunk.
function DPI.windowSize(sw, sh)
  local s = DPI.scale
  local w, h = math.floor(1280 * s + .5), math.floor(820 * s + .5)
  local minw, minh = math.floor(1060 * s + .5), math.floor(680 * s + .5)
  if sw and sh and sw > 0 and sh > 0 then
    w, h = math.min(w, math.floor(sw - 40 * s)), math.min(h, math.floor(sh - 80 * s))
    minw, minh = math.min(minw, w), math.min(minh, h)
  end
  return w, h, minw, minh
end

return DPI
