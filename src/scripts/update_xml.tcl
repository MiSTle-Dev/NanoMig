#
# update_xml.tcl
#
# convert the <config>.xml to <config>_xml.hex
#

package require zlib
puts "MiSTle XML Tool, board = $board, config = $config"

# it would be nice if we could access the project options from
# here as e.g. OUTPUT_BASE_NAME would nice to distinguish which
# board we are building for

if {[catch {exec git describe --tags --always --dirty} tag]} {
    set tag "unknown"
}
puts "Version: $tag"

# Function to read the entire file content
proc readFile {filename} {
    # Check if file exists and is readable
    if {![file exists $filename]} {
        error "File '$filename' does not exist."
    }
    if {![file readable $filename]} {
        error "File '$filename' is not readable."
    }

    set fh ""
    set data ""
    # Open file in read mode
    if {[catch {open $filename r} fh]} {
        error "Failed to open file '$filename': $fh"
    }

    # Read the file content
    if {[catch {read $fh} data]} {
        close $fh
        error "Error reading file '$filename': $data"
    }

    # Close the file
    close $fh

    return $data
}

# hexdump for debugging
proc hexdump {string} {
    set where 0
    while {$where<[string length $string]} {
        set str [string range $string $where [expr $where+15]]
        if {![binary scan $str H* t] || $t==""} break
        regsub -all (..) $t {\1 } t2
        set asc ""
        foreach i $t2 {
            scan $i %2x c
            append asc [expr {$c>=32 && $c<=127? [format %c $c]: "."}]
        }
        puts [format "%8.8x  %-42s %s" $where $t2  $asc]
        incr where 16
    }
}

# convert string to hex
proc string2hex {string} {
    binary scan $string H* t
    regsub -all (..) $t "\\1\n" res
    return $res
}

set xml_ext ".xml"
set hex_ext "_xml.hex"

# step 1: create platform independent xml file name
set filename_xml [ file join misc $config$xml_ext ]

# step 2: read file into memory
set data_xml [ readFile $filename_xml ]
puts [ format "Read %d bytes from $filename_xml" [ string length $data_xml ] ]

# ===== the data loaded into memory can now be processed =====

# replace the version string
regsub -all {version="unset"} $data_xml "version=\"$tag\"" data_xml

# mark parts to be kept or removed based in the board name ...
regsub -all -line "<!--IS.*? $board .*?-->" $data_xml "<!--KEEP-->" data_xml
regsub -all -line "<!--IS.*? $board-->" $data_xml "<!--KEEP-->" data_xml
regsub -all -line {<!--IS.*?-->} $data_xml "<!--REMOVE-->" data_xml
regsub -all -line "<!--NOT.*? $board .*?-->" $data_xml "<!--REMOVE-->" data_xml
regsub -all -line "<!--NOT.*? $board-->" $data_xml "<!--REMOVE-->" data_xml
regsub -all -line "<!--NOT.*?-->" $data_xml "<!--KEEP-->" data_xml

# ... and actually remove or keep those parts
regsub -all {<!--REMOVE-->.*?<!--END-->} $data_xml "" data_xml
regsub -all {<!--KEEP-->(.*?)<!--END-->} $data_xml {\1} data_xml

# remove all <!-- --> style xml comments
regsub -all {<!--.*?-->} $data_xml "" data_xml
# remove all blank lines
regsub -all -line {^\s*$\n?} $data_xml "" data_xml
# remove all leading and trailing white spaces from each line
regsub -all -line {^[ \t]+|[ \t]+$} $data_xml "" data_xml

puts [ format "Cleaned up to %d bytes" [ string length $data_xml ] ]

# dump filtered xml for debugging
# puts $data_xml

# step 3: gzip compress
set data_gzip [zlib gzip $data_xml]
# hexdump $data_gzip

# step 4: convert binary to hex
set data_hex [ string2hex $data_gzip ]
# puts $data_hex

# step 5: writing out hex
set filename_hex [ file join misc $config$hex_ext ]
puts [ format "Writing %d compressed bytes to $filename_hex" [ string length $data_gzip ] ]
set outfile [open $filename_hex w]
puts -nonewline $outfile $data_hex
close $outfile

# Exiting here will prevent the subsequent synthesis run. Useful for
# debugging of this script
# exit
