"""Verify the extracted preview ZIP with its native interpreter and isolated profile."""
import os
import pathlib
import platform
import plistlib
import subprocess
import tempfile
import zipfile
import sys
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "tests"))
from fixture_server import Fixture

root = pathlib.Path(__file__).resolve().parents[1]
archive = next((root / "artifacts").glob("Potato-Pueblo-Preview-*.zip"))
with tempfile.TemporaryDirectory(prefix="potato-extracted-preview-") as extracted, tempfile.TemporaryDirectory(prefix="potato-package-profile-") as profile:
    destination = pathlib.Path(extracted)
    if platform.system() == "Darwin":
        subprocess.run(["ditto", "-x", "-k", str(archive), str(destination)], check=True)
    else:
        with zipfile.ZipFile(archive) as package_zip:
            package_zip.extractall(destination)
            if platform.system() != "Windows":
                for member in package_zip.infolist():
                    mode = member.external_attr >> 16
                    if mode:
                        (destination / member.filename).chmod(mode)
    package = next(destination.rglob("BUILD.json")).parent
    resources = package
    executable = resources / "runtime" / "bin" / ("wish86s.exe" if platform.system() == "Windows" else "wish8.6")
    env = dict(os.environ, TCL_LIBRARY=str(resources / "runtime/lib/tcl8.6"),
               TK_LIBRARY=str(resources / "runtime/lib/tk8.6"), POTATO_HOME=profile,
               POTATO_TEST_SOURCE_ROOT=str(resources))
    command = [str(executable), str(root / "tests/run.tcl"), str(root / "tests/client.test.tcl")]
    if platform.system() == "Darwin":
        contents = resources.parent
        info = plistlib.loads((contents / "Info.plist").read_bytes())
        executable = contents / "MacOS" / info["CFBundleExecutable"]
        # Exercise the actual app launcher with no inherited runtime overrides.
        env.pop("TCL_LIBRARY", None)
        env.pop("TK_LIBRARY", None)
        command[0] = str(executable)
    build_runtime = root / ".build/runtime"
    hidden_runtime = root / ".build/runtime-not-for-package-tests"
    build_runtime.rename(hidden_runtime)
    try:
        if platform.system() == "Darwin":
            receipt = destination / "finder-startup.txt"
            launch_env = {"POTATO_HOME": str(destination / "finder-profile"),
                          "POTATO_TEST_SOURCE_ROOT": str(resources),
                          "POTATO_TEST_RESULT": str(receipt)}
            open_command = ["open", "-n", "-W"]
            for key, value in launch_env.items():
                open_command.extend(["--env", f"{key}={value}"])
            subprocess.run(open_command + [str(contents.parent), "--args",
                            str(root / "tests/run.tcl"), str(root / "tests/startup.tcl")],
                           env=env, cwd=destination, check=True, timeout=60)
            if not receipt.exists() or receipt.read_text().strip() != "PASS":
                raise RuntimeError("LaunchServices app startup did not complete")
        with Fixture() as fixture:
            env.update(fixture.environment())
            subprocess.run(command, env=env, cwd=package, check=True, timeout=60)
        with tempfile.TemporaryDirectory(prefix="potato-package-ssl-") as ssl_profile:
            env["POTATO_HOME"] = ssl_profile
            subprocess.run([str(executable), str(root / "tests/run.tcl"), str(root / "tests/ssl.test.tcl")],
                           env=env, cwd=package, check=True, timeout=60)
    finally:
        hidden_runtime.rename(build_runtime)
print("PASS: extracted packaged client, isolated profile, build runtime unavailable")
