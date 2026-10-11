"""Benchmark the native packaged client, sampling process memory/CPU/OS I/O."""
import argparse
import json
import os
import pathlib
import platform
import statistics
import subprocess
import sys
import tempfile
import time
import zipfile
import psutil

root = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root / "tests"))
from fixture_server import Fixture

parser = argparse.ArgumentParser()
parser.add_argument("--archive", type=pathlib.Path)
parser.add_argument("--source", action="store_true", help="Use working source with the same packaged runtime")
parser.add_argument("--output", type=pathlib.Path, default=root / "artifacts/performance.json")
args = parser.parse_args()
archive = args.archive or next((root / "artifacts").glob("Potato-Pueblo-Preview-*.zip"))
samples = []
with tempfile.TemporaryDirectory(prefix="potato-benchmark-") as folder, Fixture() as fixture:
    folder = pathlib.Path(folder)
    if platform.system() == "Darwin":
        subprocess.run(["ditto", "-x", "-k", str(archive), str(folder)], check=True)
    else:
        with zipfile.ZipFile(archive) as z:
            z.extractall(folder)
            if platform.system() != "Windows":
                for member in z.infolist():
                    mode = member.external_attr >> 16
                    if mode:
                        (folder / member.filename).chmod(mode)
    package = next(folder.rglob("BUILD.json")).parent
    identity = json.loads((package / "BUILD.json").read_text())
    executable = package / "runtime/bin" / ("wish86s.exe" if platform.system() == "Windows" else "wish8.6")
    events = folder / "events.tsv"
    env = dict(os.environ, **fixture.environment(), TCL_LIBRARY=str(package / "runtime/lib/tcl8.6"),
               TK_LIBRARY=str(package / "runtime/lib/tk8.6"), POTATO_HOME=str(folder / "profile"),
               POTATO_TEST_SOURCE_ROOT=str(root if args.source else package), POTATO_PERF_EVENTS=str(events))
    with (folder / "process.log").open("w") as log:
        process = subprocess.Popen([str(executable), str(root / "tests/run.tcl"), str(root / "tests/performance.tcl")],
                                   env=env, cwd=package, stdout=log, stderr=log)
        tracked = psutil.Process(process.pid)
        start = time.monotonic()
        while process.poll() is None:
            if time.monotonic() - start > 360:
                process.kill()
                process.wait()
                break
            try:
                memory = tracked.memory_info()
                cpu = tracked.cpu_times()
                sample = dict(seconds=time.monotonic()-start, rss=memory.rss,
                              private=getattr(memory, "private", None), cpu_seconds=cpu.user+cpu.system)
                try:
                    sample["io"] = tracked.io_counters()._asdict()
                except (AttributeError, psutil.AccessDenied):
                    pass
                if events.exists():
                    rows = events.read_text(errors="replace").splitlines()
                    stages = [r.split("\t")[1] for r in rows if r.startswith("BEGIN\t")]
                    sample["stage"] = stages[-1] if stages else "startup"
                samples.append(sample)
            except psutil.NoSuchProcess:
                break
            time.sleep(.1)
        text = events.read_text() if events.exists() else ""
        if process.returncode or not text.rstrip().endswith("PASS"):
            diagnostics = dict(build=identity, status="FAIL", samples=samples, events=text,
                               process_log=(folder / "process.log").read_text(errors="replace"))
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(json.dumps(diagnostics, indent=2))
            print(diagnostics["process_log"])
            raise RuntimeError(f"Benchmark failed: {text[-4000:]}")

def distribution(values):
    values = sorted(values)
    if not values:
        return None
    return dict(n=len(values), median_ms=statistics.median(values), p95_ms=values[min(len(values)-1, int(len(values)*.95))], max_ms=max(values))

phases = []
outgoing = None
for row in text.splitlines():
    fields = row.split("\t")
    if fields[0] == "PHASE":
        _, name, ms, size, calls, ticks, lags, rtts, tags, images = fields
        phases.append(dict(name=name, elapsed_ms=float(ms), received_bytes=int(size), read_calls=int(calls),
                           throughput_kib_s=int(size)/1024/(float(ms)/1000),
                           event_loop_lag=distribution([float(v) for v in lags.split(",") if v]),
                           input_round_trip=distribution([float(v) for v in rtts.split(",") if v]),
                           transcript_tags=int(tags), images=int(images), hot_path_ms={}))
    elif fields[0] == "HOT":
        phases[-1]["hot_path_ms"][fields[2]] = int(fields[3])/1000
    elif fields[0] == "OUTGOING":
        _, ms, size, count, rtts = fields
        if int(count) != 1000:
            raise RuntimeError("Lost outgoing commands")
        outgoing = dict(elapsed_ms=float(ms), bytes=int(size), commands=int(count),
                        throughput_kib_s=int(size)/1024/(float(ms)/1000),
                        round_trip=distribution([float(v) for v in rtts.split(",") if v]))
result = dict(build=identity, status="PASS", working_source=args.source, platform=platform.platform(),
              elapsed_seconds=samples[-1]["seconds"], peak_rss_bytes=max(s["rss"] for s in samples),
              cpu_seconds=samples[-1]["cpu_seconds"], phases=phases, samples=samples, outgoing=outgoing,
              cleanup=[r for r in text.splitlines() if r.startswith(("CLEAN\t", "SOAK\t", "IMAGES\t", "RECONNECT\t"))])
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(result, indent=2))
for phase in phases:
    if phase["name"].startswith("soak_") and phase["name"] not in ("soak_0", "soak_29"):
        continue
    print(f"{phase['name']}: {phase['elapsed_ms']:.0f}ms, {phase['throughput_kib_s']:.1f} KiB/s, {phase['read_calls']} reads, input {phase['input_round_trip']}")
print(f"PASS: benchmark; peak RSS {result['peak_rss_bytes']/1048576:.1f} MiB; report {args.output}")
