#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
swift build -c release
binary_dir=$(swift build -c release --show-bin-path)
app_path="$PWD/dist/MornDesktopTube.app"
mkdir -p "$app_path/Contents/MacOS"
cp "$binary_dir/MornDesktopTube" "$app_path/Contents/MacOS/MornDesktopTube"
cp Support/Info.plist "$app_path/Contents/Info.plist"
codesign --force --sign - --identifier studio.tsukumi.MornDesktopTube "$app_path"
print "Built: $app_path"
