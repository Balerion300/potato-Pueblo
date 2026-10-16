# A wish script error normally opens a modal dialog. CI needs a bounded failure.
if {[catch {source [lindex $argv 0]} message options]} {
    puts stderr [dict get $options -errorinfo]
    if {[info exists ::env(POTATO_TEST_RESULT)]} {
        set receipt [open $::env(POTATO_TEST_RESULT) w]
        puts $receipt "FAIL: [dict get $options -errorinfo]"
        close $receipt
    }
    catch {destroy .}
    exit 1
}
exit 0
