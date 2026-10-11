package require Tk 8.6
wm withdraw .
set root [file normalize [file join [file dirname [info script]] ..]]
source [file join $root potato.vfs lib potato-pueblo.tcl]
source [file join $root potato.vfs lib potato-pueblo-images.tcl]
set ::potato::conn(1,world) 1
set ::potato::conn(1,connected) 1
foreach key {enabled images commands} {set ::potato::world(1,pueblo,$key) 1}
set ::sent {}
set ::opened {}
proc ::potato::send_to_noparse {c value args} {lappend ::sent $value}
proc ::potato::launchWebPage {value} {lappend ::opened $value}
proc ::potato::atEnd {w} {return [expr {[lindex [$w yview] 1] >= 0.999}]}
proc tagged {s} {
    set result {}
    foreach ch [split $s ""] {lappend result [list $ch {fg bg {}}]}
    return $result
}
proc plain {items} {set s ""; foreach item $items {append s [lindex $item 0]}; return $s}
proc assert {value message} {
    if {![uplevel 1 [list expr $value]]} {error "FAIL: $message"}
    incr ::checks
}
proc start {} {
    ::potato::pueblo::reset 1
    ::potato::pueblo::parse 1 [tagged {This world is Pueblo 1.10 Enhanced.}]
    ::potato::pueblo::parse 1 [tagged {<xch_mudtext>}]
}
set ::checks 0
start
assert {[lindex $::sent end] eq "PUEBLOCLIENT 1.10"} negotiation
set fixture {<pre>  Name&#9;House<BR>
<a xch_cmd="true" href="look &amp; say {hi}; [exec bad]">http://caption.example.org</a><br>
<a href="https://www.example.org/path?a=1&amp;b=2">Website</a><img src="https://www.example.org/pic.png" alt="Portrait"></pre>}
set expected [::potato::pueblo::parse 1 [tagged $fixture]]
set expectedText [plain $expected]
for {set split 0} {$split <= [string length $fixture]} {incr split} {
    start
    set a [::potato::pueblo::parse 1 [tagged [string range $fixture 0 $split-1]]]
    set b [::potato::pueblo::parse 1 [tagged [string range $fixture $split end]]]
    assert {[plain [concat $a $b]] eq $expectedText} "fragment $split"
}
assert {[string first "Name\tHouse\nhttp" $expectedText] >= 0} "PRE BR/wire newline normalization and tabs"
foreach bad {file:///tmp/a http://localhost/a http://127.0.0.1/a http://10.0.0.1/a http://host/a https://user:pass@example.org/a https://example.local/a javascript:bad {https://example.org/a
b} https://example.org:99999/a} {
    assert {![::potato::pueblo::url $bad]} "blocked URL $bad"
}
assert {[::potato::pueblo::url https://www.example.org/a?q=1&b=2]} "public URL"
assert {![::potato::pueblo::command "look\nquit"]} "single-line commands"
assert {[::potato::pueblo::entities {&lt;&gt;&amp;&quot;&apos;&#9;} ] eq "<>&\"'\t"} entities
start
set ::sent {}
set result [::potato::pueblo::parse 1 [tagged {<a xch_cmd="true" href="look">Click</a>}]]
assert {$::sent eq {}} "parsing never executes commands"
set action [lindex $result 0 1 2 0]
::potato::pueblo::activate {*}[lrange $action 1 end]
assert {$::sent eq {look}} "explicit command activation"
set ::potato::world(1,pueblo,commands) 0
::potato::pueblo::activate {*}[lrange $action 1 end]
assert {[llength $::sent] == 1} "command opt out"
set ::potato::world(1,pueblo,commands) 1
::potato::pueblo::reset 1
::potato::pueblo::activate {*}[lrange $action 1 end]
assert {[llength $::sent] == 1} "stale connection action"
set ::potato::world(1,pueblo,enabled) 0
assert {[plain [::potato::pueblo::parse 1 [tagged {<b>literal &amp;</b>}]]] eq {<b>literal &amp;</b>}} "disabled passthrough"
set ::potato::world(1,pueblo,enabled) 1
::potato::pueblo::reset 1
assert {[plain [::potato::pueblo::parse 1 [tagged {<b>literal &amp;</b>}]]] eq {<b>literal &amp;</b>}} "unnegotiated passthrough"
start
::potato::pueblo::parse 1 [tagged [string repeat < 9000]]
assert {[llength [dict get $::potato::pueblo::state(1) pending]] <= 8192} "bounded partial tags"
set png [binary decode base64 {iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAFklEQVR4nGP4z8DAwMDAxMDAwMDAAAANHQEDasKb6QAAAABJRU5ErkJggg==}]
assert {[::potato::pueblo::images::dimensions $png] eq {2 2}} "PNG dimensions"
set huge [string replace $png 16 23 [binary format II 99999 99999]]
assert {[catch {::potato::pueblo::images::dimensions $huge}]} "oversize header rejected"
assert {[catch {::potato::pueblo::images::dimensions not-an-image}]} "non-image rejected"
# Use an actual Tk transcript and checksum-valid PNG created by Tk itself.
set photo [image create photo -width 40 -height 20]
$photo put red -to 0 0 40 20
set png [$photo data -format png]
image delete $photo
text .output -width 60 -height 12
pack .output
wm deiconify .
update
start
set items [::potato::pueblo::parse 1 [tagged {Before<img src="https://www.example.org/pic.png" alt="Portrait">After}]]
foreach item $items {
    lassign $item ch tags
    .output insert end $ch [concat {*}$tags]
}
set imageTag ""
foreach tag [.output tag names] {if {[lindex $tag 0] eq "potatoImage"} {set imageTag $tag}}
set key [list .output $imageTag]
dict set ::potato::pueblo::images::seen $key 1
::potato::pueblo::images::install $key $png
assert {[llength [.output image names]] == 1} "image inside transcript"
assert {[string first {[Portrait: https://www.example.org/pic.png]} [.output get 1.0 end]] >= 0} "copy/log URL fallback"
assert {[dict size $::potato::pueblo::images::photos] == 1} "tracked photo"
.output delete 1.0 end
::potato::pueblo::images::collect
assert {[dict size $::potato::pueblo::images::photos] == 0} "trim/clear releases photo"
assert {$::potato::pueblo::images::totalPixels == 0} "image budget released"
destroy .output
puts "PASS: $::checks checks (Tcl [info patchlevel], Tk [package present Tk], [tk windowingsystem])"
destroy .
