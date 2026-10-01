#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/build/ModuleCache"
export CLANG_MODULE_CACHE_PATH="$PWD/build/ModuleCache"
swift test --scratch-path build/swift --cache-path build/cache --config-path build/config --security-path build/security --disable-sandbox "$@"
