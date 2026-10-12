# Sourced by the connected full-client fixture, before disconnecting.
after cancel $testDeadline
set testDeadline [after 20000 testTimeout]
set ::potato::world($w,outputLimit,on) 0
set ::potato::world($w,mxp,enabled) 1
if {[info exists ::env(POTATO_FIXTURE_GAME_PORT)]} {
    puts $::peer MXP-START
} else {
    fconfigure $::peer -encoding binary
    puts $::peer "\xff\xfb\x5b\xff\xfa\x5b\xff\xf0\x1b\[1z<VERSION><SUPPORT send.prompt image.* frame>"
    fconfigure $::peer -encoding utf-8
}
waitFor {[::potato::mxp::active $c] && [string first {<SUPPORTS} [join $::wire]]>=0}
assert {[string first {+send.prompt} [join $::wire]]>=0 && [string first {-frame} [join $::wire]]>=0} "socket MXP capability reply"
if {[info exists ::env(POTATO_FIXTURE_GAME_PORT)]} {
    waitFor {[lsearch -exact $::wire MXP-DO-91]>=0}
    assert {[lsearch -exact $::wire MXP-DO-91]>=0} "actual socket IAC DO MXP"
}
puts $::peer "\x1b\[1z\x1b\[32m<B><SEND href='mxp-look'>MXP look</SEND></B>\x1b\[0m"
waitFor {[string first {MXP look} [$t get 1.0 end]]>=0}
proc mxpTag {widget caption} {
    set pos [$widget search -exact -- $caption 1.0 end]
    foreach tag [$widget tag names $pos] {if {[lindex $tag 0] eq "potatoAction" && [lindex $tag 3] eq "mxp"} {return $tag}}
    return ""
}
proc mxpClick {widget caption} {
    set pos [$widget search -exact -- $caption 1.0 end]
    $widget see $pos
    testPump
    lassign [$widget bbox $pos] x y width height
    event generate $widget <Motion> -x [expr {$x+2}] -y [expr {$y+2}]
    event generate $widget <ButtonPress-1> -x [expr {$x+2}] -y [expr {$y+2}]
    event generate $widget <ButtonRelease-1> -x [expr {$x+2}] -y [expr {$y+2}]
}
set mxpAction [mxpTag $t {MXP look}]
assert {$mxpAction ne ""} "MXP SEND survives real ANSI parser"
assert {[lsearch -exact [$t tag names [$t search {MXP look} 1.0]] puebloBold]>=0} "MXP formatting in native transcript"
mxpClick $t {MXP look}
waitFor {[lsearch -exact $::wire mxp-look]>=0}
assert {[lsearch -exact $::wire mxp-look]>=0} "MXP native mouse command delivery"
puts $::peer "<SEND quit>Open caption</SEND>\n\x1b\[2z<SEND quit>Locked literal</SEND>\n\x1b\[1z<SEND 'tell friend ' PROMPT>MXP prefill</SEND>"
waitFor {[string first {MXP prefill} [$t get 1.0 end]]>=0}
assert {[mxpTag $t {Open caption}] eq ""} "Open mode blocks command links in client"
assert {[string first {<SEND quit>Locked literal</SEND>} [$t get 1.0 end]]>=0} "Locked mode displays literal markup"
mxpClick $t {MXP prefill}
assert {[$::potato::conn($c,input1) get 1.0 end-1c] eq {tell friend }} "native PROMPT click prefills input"
assert {[lsearch -exact $::wire {tell friend }]<0} "PROMPT click sends nothing"
rename ::potato::pueblo::url ::potato::pueblo::productionURL
proc ::potato::pueblo::url {value} {expr {$value eq $::fixtureURL || [productionURL $value]}}
if {[info exists httpPort]} {set httpServer [socket -server httpAccept -myaddr 127.0.0.1 $httpPort]}
set ::potato::conn($c,spawnAll) {Images}
puts $::peer "\x1b\[1z<SEND mxp-portrait><IMG src='$::fixtureURL' alt='MXP portrait'></SEND>"
waitFor {[llength [$t image names]]==1 && [llength [$spawn image names]]==2}
assert {[llength [$t image names]]==1 && [llength [$spawn image names]]==2} "MXP asynchronous images in main and spawn"
set imageName [lindex [$t image names] 0]
set imageAction ""
foreach tag [$t tag names $imageName] {if {[lindex $tag 0] eq "potatoAction" && [lindex $tag 3] eq "mxp" && [lindex $tag 4 0] eq "send"} {set imageAction $tag}}
assert {$imageAction ne ""} "MXP image inherits SEND"
$t see $imageName
testPump
lassign [$t bbox $imageName] x y width height
event generate $t <Motion> -x [expr {$x+5}] -y [expr {$y+5}]
event generate $t <ButtonPress-1> -x [expr {$x+5}] -y [expr {$y+5}]
event generate $t <ButtonRelease-1> -x [expr {$x+5}] -y [expr {$y+5}]
waitFor {[lsearch -exact $::wire mxp-portrait]>=0}
assert {[string first {MXP portrait} [$t get 1.0 end]]>=0} "MXP image copy fallback retained"
rename ::potato::pueblo::url {}; rename ::potato::pueblo::productionURL ::potato::pueblo::url
set ::potato::conn($c,spawnAll) {}
::potato::setPrompt $c "\x1b\[1z<SEND mxp-prompt>Prompt link</SEND>"
assert {[string first {Prompt link} $::potato::conn($c,prompt)]>=0 && [string first {<SEND} $::potato::conn($c,prompt)]<0} "MXP prompt caption parsing"
assert {[mxpTag $t {Prompt link}] ne ""} "MXP prompt carries action binding"
::potato::setPrompt $c ""
::potato::saveWorlds
set f [open [lindex [glob -directory $::potato::path(world) Fixture-*.wld] 0] r]
set saved [read $f]; close $f
assert {[string first {mxp,enabled} $saved]>=0} "saved per-world MXP setting"
::potato::mxp::reset $c
::potato::pueblo::activate {*}[lrange $mxpAction 1 end]
testPump
assert {[llength [lsearch -all -exact $::wire mxp-look]]==1} "MXP stale native link after reset"
puts "CHECK: MXP socket, ANSI, modes, native clicks, prompts and images verified"
