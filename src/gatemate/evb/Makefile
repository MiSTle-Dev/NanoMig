TEST_CASE := nanomig
BOARD := evb

YOSYS_PARAM = -nomx8
YOSYS_DEFS  = -DGATEMATE -DINFER_DPRAM -DYOSYS -DDISABLE_IDE -DBOARD_FREQ_STR="10.0" -DBOARD_FREQ=10000000
YOSYS_DEFS +=  -DTMDS_BY_LOGIC

# enable 2k internal ROM and 2k internal RAM allowing to run the CPU without
# flash and sdram working correctly, ram is not needed for the basic blink_led rom
YOSYS_DEFS += -DENABLE_INT_ROM -DENABLE_INT_ROM_BLINK_LED # -DENABLE_INT_RAM 

# disable the entire system and only run the HDMI/DVI with a solid image
# YOSYS_DEFS += -DNO_SYS

TARGETS ?= impl
FPGA ?= CCGM1A1
TOP ?= top
FIRMWARE ?= firmware.bin
ROOT_DIR=$(dir $(lastword $(MAKEFILE_LIST)))
OFL   = openFPGALoader
NEXTPNR = nextpnr-himbaechel
YOSYS = yosys
GMPACK = gmpack
GMUNPACK = gmunpack
EQY_CLOCK = async2sync

VERILOG_FILES = $(BOARD).vh top.sv

HDMI_FILES = audio_clock_regeneration_packet.sv audio_info_frame.sv audio_sample_packet.sv auxiliary_video_information_info_frame.sv hdmi.sv packet_assembler.sv packet_picker.sv serializer.sv source_product_description_info_frame.sv tmds_channel.sv
VERILOG_FILES += $(HDMI_FILES:%=../../hdmi/%)

MISC_FILES = amiga_keymap.v flash_dspi.v hid.v mcu_spi.v osd_u8g2.v sd_card.v sdcmd_ctrl.v sdram.sv sd_rw.v sysctrl.v video_analyzer.v
VERILOG_FILES += $(MISC_FILES:%=../../misc/%)

FX68K_FILES += fx68k.sv fx68kAlu.sv uaddrPla.sv
VERILOG_FILES += $(FX68K_FILES:%=../../fx68k/%)

NANOMIG_FILES = nanomig.v
VERILOG_FILES += $(NANOMIG_FILES:%=../../%)

MINIMIG_FILES = Amber.v
VERILOG_FILES += $(MINIMIG_FILES:%=../../minimig/%)

MINIMIG_AGA_FILES = minimig.v amiga_clk.v cpu_wrapper.v userio.v
MINIMIG_AGA_FILES += minimig_m68k_bridge.v minimig_bankmapper.v minimig_sram_bridge.v
MINIMIG_AGA_FILES += gary.v minimig_syscontrol.v

MINIMIG_AGA_FILES += gayle.v ide.v

MINIMIG_AGA_FILES += paula.v paula_uart.v paula_intcontroller.v paula_floppy.v paula_audio.v
MINIMIG_AGA_FILES += paula_audio_channel.v paula_audio_mixer.v paula_floppy_fifo.v
MINIMIG_AGA_FILES += paula_audio_volume.v

MINIMIG_AGA_FILES += ciaa.v ciab.v cia_int.v cia_timera.v cia_timerb.v cia_timerd.v cia_int.v

MINIMIG_AGA_FILES += agnus.v
MINIMIG_AGA_FILES += agnus_refresh.v agnus_diskdma.v agnus_audiodma.v agnus_bitplanedma.v
MINIMIG_AGA_FILES += agnus_spritedma.v agnus_copper.v agnus_blitter.v agnus_beamcounter.v
MINIMIG_AGA_FILES += agnus_blitter_barrelshifter.v agnus_blitter_minterm.v agnus_blitter_fill.v agnus_blitter_adrgen.v

MINIMIG_AGA_FILES += denise.v
MINIMIG_AGA_FILES += denise_bitplanes.v denise_playfields.v denise_sprites.v
MINIMIG_AGA_FILES += denise_spritepriority.v denise_colortable.v denise_hamgenerator.v
MINIMIG_AGA_FILES += denise_collision.v denise_bitplane_shifter.v denise_sprites_shifter.v
MINIMIG_AGA_FILES += denise_colortable_ram_mf.v

VERILOG_FILES += $(MINIMIG_AGA_FILES:%=../../minimig-aga/%)

define check_cc_tool
  $(if $(CC_TOOL), \
    $(eval P_R := $(CC_TOOL)/bin/p_r/p_r), \
    $(error CC_TOOL variable is not set))
endef

ifndef BOARD
$(error BOARD variable is not set)
endif

OFL_BOARD=-b gatemate_evb_jtag
FREQ = 10

ifdef SEED
SEED_OPT=--seed $(SEED)
endif

ifdef MULTICLOCK
EQY_CLOCK=clk2fflogic
endif

ifdef YOSYS_DEFS
YOSYS_DEFS_OPT=verilog_defines $(YOSYS_DEFS);
endif

SDC_OPT ?=
ifneq ($(wildcard constraints.sdc),)
SDC_OPT = --sdc constraints.sdc
endif

//NEXTPNR_PARAMS ?= --vopt clk-cp
//NEXTPNR_PARAMS ?= --vopt no-bridges --vopt clk-cp --vopt no-cpe-cp
NEXTPNR_PARAMS ?=
ifdef DIE
NEXTPNR_PARAMS = --vopt force_die=$(DIE)
endif
ifdef STRATEGY
NEXTPNR_PARAMS += --vopt strategy=$(STRATEGY)
endif

all: nextpnr

help:
        @echo "Use one of targets for '$(BOARD)' board:"
	@echo " - json - Yosys for nextpnr"
	@echo " - nextpnr - Yosys + nextpnr"
	@echo " - jtag - programming bitstream produced by nextpnr"
	@echo " - post - generate post pnr verilog netlist by nextpnr"
	@exit

json: $(TEST_CASE).json

$(TEST_CASE).json $(TEST_CASE)_ys.v: $(VERILOG_FILES)
	@echo "Running Yosys"
	@$(YOSYS) -l synth.log -p 'read_slang $(YOSYS_DEFS) -y../../test_roms --ignore-timing $^; synth_gatemate $(YOSYS_PARAM) -luttree -top $(TOP) -json $(TEST_CASE).json; write_verilog -norename -noattr $(TEST_CASE)_ys.v'

$(TEST_CASE)_$(BOARD).txt $(TEST_CASE)_$(BOARD)_pnr.json: $(TEST_CASE).json $(BOARD).ccf
	@echo "Running nextpnr for '$(BOARD)' board"
	$(NEXTPNR) --device $(FPGA) --json $(TEST_CASE).json --vopt ccf=$(BOARD).ccf --vopt out=$(TEST_CASE)_$(BOARD).txt --router router2 --freq $(FREQ) $(SEED_OPT) $(SDC_OPT) --write $(TEST_CASE)_$(BOARD)_pnr.json --timing-allow-fail --sdf $(TEST_CASE)_$(BOARD).sdf --placer-heap-beta 0.9 --vopt time_mode=typical $(NEXTPNR_PARAMS)

nextpnr: $(TEST_CASE)_$(BOARD).txt

post: $(TEST_CASE)_$(BOARD)_pnr.v

jtag: $(TEST_CASE)_$(BOARD).txt
	@echo "Running openFPGALoader for '$(BOARD)' board"
	$(GMPACK) $(TEST_CASE)_$(BOARD).txt $(TEST_CASE)_$(BOARD).bit
	$(OFL) $(OFL_BOARD) --index-chain 0 $(TEST_CASE)_$(BOARD).bit

$(TEST_CASE)_$(BOARD)_pnr.v: $(TEST_CASE)_$(BOARD).txt
	@echo "Generate post PnR Verilog netlist"
	@$(YOSYS) -q -p 'read_json $(TEST_CASE)_$(BOARD)_pnr.json; write_verilog -norename -noattr $(TEST_CASE)_$(BOARD)_pnr.v'

firmware: $(FIRMWARE)
	@echo "Running openFPGALoader to program '$(FIRMWARE)' on '$(BOARD)' board"
	@$(OFL) $(OFL_BOARD) --index-chain 0 -f -o 1048576 $(FIRMWARE)

clean:
	@rm -rf *.log *_synth.v *.history *.txt *.refwire *.refparam *_ys.v *~
	@rm -rf *.refcomp *.pos *.pathes *.path_struc *.net *.id *.prn
	@rm -rf *_00.v *.used *.sdf *.place *.pin *.cfg *.bit  *.cdf *.idh *.min *.json
	@rm -rf *_pnr.v

force-nextpnr:
	$(NEXTPNR) --device $(FPGA) --json $(TEST_CASE).json --vopt ccf=$(BOARD).ccf --vopt out=../logs/$(TEST_CASE)_$(BOARD)_$(SEED).txt --router router2 --freq $(FREQ) $(SEED_OPT) $(SDC_OPT) --placer-heap-beta 0.2 --vopt time_mode=typical $(NEXTPNR_PARAMS)

.PHONY: synth json pr nextpnr force-nextpnr jtag unpack
