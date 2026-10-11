# Performance and stability diagnostics

Run `python scripts/benchmark.py --archive <preview.zip> --output <report.json>`
with Python and psutil 7.1.0 installed. Linux also needs a display, or `xvfb-run -a`
before the command. The benchmark extracts the downloadable native runtime and
client into a temporary directory and uses a fresh, disposable profile. It talks
only to an independent loopback game/HTTP fixture; no live game or personal
settings are involved. `--source` allows a controlled comparison of working
source using the same packaged runtime.

The workload includes 1,000-line plain, ANSI, and Pueblo-link bursts, another
1,000 lines with retained links, three cycles of 16 PNGs in both main and spawn
views, 30 clear/refill cycles of 200 links, deliberately fragmented UTF-8/ANSI/
Pueblo input, 1,000 outgoing commands, bounded scrollback, and ten reconnects.
It fails on lost/duplicated lines or commands, background errors, failed image
reclamation, changed fragmented text, unbounded configured scrollback, or failed
reconnection. Native integration and real SSL checks run separately.

The JSON records actual build/OS identity, incoming bytes and read calls,
end-to-end transcript throughput, local command echo latency, 50 ms timer
lateness, instrumented hot-path time, and process RSS/private memory, CPU and
available operating-system I/O counters sampled about every 100 ms. Nested hot
paths overlap: their totals must not be added together. OS I/O counters are not
a portable measurement of network throughput; the socket byte counts supply
that measurement. Only the client process is sampled, not curl child processes.
Short phases may contain no timer/latency samples. Local echo latency is not
physical keyboard-to-screen latency or Internet/server latency.

The native GitHub matrix runs the same workload on Windows, macOS 15 and Tahoe
(Apple Silicon/Intel), Ubuntu 22.04/24.04 x86-64 and Ubuntu 24.04 ARM. Performance
numbers are diagnostic, not portable pass/fail speed thresholds: shared runners
and local desktop load vary. Completed receipt files and process exit status are
both required, including for Windows GUI executables.

## Improvements measured in the Windows comparison

The original client read ten bytes per socket callback and flushed widget layout
after every output line. It also rescanned all retained Pueblo tags and reset
style fonts on every line. The update reads bounded 1 KiB chunks, flushes layout
once per chunk, binds newly inserted markup, sweeps old tags every 64 renders,
and only changes style fonts when the transcript font changes. Small reads remain
nonblocking; buffering does not wait for a full chunk. The bounded chunk is
intentional to keep incoming bursts from monopolizing the UI event loop.

An original 4,000-line/2,000-link-cycle Windows run took 108 seconds with about
90 CPU seconds. A matching run after these changes took 25 seconds and about
22 CPU seconds; plain throughput rose from 13.8 to 46.9 KiB/s, and link throughput
from 6.3 to 40.5 KiB/s. Peak RSS was approximately 55 versus 58 MiB. These are
individual instrumented runs, not a statistical hardware-independent guarantee.
Batching trades more work per event for much lower total work; command/timer
latencies are recorded explicitly so regressions remain visible.

The pre-existing main-transcript output-limit setting was unused. A regression
test fails on the previous package and passes after enforcing the configured
positive line limit. Trimming reclaims main-view image resources while preserving
images still present in spawn views. Unlimited output remains the default;
retaining unlimited history necessarily grows memory. Enable the output limit
when bounded transcript memory is wanted.

These checks cover synthetic bursts and repeated lifecycle operations, not
multi-day sessions, every user script/trigger, every Linux distribution, Finder
security prompts, or Mac app notarization. Native desktop and longer real-game
acceptance still matter before a final release designation.
