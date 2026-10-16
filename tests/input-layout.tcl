# Exercise the actual packaged input panes at default and restored geometry.
package require Tk 8.6
set ::argv {}; set ::argc 0
file mkdir $::env(POTATO_HOME)
set f [open [file join $::env(POTATO_HOME) potato.ini] w]
puts $f {set ::potato::misc(autoConnect) 0
set ::potato::misc(checkForUpdates) 0
return 2.0}; close $f
if {[info exists ::env(POTATO_COLLAPSED_INPUT)]} {
    file mkdir [file join $::env(POTATO_HOME) skins]
    set f [open [file join $::env(POTATO_HOME) skins skin.prefs] w]
    puts $f {array set ::skin::potato::opts {inputheights 1 input1height 1 input2height 1}}
    close $f
}
source [file join $::env(POTATO_TEST_SOURCE_ROOT) potato.vfs main.tcl]
proc pump {} {after 150 {set ::tick 1}; vwait ::tick; unset ::tick}
set ::failures 0
proc record {stage c} {
    pump
    set i $::potato::conn($c,input1)
    set outer $::skin::potato::widgets(pane)
    set bottom $::skin::potato::widgets(pane,btm)
    set fontHeight [font metrics [$i cget -font] -linespace]
    set usable [expr {[winfo ismapped $i] && [winfo width $i]>=100 &&
        [winfo height $i]>=$fontHeight &&
        [winfo rooty $i]+$fontHeight <= [winfo rooty .]+[winfo height .]}]
    if {!$usable} {incr ::failures}
    set f [open $::env(POTATO_LAYOUT_RESULT) a]
    puts $f [list $stage usable $usable input [winfo geometry $i] mapped [winfo ismapped $i] \
        fontHeight $fontHeight window [wm geometry .] pane [winfo geometry $outer] \
        bottom [winfo geometry $bottom] options [$outer paneconfigure $bottom]]
    close $f
    if {[tk windowingsystem] eq "aqua" && $stage eq "connected-default"} {
        catch {exec screencapture -x [file join [file dirname $::env(POTATO_LAYOUT_RESULT)] input-$::env(POTATO_LAYOUT_LABEL).png]}
    }
}
set ::peer [socket 127.0.0.1 $::env(POTATO_FIXTURE_CONTROL_PORT)]
fconfigure $::peer -translation crlf -blocking 0 -buffering line
set ::wire {}
proc receive {} {while {[gets $::peer line]>=0} {lappend ::wire [string trimright $line \r]}}
fileevent $::peer readable receive
set w [::potato::addNewWorld {Input Fixture} 127.0.0.1 $::env(POTATO_FIXTURE_GAME_PORT) 1]
::potato::newConnection $w
set c [::potato::up]
record connected-default $c
wm state . normal
wm geometry . 800x500
record resized $c
::potato::showConn 0
pump
::potato::showConn $c
record tab-restored $c
set ::potato::conn($c,twoInputWindows) 0
::potato::toggleInputWindows $c 0
record single-input $c
set i $::potato::conn($c,input1)
$i delete 1.0 end
focus -force $i
$i insert 1.0 input-fixture-command
event generate $i <KeyPress-Return>
set limit [expr {[clock milliseconds]+3000}]
while {[lsearch -exact $::wire input-fixture-command]<0 && [clock milliseconds]<$limit} {pump}
set sent [expr {[lsearch -exact $::wire input-fixture-command]>=0}]
set f [open $::env(POTATO_LAYOUT_RESULT) a]
puts $f [list INPUT-SEND $sent failures $::failures]; close $f
if {[info exists ::env(POTATO_ASSERT_INPUT)] && (!$sent || $::failures)} {error "Input acceptance failed: sent=$sent geometryFailures=$::failures"}
::potato::disconnect $c 0
close $::peer
if {[info exists ::env(POTATO_ASSERT_INPUT)]} {::skin::potato::savePrefs}
destroy .
