#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
configuration="${FANDY_BUILD_CONFIGURATION:-Debug}"
case "$configuration" in
  Debug|Release) ;;
  *) print -u2 'FANDY_BUILD_CONFIGURATION must be Debug or Release'; exit 2 ;;
esac
typeset -a privacy_flags
privacy_flags=()
if [[ "$configuration" == Release ]]; then
  # Keep developer home paths out of source locations and separate debug symbols.
  privacy_flags+=("OTHER_SWIFT_FLAGS=\$(inherited) -file-prefix-map \"${PWD}=/Fandy\" -debug-prefix-map \"${PWD}=/Fandy\"")
  privacy_flags+=("OTHER_CFLAGS=\$(inherited) -ffile-prefix-map=\"${PWD}=/Fandy\" -fdebug-prefix-map=\"${PWD}=/Fandy\"")
  # Build actions otherwise retain Mach-O local/debug symbol paths. Keep dSYMs
  # outside the app, strip before Xcode signs, and preserve executable symbols.
  privacy_flags+=(DEPLOYMENT_POSTPROCESSING=YES STRIP_INSTALLED_PRODUCT=YES STRIP_STYLE=non-global)
fi
xcodebuild -project Fandy.xcodeproj -scheme Fandy -configuration "$configuration" -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData "${privacy_flags[@]}" "$@" build
