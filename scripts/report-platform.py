"""Record the actual CI host, rather than treating the runner label as proof."""
import json
import os
import pathlib
import platform
import subprocess

def describe():
    result = dict(system=platform.system(), architecture=platform.machine(),
                  release=platform.release(), version=platform.version(),
                  runner=os.environ.get("POTATO_RUNNER_LABEL", "local"),
                  image_version=os.environ.get("ImageVersion", ""))
    if platform.system() == "Darwin":
        result["macos"] = subprocess.check_output(["sw_vers"], text=True).strip()
    elif platform.system() == "Linux":
        result["distribution"] = pathlib.Path("/etc/os-release").read_text().strip()
    elif platform.system() == "Windows":
        result["windows"] = platform.win32_ver()
    return result

if __name__ == "__main__":
    root = pathlib.Path(__file__).resolve().parents[1]
    output = root / ".build" / "platform-report.json"
    output.parent.mkdir(exist_ok=True)
    report = describe()
    output.write_text(json.dumps(report, indent=2) + "\n")
    print(output.read_text())
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as summary:
            summary.write("### Actual test platform\n\n```json\n" + output.read_text() + "```\n")
