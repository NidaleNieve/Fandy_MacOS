#!/bin/zsh
# Software-only verification. Never installs/starts a helper or requests fan control.
set -euo pipefail
cd "${0:A:h:h}"
if (( $# > 1 )) || (( $# == 1 )) && [[ "$1" != '--sanitizers' && "$1" != '--native-build' ]]; then
  print -u2 'Usage: Scripts/verify.sh [--sanitizers|--native-build]'; exit 2
fi
xcodebuild -version
swift --version
case "${1:-}" in
  --sanitizers)
    ASAN_OPTIONS=detect_leaks=0 Scripts/test.sh -j 1 --no-parallel --sanitize address
    Scripts/test.sh -j 1 --no-parallel --sanitize thread --filter 'concurrentAdmission|concurrentDiagnosticRecords|pollingRestart|overlappingLifecycle|failedRelease|cancellingOneWaiter'
    ;;
  --native-build) Scripts/build.sh -jobs 1 CODE_SIGNING_ALLOWED=NO ;;
  *)
    Scripts/test.sh -j 1 --no-parallel
    python3 -m unittest discover -s Tests/ToolTests -v
    ;;
esac
