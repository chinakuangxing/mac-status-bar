#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
APP="$PWD/build/Mac Status.app"
mkdir -p "$APP/Contents/MacOS" "$PWD/build/module-cache-v010" "$PWD/build/tmp"
export TMPDIR="build/tmp"
export MACOSX_DEPLOYMENT_TARGET=13.0
xcrun swiftc -O -target "$(uname -m)-apple-macosx13.0" -module-cache-path "$PWD/build/module-cache-v010" -framework AppKit MacStatus.swift -o "$APP/Contents/MacOS/MacStatus"
cp Info.plist "$APP/Contents/Info.plist"
"$APP/Contents/MacOS/MacStatus" --self-test
print "Built locally only: $APP"

