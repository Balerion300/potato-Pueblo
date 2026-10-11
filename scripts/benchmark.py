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
parser.add_argument("--stress-seconds", type=int, default=0, help="Additional sustained mixed workload duration")
parser.add_argument("--output", type=pathlib.Path, default=root / "artifacts/performance.json")
args = parser.parse_args()
if not 0 <= args.stress_seconds <= 7200:
    parser.error("stress duration must be between 0 and 7200 seconds")
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
               POTATO_TEST_SOURCE_ROOT=str(root if args.source else package), POTATO_PERF_EVENTS=str(events),
               POTATO_STRESS_SECONDS=str(args.stress_seconds))
    with (folder / "process.log").open("w") as log:
        for trial in range(5):
            receipt = folder / f"startup-{trial}.txt"
            startup_env = dict(env, POTATO_HOME=str(folder / f"startup-profile-{trial}"),
                               POTATO_TEST_RESULT=str(receipt))
            startup = subprocess.run([str(executable), str(root / "tests/run.tcl"), str(root / "tests/startup.tcl")],
                                     env=startup_env, cwd=package, stdout=log, stderr=log, timeout=60)
            outcome = receipt.read_text() if receipt.exists() else "No startup completion receipt"
            if startup.returncode or outcome.strip() != "PASS":
                args.output.parent.mkdir(parents=True, exist_ok=True)
                args.output.write_text(json.dumps(dict(build=identity, status="FAIL", startup_trial=trial, error=outcome), indent=2))
                raise RuntimeError(f"Native startup {trial} failed: {outcome}")
        process = subprocess.Popen([str(executable), str(root / "tests/run.tcl"), str(root / "tests/performance.tcl")],
                                   env=env, cwd=package, stdout=log, stderr=log)
        tracked = psutil.Process(process.pid)
        start = time.monotonic()
        event_offset = 0
        stage = "startup"
        while process.poll() is None:
            if time.monotonic() - start > 360 + args.stress_seconds:
                process.kill()
                process.wait()
                break
            try:
                memory = tracked.memory_info()
                cpu = tracked.cpu_times()
                sample = dict(seconds=time.monotonic()-start, rss=memory.rss,
                              private=getattr(memory, "private", None), cpu_seconds=cpu.user+cpu.system)
                sample["threads"] = tracked.num_threads()
                sample["handles"] = tracked.num_handles() if os.name == "nt" else tracked.num_fds()
                children = []
                for child in tracked.children(recursive=True):
                    try:
                        children.append(dict(pid=child.pid, name=child.name(), rss=child.memory_info().rss))
                    except (psutil.NoSuchProcess, psutil.AccessDenied):
                        pass
                sample["children"] = children
                sample["tree_rss"] = memory.rss + sum(c["rss"] for c in children)
                try:
                    sample["io"] = tracked.io_counters()._asdict()
                except (AttributeError, psutil.AccessDenied):
                    pass
                if events.exists():
                    with events.open(encoding="utf-8", errors="replace") as stream:
                        stream.seek(event_offset)
                        for row in stream:
                            if row.startswith("BEGIN\t"):
                                stage = row.rstrip().split("\t")[1]
                        event_offset = stream.tell()
                sample["stage"] = stage
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
total_hot = {}
resources = []
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
    elif fields[0] == "TOTALHOT":
        total_hot[fields[1]] = dict(milliseconds=int(fields[2])/1000, calls=int(fields[3]))
    elif fields[0] == "RESOURCES":
        names = ('cycle', 'timestamp_ms', 'tk_images', 'photo_pairs', 'pixels', 'downloads',
                 'queued_downloads', 'seen_images', 'main_tags', 'channels', 'callbacks', 'views')
        resources.append(dict(zip(names, [fields[1]] + [int(v) for v in fields[2:]])))
    elif fields[0] == "OUTGOING":
        _, ms, size, count, rtts = fields
        if int(count) != 1000:
            raise RuntimeError("Lost outgoing commands")
        outgoing = dict(elapsed_ms=float(ms), bytes=int(size), commands=int(count),
                        throughput_kib_s=int(size)/1024/(float(ms)/1000),
                        round_trip=distribution([float(v) for v in rtts.split(",") if v]))
result = dict(build=identity, status="PASS", startup_trials=5, working_source=args.source, platform=platform.platform(),
              stress_seconds=args.stress_seconds,
              elapsed_seconds=samples[-1]["seconds"], peak_rss_bytes=max(s["rss"] for s in samples),
              cpu_seconds=samples[-1]["cpu_seconds"], phases=phases, samples=samples, outgoing=outgoing,
              peak_tree_rss_bytes=max(s["tree_rss"] for s in samples),
              resources=resources, total_hot_paths=total_hot,
              allocations=[r for r in text.splitlines() if r.startswith("ALLOCATED\t")],
              cleanup=[r for r in text.splitlines() if r.startswith(("CLEAN\t", "SOAK\t", "IMAGES\t", "RECONNECT\t", "STRESS\t"))])
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(result, indent=2))
for phase in phases:
    if phase["name"].startswith("stress_") or (phase["name"].startswith("soak_") and phase["name"] not in ("soak_0", "soak_29")):
        continue
    print(f"{phase['name']}: {phase['elapsed_ms']:.0f}ms, {phase['throughput_kib_s']:.1f} KiB/s, {phase['read_calls']} reads, input {phase['input_round_trip']}")
print(f"PASS: benchmark; peak RSS {result['peak_rss_bytes']/1048576:.1f} MiB; report {args.output}")
