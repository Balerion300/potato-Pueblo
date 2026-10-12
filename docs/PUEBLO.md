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
Pueblo is off. This is not a general HTML browser. Separate negotiated
[MXP display support](MXP.md) is available through the MXP world setting.
`<xch_mudtext>` selects literal text; `</xch_mudtext>` selects markup, matching
PennMUSH's actual negotiation response. Mode-only IMG messages stay invisible.
Incoming CRLF and LF lines are both accepted, including through Telnet buffering.
Game SSL connections explicitly select TLS 1.2 and send the server hostname,
including when using the legacy bundled TclTLS library.

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
The native test matrix now includes Tahoe on Apple Silicon and Intel, macOS 15
on both architectures, Ubuntu 22.04/24.04 x86_64, Ubuntu 24.04 ARM, and Windows.
Every job records the actual OS version in its logs, job summary and packaged
BUILD.json. Check the latest successful run for evidence on each platform.
These tests exercise the portable native runtime; they do not prove the old
upstream Mac application bundle works. Native desktop user acceptance is still
required, particularly for downloaded-file security prompts and appearance.

Unix previews now build TclTLS 2.0.1 with statically linked OpenSSL 3.5.9 from
pinned sources. Apple Silicon/Intel Mac and Linux require no separately installed
SSL package. Windows retains its existing bundled TclTLS library. TLS build
identity and licenses are included in each Unix runtime. Game connections disable
obsolete protocols and send SNI. Existing self-signed-server compatibility is
preserved: game encryption does not validate the server certificate; HTTPS image
downloads continue to validate certificates through curl.

The explicitly invoked `tests/ssl.test.tcl` uses the full client to connect to
`bod.westeros.org:3001`, check the negotiated cipher, receive the greeting, send
Pueblo negotiation, receive the response, disconnect and reconnect. It does not
log in or modify the game. Extracted-package verification runs this test with a
fresh profile and the build runtime unavailable. Unlike the ordinary loopback
fixtures, this is a real SSL interoperability check and requires network access.

Download the ZIP for your platform from the successful GitHub Actions run.
Mac: open `Potato Pueblo.app`; Windows/Linux: use the included Start
launcher. The Mac application includes its own native runtime, SSL library,
scripts and icon. Extracted-package checks exercise both LaunchServices startup
and the bundle launcher with the build runtime unavailable. These previews are
not notarized. Linux requires the
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
