# A wish script error normally opens a modal dialog. CI needs a bounded failure.
if {[catch {source [lindex $argv 0]} message options]} {
    puts stderr [dict get $options -errorinfo]
    catch {destroy .}
    exit 1
}
exit 0
