"""Verify the extracted preview ZIP with its native interpreter and isolated profile."""
import os
import pathlib
import platform
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
    if platform.system() == "Darwin":
        contents = package / "Potato Pueblo Preview.app" / "Contents"
        resources = contents / "Resources"
        executable = contents / "MacOS" / "Wish"
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(contents.parent)], check=True)
    else:
        resources = package
        executable = resources / "runtime" / "bin" / ("wish86s.exe" if platform.system() == "Windows" else "wish8.6")
    env = dict(os.environ, TCL_LIBRARY=str(resources / "runtime/lib/tcl8.6"),
               TK_LIBRARY=str(resources / "runtime/lib/tk8.6"), POTATO_HOME=profile,
               POTATO_TEST_SOURCE_ROOT=str(resources))
    command = [str(executable), str(root / "tests/run.tcl"), str(root / "tests/client.test.tcl")]
    if platform.system() == "Darwin":
        env.update(POTATO_TEST_ENTRY=str(root / "tests/run.tcl"),
                   POTATO_TEST_FIXTURE=str(root / "tests/client.test.tcl"))
        env.pop("TCL_LIBRARY", None)
        env.pop("TK_LIBRARY", None)
        receipt = pathlib.Path(profile) / "test-result.txt"
        env["POTATO_TEST_RESULT"] = str(receipt)
        command = ["open", "-W", "-n", "-a", str(contents.parent)]
    build_runtime = root / ".build/runtime"
    hidden_runtime = root / ".build/runtime-not-for-package-tests"
    build_runtime.rename(hidden_runtime)
    try:
        with Fixture() as fixture:
            env.update(fixture.environment())
            if platform.system() == "Darwin":
                # Use the same LaunchServices path as a Finder double-click.
                # open's exit code is not the app's result: require a test receipt.
                for key, value in env.items():
                    if key.startswith("POTATO_"):
                        command.extend(["--env", f"{key}={value}"])
            subprocess.run(command, env=env, cwd=package, check=True, timeout=90)
            if platform.system() == "Darwin":
                result = receipt.read_text() if receipt.exists() else "No full-client result receipt"
                print(result)
                assert result.strip() == "PASS: 15; Tcl 8.6.18; Tk 8.6.18", result
    finally:
        hidden_runtime.rename(build_runtime)
print("PASS: extracted packaged client, isolated profile, build runtime unavailable")
