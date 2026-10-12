#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
runtime_root="$project_root/.build/runtime"
# Cached runtimes predate installation of Tk's public headers. Fetch exactly
# the headers matching the pinned static library, never the system Tcl/Tk.
headers_root="$project_root/.build/mac-launcher-tk"
git clone --depth 1 --branch core-8-6-18 https://github.com/tcltk/tk.git "$headers_root"
test "$(git -C "$headers_root" rev-parse HEAD)" = 6dbe68819aac4a22f6f7a143133ce26c5e8d2b05
source "$runtime_root/lib/tclConfig.sh"
source "$runtime_root/lib/tkConfig.sh"
# Config files originate from our pinned runtime build. Expand their linker flags.
eval "clang -DMAC_OSX_TK -I\"$runtime_root/include\" -I\"$headers_root/generic\" -I\"$headers_root/xlib\" -o \"\$1\" \"$project_root/scripts/mac-launcher.c\" $TK_LIB_SPEC $TCL_LIB_SPEC $TK_LIBS $TCL_LIBS"
codesign --force --sign - "$1"
