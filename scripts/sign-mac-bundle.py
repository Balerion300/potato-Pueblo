"""Ad-hoc sign nested native code, then seal the fully assembled app bundle."""
import pathlib
import subprocess
import sys

app = pathlib.Path(sys.argv[1]).resolve()
assert app.suffix == '.app' and (app / 'Contents/Info.plist').is_file()
magic = {bytes.fromhex(h) for h in ('feedface', 'cefaedfe', 'feedfacf', 'cffaedfe',
                                 'cafebabe', 'bebafeca', 'cafebabf', 'bfbafeca')}
for path in sorted(app.rglob('*')):
    if path.is_symlink() or not path.is_file():
        continue
    with path.open('rb') as stream:
        native = stream.read(4) in magic
    if native:
        subprocess.run(['codesign', '--force', '--sign', '-', str(path)], check=True)
subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', '--verbose=2', str(app)], check=True)
assert (app / 'Contents/_CodeSignature/CodeResources').is_file()
print('PASS: assembled app and nested native signatures verified; ad-hoc, not notarized')
