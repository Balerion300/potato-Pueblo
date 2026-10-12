#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
runtime_root="$project_root/.build/runtime"
source "$runtime_root/lib/tclConfig.sh"
source "$runtime_root/lib/tkConfig.sh"
# Config files originate from our pinned runtime build. Expand their linker flags.
eval "clang -I\"$runtime_root/include\" -o \"\$1\" \"$project_root/scripts/mac-launcher.c\" $TK_LIB_SPEC $TCL_LIB_SPEC $TK_LIBS $TCL_LIBS"
codesign --force --sign - "$1"
