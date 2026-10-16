#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
build_root="$project_root/.build"
runtime_root="$build_root/runtime"
mkdir -p "$build_root" "$runtime_root"
git clone --depth 1 --branch core-8-6-18 https://github.com/tcltk/tcl.git "$build_root/tcl"
git clone --depth 1 --branch core-8-6-18 https://github.com/tcltk/tk.git "$build_root/tk"
test "$(git -C "$build_root/tcl" rev-parse HEAD)" = 515167c897a7c8066abfbd71e8fe7bd8bf3569de
test "$(git -C "$build_root/tk" rev-parse HEAD)" = 6dbe68819aac4a22f6f7a143133ce26c5e8d2b05
platform="$(uname -s)"
configure_dir=unix
tk_options=()
case "$platform" in
  Darwin) tk_options+=(--enable-aqua) ;;
  MINGW*|MSYS*) configure_dir=win ;;
esac
cd "$build_root/tcl/$configure_dir"
./configure --prefix="$runtime_root" --disable-shared --enable-threads
make -j4
make install-binaries install-libraries install-headers
if [ "$configure_dir" = unix ]; then make install-msgs install-tzdata; fi
cd "$build_root/tk/$configure_dir"
./configure --prefix="$runtime_root" --disable-shared --with-tcl="$runtime_root/lib" "${tk_options[@]}"
make -j4
make install-binaries install-libraries
cp "$build_root/tcl/license.terms" "$runtime_root/Tcl-LICENSE.txt"
cp "$build_root/tk/license.terms" "$runtime_root/Tk-LICENSE.txt"
