# last sucessful build Gowin 1.9.10.03
set_device GW5AST-LV138FPG676AES -name GW5AST-138B

add_file nanomig.v
add_file minimig-aga/amiga_clk.v
add_file minimig-aga/cpu_wrapper.v
add_file minimig-aga/minimig.v 
add_file minimig-aga/ciaa.v
add_file minimig-aga/ciab.v
add_file minimig-aga/cia_int.v
add_file minimig-aga/cia_timera.v
add_file minimig-aga/cia_timerb.v
add_file minimig-aga/cia_timerd.v 
add_file minimig-aga/paula.v
add_file minimig-aga/paula_uart.v
add_file minimig-aga/paula_audio_channel.v
add_file minimig-aga/paula_audio_mixer.v
add_file minimig-aga/paula_audio.v
add_file minimig-aga/paula_audio_volume.v
add_file minimig-aga/paula_floppy_fifo.v
add_file minimig-aga/paula_floppy.v
add_file minimig-aga/paula_intcontroller.v
add_file minimig-aga/agnus.v
add_file minimig-aga/agnus_audiodma.v
add_file minimig-aga/agnus_blitter_adrgen.v
add_file minimig-aga/agnus_blitter_minterm.v
add_file minimig-aga/agnus_diskdma.v
add_file minimig-aga/agnus_beamcounter.v
add_file minimig-aga/agnus_blitter_barrelshifter.v
add_file minimig-aga/agnus_blitter.v
add_file minimig-aga/agnus_refresh.v
add_file minimig-aga/agnus_bitplanedma.v
add_file minimig-aga/agnus_blitter_fill.v
add_file minimig-aga/agnus_copper.v
add_file minimig-aga/agnus_spritedma.v
add_file minimig-aga/denise.v
add_file minimig-aga/denise_bitplane_shifter.v
add_file minimig-aga/denise_collision.v
add_file minimig-aga/denise_colortable.v
add_file minimig-aga/denise_playfields.v
add_file minimig-aga/denise_sprites_shifter.v
add_file minimig-aga/denise_bitplanes.v
add_file minimig-aga/denise_hamgenerator.v
add_file minimig-aga/denise_spritepriority.v
add_file minimig-aga/denise_sprites.v
add_file minimig-aga/denise_colortable_ram_mf.v
add_file minimig-aga/gary.v
add_file minimig-aga/gayle.v
add_file minimig-aga/ide.v
add_file minimig-aga/minimig_m68k_bridge.v
add_file minimig-aga/minimig_bankmapper.v
add_file minimig-aga/minimig_sram_bridge.v
add_file minimig-aga/minimig_syscontrol.v
add_file minimig-aga/userio.v
add_file minimig/Amber.v
add_file fx68k/fx68k.sv
add_file fx68k/fx68kAlu.sv
add_file fx68k/uaddrPla.sv
add_file hdmi/audio_clock_regeneration_packet.sv
add_file hdmi/audio_info_frame.sv
add_file hdmi/audio_sample_packet.sv
add_file hdmi/auxiliary_video_information_info_frame.sv
add_file hdmi/hdmi.sv
add_file hdmi/packet_assembler.sv
add_file hdmi/packet_picker.sv
add_file hdmi/serializer.sv
add_file hdmi/source_product_description_info_frame.sv
add_file hdmi/tmds_channel.sv
add_file misc/mcu_spi.v
add_file misc/sysctrl.v
add_file misc/hid.v
add_file misc/osd_u8g2.v
add_file misc/ws2812.v
add_file misc/video_analyzer.v
add_file misc/sd_card.v
add_file misc/sd_rw.v
add_file misc/sdcmd_ctrl.v
add_file misc/amiga_keymap.v
add_file misc/flash_dspi.v
add_file tang/mega138kpro/gowin_clkdiv/gowin_clkdiv.v
add_file tang/mega138kpro/gowin_pll/pll_142m.v
add_file tang/mega138kpro/gowin_pll/pll_142m_mod.v
add_file tang/mega138kpro/gowin_pll/pll_init.v
add_file tang/mega138kpro/gowin_dpb/sector_dpram.v
add_file tang/mega138kpro/gowin_dpb/ide_dpram.v
add_file tang/mega138kpro/top.sv
add_file misc/sdram.sv
add_file tang/mega138kpro/nanomig.cst
add_file tang/mega138kpro/nanomig.sdc
add_file fx68k/microrom.mem
add_file fx68k/nanorom.mem
add_file tg68k/TG68K_Pack.vhd
add_file tg68k/TG68K.vhd
add_file tg68k/TG68K_ALU.vhd
add_file tg68k/TG68KdotC_Kernel.vhd
add_file misc/amiga_xml.hex

set_option -synthesis_tool gowinsynthesis
set_option -output_base_name nanomig_tm138kpro
set_option -verilog_std sysv2017
set_option -top_module top
set_option -use_mspi_as_gpio 1
set_option -use_sspi_as_gpio 1
set_option -use_done_as_gpio 1
set_option -use_cpu_as_gpio 1
set_option -use_ready_as_gpio 1
set_option -use_jtag_as_gpio 0
set_option -use_mode_as_gpio 0
set_option -use_i2c_as_gpio 0
set_option -bit_compress 1
set_option -multi_boot 0
set_option -mspi_jump 0
set_option -cst_warn_to_error 1
set_option -loading_rate 70.000
set_option -place_option 1
set_option -route_option 2
#set_option -ireg_in_iob 0
#set_option -oreg_in_iob 0
#set_option -ioreg_in_iob 0

run all
