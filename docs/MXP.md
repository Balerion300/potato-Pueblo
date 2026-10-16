# MXP display support

In World Configuration → Output Settings, enable **MXP** and reconnect.
**Show inline images** and **Allow command clicks** also apply to MXP.
The server must negotiate Telnet option 91 and send MXP mode controls;
enabling the option does not turn ordinary server text into markup.
An MXP-enabled world continues detecting Telnet negotiation after the legacy
90-second detection window, so servers can activate MXP later in a session.

Supported subset of the [MXP 1.0 specification](https://www.zuggsoft.com/zmud/mxp.htm):

- Open, Secure, Locked, temporary Secure, reset, and persistent default modes.
- Bold, italic, underline, strikeout, BR, SBR, basic and numeric entities.
- Secure A/HREF web links and SEND command links. SEND accepts positional or
  named HREF, caption defaults, `&text;`, PROMPT input prefilling, pipe-separated
  command menus with HINT labels, and named/global EXPIRE.
- Secure IMAGE (FNAME, URL, T) and IMG (SRC, ALT), using the same asynchronous,
  bounded image loader as Pueblo in main and spawn transcripts.
- Secure VERSION and SUPPORT queries, reporting only implemented capabilities.
- Readable captions for triggers, logs, copied text, and prompts.

Command links send literal game commands only after activation. PROMPT links
fill the input without sending. Mode restrictions, the command opt-in, reconnect
epochs, and expiration are checked again when a link or menu item is activated.
As specified by MXP, links without an EXPIRE name remain active through EXPIRE.
The client does not evaluate incoming text as Tcl or local slash commands.
Menus accept at most 16 commands; command length is bounded at 2,048 characters.
Incomplete tokens and SEND captions are bounded at 8,192 characters, and the
formatting stack at 128 entries. Expiration
names are limited to 128; overflowing that table expires existing links.

This is a display subset, not complete MXP. Custom ELEMENT/ENTITY definitions,
COLOR/FONT, P/NOBR paragraph behavior, frames, sound, gauges, server variables,
scripts, and automatic command execution are not implemented or advertised.
JPEG requires the optional Tk Img extension; the bundled runtime supports PNG
and GIF. Existing image resource limits and HTTPS validation remain in effect.

Tests cover every split point in representative markup and Telnet negotiation,
malformed input, mode boundaries, command opt-outs, expiry, native menu widgets,
real socket capability replies, ANSI mixing, mouse command/image clicks, main
and spawn image loading, prompt parsing, saved settings, and stale links.
Unattended menu tests invoke the actual Tk menu entries while substituting the
interactive `tk_popup` call; physical menu interaction still needs user testing.
The diagnostic soak alternates Pueblo and MXP sessions and profiles both parsers.
