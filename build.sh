#!/bin/zsh
# Builds Hearthfire Chronicle for macOS and Windows from the Lua source in ./game.
# Run on a Mac:  ./build.sh
# Output in ./dist:
#   Hearthfire Chronicle.app                     double-click app for macOS (Apple Silicon and Intel)
#   Hearthfire Chronicle for Windows.zip         unzip on Windows and run "Hearthfire Chronicle.exe"
#   Hearthfire Chronicle.love                    runs anywhere LÖVE 11.5 is installed
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
GAME="$HERE/game"
VENDOR="$HERE/vendor"
OUT="$HERE/dist"
VER=11.5
NAME="Hearthfire Chronicle"

mkdir -p "$VENDOR"
if [ ! -d "$VENDOR/mac/love.app" ]; then
  curl -sL -o "$VENDOR/love-macos.zip" "https://github.com/love2d/love/releases/download/$VER/love-$VER-macos.zip"
  unzip -q -o "$VENDOR/love-macos.zip" -d "$VENDOR/mac"
fi
if [ ! -d "$VENDOR/win/love-$VER-win64" ]; then
  curl -sL -o "$VENDOR/love-win64.zip" "https://github.com/love2d/love/releases/download/$VER/love-$VER-win64.zip"
  unzip -q -o "$VENDOR/love-win64.zip" -d "$VENDOR/win"
fi

rm -rf "$OUT"
mkdir -p "$OUT"

# 1. The game itself, as a .love archive
(cd "$GAME" && zip -9 -q -r "$OUT/$NAME.love" . -x '.*')

# 2. macOS: the LÖVE runtime with the game fused inside
APP="$OUT/$NAME.app"
cp -R "$VENDOR/mac/love.app" "$APP"
cp "$OUT/$NAME.love" "$APP/Contents/Resources/game.love"
PL="$APP/Contents/Info.plist"
PB=/usr/libexec/PlistBuddy
$PB -c "Set :CFBundleIdentifier local.hearthfire.chronicle" "$PL"
$PB -c "Set :CFBundleName $NAME" "$PL"
$PB -c "Add :CFBundleDisplayName string $NAME" "$PL" 2>/dev/null || $PB -c "Set :CFBundleDisplayName $NAME" "$PL"
for kv in "CFBundleShortVersionString 2.0" "CFBundleVersion 2"; do
  k=${kv%% *}; v=${kv#* }
  $PB -c "Set :$k $v" "$PL" 2>/dev/null || $PB -c "Add :$k string $v" "$PL"
done
$PB -c "Delete :UTExportedTypeDeclarations" "$PL" 2>/dev/null || true
$PB -c "Delete :CFBundleDocumentTypes" "$PL" 2>/dev/null || true
$PB -c "Delete :CFBundleIconName" "$PL" 2>/dev/null || true
$PB -c "Set :CFBundleIconFile AppIcon" "$PL"
rm -f "$APP/Contents/Resources/Assets.car" "$APP/Contents/Resources/OS X AppIcon.icns" "$APP/Contents/Resources/GameIcon.icns"
ICONSET="$OUT/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$HERE/assets/icon_1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) "$HERE/assets/icon_1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"

# 3. Windows: love.exe with the game appended, plus the runtime's DLLs.
# The game's icon and name are first written over the engine's icon pixels and version block inside love.exe (see
# tools/set_exe_icon.py: nothing else in the program changes). If that cannot be done, the engine's own icon and name stay.
WIN="$OUT/$NAME"
mkdir -p "$WIN"
ENGINE="$VENDOR/win/love-$VER-win64/love.exe"
if python3 -I "$HERE/tools/set_exe_icon.py" "$ENGINE" "$HERE/assets/icon_1024.png" "$OUT/engine-with-icon.exe"; then
  ENGINE="$OUT/engine-with-icon.exe"
else
  echo "Note: the game's icon and name could not be put on the Windows program; it keeps the engine's."
fi
cat "$ENGINE" "$OUT/$NAME.love" > "$WIN/$NAME.exe"
rm -f "$OUT/engine-with-icon.exe"
cp "$VENDOR/win/love-$VER-win64/"*.dll "$WIN/"
cp "$VENDOR/win/love-$VER-win64/license.txt" "$WIN/LOVE license.txt"
cp "$GAME/fonts/"OFL-*.txt "$WIN/"
(cd "$OUT" && zip -9 -q -r "$NAME for Windows.zip" "$NAME")
rm -rf "$WIN"

echo "Built:"
ls -1 "$OUT"
