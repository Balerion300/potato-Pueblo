# A deliberately small display parser. Incoming markup is data, never Tcl.
namespace eval ::potato::pueblo {
    variable state
    variable serial 0
    variable views [dict create]
}

proc ::potato::pueblo::option {c key} {
    upvar ::potato::conn conn ::potato::world world
    return [expr {[info exists conn($c,world)] &&
        [info exists world($conn($c,world),pueblo,$key)] && $world($conn($c,world),pueblo,$key)}]
}

proc ::potato::pueblo::reset {c} {
    variable state
    variable serial
    set state($c) [dict create epoch [incr serial] offered 0 active 0 pending {} action {} pre 0 br 0 styles {}]
}

proc ::potato::pueblo::url {value} {
    # Public named HTTP(S) hosts only; redirects are not followed by the loader.
    if {[string length $value] > 2048 || [regexp {[\x00-\x20\x7f\\]} $value]} {return 0}
    if {![regexp -nocase {^https?://([a-z0-9.-]+)(?::([0-9]+))?(?:[/?#]|$)} $value -> host port]} {return 0}
    set host [string tolower [string trimright $host .]]
    if {![regexp {^[a-z0-9][a-z0-9.-]*\.[a-z][a-z0-9-]*$} $host]} {return 0}
    if {[regexp {(^|\.)(localhost|local|internal|test|invalid)$} $host]} {return 0}
    if {$port ne "" && ($port < 1 || $port > 65535)} {return 0}
    return 1
}

proc ::potato::pueblo::command {value} {
    return [expr {$value ne "" && [string length $value] <= 2048 &&
        ![regexp {[\x00-\x1f\x7f]} $value]}]
}

proc ::potato::pueblo::entities {text} {
    set out ""
    while {[regexp -indices {&(#x[0-9a-fA-F]+|#[0-9]+|amp|lt|gt|quot|apos|nbsp|Tab);} $text match name]} {
        lassign $match first last
        append out [string range $text 0 $first-1]
        set entity [string range $text {*}$name]
        set value [string range $text $first $last]
        switch -- $entity {
            amp {set value &} lt {set value <} gt {set value >}
            quot {set value \"} apos {set value '} nbsp {set value \u00a0} Tab {set value \t}
            default {
                if {[string index $entity 1] eq "x"} {
                    scan [string range $entity 2 end] %x code
                } else {scan [string range $entity 1 end] %d code}
                if {$code > 0 && $code <= 65535 && !($code >= 55296 && $code <= 57343)} {
                    set value [format %c $code]
                }
            }
        }
        append out $value
        set text [string range $text $last+1 end]
    }
    return "$out$text"
}

proc ::potato::pueblo::attributes {tag} {
    set attrs [dict create]
    set pattern {([a-zA-Z][a-zA-Z0-9_-]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))}
    foreach {all key double single bare} [regexp -all -inline $pattern $tag] {
        set value "$double$single$bare"
        dict set attrs [string tolower $key] [entities $value]
    }
    return $attrs
}

proc ::potato::pueblo::get {attrs key {default ""}} {
    if {[dict exists $attrs $key]} {return [dict get $attrs $key]}
    return $default
}

proc ::potato::pueblo::decorate {c item} {
    variable state
    set tags [lindex $item 1]
    set extra [concat [lindex $tags 2] [dict get $state($c) styles]]
    set action [dict get $state($c) action]
    if {$action ne ""} {lappend extra [list potatoAction $c [dict get $state($c) epoch] {*}$action] link}
    lset tags 2 $extra
    return [list [lindex $item 0] $tags]
}

proc ::potato::pueblo::text {c items resultVar} {
    upvar 1 $resultVar result
    foreach item $items {lappend result [decorate $c $item]}
}

proc ::potato::pueblo::parse {c tagged} {
    variable state
    variable serial
    if {![info exists state($c)]} {reset $c}
    if {![option $c enabled]} {return $tagged}
    set plain ""
    foreach item $tagged {append plain [lindex $item 0]}
    if {![dict get $state($c) offered] && [regexp -nocase {This world is Pueblo [0-9]+\.[0-9]+ Enhanced\.} $plain]} {
        dict set state($c) offered 1
        ::potato::send_to_noparse $c {PUEBLOCLIENT 1.10} "" 0
    }
    if {![dict get $state($c) offered]} {return $tagged}
    set items [concat [dict get $state($c) pending] $tagged]
    dict set state($c) pending {}
    set result {}
    set count [llength $items]
    for {set i 0} {$i < $count} {incr i} {
        set item [lindex $items $i]
        set char [lindex $item 0]
        if {$char eq "<"} {
            set raw ""
            set quote ""
            set end -1
            for {set j $i} {$j < $count && $j-$i <= 8192} {incr j} {
                set ch [lindex $items $j 0]
                append raw $ch
                if {$quote ne ""} {
                    if {$ch eq $quote} {set quote ""}
                } elseif {$ch in {\" '}} {set quote $ch
                } elseif {$ch eq ">"} {set end $j; break}
            }
            if {$end < 0} {
                if {$count-$i <= 8192} {dict set state($c) pending [lrange $items $i end]; break}
                # Advance the whole oversized token fragment, avoiding quadratic
                # rescans when a hostile line contains thousands of '<' chars.
                text $c [lrange $items $i [expr {$i+8192}]] result
                incr i 8192
                continue
            }
            if {[regexp -nocase {^</?xch_mudtext(?:\s|>)} $raw] && [dict get $state($c) offered]} {
                # MUDTEXT encloses literal text; its closing tag enters HTML.
                dict set state($c) active [string match {</*} $raw]
                dict set state($c) action {}
                dict set state($c) styles {}
                dict set state($c) pre 0
                dict set state($c) br 0
                set i $end
                continue
            }
            if {![dict get $state($c) active]} {
                text $c [lrange $items $i $end] result
                set i $end
                continue
            }
            set i $end
            dict set state($c) br 0
            if {![regexp -nocase {^<(/?)([a-z][a-z0-9_]*)} $raw -> closing name]} {continue}
            set name [string tolower $name]
            set attrs [attributes $raw]
            switch -- $name {
                a - send {
                    dict set state($c) action {}
                    if {$closing ne ""} {continue}
                    set value [get $attrs href]
                    if {$name eq "send" || [string equal -nocase [get $attrs xch_cmd] true]} {
                        if {[command $value]} {dict set state($c) action [list command $value]}
                    } elseif {[url $value]} {dict set state($c) action [list url $value]}
                }
                pre {dict set state($c) pre [expr {$closing eq ""}]}
                br {
                    lappend result [decorate $c [list \n [lindex $item 1]]]
                    dict set state($c) br 1
                }
                p {if {[llength $result] && [lindex $result end 0] ne "\n"} {lappend result [decorate $c [list \n [lindex $item 1]]]}}
                b - strong - i - em - u {
                    set style [dict get {b puebloBold strong puebloBold i puebloItalic em puebloItalic u ANSI_underline} $name]
                    set styles [dict get $state($c) styles]
                    set pos [lsearch -exact $styles $style]
                    if {$closing eq "" && $pos < 0} {lappend styles $style}
                    if {$closing ne "" && $pos >= 0} {set styles [lreplace $styles $pos $pos]}
                    dict set state($c) styles $styles
                }
                img {
                    set src [get $attrs src]
                    # Pueblo uses IMG without SRC for mode-control messages.
                    if {$src eq ""} {continue}
                    set alt [get $attrs alt Image]
                    set fallback "\[$alt: $src\]"
                    set base [lindex [decorate $c $item] 1]
                    if {[url $src]} {
                        if {[dict get $state($c) action] eq ""} {
                            lset base 2 [concat [lindex $base 2] [list [list potatoAction $c [dict get $state($c) epoch] url $src] link]]
                        }
                        if {[option $c images]} {
                            lset base 2 [concat [lindex $base 2] [list [list potatoImage [incr serial] $src $attrs]]]
                        }
                    }
                    foreach ch [split $fallback ""] {lappend result [list $ch $base]}
                }
            }
            continue
        }
        if {![dict get $state($c) active]} {lappend result $item; continue}
        if {$char eq "&"} {
            set entity ""
            set end -1
            for {set j $i} {$j < $count && $j-$i < 32} {incr j} {
                set ch [lindex $items $j 0]
                append entity $ch
                if {$ch eq ";"} {set end $j; break}
                if {$j > $i && ![regexp {[a-zA-Z0-9#]} $ch]} {break}
            }
            if {$end >= 0} {
                foreach ch [split [entities $entity] ""] {lappend result [decorate $c [list $ch [lindex $item 1]]]}
                set i $end
                continue
            }
            if {$j == $count && $count-$i < 32} {dict set state($c) pending [lrange $items $i end]; break}
        }
        if {$char in {\r \n}} {
            if {[dict get $state($c) br]} {
                dict set state($c) br [expr {$char eq "\r" ? 2 : 0}]
                continue
            }
            if {![dict get $state($c) pre]} {continue}
        } else {dict set state($c) br 0}
        lappend result [decorate $c $item]
    }
    return $result
}

proc ::potato::pueblo::activate {c epoch kind value} {
    variable state
    upvar ::potato::conn conn
    if {![option $c enabled]} {return}
    if {$kind eq "url" && [url $value]} {::potato::launchWebPage $value; return}
    if {$kind eq "command" && [command $value] && [option $c commands] &&
        [info exists state($c)] && [dict get $state($c) epoch] == $epoch &&
        [info exists conn($c,connected)] && $conn($c,connected) == 1} {
        # Bypass local slash expansion, timers and semicolon splitting.
        ::potato::send_to_noparse $c $value "" 1
    }
}

proc ::potato::pueblo::forgetView {widget} {
    variable views
    if {[dict exists $views $widget]} {dict unset views $widget}
}

proc ::potato::pueblo::render {c widget {start ""}} {
    variable views
    if {![dict exists $views $widget]} {
        dict set views $widget [dict create count 0 font {}]
        bind $widget <Destroy> +[list ::potato::pueblo::forgetView $widget]
    }
    set view [dict get $views $widget]
    dict incr view count
    # Bind only newly inserted links/images. Periodic full sweeps reclaim tags
    # trimmed by transcript limits; an explicit full render also sweeps.
    if {$start eq "" || [dict get $view count] % 64 == 0} {
        set tags [$widget tag names]
    } else {
        set tags [$widget tag names $start]
        foreach {kind tag index} [$widget dump -tag $start end] {
            if {$kind eq "tagon"} {lappend tags $tag}
        }
        set tags [lsort -unique $tags]
    }
    foreach tag $tags {
        switch -- [lindex $tag 0] {
            potatoAction {
                if {[$widget tag ranges $tag] eq ""} {$widget tag delete $tag; continue}
                $widget tag bind $tag <ButtonRelease-1> [list ::potato::pueblo::activate {*}[lrange $tag 1 end]]
                $widget tag raise $tag
            }
            potatoImage {
                if {[$widget tag ranges $tag] eq ""} {$widget tag delete $tag; continue}
                ::potato::pueblo::images::request $c $widget $tag
            }
        }
    }
    # Use each transcript's existing font rather than a hard-coded family.
    set font [font actual [$widget cget -font]]
    if {$font ne [dict get $view font]} {
        $widget tag configure puebloBold -font [concat $font {-weight bold}]
        $widget tag configure puebloItalic -font [concat $font {-slant italic}]
        dict set view font $font
    }
    dict set views $widget $view
}
