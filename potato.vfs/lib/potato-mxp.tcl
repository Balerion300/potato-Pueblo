# MXP data is never evaluated as Tcl or as a local Potato command.
namespace eval ::potato::mxp {variable state; variable serial 0}
proc ::potato::mxp::option {c} {
    upvar ::potato::conn conn ::potato::world world
    expr {[info exists conn($c,world)] && [info exists world($conn($c,world),mxp,enabled)] && $world($conn($c,world),mxp,enabled)}
}
proc ::potato::mxp::reset {c {active 0}} {
    variable state; variable serial
    set state($c) [dict create active $active epoch [incr serial] mode 0 default 0 temp 0 pending {} styles {} stack {} action {} send {} expires {} allExpiry 0]
}
proc ::potato::mxp::active {c} {
    variable state
    expr {[option $c] && [info exists state($c)] && [dict get $state($c) active]}
}
proc ::potato::mxp::negotiate {c cmd} {
    variable state
    if {![info exists state($c)]} {reset $c}
    set enabled [option $c]
    set old [dict get $state($c) active]
    switch -- $cmd {
        WILL - DO {
            if {!$old} {
                ::potato::sendRaw $c [binary format ccc 255 [expr {$cmd eq "WILL" ? ($enabled ? 253 : 254) : ($enabled ? 251 : 252)}] 91] 1
                if {$enabled} {reset $c 1; ::potato::addProtocol $c telnet,MXP}
            }
        }
        WONT - DONT {
            reset $c
            if {[info exists ::potato::conn($c,protocols)]} {
                set protocols $::potato::conn($c,protocols)
                set pos [lsearch -exact $protocols telnet,MXP]
                if {$pos >= 0} {set ::potato::conn($c,protocols) [lreplace $protocols $pos $pos]}
            }
        }
    }
}
proc ::potato::mxp::words {raw} {
    # Quote-aware positional arguments, named values, and standalone flags.
    set result {}
    foreach token [regexp -all -inline {[^\s=<>]+\s*=\s*(?:"[^"]*"|'[^']*'|[^\s<>]+)|"[^"]*"|'[^']*'|[^\s<>]+} $raw] {
        lappend result [string trim $token]
    }
    return $result
}
proc ::potato::mxp::args {raw positions} {
    set result [dict create]; set index 0
    foreach token [words $raw] {
        if {[regexp {^([^=\s]+)\s*=\s*(.*)$} $token -> key value]} {
            dict set result [string tolower $key] [::potato::pueblo::entities [string trim $value {"'}]]
        } elseif {[string tolower $token] in {prompt ismap}} {
            dict set result [string tolower $token] 1
        } else {
            if {$index < [llength $positions]} {
                dict set result [lindex $positions $index] [::potato::pueblo::entities [string trim $token {"'}]]
            }
            incr index
        }
    }
    return $result
}
proc ::potato::mxp::closeOpen {c} {
    variable state
    set stack {}; set styles {}
    foreach entry [dict get $state($c) stack] {
        if {[lindex $entry 1]} {lappend stack $entry; lappend styles [lindex $entry 0]}
    }
    dict set state($c) stack $stack
    dict set state($c) styles [lsort -unique $styles]
}
proc ::potato::mxp::mode {c number} {
    variable state
    if {$number ni {0 1 2 3 4 5 6 7}} {return}
    if {[dict get $state($c) mode] == 0} {closeOpen $c}
    dict set state($c) pending {}
    dict set state($c) temp 0
    switch -- $number {
        0 - 1 - 2 {dict set state($c) mode $number}
        3 {
            dict set state($c) mode 0; dict set state($c) styles {}; dict set state($c) stack {}; dict set state($c) action {}; dict set state($c) send {}
            foreach {key value} {fg fg bg bg flash 0 underline 0 highlight 0 inverse 0} {set ::potato::conn($c,ansi,$key) $value}
        }
        4 {dict set state($c) temp 1}
        5 - 6 - 7 {dict set state($c) mode [expr {$number-5}]; dict set state($c) default [expr {$number-5}]}
    }
}
proc ::potato::mxp::action {c kind value attrs} {
    variable state
    set expiry [::potato::pueblo::get $attrs expire]
    set generation 0
    if {$expiry ne "" && [dict exists $state($c) expires $expiry]} {set generation [dict get $state($c) expires $expiry]}
    return [list potatoAction $c [dict get $state($c) epoch] mxp [list $kind $value $expiry $generation [dict get $state($c) allExpiry]]]
}
proc ::potato::mxp::decorate {c item} {
    variable state
    set tags [lindex $item 1]
    lset tags 2 [concat [lindex $tags 2] [dict get $state($c) styles]]
    if {[dict get $state($c) action] ne ""} {lset tags 2 [concat [lindex $tags 2] [list [dict get $state($c) action] link]]}
    return [list [lindex $item 0] $tags]
}
proc ::potato::mxp::emit {c item outputVar} {
    variable state; upvar 1 $outputVar output
    set item [decorate $c $item]
    if {[dict get $state($c) send] ne ""} {
        dict lappend state($c) sendItems $item
        if {[llength [dict get $state($c) sendItems]] > 8192} {
            lappend output {*}[dict get $state($c) sendItems]
            dict set state($c) send {}; dict unset state($c) sendItems
        }
    } else {lappend output $item}
}
proc ::potato::mxp::finishSend {c outputVar} {
    variable state; upvar 1 $outputVar output
    if {[dict get $state($c) send] eq ""} {return}
    set attrs [dict get $state($c) send]; set items [dict get $state($c) sendItems]
    set caption ""; foreach item $items {append caption [lindex $item 0]}
    set value [::potato::pueblo::get $attrs href $caption]
    set value [string map [list &text\; $caption] $value]
    set commands [split $value |]
    set valid [expr {[llength $commands] <= 16}]
    foreach command $commands {if {![::potato::pueblo::command $command]} {set valid 0}}
    if {$valid} {
        set action [action $c [expr {[dict exists $attrs prompt] ? "prompt" : "send"}] [list $commands [::potato::pueblo::get $attrs hint]] $attrs]
        foreach item $items {lset item 1 2 [concat [lindex $item 1 2] [list $action link]]; lappend output $item}
    } else {lappend output {*}$items}
    dict set state($c) send {}; dict unset state($c) sendItems
}
proc ::potato::mxp::reply {c text} {::potato::send_to_noparse $c "\x1b\[1z$text" "" 0}
proc ::potato::mxp::support {c requests} {
    set supported {b bold strong i italic em u underline s strikeout br sbr a a.href a.expire send send.href send.hint send.prompt send.expire image image.fname image.url image.t img img.src img.alt expire version support}
    set result {}
    if {![llength $requests]} {set requests {b i u s br sbr a send image img expire version support}}
    foreach request $requests {
        set request [string tolower [string trim $request {"'}]]
        if {[string range $request end-1 end] eq ".*"} {
            set matched 0
            foreach name $supported {if {[string match $request $name]} {lappend result +$name}}
            foreach name $supported {if {[string match $request $name]} {set matched 1; break}}
            if {!$matched} {lappend result -$request}
        } elseif {[regexp {^[a-z!][a-z0-9!.*_-]*$} $request]} {
            lappend result [expr {$request in $supported ? "+$request" : "-$request"}]
        }
    }
    reply $c "<SUPPORTS [join $result { }]>"
}
proc ::potato::mxp::parse {c tagged} {
    variable state; variable serial
    if {![active $c]} {return $tagged}
    set items [concat [dict get $state($c) pending] $tagged]
    dict set state($c) pending {}; set output {}; set count [llength $items]
    for {set i 0} {$i < $count} {incr i} {
        set item [lindex $items $i]; set char [lindex $item 0]
        if {$char eq "<" && ([dict get $state($c) mode] != 2 || [dict get $state($c) temp])} {
            set raw ""; set quote ""; set end -1
            for {set j $i} {$j < $count && $j-$i < 8192} {incr j} {
                set ch [lindex $items $j 0]; append raw $ch
                if {$ch eq "\n"} {break}
                if {$quote ne ""} {if {$ch eq $quote} {set quote ""}
                } elseif {$ch in {\" '}} {set quote $ch
                } elseif {$ch eq ">"} {set end $j; break}
            }
            if {$end < 0} {
                if {$j == $count && $count-$i < 8192} {dict set state($c) pending [lrange $items $i end]; break}
                # Flush malformed tokens in one pass instead of rescanning '<'.
                foreach literal [lrange $items $i [expr {$j-1}]] {emit $c $literal output}
                set i [expr {$j-1}]; continue
            }
            set i $end
            set secure [expr {[dict get $state($c) mode] == 1 || [dict get $state($c) temp]}]
            dict set state($c) temp 0
            if {![regexp -nocase {^<(/?)([a-z][a-z0-9]*)\s*(.*?)>$} $raw -> closing name arguments]} {continue}
            set name [string tolower $name]
            set open [expr {$name in {b bold strong i italic em u underline s strikeout}}]
            if {!$secure && !$open} {continue}
            if {$open} {
                set style [dict get {b puebloBold bold puebloBold strong puebloBold i puebloItalic italic puebloItalic em puebloItalic u ANSI_underline underline ANSI_underline s mxpStrike strikeout mxpStrike} $name]
                set styles [dict get $state($c) styles]
                set pos [lsearch -exact $styles $style]
                set stack [dict get $state($c) stack]
                if {$closing eq "" && [llength $stack] < 128} {lappend stack [list $style $secure]}
                if {$closing ne ""} {
                    set index [lindex [lsearch -all -index 0 -exact $stack $style] end]
                    if {$index ne ""} {set stack [lreplace $stack $index $index]}
                }
                dict set state($c) stack $stack
                set styles {}; foreach entry $stack {lappend styles [lindex $entry 0]}
                set styles [lsort -unique $styles]
                dict set state($c) styles $styles; continue
            }
            switch -- $name {
                send {
                    finishSend $c output
                    if {$closing eq ""} {
                        set attrs [args $arguments {href hint}]; dict set attrs capture 1
                        dict set state($c) send $attrs; dict set state($c) sendItems {}
                    }
                }
                a {
                    dict set state($c) action {}
                    set attrs [args $arguments {href hint}]
                    set value [::potato::pueblo::get $attrs href]
                    if {$closing eq "" && [::potato::pueblo::url $value]} {dict set state($c) action [action $c url $value $attrs]}
                }
                image - img {
                    if {$closing ne ""} {continue}
                    set attrs [args $arguments [expr {$name eq "image" ? "fname url t" : "src"}]]
                    set src [::potato::pueblo::get $attrs src [::potato::pueblo::get $attrs fname]]
                    set base [::potato::pueblo::get $attrs url]
                    if {$base ne "" && ![regexp -nocase {^https?://} $src]} {
                        set type [::potato::pueblo::get $attrs t]
                        set src "[string trimright $base /]/"
                        if {$type ne ""} {append src "[string trim $type /]/"}
                        append src [::potato::pueblo::get $attrs fname]
                    }
                    set tags [lindex [decorate $c $item] 1]
                    if {[::potato::pueblo::url $src]} {
                        if {[dict get $state($c) action] eq ""} {lset tags 2 [concat [lindex $tags 2] [list [action $c url $src $attrs] link]]}
                        if {[::potato::pueblo::option $c images]} {lset tags 2 [concat [lindex $tags 2] [list [list potatoImage mxp[incr serial] $src $attrs]]]}
                    }
                    foreach ch [split "\[[::potato::pueblo::get $attrs alt Image]: $src\]" ""] {emit $c [list $ch $tags] output}
                }
                br {emit $c [list \n [lindex $item 1]] output}
                sbr {emit $c [list { } [lindex $item 1]] output}
                version {if {$closing eq ""} {reply $c {<VERSION MXP="1.0" CLIENT="Potato-Pueblo" VERSION="2.0" >}}}
                support {if {$closing eq ""} {support $c [words $arguments]}}
                expire {
                    set expiry [string trim $arguments { "'}]
                    if {$expiry eq ""} {dict incr state($c) allExpiry
                    } elseif {[dict size [dict get $state($c) expires]] < 128 || [dict exists $state($c) expires $expiry]} {
                        set generation 0
                        if {[dict exists $state($c) expires $expiry]} {set generation [dict get $state($c) expires $expiry]}
                        dict set state($c) expires $expiry [incr generation]
                    } else {dict incr state($c) allExpiry}
                }
            }
            continue
        }
        if {[dict get $state($c) temp]} {dict set state($c) temp 0}
        if {$char eq "&" && [dict get $state($c) mode] != 2} {
            set token ""; set end -1
            for {set j $i} {$j < $count && $j-$i < 32} {incr j} {
                set ch [lindex $items $j 0]; append token $ch
                if {$ch eq ";"} {set end $j; break}
                if {$j > $i && ![regexp {[a-zA-Z0-9#]} $ch]} {break}
            }
            if {$end >= 0} {
                foreach ch [split [::potato::pueblo::entities $token] ""] {if {![regexp {[\x00-\x1f\x7f]} $ch]} {emit $c [list $ch [lindex $item 1]] output}}
                set i $end; continue
            }
            if {$j == $count && $count-$i < 32} {dict set state($c) pending [lrange $items $i end]; break}
        }
        if {$char eq "\n"} {
            if {[dict get $state($c) mode] == 0} {closeOpen $c}
            dict set state($c) mode [dict get $state($c) default]
            dict set state($c) temp 0
        }
        emit $c $item output
    }
    return $output
}
proc ::potato::mxp::line {c line {newline 1}} {
    # Remove MXP mode controls before the legacy ANSI parser sees ESC ... z.
    set output {}; set offset 0
    foreach {match number} [regexp -all -inline -indices {\x1b\[([0-9]{0,2})z} $line] {
        lassign $match first last
        set part [string range $line $offset $first-1]
        lappend output {*}[parse $c [::potato::parseANSI $part ::potato::conn $c]]
        set code [string range $line {*}$number]; if {$code eq ""} {set code 0}
        scan $code %d code
        if {$code == 3} {finishSend $c output}
        mode $c $code
        set offset [expr {$last+1}]
    }
    set part [string range $line $offset end]
    if {$newline} {append part \n}
    lappend output {*}[parse $c [::potato::parseANSI $part ::potato::conn $c]]
    if {$newline && [llength $output] && [lindex $output end 0] eq "\n"} {set output [lrange $output 0 end-1]}
    return $output
}
proc ::potato::mxp::activate {c epoch payload} {
    variable state; upvar ::potato::conn conn
    if {![active $c] || [dict get $state($c) epoch] != $epoch} {return}
    lassign $payload kind value expiry generation all
    if {$expiry ne ""} {
        set current 0
        if {[dict exists $state($c) expires $expiry]} {set current [dict get $state($c) expires $expiry]}
        if {$current != $generation || [dict get $state($c) allExpiry] != $all} {return}
    }
    if {$kind eq "url"} {if {[::potato::pueblo::url $value]} {::potato::launchWebPage $value}; return}
    if {![::potato::pueblo::option $c commands] || ![info exists conn($c,connected)] || $conn($c,connected) != 1} {return}
    lassign $value commands hints
    if {[llength $commands] > 1} {
        set menu .potatoMxpCommands
        catch {destroy $menu}; menu $menu -tearoff 0
        set labels [split $hints |]
        if {[llength $labels] == [llength $commands]+1} {set labels [lrange $labels 1 end]}
        set i 0
        foreach command $commands {
            set label [lindex $labels $i]; if {$label eq ""} {set label $command}
            $menu add command -label $label -command [list ::potato::mxp::activate $c $epoch [list $kind [list [list $command] ""] $expiry $generation $all]]
            incr i
        }
        tk_popup $menu [winfo pointerx .] [winfo pointery .]
        return
    }
    set command [lindex $commands 0]
    if {![::potato::pueblo::command $command]} {return}
    if {$kind eq "prompt"} {
        if {[info exists conn($c,input1)] && [winfo exists $conn($c,input1)]} {
            set widget $conn($c,input1); $widget replace 1.0 end $command; $widget mark set insert end-1c; focus $widget
        }
    } elseif {$kind eq "send"} {::potato::send_to_noparse $c $command "" 1}
}
