"""Reject TLS packages which still need the builder's OpenSSL installation."""
import pathlib
import platform
import subprocess

root = pathlib.Path(__file__).resolve().parents[1]
libraries = [p for p in (root / ".build/runtime/lib").glob("tcltls2.0.1/libtls*")
             if p.suffix in (".so", ".dylib")]
if len(libraries) != 1:
    raise RuntimeError(f"Expected one bundled TLS extension, found {libraries}")
command = ["otool", "-L"] if platform.system() == "Darwin" else ["ldd"]
output = subprocess.check_output(command + [str(libraries[0])], text=True)
print(output)
dependencies = "\n".join(output.splitlines()[1:]) if platform.system() == "Darwin" else output
if any(token in dependencies for token in ("libssl", "libcrypto", ".build/", "/opt/homebrew", "/usr/local/opt", "not found")):
    raise RuntimeError("TLS extension depends on an external or missing build library")
print("PASS: bundled TLS has no external OpenSSL/build-library dependency")
