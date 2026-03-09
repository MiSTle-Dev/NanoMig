#ifndef SD_CARD_CONFIG_H
#define SD_CARD_CONFIG_H

#define TICKLEN   (0.5/28375160)

#define TB_NAME   Vnanomig_tb

#include "Vnanomig_tb.h"

#ifdef SD_CARD_CPP
const char *file_image[8] = {
  "./df0.adf",           // DF0
  NULL,                  // DF1
  NULL,                  // DF2
  NULL,                  // DH3
  NULL,                  // DH0
  NULL,                  // DH1
  NULL, NULL             // unused
};
#endif

#define MAX_DRIVES   6   // DF0-3/DH0-1

// enable to test direct mapping bypassing the companion if possible
// #define ENABLE_DIRECT_MAP

// enable writing of modified data back into image ... potentially corrupting it
// #define WRITE_BACK

// interface to sd card simulation
void sd_init(void);
void sd_handle(void);
void sd_get_sector(int drive, int lba, uint8_t *data);

// clocks the SD card claims to be busy before read data is returned
#define READ_BUSY_COUNT 1000

#endif
