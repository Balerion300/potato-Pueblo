"""Compare released bundle integrity with the working Atlantis packaging."""
import json
import pathlib
import subprocess

results = {}
for name, folder in [('potato', 'audit/old'), ('atlantis', 'audit/atlantis')]:
    app = next(pathlib.Path(folder).rglob('*.app'))
    check = subprocess.run(['codesign', '--verify', '--deep', '--strict', '--verbose=2',
                            str(app)], capture_output=True, text=True)
    details = subprocess.run(['codesign', '-dv', '--verbose=4', str(app)],
                             capture_output=True, text=True)
    results[name] = dict(verify_exit=check.returncode, verify_output=check.stdout + check.stderr,
                         details=details.stdout + details.stderr,
                         sealed_resources=(app / 'Contents/_CodeSignature/CodeResources').is_file())
pathlib.Path('audit/signatures.json').write_text(json.dumps(results, indent=2))
print(json.dumps(results, indent=2))
assert results['atlantis']['verify_exit'] == 0, 'Working Atlantis signature must pass'
assert results['potato']['verify_exit'] != 0, 'Old Potato must reproduce signature failure'
