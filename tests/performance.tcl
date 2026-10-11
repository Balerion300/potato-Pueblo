# Diagnostic workload against an independent loopback server; no live game.
package require Tk 8.6
set report [open $::env(POTATO_PERF_EVENTS) w]
fconfigure $report -buffering line
proc record {args} {puts $::report [join $args "\t"]}
proc fail {message} {record FAIL $message; exit 1}
proc perfBackgroundError {message options} {fail [dict get $options -errorinfo]}
interp bgerror {} perfBackgroundError
rename tk_messageBox nativeMessageBox
proc tk_messageBox {args} {error "Unexpected dialog: $args"}
file mkdir $::env(POTATO_HOME)
set f [open [file join $::env(POTATO_HOME) potato.ini] w]
puts $f {set ::potato::misc(autoConnect) 0
set ::potato::misc(checkForUpdates) 0
return 2.0}; close $f
set ::argv {}; set ::argc 0
source [file join $::env(POTATO_TEST_SOURCE_ROOT) potato.vfs main.tcl]
interp bgerror {} perfBackgroundError
set stressSeconds $::env(POTATO_STRESS_SECONDS)
after [expr {300000+1000*$stressSeconds}] {fail {benchmark timeout}}
proc waitFor {expression} {
    set deadline [expr {[clock milliseconds]+30000}]
    while {![uplevel 1 [list expr $expression]]} {
        if {[clock milliseconds]>$deadline} {error "Timeout: $expression"}
        after 5 {set ::tick 1}; vwait ::tick; unset ::tick
    }
}
set ::wire {}; set ::rtts {}; set ::pending [dict create]; set ::lags {}; set ::beatRunning 1
proc receive {} {
    while {[gets $::peer line]>=0} {
        set line [string trimright $line \r]
        if {[dict exists $::pending $line]} {
            lappend ::rtts [expr {([clock microseconds]-[dict get $::pending $line])/1000.0}]
            dict unset ::pending $line
        }
        lappend ::wire $line
        # The diagnostic must not create an apparent client leak itself.
        if {[llength $::wire]>64} {set ::wire [lrange $::wire end-63 end]}
    }
}
set ::peer [socket 127.0.0.1 $::env(POTATO_FIXTURE_CONTROL_PORT)]
fconfigure $::peer -translation crlf -blocking 0 -buffering line
fileevent $::peer readable receive
set w [::potato::addNewWorld Performance 127.0.0.1 $::env(POTATO_FIXTURE_GAME_PORT) 1]
foreach key {enabled commands images} {set ::potato::world($w,pueblo,$key) 1}
set ::potato::world($w,spawnAll) {}
set ::potato::world($w,encoding,start) utf-8
::potato::newConnection $w
set c $::potato::potato(up); set t $::potato::conn($c,textWidget)
waitFor {[dict get $::potato::pueblo::state($c) active]}
# Measure actual application hot paths, including native widget work.
set ::timings [dict create]; set ::totalTimings [dict create]; set ::totalCalls [dict create]
set ::readCalls 0; set ::readBytes 0; set ::receivedLines 0
proc profileWidget {widget} {
    rename $widget ${widget}_perfNative
    proc $widget {args} [string map [list @WIDGET@ $widget] {
        set start [clock microseconds]
        set code [catch {uplevel 1 [list @WIDGET@_perfNative {*}$args]} value options]
        set elapsed [expr {[clock microseconds]-$start}]
        dict incr ::timings widget:[lindex $args 0] $elapsed
        dict incr ::totalTimings widget:[lindex $args 0] $elapsed
        dict incr ::totalCalls widget:[lindex $args 0]
        return -options $options $value
    }]
}
profileWidget $t
foreach name {get_mushageProcess parseANSI flattenParsedANSI eventsMatch atEnd skinStatus setPrompt pueblo::parse pueblo::render pueblo::images::collect pueblo::images::resize pueblo::images::readable pueblo::images::install} {
    set original "[namespace qualifiers ::potato::$name]::perfOriginal_[namespace tail ::potato::$name]"
    rename ::potato::$name $original
    proc ::potato::$name {args} [string map [list @NAME@ $name @ORIGINAL@ $original] {
        if {"@NAME@" eq "get_mushageProcess"} {incr ::receivedLines}
        set start [clock microseconds]
        set code [catch {uplevel 1 [list @ORIGINAL@ {*}$args]} value options]
        set elapsed [expr {[clock microseconds]-$start}]
        dict incr ::timings @NAME@ $elapsed
        dict incr ::totalTimings @NAME@ $elapsed
        dict incr ::totalCalls @NAME@
        return -options $options $value
    }]
}
rename ::potato::ioRead ::potato::perfOriginal_ioRead
proc ::potato::ioRead {args} {
    incr ::readCalls
    set result [::potato::perfOriginal_ioRead {*}$args]
    incr ::readBytes [string length $result]
    return $result
}
set ::probeNumber 0
proc beat {expected} {
    if {!$::beatRunning} {return}
    set now [clock milliseconds]; lappend ::lags [expr {max(0,$now-$expected)}]
    set command "PERF-PROBE-[incr ::probeNumber]"
    dict set ::pending $command [clock microseconds]
    ::potato::send_to_noparse $::c $command "" 0
    set ::beatTimer [after 50 [list beat [expr {$now+50}]]]
}
beat [clock milliseconds]
record START [info patchlevel] [tk windowingsystem]
proc phase {name payload} {
    set marker "PERF-END-$name"
    set ::timings [dict create]; set ::readCalls 0; set ::readBytes 0; set ::lags {}; set ::rtts {}; set ::receivedLines 0
    record BEGIN $name
    set start [clock microseconds]
    puts $::peer "$payload\n$marker"
    waitFor {[string first $marker [$::t get end-4l end]]>=0}
    if {$::receivedLines != [llength [split $payload \n]]+1} {error "Lost or duplicated lines in $name: $::receivedLines"}
    set ms [expr {([clock microseconds]-$start)/1000.0}]
    record PHASE $name $ms $::readBytes $::readCalls [llength $::lags] [join $::lags ,] [join $::rtts ,] [llength [$::t tag names]] [llength [$::t image names]]
    dict for {key value} $::timings {record HOT $name $key $value}
}
set plain {}; set ansi {}; set links {}
for {set i 0} {$i<1000} {incr i} {
    lappend plain "Plain $i [string repeat {The garden is quiet. } 6]"
    lappend ansi "\x1b\[31mRed $i\x1b\[0m [string repeat {The garden is quiet. } 6]"
    lappend links "<a xch_cmd=\"true\" href=\"look-$i\">Look $i</a> [string repeat {The garden is quiet. } 6]"
}
phase plain [join $plain \n]
phase ansi [join $ansi \n]
phase links [join $links \n]
phase retained_links [join $plain \n]
set ::fixtureURL $::env(POTATO_FIXTURE_HTTP_URL)
rename ::potato::pueblo::url ::potato::pueblo::productionURL
proc ::potato::pueblo::url {value} {return [expr {[string match "$::fixtureURL*" $value] || [productionURL $value]}]}
set ::potato::conn($c,spawnAll) {Images}
set spawn [lindex [::potato::createSpawnWindow $c Images] 1]
profileWidget $spawn
for {set cycle 0} {$cycle<3} {incr cycle} {
    $t delete 1.0 end; $spawn delete 1.0 end
    ::potato::pueblo::render $c $t; ::potato::pueblo::render $c $spawn
    ::potato::pueblo::images::collect
    set lines {}
    for {set i 0} {$i<16} {incr i} {lappend lines "<img src=\"$::fixtureURL\" alt=\"Portrait $cycle $i\">"}
    phase images_$cycle [join $lines \n]
    waitFor {[llength [$t image names]]==16 && [llength [$spawn image names]]==16}
    record IMAGES $cycle [dict size $::potato::pueblo::images::photos] $::potato::pueblo::images::totalPixels
    $t delete 1.0 end; $spawn delete 1.0 end
    ::potato::pueblo::images::collect
    if {[dict size $::potato::pueblo::images::photos] || $::potato::pueblo::images::totalPixels} {error {Images were not reclaimed}}
    record CLEAN $cycle [dict size $::potato::pueblo::images::seen] [dict size $::potato::pueblo::images::jobs] [llength [$t tag names]]
}
set ::potato::conn($c,spawnAll) {}
for {set cycle 0} {$cycle<30} {incr cycle} {
    $t delete 1.0 end
    phase soak_$cycle [join [lrange $links 0 199] \n]
    $t delete 1.0 end; ::potato::pueblo::render $c $t
    record SOAK $cycle [llength [$t tag names]] [llength [image names]]
}
proc resources {cycle} {
    record RESOURCES $cycle [clock milliseconds] [llength [image names]] \
        [dict size $::potato::pueblo::images::photos] $::potato::pueblo::images::totalPixels \
        [dict size $::potato::pueblo::images::jobs] [llength $::potato::pueblo::images::queue] \
        [dict size $::potato::pueblo::images::seen] [llength [$::t tag names]] \
        [llength [chan names]] [llength [after info]] [dict size $::potato::pueblo::views]
}
set deadline [expr {[clock milliseconds]+1000*$stressSeconds}]
set cycle 0
resources start
set tagLimit [expr {max([llength [$t tag names]],[llength [$spawn tag names]])}]
while {[clock milliseconds]<$deadline} {
    $t delete 1.0 end
    phase stress_links_$cycle [join [lrange $links 0 199] \n]
    phase stress_ansi_$cycle [join [lrange $ansi 0 199] \n]
    if {$cycle%5==0} {
        set ::potato::conn($c,spawnAll) {Images}
        set lines {}
        for {set i 0} {$i<12} {incr i} {lappend lines "<img src=\"$::fixtureURL\" alt=\"Stress $cycle $i\">"}
        phase stress_images_$cycle [join $lines \n]
        waitFor {[llength [$t image names]]==12 && [llength [$spawn image names]]==12}
        # Repeated layout changes exercise image reallocations.
        foreach width {320 800 400 900} {
            wm geometry . ${width}x600
            update idletasks
            ::potato::pueblo::images::collect
        }
        $spawn delete 1.0 end
        $t delete 1.0 end
        ::potato::pueblo::images::collect
        set ::potato::conn($c,spawnAll) {}
    }
    if {$cycle%15==0} {
        phase stress_bad_image_$cycle "<img src=\"$::fixtureURL?bad\" alt=\"Invalid image\">"
        waitFor {[dict size $::potato::pueblo::images::jobs]==0 && [llength $::potato::pueblo::images::queue]==0}
        if {[llength [$t image names]]} {error {Invalid image installed pixels}}
        phase stress_cancel_image_$cycle "<img src=\"$::fixtureURL?slow\" alt=\"Cancelled image\">"
        waitFor {[dict size $::potato::pueblo::images::jobs]>0}
        # Clearing the view before the delayed download finishes must reclaim
        # its channel and never install pixels back into the new transcript.
    }
    if {$cycle%20==0} {
        $t delete 1.0 end
        ::potato::pueblo::render $c $t
        set ::potato::conn($c,spawnAll) {Images}
        phase stress_large_images_$cycle [join [lrepeat 4 "<img src=\"$::fixtureURL?large\" alt=\"Large allocation\">"] \n]
        waitFor {[llength [$t image names]]==4 && [llength [$spawn image names]]==4}
        record ALLOCATED $cycle [dict size $::potato::pueblo::images::photos] $::potato::pueblo::images::totalPixels
        $spawn delete 1.0 end
        set ::potato::conn($c,spawnAll) {}
    }
    $t delete 1.0 end
    ::potato::pueblo::render $c $t
    ::potato::pueblo::render $c $spawn
    ::potato::pueblo::images::collect
    waitFor {[dict size $::potato::pueblo::images::jobs]==0}
    if {[dict size $::potato::pueblo::images::photos] || $::potato::pueblo::images::totalPixels} {error {Stress image allocations leaked}}
    if {[llength [$t tag names]]>$tagLimit || [llength [$spawn tag names]]>$tagLimit} {error {Stress transcript tags grew after cleanup}}
    if {$cycle%10==0} {
        set ::beatRunning 0
        after cancel $::beatTimer
        waitFor {[dict size $::pending]==0}
        ::potato::disconnect $c 0
        ::potato::reconnect $c
        waitFor {[dict get $::potato::pueblo::state($c) active]}
        set ::beatRunning 1
        beat [clock milliseconds]
        record STRESS reconnect $cycle
    }
    resources $cycle
    incr cycle
}
record STRESS cycles $cycle
record BEGIN recovered_idle
set idleDone 0
after 3000 {set idleDone 1}
vwait idleDone
resources recovered
dict for {name value} $::totalTimings {record TOTALHOT $name $value [dict get $::totalCalls $name]}
set ::beatRunning 0
after cancel $::beatTimer
waitFor {[dict size $::pending]==0}
record BEGIN fragmented_input
puts $::peer PERF-FRAGMENT
waitFor {[string first PERF-FRAGMENT-DONE [$t get end-4l end]]>=0}
if {[string first "Snowman \u2603 and caf\u00e9 fragmented" [$t get end-5l end]]<0} {error {Fragmented Unicode/ANSI/Pueblo input changed}}
record FRAGMENT PASS
record BEGIN outgoing
set ::rtts {}
set sendStart [clock microseconds]; set sendBytes 0
for {set i 0} {$i<1000} {incr i} {
    set command "PERF-OUT-$i [string repeat abcdef 10]"
    dict set ::pending $command [clock microseconds]
    incr sendBytes [expr {[string length $command]+2}]
    ::potato::send_to $c $command "" 0
}
waitFor {[dict size $::pending]==0}
record OUTGOING [expr {([clock microseconds]-$sendStart)/1000.0}] $sendBytes [llength $::rtts] [join $::rtts ,]
set ::potato::world($w,outputLimit,on) 1
set ::potato::world($w,outputLimit,to) 500
phase limited_scrollback [join $plain \n]
if {[lindex [split [$t index end] .] 0]>501} {error {Configured output limit did not bound the transcript}}
set ::potato::world($w,outputLimit,on) 0
record BEGIN reconnect
for {set cycle 0} {$cycle<10} {incr cycle} {
    ::potato::disconnect $c 0
    ::potato::reconnect $c
    waitFor {[dict get $::potato::pueblo::state($c) active]}
    if {$::potato::conn($c,connected)!=1} {error {Reconnect failed}}
    set command "PERF-RECONNECT-$cycle"
    ::potato::send_to_noparse $c $command "" 0
    waitFor {[lsearch -exact $::wire $command]>=0}
    record RECONNECT $cycle
}
::potato::disconnect $c 0
close $::peer
record PASS
close $report
destroy .
