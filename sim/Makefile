#
# Makefile
#

# SD_EMU=1   # set to enable sd card emulation

PRJ=nanomig

OBJ_DIR=obj_dir

# the original fx68k won't simulate. Thus we use this special version for simulation
FX68K_DIR=./fx68x_verilator
FX68K_FILES= fx68k.sv fx68kAlu.sv uaddrPla.sv fx68k_MicroRom.v fx68k_NanoRom.v

# Minimig-AGA
MINIMIG_DIR=../src/minimig-aga
MINIMIG_FILES=../nanomig.v amiga_clk.v cpu_wrapper.v minimig.v 
MINIMIG_FILES+=ciaa.v ciab.v cia_int.v cia_timera.v cia_timerb.v cia_timerd.v 
MINIMIG_FILES+=paula.v paula_uart.v paula_audio_channel.v paula_audio_mixer.v paula_audio.v paula_audio_volume.v paula_floppy_fifo.v paula_floppy.v paula_intcontroller.v
MINIMIG_FILES+=agnus.v agnus_audiodma.v agnus_blitter_adrgen.v agnus_blitter_minterm.v agnus_diskdma.v agnus_beamcounter.v agnus_blitter_barrelshifter.v agnus_blitter.v agnus_refresh.v agnus_bitplanedma.v agnus_blitter_fill.v agnus_copper.v agnus_spritedma.v
MINIMIG_FILES+=denise.v denise_bitplane_shifter.v denise_collision.v denise_colortable.v denise_playfields.v denise_sprites_shifter.v denise_bitplanes.v denise_hamgenerator.v denise_spritepriority.v denise_sprites.v denise_colortable_ram_mf.v
MINIMIG_FILES+=gary.v gayle.v ide.v minimig_m68k_bridge.v minimig_bankmapper.v minimig_sram_bridge.v minimig_syscontrol.v
MINIMIG_FILES+=../minimig/Amber.v userio.v
TB=nanomig_tb

MISC_DIR=../src/misc
MISC_FILES=video_analyzer.v

ifdef SD_EMU
MISC_FILES+=sd_rw.v sdcmd_ctrl.v
endif

VERILATOR_DIR=/usr/local/share/verilator/include
VERILATOR_FILES=verilated.cpp verilated_vcd_c.cpp verilated_threads.cpp

HDL_FILES=$(TB).v $(MINIMIG_FILES:%=$(MINIMIG_DIR)/%) $(FX68K_FILES:%=$(FX68K_DIR)/%) TG68KdotC_Kernel.v
HDL_FILES+=$(MISC_FILES:%=$(MISC_DIR)/%) 

EXTRA_CFLAGS = `sdl2-config --cflags` -DVIDEO
EXTRA_LDFLAGS = `sdl2-config --libs` -lSDL2_image

ifdef SD_EMU
EXTRA_CFLAGS+=-DSD_EMU
VERILATOR_FLAGS=-DSD_EMU
endif

all: $(PRJ)

$(PRJ): $(TB).cpp ${HDL_FILES} Makefile
	verilator -O3 -Wno-fatal --no-timing --trace-fst --threads 1 --trace-underscore  -top-module $(PRJ)_tb $(VERILATOR_FLAGS) -cc ${HDL_FILES} --exe $(TB).cpp -o ../$(PRJ) -CFLAGS "${EXTRA_CFLAGS}" -LDFLAGS "${EXTRA_LDFLAGS}"
	make -j -C ${OBJ_DIR} -f V$(PRJ)_tb.mk

$(PRJ).fst: $(PRJ)
	./$(PRJ)

run: $(PRJ)
	./$(PRJ)

wave: $(PRJ).fst
	gtkwave $(PRJ).gtkw

clean:
	rm -rf obj_dir $(PRJ)
