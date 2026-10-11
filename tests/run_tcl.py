"""Run native Tcl/Tk tests with Python's Tk interpreter when wish is absent."""
import pathlib
import sys
import tkinter
import os
import tempfile

root = tkinter.Tk()
profile = tempfile.TemporaryDirectory(prefix="potato-test-")
os.environ["POTATO_HOME"] = profile.name
root.tk.call("set", "env(POTATO_HOME)", profile.name)
try:
    root.tk.call("source", str(pathlib.Path(sys.argv[1]).resolve()))
except tkinter.TclError:
    print(root.tk.call("set", "errorInfo"), file=sys.stderr)
    raise SystemExit(1)
