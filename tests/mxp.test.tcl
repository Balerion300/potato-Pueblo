package require Tk 8.6
wm withdraw .
set deadline [after 15000 {puts stderr {FAIL: MXP test deadline}; exit 1}]
set root [file normalize [file join [file dirname [info script]] ..]]
foreach file {pueblo pueblo-images mxp telnet} {source [file join $root potato.vfs lib potato-$file.tcl]}
set ::potato::conn(1,world) 1
set ::potato::conn(1,connected) 1
set ::potato::world(1,mxp,enabled) 1
foreach key {enabled images commands} {set ::potato::world(1,pueblo,$key) 1}
foreach {key value} {prompts 0 prompt,ignoreNewline 0} {set ::potato::world(1,telnet,$key) $value}
set ::sent {}; set ::raw {}; set ::opened {}; set ::checks 0
proc ::potato::sendRaw {c value args} {lappend ::raw $value}
proc ::potato::send_to_noparse {c value args} {lappend ::sent $value}
proc ::potato::launchWebPage {value} {lappend ::opened $value}
proc ::potato::addProtocol {c value} {lappend ::potato::conn($c,protocols) $value}
proc tagged {value} {set items {}; foreach ch [split $value ""] {lappend items [list $ch {fg bg {}}]}; return $items}
proc plain {items} {set value ""; foreach item $items {append value [lindex $item 0]}; return $value}
proc ::potato::parseANSI {value args} {return [::tagged $value]}
proc assert {value message} {if {![uplevel 1 [list expr $value]]} {error "FAIL: $message"}; incr ::checks}
proc begin {{mode 1}} {::potato::mxp::reset 1 1; ::potato::mxp::mode 1 $mode}
proc parse {value} {::potato::mxp::parse 1 [tagged $value]}
proc action {items} {
    foreach item $items {foreach tag [lindex $item 1 2] {if {[lindex $tag 0] eq "potatoAction"} {return $tag}}}
    return ""
}
proc click {tag} {::potato::pueblo::activate {*}[lrange $tag 1 end]}
::potato::telnet::init
::potato::mxp::reset 1
::potato::mxp::negotiate 1 WILL
assert {[lindex $::raw end] eq [binary format ccc 255 253 91]} "WILL MXP accepts option 91"
assert {[::potato::mxp::active 1]} "negotiated MXP active"
set before [llength $::raw]; ::potato::mxp::negotiate 1 WILL
assert {[llength $::raw] == $before} "duplicate negotiation suppressed"
::potato::mxp::negotiate 1 WONT
assert {![::potato::mxp::active 1]} "WONT disables MXP"
set ::potato::world(1,mxp,enabled) 0
::potato::mxp::negotiate 1 WILL
assert {[lindex $::raw end] eq [binary format ccc 255 254 91]} "opt-out refuses MXP"
set ::potato::world(1,mxp,enabled) 1
begin
set items [parse {<SEND 'look'>Look</SEND>}]
assert {[plain $items] eq "Look"} "positional SEND caption"
set link [action $items]; click $link
assert {[lindex $::sent end] eq "look"} "explicit SEND click"
set before [llength $::sent]
parse {<SEND href="quit">Never clicked</SEND>}
assert {[llength $::sent] == $before} "parsing never runs commands"
set ::potato::world(1,pueblo,commands) 0; click $link
assert {[llength $::sent] == $before} "command click opt-out"
set ::potato::world(1,pueblo,commands) 1
set items [parse {<SEND>north</SEND>}]; click [action $items]
assert {[lindex $::sent end] eq "north"} "SEND caption is default command"
set items [parse {<SEND href='buy &text;'>bread &amp; butter</SEND>}]; click [action $items]
assert {[lindex $::sent end] eq "buy bread & butter"} "SEND text substitution"
begin 0
set items [parse {<SEND look>player</SEND><IMAGE https://www.example.org/a.png><VERSION><B>bold</B>}]
assert {[action $items] eq ""} "open mode cannot create command links"
assert {[plain $items] eq "playerbold"} "open mode formatting and no image fallback"
assert {[lsearch -exact [lindex $items end 1 2] puebloBold]>=0} "open bold retained"
begin 2
assert {[plain [parse {<SEND look>literal</SEND>&amp;}]] eq {<SEND look>literal</SEND>&amp;}} "locked mode literal tags and entities"
begin 0; ::potato::mxp::mode 1 4
set items [parse {<SEND look>Look}]
::potato::mxp::mode 1 4; set items [concat $items [parse {</SEND>}]]
assert {[action $items] ne ""} "temporary secure applies to one tag"
begin 0; ::potato::mxp::mode 1 4
parse {x<SEND quit>bad</SEND>}
assert {[dict get $::potato::mxp::state(1) send] eq ""} "temporary mode must immediately precede tag"
begin 1; parse "<B>A\n"
assert {[dict get $::potato::mxp::state(1) mode] == 0} "secure line reverts to default"
begin 6; parse "A\n"
assert {[dict get $::potato::mxp::state(1) mode] == 1} "locked secure survives newline"
::potato::mxp::mode 1 3
assert {[dict get $::potato::mxp::state(1) action] eq ""} "reset closes actions"
begin
set fixture {<B><SEND href='say &text;' hint='Speak'>caf&#233; &amp; snow</SEND></B><IMG src='https://www.example.org/pic.png' alt='Portrait'>}
set expected [plain [parse $fixture]]
for {set split 0} {$split <= [string length $fixture]} {incr split} {
    begin
    set a [parse [string range $fixture 0 $split-1]]
    set b [parse [string range $fixture $split end]]
    assert {[plain [concat $a $b]] eq $expected} "fragmented tags/entities at $split"
}
begin
set items [parse {<IMAGE pic.png URL='https://www.example.org/assets/' T=portraits>}]
assert {[string first {https://www.example.org/assets/portraits/pic.png} [plain $items]]>=0} "IMAGE filename URL and class"
set imageTag ""; foreach tag [lindex $items 0 1 2] {if {[lindex $tag 0] eq "potatoImage"} {set imageTag $tag}}
assert {$imageTag ne ""} "IMAGE reuses native loader"
assert {[action [parse {<SEND 'look&#10;quit'>Unsafe</SEND>}]] eq ""} "control character command rejected"
assert {[action [parse {<A href='file:///private'>Unsafe</A>}]] eq ""} "unsafe web protocol rejected"
set items [parse {<SEND look expire=room>Look</SEND>}]; set old [action $items]
set before [llength $::sent]; parse {<EXPIRE room>}; click $old
assert {[llength $::sent] == $before} "named expiration disables old links"
set items [parse {<SEND look expire=room>Look</SEND>}]; click [action $items]
assert {[llength $::sent] == $before+1} "new link after named expiry works"
set old [action [parse {<SEND look expire=room>Look</SEND>}]]
parse {<EXPIRE>}; set before [llength $::sent]; click $old
assert {[llength $::sent] == $before} "global expiration"
set old [action [parse {<SEND look>Unnamed</SEND>}]]
parse {<EXPIRE>}; click $old
assert {[llength $::sent] == $before+1} "unnamed links never expire per MXP specification"
set before [llength $::sent]
set old [action [parse {<SEND look>Look</SEND>}]]; ::potato::mxp::reset 1 1; click $old
assert {[llength $::sent] == $before} "connection epoch invalidates links"
begin
parse {<VERSION><SUPPORT send.prompt image.* frame !element>}
assert {[string first "\x1b\[1z<VERSION" [lindex $::sent end-1]] == 0} "secure VERSION reply"
assert {[string first {+send.prompt} [lindex $::sent end]]>=0 && [string first {-frame} [lindex $::sent end]]>=0 && [string first {-!element} [lindex $::sent end]]>=0} "honest support subset"
text .input
set ::potato::conn(1,input1) .input
set before [llength $::sent]; click [action [parse {<SEND 'tell friend ' PROMPT>Friend</SEND>}]]
assert {[.input get 1.0 end-1c] eq {tell friend }} "PROMPT prefills native input"
assert {[llength $::sent] == $before} "PROMPT does not send"
wm deiconify .
update idletasks
puts {CHECK: native MXP menu widget}
# Windows tk_popup enters a platform modal loop. Inspect and invoke the native
# menu widget without entering that interactive loop in unattended tests.
rename tk_popup nativePopup
proc tk_popup {args} {set ::popupArgs $args}
click [action [parse {<SEND 'look|inventory' hint='Choose|Look|Inventory'>Menu</SEND>}]]
assert {[lindex $::popupArgs 0] eq ".potatoMxpCommands" && [.potatoMxpCommands index end] == 1} "SEND creates native menu"
.potatoMxpCommands invoke 1
rename tk_popup {}; rename nativePopup tk_popup
assert {[lindex $::sent end] eq "inventory"} "only selected menu action sends"
destroy .potatoMxpCommands
begin; parse [string repeat < 20000]
assert {[llength [dict get $::potato::mxp::state(1) pending]] < 8192} "bounded malformed token"
begin; parse "<SEND look>[string repeat x 9000]"
assert {[dict get $::potato::mxp::state(1) send] eq ""} "bounded unterminated SEND"
begin 6; parse [string repeat <B> 1000]
assert {[llength [dict get $::potato::mxp::state(1) stack]]==128} "bounded unclosed secure formatting"
begin
set items [parse {<B>outer<B>inner</B>outer</B>}]
assert {"puebloBold" in [lindex $items 11 1 2]} "nested formatting retains outer style"
begin 1; parse "<B>secure\n"; parse "open\n"
assert {"puebloBold" in [lindex [parse continued] 0 1 2]} "secure formatting persists across open newlines"
begin 0; parse "<B>open\n"
assert {"puebloBold" ni [lindex [parse continued] 0 1 2]} "open formatting closes at newline"
set wire [binary format ccc 255 251 91]
append wire [binary format ccc 255 250 91] [binary format cc 255 240] "\x1b\[1z<SEND look>Look</SEND>\n"
for {set split 0} {$split <= [string length $wire]} {incr split} {
    ::potato::mxp::reset 1
    foreach {key value} {state 0 subState 0 buffer,line {} buffer,codes {} afterPrompt 0 protocols {}} {set ::potato::conn(1,telnet,$key) $value}
    set ::potato::conn(1,protocols) {}
    set a [::potato::telnet::process 1 [string range $wire 0 $split-1]]
    set b [::potato::telnet::process 1 [string range $wire $split end]]
    assert {[::potato::mxp::active 1] && [plain [::potato::mxp::line 1 [string trimright "$a$b" \n]]] eq "Look"} "fragmented Telnet negotiation at $split"
}
puts "PASS: $::checks MXP checks (Tcl [info patchlevel], Tk [package present Tk], [tk windowingsystem])"
after cancel $deadline
destroy .
