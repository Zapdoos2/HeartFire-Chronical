# Hearthfire Chronicle

A tribe-to-civilization incremental game in the style of NeverEnding Legacy, written in Lua for LÖVE 11.5 so it runs on macOS and Windows. Every icon, sound and note of music is generated in code; there are no image or audio assets apart from the app icon and fonts.

## Layout

- `game/` — the game (what LÖVE runs). `main.lua` start-up, title/game modes, saving, input, test modes; `sim.lua` all rules and data; `story.lua` story events; `legacy.lua` embers, perks, milestones; `flavor.lua` the one-line jokes (field `q`) attached to game data; `screens.lua` the board and tabs; `title.lua` title, new tribe, Legacy screens; `ui.lua` drawing/input toolkit and interface scaling; `art.lua` icons painted in code; `audio.lua` + `musicthread.lua` sound and generated music; `dpi.lua` display scale on Windows; `settings.lua`, `json.lua`, `conf.lua`.
- `assets/icon_1024.png` — the app icon used by the build.
- `build.sh` — builds `dist/` (Mac app, Windows zip, `.love`). Downloads LÖVE 11.5 into `vendor/` if missing.
- `tools/set_exe_icon.py` — used by `build.sh` to put the game's icon and name on the Windows `love.exe`. It only overwrites the pixels of the engine's six icon pictures in place (same sizes, same positions) and rewrites the version block (the name Task Manager shows; "LÖVE 11.5" → "Hearthfire Chronicle", version 2.0) inside its existing space, so the program is otherwise byte-identical to stock LÖVE; it refuses to write anything if the file is not laid out as expected or the new names don't fit. Keep it that way: the Windows build cannot be run here, so never change the program's structure.
- `Artwork/` — title-screen capture and the Steam library images.
- `Earlier versions/` — the first Lua edition, the HTML web edition with its Swift Mac wrapper, and Cookie Conjurer. Kept for reference; not built.
- `dist/` and `vendor/` are build outputs and downloads, not tracked in git.

## Running and testing

- Run from source: `vendor/mac/love.app/Contents/MacOS/love game`
- Self-test (separate save folder, never touches the real save): `vendor/mac/love.app/Contents/MacOS/love game --selftest` — expect all tribes alive or one early starvation, `story choices that failed: none`, `save round trip: ok`. Results also go to `selftest.txt` in `~/Library/Application Support/LOVE/Hearthfire Chronicle test/`.
- Layout stability: `... love game --snapshot --mute --fresh --techs 46 --rich --tab production --sweep hover` (also `--sweep click`, `--sweepscroll max`, `--sweepstep 13` for a quicker run) must report `0 bouncing`. Nothing on the Production tab may change size with what is hovered; the info box height is fixed by `infoBoxHeight`.
- Windows look on a Mac: add `--lowdpi` (standard pixel density, as on Windows) and `--osscale 1.25` or `1.5` (a Windows display set to 125% / 150%) to any snapshot or sweep. `game/dpi.lua` holds the Windows-only code (asks Windows for real-resolution drawing, reads the display scale); it cannot run on a Mac, so keep it tiny and inside `pcall`. The self-test line `window on common Windows displays: all fit` checks the window sizing.
- Screenshots: `... love game --snapshot --mute --fresh --botdays 1300 --tab research` (also `--title --page legacy`, `--scale 1.3 --size 1440x900`, `--techs 30`, `--story fever`, `--fps`). The picture lands in the test save folder as `snapshot.png`. Delete the test folders afterwards.

## Rules of the road

- Never read from or write to the player's real save folder `~/Library/Application Support/Hearthfire Chronicle/` (save.json, legacy.json, settings.json) except to make a read-only copy for testing. Test modes switch to the "Hearthfire Chronicle test" identity.
- Install builds in place at `~/Applications/Hearthfire Chronicle.app` with bundle id `local.hearthfire.chronicle`: the Dock icon and a Steam non-Steam-game shortcut point at that path. Check the game is not running before replacing it.
- Text goes through `UI.text` / `UI.para` / `UI.print` (fonts are built at the screen's exact pixel size so every letter sits on a whole pixel); layout is in logical units and `UI.scale` handles interface size, including the Windows display scale (`UI.os`). Icons are painted at 128 px with mipmaps so they stay smooth when drawn small.
- Flavor lines: one dry, mock-encyclopedic sentence; never copy NeverEnding Legacy's own text.
- The Windows build has not yet been tried on a real Windows PC.
