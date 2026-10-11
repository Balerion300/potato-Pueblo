#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
build_root="$project_root/.build"
runtime_root="$build_root/runtime"
openssl_root="$build_root/openssl-install"
git clone --depth 1 --branch openssl-3.5.9 https://github.com/openssl/openssl.git "$build_root/openssl-source"
test "$(git -C "$build_root/openssl-source" rev-parse HEAD)" = 45e844fa2a14ec92d146bd8f5778ac130b6625fb
git clone --depth 1 --branch tls-2.0.1 https://github.com/bohagan1/TclTLS.git "$build_root/tcltls"
test "$(git -C "$build_root/tcltls" rev-parse HEAD)" = 93fd7d96b868c5136f63b2faf3243489f27ebc55
cd "$build_root/openssl-source"
# Static PIC libraries make the Tcl extension independent of Homebrew and
# distribution-specific OpenSSL libraries, including after ZIP relocation.
./Configure --prefix="$openssl_root" --libdir=lib no-shared no-tests no-module -fPIC
make -j4
make install_sw
cd "$build_root/tcltls"
export TCL_LIBRARY="$runtime_root/lib/tcl8.6"
./configure --prefix="$runtime_root" --with-tcl="$runtime_root/lib" \
    --with-openssl-dir="$openssl_root" --enable-static-ssl --enable-shared --enable-64bit
make -j4
make install
cp license.terms "$runtime_root/TclTLS-LICENSE.txt"
cp "$build_root/openssl-source/LICENSE.txt" "$runtime_root/OpenSSL-LICENSE.txt"
printf '%s\n' 'TclTLS 2.0.1: 93fd7d96b868c5136f63b2faf3243489f27ebc55' \
    'OpenSSL 3.5.9: 45e844fa2a14ec92d146bd8f5778ac130b6625fb' > "$runtime_root/TLS-BUILD.txt"
