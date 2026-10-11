# Potato Pueblo preview

This fork adds negotiated Pueblo captions, clickable web and game-command
links, and static images inside the scrolling transcript. Existing plain URL
recognition is retained. In World Configuration, under Output Settings, enable
Pueblo and reconnect. **Show inline images** and **Allow command clicks** are
separate opt-in controls. Nothing executes when a link arrives; commands are sent
only when clicked and bypass Potato's local slash-command interpreter.

Supported display subset: `XCH_MUDTEXT`, `A HREF` (including `XCH_CMD="true"`),
`IMG SRC`, `PRE`, `BR`, `P`, bold, italic, underline, basic/numeric entities.
Literal/entity tabs survive; a BR followed by its transport newline does not
double-space PRE output. The server's Pueblo greeting gets one PUEBLOCLIENT reply
per connection. Ordinary output remains literal before negotiation or when
Pueblo is off. This is not a general HTML browser or complete MXP implementation.

PNG and the first frame of GIF use Tk's built-in decoder. JPEG requires the
optional Tcl **Img** package; without it the clickable fallback remains visible.
Images retain their link or command action, scroll with surrounding text, scale
down to each output widget's width, and retain a text URL for copying and logs.
Triggers match readable captions and image URL fallbacks, not image pixels.
Main and spawn transcripts render separately. Images are neither HTML panes nor
floating windows. Font/color attributes, tables, animation and text wrapping
alongside images are outside this first subset.

Image downloads use the platform's `curl`, asynchronously: four requests, 64
queued, 15-second timeout, 8 MiB per response, 8192 pixels per dimension and 16
million source pixels. At most 64 loaded images share a 16-million-pixel decoded
budget (about 64 MiB). Clear/trim/destroy releases photos. No disk cache, scripts,
cookies, curl config, proxy environment or redirects. Only public named HTTP(S)
URLs are allowed; credentials, local names and literal IPs are rejected. DNS
resolved address ranges are not checked. TLS uses curl's certificate validation.
Failed/unsupported/over-budget images keep their clickable text fallback.

## Native runtimes and the Tahoe report

Upstream issue [541](https://github.com/potatomushclient/potato/issues/541), filed
October 5, 2026, reports that the last Mac version does not work on Tahoe 26.6.2.
It supplies no exception, architecture or reproduction details. These previews
build Tcl/Tk **8.6.18** from pinned source for Windows, Linux and both Mac
architectures. That release includes support for macOS's major-version
renumbering: [release notes](https://github.com/tcltk/tcl/releases/tag/core-8-6-18).
This is a plausible runtime remedy, not evidence that the reported Tahoe failure
is fixed. Native Tahoe user acceptance is still required.

Download the ZIP for your platform from the successful GitHub Actions run.
Mac: open `Potato Pueblo Preview.app`; Windows/Linux: use the included Start
launcher. Mac previews are ad-hoc signed, not notarized. Linux requires the
desktop X11/font libraries. `curl` must be available for remote images.
Preview launchers use their own profile directory and copy no existing worlds,
passwords, startup scripts or preferences. `POTATO_HOME` can explicitly choose
another profile directory. Source launch remains `wish8.6 potato.vfs/main.tcl`.

## Verification

`wish8.6 tests/pueblo.test.tcl` checks fragmented markup, negotiation, links,
entities, tabs, opt-outs, URL/command validation, native Tk image insertion,
copy/log fallbacks and photo cleanup. `tests/client.test.tcl` requires an empty
`POTATO_HOME` and checks complete client startup, a local socket connection,
visible spacing, native Tk mouse command delivery, caption triggers and config.
`python tests/run_tcl.py tests/pueblo.test.tcl` (or `client.test.tcl`) can use
Python's native Tk interpreter when wish is absent. All fixtures are isolated
from live games and personal profiles. Everyday sessions and native Tahoe
acceptance remain preview gates.
