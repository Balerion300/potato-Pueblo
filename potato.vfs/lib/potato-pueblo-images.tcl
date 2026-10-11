# Bounded, event-driven downloads using the platform's curl and certificate store.
namespace eval ::potato::pueblo::images {
    variable jobs [dict create]
    variable queue {}
    variable photos [dict create]
    variable seen [dict create]
    variable totalPixels 0
    variable timer ""
}

proc ::potato::pueblo::images::request {c widget tag} {
    variable seen
    variable queue
    variable timer
    set key [list $widget $tag]
    if {[dict exists $seen $key]} {return}
    dict set seen $key $c
    if {[llength $queue] < 64 && [::potato::pueblo::option $c images]} {
        lappend queue $key
        pump
    }
    if {$timer eq ""} {set timer [after 500 ::potato::pueblo::images::collect]}
}

proc ::potato::pueblo::images::alive {key} {
    variable seen
    variable photos
    lassign $key widget tag
    set alive [expr {[dict exists $seen $key] && [winfo exists $widget] &&
        [$widget tag ranges $tag] ne "" &&
        [::potato::pueblo::option [dict get $seen $key] images]}]
    if {$alive && [dict exists $photos $key] &&
        [lindex [dict get $photos $key] 1] ni [$widget image names]} {return 0}
    return $alive
}

proc ::potato::pueblo::images::pump {} {
    variable jobs
    variable queue
    while {[dict size $jobs] < 4 && [llength $queue]} {
        set key [lindex $queue 0]
        set queue [lrange $queue 1 end]
        if {![alive $key]} {continue}
        set url [lindex $key 1 2]
        if {![::potato::pueblo::url $url]} {continue}
        set curl [auto_execok curl]
        if {$curl eq ""} {continue}
        # No shell, redirects, proxy environment, credentials, cookies or config.
        set command [list | {*}$curl -q --silent --fail --max-time 15 --connect-timeout 5 \
            --max-filesize 8388608 --proto =http,https --noproxy * --url $url 2>@1]
        if {[catch {open $command r} channel]} {continue}
        fconfigure $channel -blocking 0 -translation binary -encoding binary
        dict set jobs $channel [dict create key $key data ""]
        fileevent $channel readable [list ::potato::pueblo::images::readable $channel]
    }
}

proc ::potato::pueblo::images::readable {channel} {
    variable jobs
    if {![dict exists $jobs $channel]} {return}
    set key [dict get $jobs $channel key]
    if {![alive $key]} {finish $channel 0; return}
    if {[catch {read $channel 65536} chunk]} {finish $channel 0; return}
    dict set jobs $channel data "[dict get $jobs $channel data]$chunk"
    if {[string length [dict get $jobs $channel data]] > 8388608} {finish $channel 0; return}
    if {[eof $channel]} {finish $channel 1}
}

proc ::potato::pueblo::images::finish {channel success} {
    variable jobs
    if {![dict exists $jobs $channel]} {return}
    set job [dict get $jobs $channel]
    dict unset jobs $channel
    fileevent $channel readable {}
    # Closing a nonblocking pipeline never waits for an unfinished download.
    # curl has its own hard timeout, including after the owning view disappears.
    catch {close $channel}
    if {$success && [alive [dict get $job key]]} {
        catch {install [dict get $job key] [dict get $job data]}
    }
    after idle ::potato::pueblo::images::pump
}

proc ::potato::pueblo::images::dimensions {data} {
    set width 0; set height 0
    if {[string range $data 0 7] eq "\x89PNG\r\n\x1a\n" && [string length $data] >= 24 &&
        [string range $data 12 15] eq "IHDR"} {
        binary scan [string range $data 16 23] II width height
    } elseif {[string range $data 0 5] in {GIF87a GIF89a} && [string length $data] >= 10} {
        binary scan [string range $data 6 9] ssu width height
        set width [expr {$width & 65535}]; set height [expr {$height & 65535}]
    } elseif {[string range $data 0 1] eq "\xff\xd8"} {
        # Read JPEG SOF dimensions before asking an optional Img decoder to allocate.
        set pos 2
        while {$pos+3 < [string length $data]} {
            binary scan [string range $data $pos $pos+3] cu* bytes
            lassign $bytes prefix marker high low
            if {$prefix != 255 || $marker == 218 || $marker == 217} {break}
            if {$marker == 255} {incr pos; continue}
            set len [expr {($high << 8) | $low}]
            if {$len < 2 || $pos+2+$len > [string length $data]} {break}
            if {$marker in {192 193 194 195 197 198 199 201 202 203 205 206 207}} {
                binary scan [string range $data $pos+5 $pos+8] cu* bytes
                lassign $bytes hh hl wh wl
                set width [expr {($wh << 8) | $wl}]; set height [expr {($hh << 8) | $hl}]
                break
            }
            incr pos [expr {$len+2}]
        }
    }
    if {$width < 1 || $height < 1 || $width > 8192 || $height > 8192 || $width*$height > 16000000} {
        error "Unsupported or oversized image"
    }
    return [list $width $height]
}

proc ::potato::pueblo::images::install {key data} {
    variable photos
    variable totalPixels
    lassign $key widget tag
    lassign [dimensions $data] width height
    if {[dict size $photos] >= 64 || $totalPixels+$width*$height > 16000000} {return}
    catch {package require Img}
    set original [image create photo]
    if {[catch {$original configure -data $data} err]} {image delete $original; return}
    if {[image width $original] != $width || [image height $original] != $height} {image delete $original; return}
    set display [image create photo]
    set attrs [lindex $tag 3]
    set maxWidth [expr {max(32, min(640, [winfo width $widget]-24))}]
    set maxHeight 480
    foreach {keyName var} {width maxWidth height maxHeight} {
        set n [::potato::pueblo::get $attrs $keyName]
        if {[string is integer -strict $n] && $n > 0 && $n <= 8192} {set $var [expr {min([set $var],$n)}]}
    }
    set factor [expr {max(1, int(ceil(double($width)/$maxWidth)), int(ceil(double($height)/$maxHeight)))}]
    $display copy $original -subsample $factor $factor
    set pixels [expr {$width*$height+[image width $display]*[image height $display]}]
    if {$totalPixels+$pixels > 16000000} {image delete $original $display; return}
    # Snapshot before insertion; replacing elided fallback must preserve scrollback.
    set atEnd [::potato::atEnd $widget]
    set anchor [$widget index @0,0]
    lassign [$widget tag ranges $tag] start end
    set inherited [$widget tag names $start]
    set imageName [$widget image create $start -image $display -align center]
    foreach inheritedTag $inherited {$widget tag add $inheritedTag $start "$start + 1 indices"}
    set hide [list potatoImageFallback [lindex $tag 1]]
    $widget tag configure $hide -elide 1
    $widget tag add $hide "$start + 1 indices" "$end + 1 indices"
    dict set photos [list $widget $tag] [list $display $imageName $pixels $hide $original $factor]
    incr totalPixels $pixels
    if {$atEnd} {$widget see end} else {$widget yview $anchor}
}

proc ::potato::pueblo::images::collect {} {
    variable seen
    variable photos
    variable jobs
    variable totalPixels
    variable timer
    set timer ""
    foreach channel [dict keys $jobs] {
        if {![alive [dict get $jobs $channel key]]} {finish $channel 0}
    }
    foreach key [dict keys $seen] {
        lassign $key widget tag
        if {[alive $key]} {
            if {[dict exists $photos $key]} {resize $key}
            continue
        }
        if {[dict exists $photos $key]} {
            lassign [dict get $photos $key] photo imageName pixels hide original
            if {[winfo exists $widget]} {
                catch {$widget delete $imageName}
                catch {$widget tag delete $hide}
            }
            image delete $photo $original
            incr totalPixels -$pixels
            dict unset photos $key
        }
        if {[winfo exists $widget]} {catch {$widget tag delete $tag}}
        dict unset seen $key
    }
    if {[dict size $seen] || [dict size $jobs]} {set timer [after 500 ::potato::pueblo::images::collect]}
}

proc ::potato::pueblo::images::resize {key} {
    variable photos
    variable totalPixels
    lassign $key widget tag
    lassign [dict get $photos $key] display name pixels hide original oldFactor
    set width [image width $original]; set height [image height $original]
    set maxWidth [expr {max(32,min(640,[winfo width $widget]-24))}]
    set maxHeight 480
    foreach {keyName var} {width maxWidth height maxHeight} {
        set n [::potato::pueblo::get [lindex $tag 3] $keyName]
        if {[string is integer -strict $n] && $n > 0 && $n <= 8192} {set $var [expr {min([set $var],$n)}]}
    }
    set factor [expr {max(1,int(ceil(double($width)/$maxWidth)),int(ceil(double($height)/$maxHeight)))}]
    if {$factor == $oldFactor} {return}
    set newPixels [expr {$width*$height+int(ceil(double($width)/$factor))*int(ceil(double($height)/$factor))}]
    if {$totalPixels-$pixels+$newPixels > 16000000} {return}
    set atEnd [::potato::atEnd $widget]
    set anchor [$widget index @0,0]
    $display blank
    $display configure -width [expr {int(ceil(double($width)/$factor))}] \
        -height [expr {int(ceil(double($height)/$factor))}]
    $display copy $original -subsample $factor $factor
    incr totalPixels [expr {$newPixels-$pixels}]
    dict set photos $key [list $display $name $newPixels $hide $original $factor]
    if {$atEnd} {$widget see end} else {$widget yview $anchor}
}
