#ifndef SD_CARD_CONFIG_H
#define SD_CARD_CONFIG_H

#define TICKLEN   (0.5/28375160)

#define TB_NAME   Vnanomig_tb

#include "Vnanomig_tb.h"

#ifdef SD_CARD_CPP
const char *file_image[8] = {
  "../disks/wb13.adf",         // DF0
  NULL,                        // DF1
  NULL,                        // DF2
  NULL,                        // DH3
  NULL, // "../disks/dh0.hdf",                        // DH0
  NULL,                        // DH1
  NULL, NULL                   // unused
};

const char *rom_image[8] = {
  NULL, //  "kick13.rom",
  NULL, NULL, NULL, NULL, NULL, NULL, NULL
};
#endif

#define MAX_DRIVES   6   // DF0-3/DH0-1
#define MAX_ROMS     1

// enable to test direct mapping bypassing the companion if possible
#define ENABLE_DIRECT_MAP

// enable writing of modified data back into image ... potentially corrupting it
// #define WRITE_BACK

// enable this to simulate a FPGA Companion constantly writing and reading data,
// potentially colliding with the Core's own accesses
// #define FC_RW_STORM

// interface to sd card simulation
void sd_init(void);
void sd_handle(void);
void sd_get_sector(int drive, int lba, uint8_t *data);

void hexdump(void *data, int size);
void hexdiff(void *data1, void *data2, int size);

// clocks the SD card claims to be busy before read data is returned
#define READ_BUSY_COUNT 1000

#endif
