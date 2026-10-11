# Repeated native launch acceptance, including every real menu post callback.
package require Tk 8.6
proc startupFailure {message options} {
    set f [open $::env(POTATO_TEST_RESULT) w]
    puts $f "FAIL: [dict get $options -errorinfo]"; close $f
    exit 1
}
interp bgerror {} startupFailure
rename tk_messageBox nativeMessageBox
proc tk_messageBox {args} {error "Unexpected dialog: $args"}
file mkdir $::env(POTATO_HOME)
set f [open [file join $::env(POTATO_HOME) potato.ini] w]
puts $f {set ::potato::misc(autoConnect) 0
set ::potato::misc(checkForUpdates) 0
return 2.0}; close $f
set ::argv {}; set ::argc 0
source [file join $::env(POTATO_TEST_SOURCE_ROOT) potato.vfs main.tcl]
interp bgerror {} startupFailure
if {!$::potato::potato(menusReady) || [::potato::up]!=0} {error {Incomplete native startup}}
foreach kind {file edit view log log,stop options tools help} {
    set m $::potato::menu($kind,path)
    {*}[ $m cget -postcommand ]
}
after 200 {set ::startupTick 1}; vwait ::startupTick
set f [open $::env(POTATO_TEST_RESULT) w]
puts $f PASS; close $f
destroy .
