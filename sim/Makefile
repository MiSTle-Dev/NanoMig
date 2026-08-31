#
# Makefile
#

PRJ=nanomig

OBJ_DIR=obj_dir

# generic config defines
DEFINES = -DINFER_DPRAM
DEFINES += -DENABLE_TG68K
DEFINES += -DENABLE_CACHE
DEFINES += -DCHIPRAM_CACHE
DEFINES += -DCPU_SLOW14
DEFINES += -DDENISE_EBR
#DEFINES += -DNO_COMPANION -DIMAGE_SIZE=1048576 -DIMAGE_INDEX=0

# the original fx68k won't simulate. Thus we use this special version for simulation
FX68K_DIR=./fx68k
FX68K_FILES=fx68k.sv fx68kAlu.sv uaddrPla.sv

#TG68K_DIR=../src/tg68k/verilog
#TG68K_FILES=TG68K_ALU.v TG68KdotC_Kernel.v TG68K.v
TG68K_DIR=.
TG68K_FILES=TG68KdotC_Kernel.v

# Minimig-AGA
MINIMIG_DIR=../src/minimig-aga
MINIMIG_FILES=../nanomig.v amiga_clk.v cpu_wrapper.v cpu_cache_new.v dpram.v dpram_be_1024x16.v minimig.v 
MINIMIG_FILES+=bitplane_ram.v sprite_ram.v
MINIMIG_FILES+=ciaa.v ciab.v cia_int.v cia_timera.v cia_timerb.v cia_timerd.v 
MINIMIG_FILES+=paula.v paula_uart.v paula_audio_channel.v paula_audio_mixer.v paula_audio.v paula_audio_volume.v paula_floppy_fifo.v paula_floppy.v paula_intcontroller.v
MINIMIG_FILES+=agnus.v agnus_audiodma.v agnus_blitter_adrgen.v agnus_blitter_minterm.v agnus_diskdma.v agnus_beamcounter.v agnus_blitter_barrelshifter.v agnus_blitter.v agnus_refresh.v agnus_bitplanedma.v agnus_blitter_fill.v agnus_copper.v agnus_spritedma.v
MINIMIG_FILES+=denise.v denise_bitplane_shifter.v denise_collision.v denise_colortable.v denise_playfields.v denise_sprites_shifter.v denise_bitplanes.v denise_hamgenerator.v denise_spritepriority.v denise_sprites.v denise_colortable_ram_mf.v
MINIMIG_FILES+=gary.v gayle.v ide.v minimig_m68k_bridge.v minimig_bankmapper.v minimig_sram_bridge.v minimig_syscontrol.v
MINIMIG_FILES+=../minimig/Amber.v userio.v
TB=nanomig_tb

MISC_DIR=../src/misc
MISC_FILES=sd_card.v sd_rw.v sdcmd_ctrl.v sdram.sv

VERILATOR_DIR=/usr/local/share/verilator/include
VERILATOR_FILES=verilated.cpp verilated_vcd_c.cpp verilated_threads.cpp

HDL_FILES=$(TB).v sdr_chip_model.v $(MINIMIG_FILES:%=$(MINIMIG_DIR)/%) $(FX68K_FILES:%=$(FX68K_DIR)/%)
HDL_FILES+=$(MISC_FILES:%=$(MISC_DIR)/%)
HDL_FILES+=$(TG68K_FILES:%=$(TG68K_DIR)/%)

EXTRA_CFLAGS = `sdl2-config --cflags`
EXTRA_LDFLAGS = `sdl2-config --libs` -lSDL2_image

all: $(PRJ)

$(PRJ): $(TB).cpp sd_card.cpp sd_card_config.h ${HDL_FILES} Makefile
	cp ../src/fx68k/*.mem .
	verilator -O3 $(DEFINES) -Wno-fatal -Wno-BLKANDNBLK --no-timing --trace-fst --threads 1 --trace-underscore -I$(TG68K_DIR) -top-module $(PRJ)_tb $(VERILATOR_FLAGS) -cc ${HDL_FILES} --exe $(TB).cpp sd_card.cpp -o ../$(PRJ) -CFLAGS "${EXTRA_CFLAGS} ${DEFINES}" -LDFLAGS "${EXTRA_LDFLAGS}"
	make -j -C ${OBJ_DIR} -f V$(PRJ)_tb.mk

$(FX68K_DIR)/%.sv: ../src/fx68k/%.sv
	rm -rf $(FX68K_DIR)
	mkdir $(FX68K_DIR)
	cp -a ../src/fx68k/*.sv $(FX68K_DIR)
	patch -p1 < fx68k_sim.patch

$(PRJ).fst: $(PRJ)
	./$(PRJ)

run: $(PRJ)
	./$(PRJ)

wave: $(PRJ).fst
	gtkwave $(PRJ).gtkw

clean:
	rm -rf obj_dir $(FX68K_DIR) *.mem $(PRJ)
