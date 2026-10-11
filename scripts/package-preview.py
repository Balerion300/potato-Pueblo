"""Package the pinned native runtime and public source; never copy user profiles."""
import json
import os
import pathlib
import platform
import plistlib
import shutil
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parents[1]
runtime = root / ".build" / "runtime"
out = root / "artifacts"
out.mkdir(exist_ok=True)
system = platform.system()
arch = platform.machine()
name = f"Potato-Pueblo-Preview-{system}-{arch}"
destination = out / name
destination.mkdir(exist_ok=True)
if system == "Darwin":
    app = destination / "Potato Pueblo Preview.app"
    contents = app / "Contents"
    resources = contents / "Resources"
    binaries = contents / "MacOS"
    binaries.mkdir(parents=True)
    resources.mkdir(parents=True)
    plist = dict(CFBundleName="Potato Pueblo Preview", CFBundleDisplayName="Potato Pueblo Preview",
                 CFBundleIdentifier="org.westeros.potato-pueblo.preview", CFBundleVersion="1",
                 CFBundleShortVersionString="0.1", CFBundleExecutable="Wish",
                 CFBundleInfoDictionaryVersion="6.0",
                 CFBundlePackageType="APPL", NSHighResolutionCapable=True,
                 LSMinimumSystemVersion="13.0",
                 NSLocalNetworkUsageDescription="Connect to MUSH games hosted on your local network.")
    (contents / "Info.plist").write_bytes(plistlib.dumps(plist))
    shutil.copy2(runtime / "bin" / "wish8.6", binaries / "Wish")
    # Use Wish's supported native AppMain entry point, rather than a shell as
    # CFBundleExecutable. Tcl also finds its libraries relative to Contents/MacOS.
    (contents / "lib").symlink_to("Resources/runtime/lib", target_is_directory=True)
    scripts = resources / "Scripts"
    scripts.mkdir()
    (scripts / "AppMain.tcl").write_text('''if {[info exists ::env(POTATO_TEST_ENTRY)]} {
    if {![string match "$::env(POTATO_TEST_SOURCE_ROOT)/*" [file normalize [info library]]]} {
        error "Packaged Tcl library was not loaded from the app"
    }
    set ::argv [list $::env(POTATO_TEST_FIXTURE)]
    source $::env(POTATO_TEST_ENTRY)
} else {
    if {![info exists ::env(POTATO_HOME)] || $::env(POTATO_HOME) eq ""} {
        set ::env(POTATO_HOME) [file join $::env(HOME) Library {Application Support} Potato-Pueblo-Preview]
    }
    source [file join [file dirname [info script]] .. potato.vfs main.tcl]
}
''')
else:
    resources = destination
    if system == "Windows":
        (destination / "Start Potato Pueblo.cmd").write_text('''@echo off
setlocal
set "TCL_LIBRARY=%~dp0runtime\\lib\\tcl8.6"
set "TK_LIBRARY=%~dp0runtime\\lib\\tk8.6"
if not defined POTATO_HOME set "POTATO_HOME=%APPDATA%\\Potato-Pueblo-Preview"
start "" "%~dp0runtime\\bin\\wish86s.exe" "%~dp0potato.vfs\\main.tcl" %*
''', newline="\r\n")
    else:
        launcher = destination / "Start Potato Pueblo.sh"
        launcher.write_text('''#!/bin/sh
set -eu
resources="$(cd "$(dirname "$0")" && pwd)"
export TCL_LIBRARY="$resources/runtime/lib/tcl8.6"
export TK_LIBRARY="$resources/runtime/lib/tk8.6"
export POTATO_HOME="${POTATO_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/potato-pueblo-preview}"
exec "$resources/runtime/bin/wish8.6" "$resources/potato.vfs/main.tcl" "$@"
''')
        launcher.chmod(0o755)
shutil.copytree(runtime, resources / "runtime")
shutil.copytree(root / "potato.vfs", resources / "potato.vfs")
for path in (root / "README.md", root / "docs" / "PUEBLO.md"):
    shutil.copy2(path, destination / path.name)
# Record the actual source identity in every downloadable package.
(destination / "BUILD.json").write_text(json.dumps(dict(
    preview=True, commit=subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip(),
    runtime="Tcl/Tk 8.6.18", system=system, architecture=arch,
    tcl="515167c897a7c8066abfbd71e8fe7bd8bf3569de", tk="6dbe68819aac4a22f6f7a143133ce26c5e8d2b05"), indent=2))
if system == "Darwin":
    # No Apple developer identity is available: this is explicitly an ad-hoc preview.
    subprocess.run(["codesign", "--force", "--deep", "--sign", "-", str(app)], check=True)
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    subprocess.run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(destination), str(out / (name + ".zip"))], check=True)
else:
    shutil.make_archive(str(out / name), "zip", out, name)
print(out / (name + ".zip"))
