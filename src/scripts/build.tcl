# build.tcl for NanoMig

# This tcl script controls the entire NanoMig build process for all Gowin based
# board variants. It also generates config files, cst and sdc files and it creates
# GPRJ and JSON files to be used with the IDE.

if {$argc == 0} {
    puts "Usage: $argv0 <device> <optons...>"
    puts "       device: nano20k, tp25k, gw5a_25, gw3a_20, mega138kpro, console60k, console138k"
    puts "       options:"
    puts "               nano20k: aga, lcd   - build aga+020 and/or rgblcd variant"
    puts "               tp25k:   aga        - build aga variant"
    puts "               gw5a_25: aga        - build aga variant"
    puts "               all:     nosyn      - generate files only, don't run synthesis"
    puts "                        dbgcpu     - include cpu test rom \"pwr_led_blink\""
    puts "                        dbgvid     - include video test rom \"video_init\""
    puts "                        dbgram     - include rom/ram test \"ram_test\""
    exit 1
}

set config "amiga"
set dev [lindex $argv 0]
set options [lrange $argv 1 end]

# default settings
set board "unset"
set defines [list "GOWIN" "ENABLE_FX68K"]
set dev_path "."

# list of cst and sdc files. Since gowin only allows
# one of these files, this has to be assembled if more
# than one is being used
set cst [list]
set sdc [list]

# ------------------------------------------------------------
# --------------------- GPRJ generator -----------------------
# ------------------------------------------------------------

# Gowin supports two main build processes. One through the ide
# using *.gprj and *.json files and one through tcl scripts using
# the command line. These files have vastly different formats but
# serve the same purpose. This involves the risk that these use
# different options and build different cores for the same setup.
# This tcl script thus re-generates the gprj/ide related files
# in an attempt to force both build processes to stay in sync.

# Wrapper for the gowin provided functions. Create lists of
# files to be able to write the final gprj

set device [list]
proc set_device_info { pn version name desc } {
    global device
    if { $version != "" } {
	set_device $pn -device_version $version -name $name
    } else {
	set_device $pn -name $name
    }
    
    set device [list $name $pn $desc ]
}

set files_verilog [list]
proc add_file_v { filename } {
    global files_verilog
    add_file $filename
    lappend files_verilog $filename
}

set files_vhdl [list]
proc add_file_vhd { filename } {
    global files_vhdl
    add_file $filename
    lappend files_vhdl $filename
}

set file_cst ""
proc add_file_cst { filename } {
    global file_cst
    add_file $filename
    set file_cst $filename
}

set file_sdc ""
proc add_file_sdc { filename } {
    global file_sdc
    add_file $filename
    set file_sdc $filename
}

set files_other [list]
proc add_file_other { filename } {
    global files_other
    add_file $filename
    lappend files_other $filename
}

set gprj_options [list]
proc set_option_int { name value } {
    global gprj_options
    lappend gprj_options [list $name $value]
    set_option $name $value
}

# we cannot pass parameters into the tcl script invoked by
# the gprj/ide build process. Thus custom wrapper scripts
# are written for each variant. This is the script that is
# being referenced in the json via option TclPre
proc write_xml_updater { board xml_enable } {
    puts "NOTE Creating \"scripts/update_xml_${board}.tcl\""
    set f [open "scripts/update_xml_${board}.tcl" w]
    puts $f "set config \"amiga\""
    puts $f "set board \"$board\""
    puts -nonewline $f "set xml_enable \[list"
    foreach str $xml_enable {
        puts -nonewline $f " \"$str\""
    }
    puts $f "\]"
    puts $f "scripts/update_xml.tcl"
    close $f
}

# impl/nanomig_process_config.json 
proc write_process_json { board } {
    global gprj_options

    # The xxx_process_config.json file contains very similar information
    # to the build.tcl although in a very different syntax. This table
    # tries to convert from tcl to json variant
    
    set table [list]
    lappend table [list "-output_base_name"  "OUTPUT_BASE_NAME" "str"] 
    lappend table [list "-use_mspi_as_gpio"  "MSPI"  "bool"] 
    lappend table [list "-use_sspi_as_gpio"  "SSPI"  "bool"] 
    lappend table [list "-use_jtag_as_gpio"  "JTAG"  "bool"]
    lappend table [list "-use_done_as_gpio"  "DONE"  "bool"]
    lappend table [list "-use_i2c_as_gpio"   "I2C"   "bool"]
    lappend table [list "-use_ready_as_gpio" "READY" "bool"]
    # the possible loading speed values inside the json are somewhat odd. So we only support a few of them ...
    lappend table [list "-loading_rate"      "DOWNLOAD_SPEED"  [list [list "25.0" "250/10" ] [list "70.0" "210/3" ]] ] 
    lappend table [list "-synthesis_tool"    "Synthesize_tool" [list [list "gowinsynthesis" "GowinSyn" ]] ] 
    lappend table [list "-verilog_std"       "Verilog_Standard"  [list [list "sysv2017" "Vlg_Std_Sysv2017" ]] ]
    lappend table [list "-top_module"        "TopModule"  "str" ]
    lappend table [list "-cst_warn_to_error" "Promote_Physical_Constraint_Warning_to_Error" "bool" ]
    lappend table [list "-multi_boot"        "Multi_Boot" "bool" ]
    lappend table [list "-mspi_jump"         "MSPI_JUMP" "bool" ]
    lappend table [list "-use_cpu_as_gpio"   "CPU" "bool" ]
    lappend table [list "-place_option"      "Place_Option" "str" ]
    lappend table [list "-route_option"      "Route_Option" "str" ]

    puts "NOTE Creating \"gowin_prj/impl/nanomig_${board}_process_config.json\""
    set f [open "gowin_prj/impl/nanomig_${board}_process_config.json" w]
    puts $f "{"

    # the "Verion" (sic!) is needed
    puts $f "    \"Process_Configuration_Verion\": \"1.0\","
    
    foreach option $gprj_options {
	set name [lindex $option 0]
	set value [lindex $option 1]

	# puts "OPTION $name $value "
	set ok 0
	foreach t $table {
	    if { $name == [lindex $t 0] } {
		set ok 1		
		set json_name [lindex $t 1]
		if { $json_name == "" } {		    
		    puts "WARN generate process config json: ignored option $name"
		} else {
		    set type [lindex $t 2]
		    
		    if {  [string index $type 0] == "\{" } {
			# search for value in list
			set result ""
			foreach s $type {
			    if { $value == [lindex $s 0] } {
				set result [lindex $s 1]
			    }
			}
			
			if { $result == "" } {
			    puts "ERROR Unknown value $name $value"
			    exit 1
			}
			
			# we have the translated value
			puts $f "    \"${json_name}\": \"$result\","
			
		    } elseif { $type == "str" } {	    
			puts $f "    \"${json_name}\": \"$value\","
		    } elseif { $type == "bool" } {
			set bool_str "false"
		    if { $value } {
			set bool_str "true"
		    }
			puts $f "    \"${json_name}\": $bool_str,"
		    } else {
			puts "What's this???"
			exit -1
		    }
		}
	    }
	}

	if { ! $ok } {
	    puts "ERROR Unknown entry $name"
	    exit 1
	}	    
	
    }    
    puts $f "    \"TclPre\": \"../scripts/update_xml_${board}.tcl\""
    
    puts $f "}"
    close $f
}

proc write_gprj { board } {
    global device
    global files_verilog
    global files_vhdl
    global files_other
    global file_cst
    global file_sdc
    
    puts "NOTE Creating \"gowin_prj/nanomig_${board}.gprj\""
    set f [open "gowin_prj/nanomig_${board}.gprj" w]
    puts $f "<?xml version=\"1\" encoding=\"UTF-8\"?>"
    puts $f "<!DOCTYPE gowin-fpga-project>"
    puts $f "<Project>"
    puts $f "    <Template>FPGA</Template>"
    puts $f "    <Version>5</Version>"
    set name [lindex $device 0]
    set pn [lindex $device 1]
    set desc [lindex $device 2]    
    puts $f "    <Device name=\"$name\" pn=\"$pn\">$desc</Device>"
    puts $f "    <FileList>"

    foreach filename $files_verilog {
	puts $f "       <File path=\"../$filename\" type=\"file.verilog\" enable=\"1\"/>"	
    }
    
    foreach filename $files_vhdl {
	puts $f "       <File path=\"../$filename\" type=\"file.vhdl\" enable=\"1\"/>"	
    }
    
    foreach filename $files_other {
	puts $f "       <File path=\"../$filename\" type=\"file.other\" enable=\"1\"/>"	
    }
    
    puts $f "       <File path=\"../$file_cst\" type=\"file.cst\" enable=\"1\"/>"	
    puts $f "       <File path=\"../$file_sdc\" type=\"file.sdc\" enable=\"1\"/>"	
    
    puts $f "    </FileList>"
    puts $f "</Project>"
    
    close $f
}

# ------------------------------------------------------------
# ------------------------------------------------------------

# process $dev
if {$dev eq "nano20k"} {
    # Tang Nano 20k
    puts "Building for Tang Nano 20k"
    set_device_info "GW2AR-LV18QN88C8/I7" "C" "GW2AR-18C" "gw2ar18c-000"

    # we use more than one cst and sdc files, so add them
    # to the lists to be concatenated later
    lappend cst tang/nano20k/nanomig_common.cst
    lappend sdc tang/nano20k/nanomig_common.sdc

    # board is used in amiga.xml to enable/disable stuff
    set board "tang_nano20k"

    # six inverted (active low) leds
    lappend defines "LEDS 6"
    lappend defines "LEDS_N"

    # sdram config
    lappend defines "SDRAM_CKE"
    lappend defines "SDRAM_DATA_WIDTH 32"
    lappend defines "SDRAM_RAS_WIDTH 11"
    lappend defines "SDRAM_CAS_WIDTH 8"
    # the GW2AR-LV18 has only 8MB SDRAM which leaves only 5.5MB FASRAM
    lappend defines "ENABLE_FASTMEM_5_5MB"
    
    # there's an internal bl616 on this board
    lappend defines "INTERNAL_COMPANION"
    
    # lappend defines "ENABLE_KICKSWITCH"

    # only IDE0 is currently being used
    lappend defines "ENABLE_IDE"

    set dev_path "tang/nano20k"

    # ====================== parse options =============================

    # AGA option
    if {[lsearch -exact $options "aga"] >= 0} {
	set options [lsearch -inline -all -not -exact $options "aga"]
	puts "Building AGA variant"
	append board "_aga"
	
	# the nano20k does not have enough capacity for both CPUs. So disable
	# fx68k if tg68k is being included
	set defines [lsearch -inline -all -not -exact $defines "ENABLE_FX68K"]
	
	lappend defines "ENABLE_TG68K" "ENABLE_AGA" "CPU_SLOW14" "ENABLE_CACHE" "ENABLE_TURBO"
	lappend defines "NO_WS2812" "DENISE_EBR" "DISABLE_TG68K_010" "ENABLE_TG68K_MENU_NO_010"
	# alternative: replace the two TG68K defines above by "ENABLE_TG68K_020_ONLY"
	# to hard-wire the 68020 (saves logic, removes the CPU menu entry)

	# once tg68k is enabled add its timing constraints
	lappend sdc tang/nano20k/nanomig_tg68k.sdc
    }
	
    # LCD option
    if {[lsearch -exact $options "lcd"] >= 0} {
	set options [lsearch -inline -all -not -exact $options "lcd"]
	puts "Building LCD variant"
	append board "_lcd"

	# On tang nano 20k, the lcd interface and the hdmi interface overlap
	# and cannot be used at the same time. Also the db09, midi and companion pins are
	# not available and the internal bl616 has to be used
	lappend defines "ENABLE_LCD"
	lappend defines "LCD_R 5"
	lappend defines "LCD_G 6"
	lappend defines "LCD_B 5"
	lappend defines "LCD_HS"
	lappend defines "LCD_VS"

	# also enable the audio amplifier
	lappend defines "ENABLE_PA"
	
	lappend cst tang/nano20k/nanomig_lcd.cst

	# LCD companion option
	if {[lsearch -exact $options "lcd_companion"] >= 0} {
	    set options [lsearch -inline -all -not -exact $options "lcd_companion"]

	    lappend defines "EXTERNAL_COMPANION"
	    lappend cst tang/nano20k/nanomig_lcd_companion.cst
	}
    } else {
	puts "Building HDMI variant"
	
	lappend defines "ENABLE_HDMI"

	# all non-lcd builds use drive sounds
	lappend defines "ENABLE_DRIVE_SOUNDS" "HQ_DRIVE_SOUNDS"
	lappend defines "EXTERNAL_COMPANION"
	lappend defines "ENABLE_DB9A" "ENABLE_DB9B"
	lappend defines	"ENABLE_MIDI"

	# on nano20k only non-lcd cores can use hdmi
	lappend cst tang/nano20k/nanomig_hdmi.cst
	lappend sdc tang/nano20k/nanomig_hdmi.sdc
    }

} elseif {$dev eq "tp25k"} {
    set board "tang_primer25k"
    set_device_info "GW5A-LV25MG121NC1/I0" "" "GW5A-25A" "gw5a25a-002"

    # we use more than one sdc file, so add them
    # to the lists to be concatenated later
    lappend sdc tang/primer25k/nanomig_common.sdc

    # only two leds
    lappend defines "LEDS 2"

    # sdram config for MiSTer RAM module
    lappend defines "SDRAM_DATA_WIDTH 16"
    lappend defines "SDRAM_RAS_WIDTH 13"
    lappend defines "SDRAM_CAS_WIDTH 9"
    lappend defines "SDRAM_SYNC_DELAY 2"

    lappend defines "ENABLE_JTAGSELN"
    
    # there's an internal bl616 on this board
    # and an external one can be used
    lappend defines "INTERNAL_COMPANION"
    lappend defines "EXTERNAL_COMPANION"

    # only IDE0 is currently being used
    lappend defines "ENABLE_IDE"

    lappend defines "ENABLE_RTC"
    lappend defines "ENABLE_HDMI"
    
    # board is used in amiga.xml to enable/disable stuff
    set board "tang_primer25k"
    set dev_path "tang/primer25k"

    # AGA option
    if {[lsearch -exact $options "aga"] >= 0} {
	set options [lsearch -inline -all -not -exact $options "aga"]
	puts "Building AGA variant"
	append board "_aga"
	
	# the nano20k does not have enough capacity for both CPUs. So disable
	# fx68k if tg68k is being included
	set defines [lsearch -inline -all -not -exact $defines "ENABLE_FX68K"]
	
	lappend defines "ENABLE_TG68K" "ENABLE_AGA" "CPU_SLOW14" "ENABLE_CACHE" "ENABLE_TURBO"
	lappend defines "NO_WS2812" "ENABLE_RAM32" "CHIPRAM_CACHE" "ENABLE_TG68K_MENU_ALL"

	# once tg68k is enabled add its timing constraints.
	lappend sdc tang/primer25k/nanomig_tg68k.sdc
    }
	
} elseif {$dev eq "gw5a_25"} {
    set board "mistle_gw5a_25"
    set_device_info "GW5A-LV25LQ144C1/I0" "" "GW5A-25A" "gw5a25a-036"

    # six inverted (active low) leds
    lappend defines "LEDS 6"
    lappend defines "LEDS_N"

    # user (menu) button is active low
    lappend defines "USER_N"

    lappend defines "ENABLE_MIDI"

    # sdram config
    lappend defines "SDRAM_DATA_WIDTH 16"
    lappend defines "SDRAM_RAS_WIDTH 13"
    lappend defines "SDRAM_CAS_WIDTH 9"
    lappend defines "ENABLE_FASTMEM_8MB"
    
    # there's no internal bl616 on this board
    lappend defines "EXTERNAL_COMPANION"

    # this board has two physical db9 ports
    lappend defines "ENABLE_DB9A" "ENABLE_DB9B"

    # only IDE0 is currently being used
    lappend defines "ENABLE_IDE"

    lappend defines "ENABLE_RTC"
    
    lappend defines "ENABLE_HDMI"

    lappend sdc mistle/gw5a_25/nanomig_common.sdc
    
    # AGA option
    if {[lsearch -exact $options "aga"] >= 0} {
	set options [lsearch -inline -all -not -exact $options "aga"]
	puts "Building AGA variant"
	append board "_aga"
	
	# remove the FX68K support to save some space
	set defines [lsearch -inline -all -not -exact $defines "ENABLE_FX68K"]

	lappend defines "ENABLE_TG68K" "ENABLE_AGA" "CPU_SLOW14" "ENABLE_CACHE" "DENISE_EBR" "ENABLE_TURBO"
	lappend defines "ENABLE_RAM32" "ENABLE_TG68K_MENU_ALL"

	# once tg68k is enabled add its timing constraints
	lappend sdc mistle/gw5a_25/nanomig_tg68k.sdc
    }
	
    set dev_path "mistle/gw5a_25"

} elseif {$dev eq "gw3a_20"} {
    set board "mistle_gw3a_20"
    set_device_info "GW3A-LV20LQ144C1/I0" "" "GW3A-20A" "gw3a20a-010"

    # remove the FX68K support to save some space
    set defines [lsearch -inline -all -not -exact $defines "ENABLE_FX68K"]

    lappend defines "ENABLE_HDMI"

    lappend defines "PLL_NO_MDCLK"

    lappend defines "ENABLE_MIDI"

    # six inverted (active low) leds
    lappend defines "LEDS 6"
    lappend defines "LEDS_N"

    # user (menu) button is active low
    lappend defines "USER_N"

    # sdram config
    lappend defines "SDRAM_DATA_WIDTH 16"
    lappend defines "SDRAM_RAS_WIDTH 13"
    lappend defines "SDRAM_CAS_WIDTH 9"
    
    # there's no internal bl616 on this board
    lappend defines "EXTERNAL_COMPANION"

    # this board has two physical db9 ports
    lappend defines "ENABLE_DB9A" "ENABLE_DB9B"

    # only IDE0 is currently being used
    lappend defines "ENABLE_IDE"

    lappend defines "ENABLE_RTC"
    
    lappend defines "ENABLE_HDMI"

    lappend sdc mistle/gw5a_25/nanomig_common.sdc

    set dev_path "mistle/gw3a_20"

} elseif {$dev eq "mega138kpro"} {
    set board "tang_mega138kpro"

    set_device_info "GW5AST-LV138FPG676AC1/I0" "" "GW5AST-138B" "gw5ast138b-007"

    # six inverted (active low) leds
    lappend defines "LEDS 6"
    lappend defines "LEDS_N"

    # reset and user (menu) buttons are active low
    lappend defines "RESET_N"
    lappend defines "USER_N"

    # sdram config for MiSTer RAM module. Unlike all other
    # boards, this one needs to run the sdram clock shifted
    # by 180 degrees (270 deg for all other boards) 
    lappend defines "SDRAM_DATA_WIDTH 16"
    lappend defines "SDRAM_RAS_WIDTH 13"
    lappend defines "SDRAM_CAS_WIDTH 9"
    lappend defines "SDRAM_SYNC_DELAY 2"

    # For unknown reason the mega138k delivers the flash
    # data one cycle later than all other boards. Also the
    # uncommon shifted sdram clock is unsuited for
    # flash. It's thus driven from an unshifted clock.
    lappend defines "FLASH_READ_DELAY 1"
    lappend defines "FLASH_CLOCK_NO_SHIFT"

    lappend defines "ENABLE_JTAGSELN"
    
    # there's an internal bl616 on this board
    # and an external one can be used
    lappend defines "INTERNAL_COMPANION"
    lappend defines "EXTERNAL_COMPANION"

    # only IDE0 is currently being used
    lappend defines "ENABLE_IDE"
    
    lappend defines "ENABLE_RTC"
    
    lappend defines "ENABLE_HDMI"

    lappend defines "ENABLE_LCD"
    lappend defines "LCD_R 6"
    lappend defines "LCD_G 6"
    lappend defines "LCD_B 6"

    # also enable the audio amplifier
    lappend defines "ENABLE_PA"

    # enable PMOD0 and PMOD2 and map the ROM hex debugger to pmod0
    # PMOD1 is being used by the external companion
    lappend defines "PMOD0"
    lappend defines "PMOD_HEX_DEBUG pmod0"
    lappend defines "PMOD2"

    # the mega138k core is bigger and thus occupies more flash space, so
    # the default amiga kickstart doesn't start at 4MB (2M words) as usual
    # but at 6MB (3M words)
    lappend defines "DEFAULT_FLASH_ADDR  23'h300000"
    
    lappend defines "ENABLE_TG68K" "ENABLE_AGA" "CPU_SLOW14" "ENABLE_CACHE"
    lappend defines "DENISE_EBR" "ENABLE_TURBO" "ENABLE_RAM32" "ENABLE_TG68K_MENU_ALL"

    # once tg68k is enabled add its timing constraints
    lappend sdc mistle/gw5a_25/nanomig_tg68k.sdc
	
    set dev_path "tang/mega138kpro"
    
} elseif {$dev eq "console60k"} {
    set board "tang_console60k"

    set_device_info "GW5AT-LV60PG484AC1/I0" "" "GW5AT-60B" "gw5at60b-002"

    # the board actually has three leds
    # but the "sys act" LED on the CFG_LED pin is not current limited
   lappend defines "LEDS 2"

    # reset and user (menu) buttons are active low
    lappend defines "RESET_N"
    lappend defines "USER_N"

    # sdram config for MiSTer RAM module
    lappend defines "SDRAM_DATA_WIDTH 16"
    lappend defines "SDRAM_RAS_WIDTH 13"
    lappend defines "SDRAM_CAS_WIDTH 9"
    lappend defines "SDRAM_SYNC_DELAY 2"

    # For unknown reason and like the mega138k the conmsole138k
    # delivers the flash data one cycle later than all other boards. Also the
    # uncommon shifted sdram clock is unsuited for
    # flash. It's thus driven from an unshifted clock.
    lappend defines "FLASH_READ_DELAY 1"
    lappend defines "FLASH_CLOCK_NO_SHIFT"

    lappend defines "ENABLE_JTAGSELN"
    
    # there's an internal bl616 on this board
    # and an external one can be used
    lappend defines "INTERNAL_COMPANION"
    lappend defines "EXTERNAL_COMPANION"

    # only IDE0 is currently being used
    lappend defines "ENABLE_IDE"

    lappend defines "ENABLE_RTC"
    
    lappend defines "ENABLE_HDMI"

    # external RGBLCD
    lappend defines "ENABLE_LCD"
    lappend defines "LCD_R 8"
    lappend defines "LCD_G 8"
    lappend defines "LCD_B 8"
    lappend defines "LCD_HS"
    lappend defines "LCD_VS"

    # This FPGA is big enough for fx68k + tg68k + AGA
    lappend defines "ENABLE_TG68K" "ENABLE_AGA" "CPU_SLOW14" "ENABLE_CACHE"
    lappend defines "DENISE_EBR" "ENABLE_TURBO" "ENABLE_RAM32" "ENABLE_TG68K_MENU_ALL"

    # once tg68k is enabled add its timing constraints
    lappend sdc mistle/gw5a_25/nanomig_tg68k.sdc

    # also enable the audio amplifier
    lappend defines "ENABLE_PA"

    # enable PMOD1 and map the ROM hex debugger to it
    lappend defines "PMOD1"
    lappend defines "PMOD_HEX_DEBUG pmod1"

    set dev_path "tang/console60k"
    
} elseif {$dev eq "console138k"} {
    set board "tang_console138k"

    set_device_info "GW5AST-LV138PG484AC1/I0" "C" "GW5AST-138C" "gw5ast138c-007"

    # the board actually has three leds
    # but the "sys act" LED on the CFG_LED pin is not current limited
   lappend defines "LEDS 2"

    # reset and user (menu) buttons are active low
    lappend defines "RESET_N"
    lappend defines "USER_N"

    # sdram config for MiSTer RAM module
    lappend defines "SDRAM_DATA_WIDTH 16"
    lappend defines "SDRAM_RAS_WIDTH 13"
    lappend defines "SDRAM_CAS_WIDTH 9"
    lappend defines "SDRAM_SYNC_DELAY 2"

    lappend defines "ENABLE_JTAGSELN"
    
    # there's an internal bl616 on this board
    # and an external one can be used
    lappend defines "INTERNAL_COMPANION"
    lappend defines "EXTERNAL_COMPANION"

    # external RGBLCD
    lappend defines "ENABLE_LCD"
    lappend defines "LCD_R 8"
    lappend defines "LCD_G 8"
    lappend defines "LCD_B 8"
    lappend defines "LCD_HS"
    lappend defines "LCD_VS"

    lappend defines "ENABLE_PA"
    
    # only IDE0 is currently being used
    lappend defines "ENABLE_IDE"

    lappend defines "ENABLE_RTC"
    
    lappend defines "ENABLE_HDMI"

    # enable PMOD1 and map the ROM hex debugger to it
    lappend defines "PMOD1"
    lappend defines "PMOD_HEX_DEBUG pmod1"

    set dev_path "tang/console138k"
    
} else {
    puts "Error, unknown device $dev"
    exit 1
}

# To debug ram and/or rom problems, some internal rom and ram
# can be enabled including some debig rom routines
if {[lsearch -exact $options "dbgcpu"] >= 0} {
    set options [lsearch -inline -all -not -exact $options "dbgcpu"]

    puts "WARN Enabling internal ram and rom"
    lappend defines "ENABLE_INT_ROM"
    lappend defines "ENABLE_INT_ROM_BLINK_LED"
}

if {[lsearch -exact $options "dbgvid"] >= 0} {
    set options [lsearch -inline -all -not -exact $options "dbgvid"]

    puts "WARN Enabling internal ram and rom"
    lappend defines "ENABLE_INT_ROM"
    lappend defines "ENABLE_INT_RAM"
    lappend defines "ENABLE_INT_ROM_VIDEO_INIT"
}

if {[lsearch -exact $options "dbgram"] >= 0} {
    set options [lsearch -inline -all -not -exact $options "dbgram"]

    puts "WARN Enabling internal ram and rom"
    lappend defines "ENABLE_INT_ROM"
    lappend defines "ENABLE_INT_ROM_RAM_TEST"
}

# set the core name to include the variant built
set_option_int -output_base_name nanomig_${board}

# process the xml config

# some defines set previously affect the menu and thus the
# amiga.xml. These are built into the variable xml_options
# and being read by the update_xml.tcl script
set xml_enable [list]
foreach define $defines {
    set prefix [string range $define 0 [expr {[string first "_" $define] - 1}]]
    set rest [string range $define [expr {[string first _ $define] + 1}] end]
    if { $prefix == "ENABLE" } {
	lappend xml_enable $rest
    }
}

source scripts/update_xml.tcl

# round value up to multiple of 512 to avoid changes in the config_xxx.vh for
# every tiny change in the xml
set gzip_len [expr {(($gzip_len + 511) / 512) * 512}]

# the actual length of the gzipped data should now be in gzip_len
lappend defines "XML_GZIP_LEN $gzip_len"

# create config file from defines and include it
if {[llength $defines] > 0} {
    puts -nonewline "NOTE : defines used:"
    
    set config_vh [open "$dev_path/config_$board.vh" w]
    puts $config_vh "// config.vh for $board, auto generated, do not edit"
    foreach define $defines {
	puts -nonewline " '$define'"
	puts $config_vh "`define $define"
    }
    close $config_vh    
    add_file_v $dev_path/config_$board.vh
    puts ""
}

if {$dev eq "nano20k"} {

    # files common to all nano20k variants
    add_file_v tang/nano20k/amigaclks.v
    add_file_v top.sv
    add_file_v tang/nano20k/gowin_dpb/sector_dpram.v
    add_file_v tang/nano20k/gowin_dpb/ide_dpram.v

    set_option_int -use_mspi_as_gpio 1
    set_option_int -use_sspi_as_gpio 1
    set_option_int -use_jtag_as_gpio 0
    set_option_int -loading_rate 25.000
} elseif {$dev eq "tp25k"} {
    add_file_v tang/primer25k/amigaclks.v
    add_file_v top.sv
    
    add_file_v tang/primer25k/gowin_clkdiv/gowin_clkdiv.v
    add_file_v tang/primer25k/gowin_pll/pll_142m.v
    add_file_v tang/primer25k/gowin_pll/pll_142m_mod.v
    add_file_v tang/primer25k/gowin_pll/pll_init.v
    add_file_v tang/primer25k/gowin_dpb/sector_dpram.v
    add_file_v tang/primer25k/gowin_dpb/ide_dpram.v
    
    add_file_cst tang/primer25k/nanomig.cst
    
    set_option_int -use_mspi_as_gpio 1
    set_option_int -use_sspi_as_gpio 1
    set_option_int -use_done_as_gpio 1
    set_option_int -use_cpu_as_gpio 1
    set_option_int -use_i2c_as_gpio 1
    set_option_int -use_ready_as_gpio 1
    set_option_int -use_jtag_as_gpio 1
    set_option_int -loading_rate 70.000

} elseif {$dev eq "gw5a_25"} {
    add_file_v mistle/gw5a_25/amigaclks.v
    add_file_v top.sv

    add_file_v tang/primer25k/gowin_clkdiv/gowin_clkdiv.v
    add_file_v tang/primer25k/gowin_pll/pll_142m.v
    add_file_v tang/primer25k/gowin_pll/pll_142m_mod.v
    add_file_v tang/primer25k/gowin_pll/pll_init.v
    add_file_v tang/primer25k/gowin_dpb/sector_dpram.v
    add_file_v tang/primer25k/gowin_dpb/ide_dpram.v

    add_file_cst mistle/gw5a_25/nanomig.cst

    set_option_int -use_mspi_as_gpio 1
    set_option_int -use_sspi_as_gpio 1
    set_option_int -use_cpu_as_gpio 1
    set_option_int -loading_rate 70.000
    set_option_int -place_option 1

} elseif {$dev eq "gw3a_20"} {
    # the GW3A uses the same board as tge GW5A and thus shares a
    # lot of files and settings
    
    add_file_v mistle/gw5a_25/amigaclks.v
    add_file_v top.sv
    
    add_file tang/primer25k/gowin_clkdiv/gowin_clkdiv.v
    add_file_v mistle/gw3a_20/gowin_pll/pll_142m.v
    add_file_v mistle/gw3a_20/gowin_dp/sector_dpram.v
    add_file_v mistle/gw3a_20/gowin_dp/ide_dpram.v

    # re-use files from gw5a
    add_file_cst mistle/gw5a_25/nanomig.cst
    add_file_sdc mistle/gw5a_25/nanomig.sdc

    set_option_int -use_mspi_as_gpio 1
    set_option_int -use_sspi_as_gpio 1
    set_option_int -use_cpu_as_gpio 1
    set_option_int -loading_rate 70.000
    set_option_int -place_option 1

} elseif {$dev eq "mega138kpro"} {
    add_file_v tang/mega138kpro/amigaclks.v
    add_file_v top.sv    

    add_file_v tang/mega138kpro/gowin_clkdiv/gowin_clkdiv.v
    add_file_v tang/mega138kpro/gowin_pll/pll_142m.v
    add_file_v tang/mega138kpro/gowin_pll/pll_142m_mod.v
    add_file_v tang/mega138kpro/gowin_pll/pll_init.v

    add_file_v tang/mega138kpro/gowin_dpb/sector_dpram.v
    add_file_v tang/mega138kpro/gowin_dpb/ide_dpram.v

    add_file_cst tang/mega138kpro/nanomig.cst
    add_file_sdc tang/mega138kpro/nanomig.sdc

    set_option_int -use_mspi_as_gpio 1
    set_option_int -use_sspi_as_gpio 1
    set_option_int -use_done_as_gpio 1
    set_option_int -use_cpu_as_gpio 1
    set_option_int -use_ready_as_gpio 1
    set_option_int -use_jtag_as_gpio 1
    set_option_int -loading_rate 70.000
    set_option_int -place_option 2
    set_option_int -route_option 1

} elseif {$dev eq "console60k"} {
    add_file_v tang/console60k/amigaclks.v
    add_file_v top.sv
    add_file_v tang/console60k/gowin_clkdiv/gowin_clkdiv.v
    add_file_v tang/primer25k/gowin_pll/pll_142m.v
    add_file_v tang/primer25k/gowin_pll/pll_142m_mod.v
    add_file_v tang/primer25k/gowin_pll/pll_init.v
    add_file_v tang/console60k/gowin_dpb/sector_dpram.v
    add_file_v tang/console60k/gowin_dpb/ide_dpram.v

    add_file_cst tang/console60k/nanomig.cst
    add_file_sdc tang/console60k/nanomig.sdc

    set_option_int -use_mspi_as_gpio 1
    set_option_int -use_sspi_as_gpio 1
    set_option_int -use_done_as_gpio 1
    set_option_int -use_cpu_as_gpio 1
    set_option_int -use_i2c_as_gpio 1
    set_option_int -use_ready_as_gpio 1
    set_option_int -use_jtag_as_gpio 1
    set_option_int -loading_rate 70.000

} elseif {$dev eq "console138k"} {
    puts "ERROR ============================================================"
    puts "ERROR ======== Not properly implemented and tested, yet =========="
    puts "ERROR ============================================================"
    
    add_file_v tang/console138k/amigaclks.v
    add_file_v top.sv
    add_file_v tang/mega138kpro/gowin_clkdiv/gowin_clkdiv.v
    add_file_v tang/console138k/gowin_pll/pll_142m.v
    add_file_v tang/console138k/gowin_pll/pll_142m_mod.v
    add_file_v tang/console138k/pll_init.v
    add_file_v tang/mega138kpro/gowin_dpb/sector_dpram.v
    add_file_v tang/mega138kpro/gowin_dpb/ide_dpram.v

    add_file_cst tang/console138k/nanomig.cst
    add_file_sdc tang/console138k/nanomig.sdc

    set_option_int -use_mspi_as_gpio 1
    set_option_int -use_sspi_as_gpio 1
    set_option_int -use_done_as_gpio 1
    set_option_int -use_cpu_as_gpio 1
    set_option_int -use_i2c_as_gpio 1
    set_option_int -use_ready_as_gpio 1
    set_option_int -use_jtag_as_gpio 1
    set_option_int -loading_rate 70.000
    set_option_int -place_option 2
    set_option_int -route_option 1
}

# files common to all variants
add_file_v nanomig.v
add_file_v minimig-aga/amiga_clk.v
add_file_v minimig-aga/cpu_wrapper.v
add_file_v minimig-aga/minimig.v 
add_file_v minimig-aga/ciaa.v
add_file_v minimig-aga/ciab.v
add_file_v minimig-aga/cia_int.v
add_file_v minimig-aga/cia_timera.v
add_file_v minimig-aga/cia_timerb.v
add_file_v minimig-aga/cia_timerd.v 
add_file_v minimig-aga/paula.v
add_file_v minimig-aga/paula_uart.v
add_file_v minimig-aga/paula_audio_channel.v
add_file_v minimig-aga/paula_audio_mixer.v
add_file_v minimig-aga/paula_audio.v
add_file_v minimig-aga/paula_audio_volume.v
add_file_v minimig-aga/paula_floppy_fifo.v
add_file_v minimig-aga/paula_floppy.v
add_file_v minimig-aga/paula_intcontroller.v
add_file_v minimig-aga/agnus.v
add_file_v minimig-aga/agnus_audiodma.v
add_file_v minimig-aga/agnus_blitter_adrgen.v
add_file_v minimig-aga/agnus_blitter_minterm.v
add_file_v minimig-aga/agnus_diskdma.v
add_file_v minimig-aga/agnus_beamcounter.v
add_file_v minimig-aga/agnus_blitter_barrelshifter.v
add_file_v minimig-aga/agnus_blitter.v
add_file_v minimig-aga/agnus_refresh.v
add_file_v minimig-aga/agnus_bitplanedma.v
add_file_v minimig-aga/agnus_blitter_fill.v
add_file_v minimig-aga/agnus_copper.v
add_file_v minimig-aga/agnus_spritedma.v
add_file_v minimig-aga/denise.v
add_file_v minimig-aga/denise_collision.v
add_file_v minimig-aga/denise_colortable.v
add_file_v minimig-aga/denise_playfields.v
add_file_v minimig-aga/denise_hamgenerator.v
add_file_v minimig-aga/denise_spritepriority.v
add_file_v minimig-aga/denise_colortable_ram_mf.v
add_file_v minimig-aga/denise_bitplanes.v
add_file_v minimig-aga/denise_bitplane_shifter.v
add_file_v minimig-aga/denise_sprites.v
add_file_v minimig-aga/denise_sprites_shifter.v
add_file_v minimig-aga/gary.v

if {[lsearch -exact $defines "ENABLE_IDE"] >= 0} {
    add_file_v minimig-aga/gayle.v
    add_file_v minimig-aga/ide.v
}
    
add_file_v minimig-aga/minimig_m68k_bridge.v
add_file_v minimig-aga/minimig_bankmapper.v
add_file_v minimig-aga/minimig_sram_bridge.v
add_file_v minimig-aga/minimig_syscontrol.v
add_file_v minimig-aga/userio.v
add_file_v minimig/Amber.v

if {[lsearch -exact $defines "ENABLE_AGA"] >= 0} {
    # used by AGA
    add_file_v minimig-aga/bitplane_ram.v
    add_file_v minimig-aga/sprite_ram.v    
}
    
# only for cores including the fx68k
if {[lsearch -exact $defines "ENABLE_FX68K"] >= 0} {
    add_file_v fx68k/fx68k.sv
    add_file_v fx68k/fx68kAlu.sv
    add_file_v fx68k/uaddrPla.sv
    add_file_other fx68k/microrom.mem
    add_file_other fx68k/nanorom.mem
}
    
# only for cores including the tg68k
if {[lsearch -exact $defines "ENABLE_TG68K"] >= 0} {
    add_file_vhd tg68k/TG68K_Pack.vhd
    add_file_vhd tg68k/TG68K.vhd
    add_file_vhd tg68k/TG68K_ALU.vhd
    add_file_vhd tg68k/TG68KdotC_Kernel.vhd

    if {[lsearch -exact $defines "ENABLE_CACHE"] >= 0} {
	add_file_v minimig-aga/cpu_cache_new.v
	add_file_v minimig-aga/dpram.v	
	add_file_v minimig-aga/dpram_be_1024x16.v
    }
}

add_file_v misc/video_analyzer.v

# include hdmi parts unless HDMI is disabled
if {[lsearch -exact $defines "ENABLE_HDMI"] >= 0} {
    add_file_v hdmi/audio_clock_regeneration_packet.sv
    add_file_v hdmi/audio_info_frame.sv
    add_file_v hdmi/audio_sample_packet.sv
    add_file_v hdmi/auxiliary_video_information_info_frame.sv
    add_file_v hdmi/hdmi.sv
    add_file_v hdmi/packet_assembler.sv
    add_file_v hdmi/packet_picker.sv
    add_file_v hdmi/serializer.sv
    add_file_v hdmi/source_product_description_info_frame.sv
    add_file_v hdmi/tmds_channel.sv
}

# include ws2812 unless it's disabled
if {[lsearch -exact $defines "NO_WS2812"] < 0} {
    add_file_v misc/ws2812.v
}

# companion related files
add_file_v misc/mcu_spi.v
add_file_v misc/sysctrl.v
add_file_v misc/hid.v
add_file_v misc/osd_u8g2.v
add_file_v misc/sd_card.v
add_file_v misc/sd_rw.v
add_file_v misc/sdcmd_ctrl.v

add_file_v misc/flash_dspi.v
add_file_v misc/sdram.sv
add_file_v misc/rst_sync.v

# include drive sounds if enabled
if {[lsearch -exact $defines "ENABLE_DRIVE_SOUNDS"] >= 0} {
    if {[lsearch -exact $defines "HQ_DRIVE_SOUNDS"] >= 0} {
	add_file_v misc/drive_sounds_hq.v
    } else {
	add_file_v misc/drive_sounds_min.v
    }
}

add_file_v misc/uart_port.v
add_file_v misc/io_fifo.v

add_file_v misc/amiga_keymap.v
add_file_other misc/amiga_xml.hex

# if cst list is not empty, then create one file from
# this and add the result
if {[llength $cst] > 0} {
    puts "NOTE Creating \"$dev_path/nanomig_$board.cst\""
    
    set outfile [open "$dev_path/nanomig_$board.cst" w]
    puts $outfile "// do not edit, auto generated from:"
    foreach file $cst {
	puts $outfile "// $file"
    }
    puts $outfile ""
    foreach file $cst {
	set sourcefile [open $file r]
	chan copy $sourcefile $outfile
	close $sourcefile
    }
    close $outfile
    add_file_cst $dev_path/nanomig_$board.cst
}

# if sdc list is not empty, then create one file from
# this and add the result
if {[llength $sdc] > 0} {
    puts "NOTE Creating \"$dev_path/nanomig_$board.sdc\""
    
    set outfile [open "$dev_path/nanomig_$board.sdc" w]
    puts $outfile "// do not edit, auto generated from:"
    foreach file $sdc {
	puts $outfile "// $file"
    }
    puts $outfile ""
    foreach file $sdc {
	set sourcefile [open $file r]
	chan copy $sourcefile $outfile
	close $sourcefile
    }
    close $outfile
    add_file_sdc $dev_path/nanomig_$board.sdc
}

# options common to all variants
set_option_int -synthesis_tool gowinsynthesis
set_option_int -verilog_std sysv2017
set_option_int -top_module top
set_option_int -cst_warn_to_error 1
set_option_int -multi_boot 0
set_option_int -mspi_jump 0

# check if we have unparsed options and complain if so
if { [llength $options] != 0 } {    
    # if only the nosyn option remains, that's fine
    if { [llength $options] != 1 || [lsearch -exact $options "nosyn"] < 0} {    
	puts "ERROR Unprocessed options $options"
	exit -1
    }
}

# (re-)generate the gprj files for IDE builds
write_gprj $board
write_process_json $board
write_xml_updater $board $xml_enable

# run synthesis unless option "nosyn" was given
if {[lsearch -exact $options "nosyn"] < 0} {
    run all

    puts "NOTE built nanomig_${board}"
    if {[lsearch -exact $defines "ENABLE_INT_ROM"] >= 0} {
	puts "WARN This is a debug version!!!!!"
    }
}
