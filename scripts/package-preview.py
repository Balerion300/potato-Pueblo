"""Package the pinned native runtime and public source; never copy user profiles."""
import json
import os
import pathlib
import platform
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
    mac = system == "Darwin"
    launcher = destination / ("Start Potato Pueblo.command" if mac else "Start Potato Pueblo.sh")
    profile = '$HOME/Library/Application Support/Potato-Pueblo-Preview' if mac else '${XDG_CONFIG_HOME:-$HOME/.config}/potato-pueblo-preview'
    launcher.write_text('''#!/bin/sh
set -eu
resources="$(cd "$(dirname "$0")" && pwd)"
export TCL_LIBRARY="$resources/runtime/lib/tcl8.6"
export TK_LIBRARY="$resources/runtime/lib/tk8.6"
''' + f'export POTATO_HOME="${{POTATO_HOME:-{profile}}}"\n' + '''exec "$resources/runtime/bin/wish8.6" "$resources/potato.vfs/main.tcl" "$@"
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
    subprocess.run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(destination), str(out / (name + ".zip"))], check=True)
else:
    shutil.make_archive(str(out / name), "zip", out, name)
print(out / (name + ".zip"))
