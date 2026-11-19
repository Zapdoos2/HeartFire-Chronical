# Hearthfire Chronicle (second edition)

A tribe game in the style of NeverEnding Legacy. Guide a camp of nine people through hunger, winter and discovery until they become a civilization, then hand your legacy on to the next tribe.

Written in **Lua** for the **LÖVE** game engine (version 11.5), so the same code runs on macOS and Windows. Every picture, sound and note of music is made in code; there are no image or audio files.

## What is new in the second edition

- **Construction.** Clicking a building plans it and pays for it; Builders then raise it over several days, and idle people lend a hand at half speed. The queue appears at the top of the Production tab, with progress bars and a cross to cancel (everything is refunded).
- **Seven wonders.** Eternal Hearth, Great Totem, Sky Stones, Terraced Gardens, Hall of Memory, Long Wall and Bronze Giant: one of each, slow to raise, with lasting effects. Finished wonders appear on the map.
- **Story events.** 25 events with two or three choices each. The game pauses until you decide (keys 1–3 work too), and outcomes go into the chronicle.
- **Legacy.** Embers are earned from 25 milestones and from each tribe's story when it dies out or you retire it. They buy 12 perks that help every later tribe. The Legacy screen also lists past tribes with their population over time.
- **History tab.** Charts of population, food in store and mood, the tribe's stats, and the option to retire it.
- **Title screen** with a campfire under the stars, naming a new tribe, and notices for discoveries, customs, wonders and milestones.
- **Sound and music.** Sound effects for clicks, building, discoveries, rites and events, and music composed live as you play: it changes with the seasons and grows richer as your tribe learns more.
- **A living map.** The home fire flickers, water glints, new land fades in, and snow, rain, falling leaves or summer motes drift over it with the seasons.
- **Flavor text.** A dry one-line joke under the description of every resource, job, building, wonder, discovery, custom, rite, policy, land, perk and milestone, plus wry asides in the chronicle, hints and title screen.
- **Settings.** Music and sound volume, interface size (100%, 115% or 130%), full screen, weather and story events on or off.

## Playing

**Mac:** open `Hearthfire Chronicle.app`. It runs on Apple Silicon and Intel Macs. The first time, if macOS says it can't check the app, right-click it and choose **Open**.

**Windows:** unzip `Hearthfire Chronicle for Windows.zip`, open the `Hearthfire Chronicle` folder and run `Hearthfire Chronicle.exe`. Keep the DLL files next to it. If Windows SmartScreen warns about an unknown app, choose **More info**, then **Run anyway**.

On Windows displays set to 125%, 150% and so on, the game draws at the screen's real resolution and sizes its window and interface to match, so it stays sharp. If it ever looks wrong on your display, right-click the `.exe`, choose **Properties → Compatibility → Change high DPI settings**, tick **Override high DPI scaling behavior** and pick **System**.

**Anywhere with LÖVE installed:** open `Hearthfire Chronicle.love` with LÖVE 11.5 (https://love2d.org).

Mouse: click a job or building to do the action chosen with the arrows (Add 1, Add 10…); a right-click (or Ctrl-click on a Mac) does the opposite, so with Add 1 chosen it removes one worker. Right-clicking a project under construction cancels it.

Keys: Space pauses, 1–8 switch tabs, 1–3 pick a choice in a story event, H opens the guide, Esc closes it, F11 (or Ctrl+Cmd+F on a Mac) toggles full screen.

## Saves

The game saves every 30 seconds, when you switch away, when you go back to the title screen, and when you quit. Tribes from the first edition load as they are.

- Mac: `~/Library/Application Support/Hearthfire Chronicle/`
- Windows: `%APPDATA%\Hearthfire Chronicle\`

That folder holds `save.json` (the tribe), `legacy.json` (embers, perks, milestones, past tribes) and `settings.json`. To move a tribe between computers, use **Settings → Copy save code**, then **Load code from clipboard** on the other computer. Settings also has **Open save folder**.

## The code

| File | What it holds |
| --- | --- |
| `game/main.lua` | Start-up, the title and game screens, the clock, saving and loading, keyboard and mouse, test modes |
| `game/sim.lua` | The rules: resources, jobs, buildings and wonders, construction, discoveries, traits, rites, policies, the map, the daily simulation, events |
| `game/story.lua` | The story events and their choices |
| `game/flavor.lua` | One dry line of flavor text for nearly everything in the game, shown in italics under its description |
| `game/legacy.lua` | Embers, perks, milestones and past tribes |
| `game/screens.lua` | The board: stores, the eight tabs, the map and its weather, charts, the chronicle, notices and the overlays |
| `game/title.lua` | The title screen, founding a tribe, the Legacy screen |
| `game/ui.lua` | Drawing and input toolkit: interface size, panels, buttons, sliders, text, tooltips, scrolling |
| `game/art.lua` | Every icon, painted in code |
| `game/audio.lua` | Sound effects, made in code, and the music player |
| `game/musicthread.lua` | The music, composed phrase by phrase in a background thread |
| `game/dpi.lua` | The display scale on Windows (125%, 150%…), so the game is drawn sharp and at the right size there |
| `tools/set_exe_icon.py` | Build helper: puts the game's icon and name on the Windows program file by overwriting only the engine icon's pixels and its version block |
| `game/settings.lua`, `game/json.lua`, `game/conf.lua` | Preferences, save-file reading and writing, window settings |

To run from source: install LÖVE 11.5 and run `love game` from this folder.

To build the Mac app and the Windows version (on a Mac): `./build.sh`. It downloads LÖVE 11.5 into `vendor/` the first time and writes everything to `dist/`.

Test modes (they use a separate save folder and never touch your real save):

- `love game --selftest` plays five tribes for 30 years with a scripted player, raises every wonder, runs every rite, policy and story choice, checks the legacy and save files. Results go to `selftest.txt` in the test save folder. Add `--trace` for a year-by-year log.
- `love game --snapshot --fresh --botdays 2000 --tab territory` lets the scripted player run for 2,000 days, then saves a picture of the window. `--title --page legacy` pictures the title or Legacy screen instead; `--scale 1.3` uses a larger interface; `--fps` measures frame time.
- `love game --snapshot --mute --fresh --techs 46 --rich --tab production --sweep hover` holds the mouse still over thousands of points on the Production tab and reports anything that moves under it (`--sweep click` also clicks and right-clicks at each point; `--sweepscroll max` scrolls to the buildings first). `--rtest` checks that a right-click removes a worker.

## Licences

- LÖVE is under the zlib licence (`LOVE license.txt` in the Windows build).
- IM FELL English SC and Alegreya Sans are under the SIL Open Font Licence (`game/fonts/OFL-*.txt`).
