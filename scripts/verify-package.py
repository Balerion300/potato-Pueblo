"""Run the complete-client fixture against the relocated packaged interpreter/source."""
import os
import pathlib
import platform
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
package = next((root / "artifacts").glob("Potato-Pueblo-Preview-*/BUILD.json")).parent
if platform.system() == "Darwin":
    contents = package / "Potato Pueblo Preview.app" / "Contents"
    resources = contents / "Resources"
    executable = contents / "MacOS" / "Wish"

else:
    resources = package
    executable = resources / "runtime" / "bin" / ("wish86s.exe" if platform.system() == "Windows" else "wish8.6")
with tempfile.TemporaryDirectory(prefix="potato-package-test-") as profile:
    env = dict(os.environ, TCL_LIBRARY=str(resources / "runtime/lib/tcl8.6"),
               TK_LIBRARY=str(resources / "runtime/lib/tk8.6"), POTATO_HOME=profile,
               POTATO_TEST_SOURCE_ROOT=str(resources))
    command = [str(executable), str(root / "tests/run.tcl"), str(root / "tests/client.test.tcl")]
    if platform.system() == "Darwin":
        env.update(POTATO_TEST_ENTRY=str(root / "tests/run.tcl"),
                   POTATO_TEST_FIXTURE=str(root / "tests/client.test.tcl"))
        command = [str(executable)]
    subprocess.run(command,
                   env=env, cwd=package, check=True, timeout=60)
print("PASS: relocated packaged client, isolated profile")
