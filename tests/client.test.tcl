# Full Potato startup and transcript integration, with a fresh explicit profile.
package require Tk 8.6
set root [file normalize [file join [file dirname [info script]] ..]]
if {![info exists ::env(POTATO_HOME)]} {error "Set POTATO_HOME to a fresh test directory"}
file mkdir $::env(POTATO_HOME)
if {[llength [glob -nocomplain -directory $::env(POTATO_HOME) *]]} {error "Test profile must be empty"}
set file [open [file join $::env(POTATO_HOME) potato.ini] w]
puts $file {set ::potato::misc(autoConnect) 0
set ::potato::misc(checkForUpdates) 0
return 2.0}
close $file
set ::argv {}; set ::argc 0
lappend ::auto_path [file join $root potato.vfs lib]
source [file join $root potato.vfs main.tcl]
set ::checks 0
proc assert {value message} {
    if {![uplevel 1 [list expr $value]]} {error "FAIL: $message"}
    incr ::checks
}
proc waitFor {expression} {
    set limit [expr {[clock milliseconds]+5000}]
    while {![uplevel 1 [list expr $expression]]} {
        if {[clock milliseconds]>$limit} {error "Timeout: $expression"}
        after 10; update
    }
}
assert {$::potato::running == 1} "full client startup"
set ::wire {}
proc accept {channel address port} {
    set ::peer $channel
    fconfigure $channel -translation crlf -blocking 0 -buffering line
    fileevent $channel readable [list receive $channel]
    after 20 [list puts $channel {This world is Pueblo 1.10 Enhanced.}]
    after 30 [list puts $channel {<xch_mudtext>}]
}
proc receive {channel} {
    while {[gets $channel line]>=0} {lappend ::wire $line}
}
set server [socket -server accept -myaddr 127.0.0.1 0]
set port [lindex [fconfigure $server -sockname] end]
set w [::potato::addNewWorld Fixture 127.0.0.1 $port 1]
foreach key {enabled commands images} {set ::potato::world($w,pueblo,$key) 1}
set ::potato::world($w,spawnAll) {}
::potato::newConnection $w
set c $::potato::potato(up)
waitFor {[lsearch -exact $::wire {PUEBLOCLIENT 1.10}]>=0}
set t $::potato::conn($c,textWidget)
assert {$::potato::conn($c,connected)==1} "loopback connection"
puts $::peer {<pre>Names<BR>}
puts $::peer {&#9;Row 1<BR>}
puts $::peer {&#9;&#9;Row 2<BR></pre>}
puts $::peer {<a xch_cmd="true" href="look">Look around</a> <a href="https://www.example.org">Website</a>}
waitFor {[string first "Look around" [$t get 1.0 end]]>=0}
set text ""
for {set pos 1.0} {[$t compare $pos < end-1c]} {set pos [$t index "$pos + 1c"]} {
    if {"timestamp" ni [$t tag names $pos]} {append text [$t get $pos]}
}
assert {[string first "Names\n\tRow 1\n\t\tRow 2" $text]>=0} "displayed spacing/tabs"
set actionTag ""
foreach tag [$t tag names] {
    if {[lindex $tag 0] eq "potatoAction" && [lindex $tag 3] eq "command"} {set actionTag $tag}
}
assert {$actionTag ne ""} "explicit action attached"
set range [$t tag ranges $actionTag]
$t see [lindex $range 0]
update
lassign [$t bbox [lindex $range 0]] x y width height
event generate $t <Motion> -x [expr {$x+2}] -y [expr {$y+2}]
event generate $t <ButtonPress-1> -x [expr {$x+2}] -y [expr {$y+2}]
event generate $t <ButtonRelease-1> -x [expr {$x+2}] -y [expr {$y+2}]
waitFor {[lsearch -exact $::wire look]>=0}
assert {[lsearch -exact $::wire look]>=0} "native Tk mouse command delivery"
# Triggers see the caption, not protocol tags or image pixels.
set ::potato::world($w,events) {1}
foreach {key value} {enabled 1 inactive {} matchAll 0 case 1 matchtype regexp pattern {^Trigger caption$} fg {} bg {} input,window 0 send {} replace 0 continue 0 spawn 0 omit 1 noActivity 0 log 0} {
    set ::potato::world($w,events,1,$key) $value
}
puts $::peer {<b>Trigger caption</b>}
puts $::peer {Trigger done}
waitFor {[string first "Trigger done" [$t get 1.0 end]]>=0}
assert {[string first "Trigger caption" [$t get 1.0 end]]<0} "caption trigger gag"
set ::potato::world($w,events) {}
::potato::pueblo::reset $c
::potato::pueblo::activate {*}[lrange $actionTag 1 end]
after 30; update
assert {[llength [lsearch -all -exact $::wire look]]==1} "stale click after reset"
::potato::configureWorld $w
update
assert {[llength [info commands ::potato::pueblo::parse]]==1} "configuration remains usable"
::potato::disconnect $c 0
close $::peer
close $server
puts "PASS: $::checks full-client checks (Tcl [info patchlevel], Tk [package present Tk], [tk windowingsystem])"
destroy .
