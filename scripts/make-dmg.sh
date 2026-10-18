#!/bin/sh
# Builds build/Flaran-<version>.dmg: a window with Flaran.app, an arrow and an Applications shortcut.
# Expects build/Flaran.app (make app). Finder lays out the window, so the first run may ask to allow
# Terminal to control Finder.
set -e
cd "$(dirname "$0")/.."
version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
dmg="build/Flaran-$version.dmg"
stage=build/dmg-stage
rw=build/dmg-rw.dmg

rm -rf "$stage" "$rw" "$dmg"
mkdir -p "$stage/.background"
cp -R build/Flaran.app "$stage/"
ln -s /Applications "$stage/Applications"
swift scripts/dmg-background.swift "$stage/.background/background.png" >/dev/null

hdiutil create -quiet -srcfolder "$stage" -volname Flaran -fs HFS+ -format UDRW "$rw"
device=$(hdiutil attach -readwrite -noverify -noautoopen "$rw" | awk '/Apple_HFS/ {print $1}')
volume=/Volumes/Flaran

osascript <<OSA
tell application "Finder"
  tell disk "Flaran"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 840, 520}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set text size of opts to 13
    set background picture of opts to file ".background:background.png"
    set position of item "Flaran.app" of container window to {160, 190}
    set position of item "Applications" of container window to {480, 190}
    update without registering applications
    delay 1
    close
  end tell
end tell
OSA

chmod -Rf go-w "$volume" || true
sync
hdiutil detach -quiet "$device"
hdiutil convert -quiet "$rw" -format UDZO -imagekey zlib-level=9 -o "$dmg"
rm -rf "$stage" "$rw"
echo "$dmg"
