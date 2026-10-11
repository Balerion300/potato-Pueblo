# Full Potato startup and transcript integration, with a fresh explicit profile.
package require Tk 8.6
proc testBackgroundError {message options} {
    puts stderr "BACKGROUND ERROR: [dict get $options -errorinfo]"
    exit 1
}
interp bgerror {} testBackgroundError
rename tk_messageBox nativeMessageBox
proc tk_messageBox {args} {error "Unexpected modal dialog: $args"}
set root [file normalize [file join [file dirname [info script]] ..]]
if {[info exists ::env(POTATO_TEST_SOURCE_ROOT)]} {set root $::env(POTATO_TEST_SOURCE_ROOT)}
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
interp bgerror {} testBackgroundError
puts "CHECK: complete client started"
puts "CAPABILITY: game TLS available=$::potato::potato(hasTLS)"
if {$::potato::potato(hasTLS)} {puts "CAPABILITY: TclTLS [package present tls], [::tls::version]"}
set ::checks 0
proc testTimeout {} {
    puts stderr "FAIL: full-client fixture exceeded 15 seconds"
    if {[info exists ::env(POTATO_TEST_RESULT)]} {
        set receipt [open $::env(POTATO_TEST_RESULT) w]
        puts $receipt "FAIL: full-client fixture exceeded 15 seconds"
        close $receipt
    }
    for {set depth 1} {$depth < 30} {incr depth} {
        if {[catch {info frame -$depth} frame]} {break}
        puts stderr "FRAME: $frame"
    }
    exit 1
}
set testDeadline [after 15000 testTimeout]
proc assert {value message} {
    if {![uplevel 1 [list expr $value]]} {error "FAIL: $message"}
    incr ::checks
}
# A bounded turn of the real event loop. Aqua can keep update busy while a
# connected socket is active; a timer/vwait gives the assertions a chance to run.
proc testPump {} {
    set tick [after 10 {set ::testTick 1}]
    vwait ::testTick
    unset ::testTick
}
proc waitFor {expression} {
    set limit [expr {[clock milliseconds]+5000}]
    while {![uplevel 1 [list expr $expression]]} {
        if {[clock milliseconds]>$limit} {error "Timeout: $expression"}
        testPump
    }
}
assert {$::potato::running == 1} "full client startup"
set priorConnection $::potato::potato(up)
set ::potato::potato(up) ""
assert {![::potato::taskState reconnect]} "Aqua startup reconnect menu without current tab"
assert {![::potato::taskState disconnect]} "Aqua startup disconnect menu without current tab"
assert {![::potato::taskState config]} "Aqua startup world configuration menu without current tab"
set ::potato::potato(up) $priorConnection
set ::wire {}
proc accept {channel address port} {
    set ::peer $channel
    fconfigure $channel -translation lf -blocking 0 -buffering line
    fileevent $channel readable [list receive $channel]
    after 20 [list puts $channel {This world is Pueblo 1.10 Enhanced.}]
    after 30 [list puts $channel {</xch_mudtext><img xch_mode=purehtml><xch_page clear=text>}]
}
proc receive {channel} {
    while {[gets $channel line]>=0} {lappend ::wire [string trimright $line \r]}
}
if {[info exists ::env(POTATO_FIXTURE_GAME_PORT)]} {
    set port $::env(POTATO_FIXTURE_GAME_PORT)
    set ::peer [socket 127.0.0.1 $::env(POTATO_FIXTURE_CONTROL_PORT)]
    fconfigure $::peer -translation crlf -blocking 0 -buffering line
    fileevent $::peer readable [list receive $::peer]
} else {
    set server [socket -server accept -myaddr 127.0.0.1 0]
    set port [lindex [fconfigure $server -sockname] end]
}
set connectionDeadline [after 10000 {puts stderr "FAIL: local connection did not complete in 10 seconds"; exit 1}]
set w [::potato::addNewWorld Fixture 127.0.0.1 $port 1]
foreach key {enabled commands images} {set ::potato::world($w,pueblo,$key) 1}
set ::potato::world($w,spawnAll) {}
::potato::newConnection $w
after cancel $connectionDeadline
puts "CHECK: local connection opened"; flush stdout
set c $::potato::potato(up)
waitFor {[lsearch -exact $::wire {PUEBLOCLIENT 1.10}]>=0}
waitFor {[dict get $::potato::pueblo::state($c) active]}
set t $::potato::conn($c,textWidget)
puts "CHECK: Pueblo negotiated"; flush stdout
assert {$::potato::conn($c,connected)==1} "loopback connection"
set ::heightEventRan 0
set heightEvent [after 0 {set ::heightEventRan 1}]
set measuredHeight [::potato::countWindowHeight $t]
assert {$measuredHeight > 0 && !$::heightEventRan} "height measurement must not re-enter events"
after cancel $heightEvent
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
testPump
lassign [$t bbox [lindex $range 0]] x y width height
event generate $t <Motion> -x [expr {$x+2}] -y [expr {$y+2}]
event generate $t <ButtonPress-1> -x [expr {$x+2}] -y [expr {$y+2}]
event generate $t <ButtonRelease-1> -x [expr {$x+2}] -y [expr {$y+2}]
waitFor {[lsearch -exact $::wire look]>=0}
assert {[lsearch -exact $::wire look]>=0} "native Tk mouse command delivery"
puts "CHECK: text command clicked"; flush stdout
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
puts "CHECK: caption trigger processed"; flush stdout
# Exercise real image arrival in both main and spawn transcripts using only a
# local HTTP fixture. The production URL validator is restored immediately.
set photo [image create photo -width 300 -height 150]
$photo put #285080 -to 0 0 300 150
$photo put #d4b060 -to 20 20 280 130
set ::fixturePNG [$photo data -format png]
image delete $photo
proc httpAccept {channel args} {
    fconfigure $channel -translation binary -encoding binary -blocking 0
    fileevent $channel readable [list httpReply $channel]
}
proc httpReply {channel} {
    read $channel
    fileevent $channel readable {}
    puts -nonewline $channel "HTTP/1.1 200 OK\r\nContent-Type: image/png\r\nContent-Length: [string length $::fixturePNG]\r\nConnection: close\r\n\r\n$::fixturePNG"
    close $channel
}
if {[info exists ::env(POTATO_FIXTURE_HTTP_URL)]} {
    set ::fixtureURL $::env(POTATO_FIXTURE_HTTP_URL)
} else {
    set httpServer [socket -server httpAccept -myaddr 127.0.0.1 0]
    set httpPort [lindex [fconfigure $httpServer -sockname] end]
    set ::fixtureURL "http://127.0.0.1:$httpPort/pic.png"
}
rename ::potato::pueblo::url ::potato::pueblo::productionURL
proc ::potato::pueblo::url {value} {return [expr {$value eq $::fixtureURL || [productionURL $value]}]}
set ::potato::conn($c,spawnAll) {Images}
set spawn [lindex [::potato::createSpawnWindow $c Images] 1]
puts $::peer "<a xch_cmd=\"true\" href=\"portrait\"><img src=\"$::fixtureURL\" alt=\"Portrait\"></a>"
waitFor {[llength [$t image names]]==1 && [llength [$spawn image names]]==1}
assert {[llength [$t image names]]==1} "main transcript asynchronous image"
assert {[llength [$spawn image names]]==1} "spawn transcript asynchronous image"
puts "CHECK: main and spawn images loaded"; flush stdout
set imageName [lindex [$t image names] 0]
set imageAction ""
foreach tag [$t tag names $imageName] {
    if {[lindex $tag 0] eq "potatoAction" && [lindex $tag 4] eq "portrait"} {set imageAction $tag}
}
assert {$imageAction ne ""} "image inherits command link"
$t see $imageName
testPump
lassign [$t bbox $imageName] x y width height
event generate $t <Motion> -x [expr {$x+5}] -y [expr {$y+5}]
event generate $t <ButtonPress-1> -x [expr {$x+5}] -y [expr {$y+5}]
event generate $t <ButtonRelease-1> -x [expr {$x+5}] -y [expr {$y+5}]
waitFor {[lsearch -exact $::wire portrait]>=0}
assert {[lsearch -exact $::wire portrait]>=0} "native image command click"
assert {[string first Portrait [$t get 1.0 end]]>=0} "full-client copy fallback"
if {[info exists ::env(POTATO_TEST_SCREENSHOT)]} {
    # The Python adapter supplies this command only for diagnostic captures.
    testPump
    captureScreenshot $::env(POTATO_TEST_SCREENSHOT)
}
rename ::potato::pueblo::url {}
rename ::potato::pueblo::productionURL ::potato::pueblo::url
if {[info exists httpServer]} {close $httpServer}
set ::potato::conn($c,spawnAll) {}
::potato::pueblo::reset $c
::potato::pueblo::activate {*}[lrange $actionTag 1 end]
testPump
assert {[llength [lsearch -all -exact $::wire look]]==1} "stale click after reset"
puts "CHECK: image command clicked"; flush stdout
::potato::configureWorld $w
testPump
assert {[llength [info commands ::potato::pueblo::parse]]==1} "configuration remains usable"
set ::potato::world($w,temp) 0
::potato::saveWorlds
set f [open [lindex [glob -directory $::potato::path(world) Fixture-*.wld] 0] r]
set saved [read $f]; close $f
assert {[string first {pueblo,enabled} $saved]>=0} "saved per-world Pueblo setting"
set ::potato::world($w,outputLimit,on) 1
set ::potato::world($w,outputLimit,to) 5
for {set i 0} {$i<10} {incr i} {puts $::peer "Bounded output $i"}
puts $::peer {Output limit complete}
waitFor {[string first {Output limit complete} [$t get 1.0 end]]>=0}
assert {[lindex [split [$t index end] .] 0]<=6} "configured main transcript limit"
assert {[string first {Bounded output 0} [$t get 1.0 end]]<0} "old output removed while latest output remains"
::potato::pueblo::images::collect
assert {[dict size $::potato::pueblo::images::photos]==1 && [llength [$spawn image names]]==1} "trimmed main photo reclaimed while spawn photo remains"
::potato::disconnect $c 0
close $::peer
if {[info exists server]} {close $server}
if {[info exists ::env(POTATO_TEST_RESULT)]} {
    set receipt [open $::env(POTATO_TEST_RESULT) w]
    puts $receipt "PASS: $::checks; Tcl [info patchlevel]; Tk [package present Tk]"
    close $receipt
}
puts "PASS: $::checks full-client checks (Tcl [info patchlevel], Tk [package present Tk], [tk windowingsystem])"
after cancel $testDeadline
destroy .
