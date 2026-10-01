#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
xcodebuild -project Fandy.xcodeproj -scheme Fandy -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData "$@" build
