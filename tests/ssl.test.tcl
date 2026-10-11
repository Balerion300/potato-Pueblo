# Explicitly invoked live SSL smoke test. No login, account or game mutation.
package require Tk 8.6
proc sslBackgroundError {message options} {puts stderr [dict get $options -errorinfo]; exit 1}
interp bgerror {} sslBackgroundError
rename tk_messageBox nativeMessageBox
proc tk_messageBox {args} {error "Unexpected modal dialog: $args"}
set root [file normalize [file join [file dirname [info script]] ..]]
if {[info exists ::env(POTATO_TEST_SOURCE_ROOT)]} {set root $::env(POTATO_TEST_SOURCE_ROOT)}
if {![info exists ::env(POTATO_HOME)]} {error "Use a fresh POTATO_HOME for SSL checks"}
file mkdir $::env(POTATO_HOME)
if {[llength [glob -nocomplain -directory $::env(POTATO_HOME) *]]} {error "SSL test profile must be empty"}
set f [open [file join $::env(POTATO_HOME) potato.ini] w]
puts $f {set ::potato::misc(autoConnect) 0
set ::potato::misc(checkForUpdates) 0
return 2.0}
close $f
set ::argv {}; set ::argc 0
source [file join $root potato.vfs main.tcl]
interp bgerror {} sslBackgroundError
after 45000 {puts stderr "FAIL: live SSL test timed out"; exit 1}
proc sslWaitFor {expression} {
    set deadline [expr {[clock milliseconds]+12000}]
    while {![uplevel 1 [list expr $expression]]} {
        if {[clock milliseconds]>$deadline} {error "SSL wait timed out: $expression"}
        after 20 {set ::sslTick 1}; vwait ::sslTick; unset ::sslTick
    }
}
if {!$::potato::potato(hasTLS)} {error "Game SSL library unavailable"}
if {$::tcl_platform(platform) ne "windows" && ![package vsatisfies [package present tls] 2.0.1-]} {
    error "Unix preview must load the bundled modern TclTLS"
}
puts "SSL LIBRARY: TclTLS [package present tls], [::tls::version]"
set w [::potato::addNewWorld {BoD SSL smoke test} bod.westeros.org 3001 1]
set ::potato::world($w,ssl) 1
set ::potato::world($w,host2) ""
set ::potato::world($w,pueblo,enabled) 1
set ::potato::world($w,autoreconnect) 0
::potato::newConnection $w
set c $::potato::potato(up)
for {set attempt 1} {$attempt<=2} {incr attempt} {
    if {$attempt>1} {::potato::reconnect $c}
    sslWaitFor {$::potato::conn($c,connected)==1}
    if {![::potato::hasProtocol $c ssl]} {error "Connection did not use SSL"}
    set status [::tls::status $::potato::conn($c,id)]
    if {[dict get $status sbits]<128 || [dict get $status cipher] eq ""} {error "No encrypted cipher negotiated"}
    if {[dict exists $status protocol] && [dict get $status protocol] ni {TLSv1.2 TLSv1.3}} {error "Obsolete TLS version negotiated"}
    # This response requires receiving the greeting, sending PUEBLOCLIENT over
    # the encrypted socket, and reading the server's markup-mode response.
    sslWaitFor {[dict get $::potato::pueblo::state($c) active]}
    puts "PASS: SSL attempt $attempt, bod.westeros.org:3001, cipher [dict get $status cipher], Pueblo bidirectional exchange"
    if {[dict exists $status protocol]} {puts "NEGOTIATED: [dict get $status protocol]"}
    ::potato::disconnect $c 0
}
puts "PASS: live game SSL connect, encrypted receive/send, Pueblo negotiation and reconnect"
destroy .
