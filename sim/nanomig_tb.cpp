/*
  nanomig_aga_tb.cpp 

  NanoMig verilator environment. This is being used to test certain
  aspects of NanoMig in verilator. Since Minimig itself is pretty
  mature this is mainly used to test things that have been changed for
  NanoMig which mainly is the fx68k CPU integration, RAM and ROM
  handling and especially the floppy disk handling-

  This code is an ugly mess as it's just written on the fly to test
  certain things. It's not meant to be nice or clean. But maybe
  someone find this useful anyway.
 */

#ifdef VIDEO
#include <SDL.h>
#include <SDL_image.h>
// one frame is 20.0326ms
#endif

#include "Vnanomig_tb.h"
#include "verilated.h"
#include "verilated_fst_c.h"

// #define KICK "kick12.rom" 
#define KICK "kick13.rom" 
// #define KICK "kick31.rom" 
// #define KICK "DiagROM/DiagROM"
// #define KICK "../src/ram_test/ram_test.bin"
// #define KICK "test_rom/test_rom.bin"

// fdc test also enables ide
#define FDC_TEST

#ifdef FDC_TEST
#define FLOPPY_ADF  "../disks/fdwrtest.adf"
// #define FLOPPY_ADF  "../disks/wb13.adf"
// #define FLOPPY_ADF  "Getaway_A.adf"
// #define FLOPPY_ADF  "random.adf"

// #define HARDDISK0_HDF   "../disks/AGS_NanoMig.HDF"
// #define HARDDISK0_HDF   "../disks/dh0.hdf"
// #define HARDDISK1_HDF   "../disks/dh1.hdf"

// #define FDC_RAM_TEST_VERIFY   // verify track data against minimigs original firmware fdd.c. only works with ram_test rom
FILE *adf_fd = NULL;
FILE *hdf_fd[] = { NULL, NULL };
#endif

// #define UART_ONLY

// with turbo kick, some vpos test exits with error

// this can be used to write (Kick) memory access patterns into a file. This can
// be used to verify the access in a different run to e.g. verify that faster
// memory access still produces the same access pattern
#define MEMTRACE  0   // 0 = no tracing, 1 = create, 2 = verify

static Vnanomig_tb *tb;
static VerilatedFstC *trace;
static double simulation_time;

#define TICKLEN   (0.5/28375160)

// specfiy simulation runtime and from which point in time a trace should
// be written
//#define TRACESTART   0
//#define TRACESTART   0.22
//#define TRACESTART   0.44
//#define TRACESTART   0.87
//#define TRACESTART   2.8
//#define TRACESTART   5.7    // floppy read
//#define TRACESTART   3.750
//#define TRACESTART   3.800

// for ECHO "Hello"
// #define TRACESTART   8.580
// #define TRACESTART   8.610

// for COPY Disk.info to Nase.info
// 8.739 // read Disk.info
// 8.814 // write Nase.info
// #define TRACESTART   8.810
// #define TRACESTART   8.740
#define TRACESTART   10.9   // FDC write

#ifdef TRACESTART
#define TRACEEND     (TRACESTART + 0.15)   // 0.1s ~ 1G
#endif

// #define TRACEEND     (60.0)

// with turbo kick:
// 1432.701 ms, LED off 

// kick13 events:
// 80ms -> hardware is out of sysctrl reset
// 330ms -> screen darkgrey
// 1540ms -> screen lightgrey
// 2489ms -> power led on
// 2500ms -> screen white
// 4235ms -> first fdd selection
// 4256ms -> first fdd read attempt
// 4560ms -> floppy/hand if no disk
// 6000ms -> second floppy access if first one was successful
// 10750ms -> workbench 1.3 draws blue AmigaDOS window
// 22000ms -> no clock found
// 54000ms -> workbench opens

// kick31
// 783ms   -> first ide cs
// 2773ms  -> first gayle selection

/* =============================== video =================================== */

#ifdef VIDEO

// This is the max texture size we can handle. The actual size at 28Mhz sampling rate
// and without scan doubler will be 1816x313 since the actual pixel clock is only 7Mhz.
// With scandoubler it will be 908x626. The aspect ratio will be adjusted to the
// window and thus the image will not looked stretched.
#define MAX_H_RES   2048
#define MAX_V_RES   1024

SDL_Window*   sdl_window   = NULL;
SDL_Renderer* sdl_renderer = NULL;
SDL_Texture*  sdl_texture  = NULL;
int sdl_cancelled = 0;

typedef struct Pixel {  // for SDL texture
    uint8_t a;  // transparency
    uint8_t b;  // blue
    uint8_t g;  // green
    uint8_t r;  // red
} Pixel;

#define SCALE 1
Pixel screenbuffer[MAX_H_RES*MAX_V_RES];

void init_video(void) {
  if (SDL_Init(SDL_INIT_VIDEO) < 0) {
    printf("SDL init failed.\n");
    return;
  }

  // start with a 454x313 or scandoubed 908x626screen
  sdl_window = SDL_CreateWindow("Nanomig", SDL_WINDOWPOS_CENTERED,
        SDL_WINDOWPOS_CENTERED, SCALE*454, SCALE*313, SDL_WINDOW_RESIZABLE | SDL_WINDOW_SHOWN);
  if (!sdl_window) {
    printf("Window creation failed: %s\n", SDL_GetError());
    return;
  }
  
  sdl_renderer = SDL_CreateRenderer(sdl_window, -1,
            SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
  if (!sdl_renderer) {
    printf("Renderer creation failed: %s\n", SDL_GetError());
    return;
  }
}

// https://stackoverflow.com/questions/34255820/save-sdl-texture-to-file
void save_texture(SDL_Renderer *ren, SDL_Texture *tex, const char *filename) {
    SDL_Texture *ren_tex = NULL;
    SDL_Surface *surf = NULL;
    int w, h;
    int format = SDL_PIXELFORMAT_RGBA32;;
    void *pixels = NULL;

    /* Get information about texture we want to save */
    int st = SDL_QueryTexture(tex, NULL, NULL, &w, &h);
    if (st != 0) { SDL_Log("Failed querying texture: %s\n", SDL_GetError()); goto cleanup; }

    // adjust aspect ratio
    while(w > 2*h) w/=2;
    
    ren_tex = SDL_CreateTexture(ren, format, SDL_TEXTUREACCESS_TARGET, w, h);
    if (!ren_tex) { SDL_Log("Failed creating render texture: %s\n", SDL_GetError()); goto cleanup; }

    /* Initialize our canvas, then copy texture to a target whose pixel data we can access */
    st = SDL_SetRenderTarget(ren, ren_tex);
    if (st != 0) { SDL_Log("Failed setting render target: %s\n", SDL_GetError()); goto cleanup; }

    SDL_SetRenderDrawColor(ren, 0x00, 0x00, 0x00, 0x00);
    SDL_RenderClear(ren);

    st = SDL_RenderCopy(ren, tex, NULL, NULL);
    if (st != 0) { SDL_Log("Failed copying texture data: %s\n", SDL_GetError()); goto cleanup; }

    /* Create buffer to hold texture data and load it */
    pixels = malloc(w * h * SDL_BYTESPERPIXEL(format));
    if (!pixels) { SDL_Log("Failed allocating memory\n"); goto cleanup; }

    st = SDL_RenderReadPixels(ren, NULL, format, pixels, w * SDL_BYTESPERPIXEL(format));
    if (st != 0) { SDL_Log("Failed reading pixel data: %s\n", SDL_GetError()); goto cleanup; }

    /* Copy pixel data over to surface */
    surf = SDL_CreateRGBSurfaceWithFormatFrom(pixels, w, h, SDL_BITSPERPIXEL(format), w * SDL_BYTESPERPIXEL(format), format);
    if (!surf) { SDL_Log("Failed creating new surface: %s\n", SDL_GetError()); goto cleanup; }

    /* Save result to an image */
    st = IMG_SavePNG(surf, filename);
    if (st != 0) { SDL_Log("Failed saving image: %s\n", SDL_GetError()); goto cleanup; }
    
    // SDL_Log("Saved texture as PNG to \"%s\" sized %dx%d\n", filename, w, h);

cleanup:
    SDL_FreeSurface(surf);
    free(pixels);
    SDL_DestroyTexture(ren_tex);
}

void capture_video(void) {
  static int last_hs_n = -1;
  static int last_vs_n = -1;
  static int sx = 0;
  static int sy = 0;
  static int frame = 0;
  static int frame_line_len = 0;
  
  // store pixel
  if(sx < MAX_H_RES && sy < MAX_V_RES) {  
    Pixel* p = &screenbuffer[sy*MAX_H_RES + sx];
    p->a = 0xFF;  // transparency
    p->b = tb->blue<<4;
    p->g = tb->green<<4;
    p->r = tb->red<<4;
  }
  sx++;
    
  if(tb->hs_n != last_hs_n) {
    last_hs_n = tb->hs_n;

    // trigger on rising hs edge
    if(tb->hs_n) {
      // no line in this frame detected, yet
      if(frame_line_len >= 0) {
	if(frame_line_len == 0)
	  frame_line_len = sx;
	else {
	  if(frame_line_len != sx) {
	    printf("frame line length unexpectedly changed from %d to %d\n", frame_line_len, sx);
	    frame_line_len = -1;	  
	  }
	}
      }
      
      sx = 0;
      sy++;
    }    
  }

  if(tb->vs_n != last_vs_n) {
    last_vs_n = tb->vs_n;

    // trigger on rising vs edge
    if(tb->vs_n) {
      // draw frame if valid
      if(frame_line_len > 0) {
	
	// check if current texture matches the frame size
	if(sdl_texture) {
	  int w=-1, h=-1;
	  SDL_QueryTexture(sdl_texture, NULL, NULL, &w, &h);
	  if(w != frame_line_len || h != sy) {
	    SDL_DestroyTexture(sdl_texture);
	    sdl_texture = NULL;
	  }
	}
	  
	if(!sdl_texture) {
	  sdl_texture = SDL_CreateTexture(sdl_renderer, SDL_PIXELFORMAT_RGBA8888,
					  SDL_TEXTUREACCESS_TARGET, frame_line_len, sy);
	  if (!sdl_texture) {
	    printf("Texture creation failed: %s\n", SDL_GetError());
	    sdl_cancelled = 1;
	  }
	}
	
	if(sdl_texture) {	
	  SDL_UpdateTexture(sdl_texture, NULL, screenbuffer, MAX_H_RES*sizeof(Pixel));
	  
	  SDL_RenderClear(sdl_renderer);
	  SDL_RenderCopy(sdl_renderer, sdl_texture, NULL, NULL);
	  SDL_RenderPresent(sdl_renderer);

	  char name[32];
	  sprintf(name, "screenshots/frame%04d.png", frame);
	  save_texture(sdl_renderer, sdl_texture, name);
	}
      }
	
      // process SDL events
      SDL_Event event;
      while( SDL_PollEvent( &event ) ){
	if(event.type == SDL_QUIT)
	  sdl_cancelled = 1;
	
	if(event.type == SDL_KEYDOWN && event.key.keysym.sym == SDLK_ESCAPE)
	    sdl_cancelled = 1;
      }
      
#ifndef UART_ONLY
      printf("%.3fms frame %d is %dx%d\n", simulation_time*1000, frame, frame_line_len, sy);
#endif

      frame++;
      frame_line_len = 0;
      sy = 0;
    }    
  }
}
#endif

void hexdump(void *data, int size) {
  int i, b2c;
  int n=0;
  char *ptr = (char*)data;

  if(!size) return;

  while(size>0) {
    printf("%04x: ", n);

    b2c = (size>16)?16:size;
    for(i=0;i<b2c;i++)      printf("%02x ", 0xff&ptr[i]);
    printf("  ");
    for(i=0;i<(16-b2c);i++) printf("   ");
    for(i=0;i<b2c;i++)      printf("%c", isprint(ptr[i])?ptr[i]:'.');
    printf("\n");

    ptr  += b2c;
    size -= b2c;
    n    += b2c;
  }
}

static uint64_t GetTickCountMs() {
  struct timespec ts;
  
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (uint64_t)(ts.tv_nsec / 1000000) + ((uint64_t)ts.tv_sec * 1000ull);
}

unsigned short ram[8*512*1024];  // 8 Megabytes

void load_kick(void) {
  printf("Loading kick into last 512k of 8MB ram\n");
  FILE *fd = fopen(KICK, "rb");
  if(!fd) { perror("load kick"); exit(-1); }
  
  int len = fread(ram+(0x780000/2), 1024, 512, fd);
  if(len != 512) {
    if(len != 256) {
      printf("256/512k kick read failed\n");
    } else {
      // just read a second image
      fseek(fd, 0, SEEK_SET);
      len = fread(ram+(0x780000/2)+128*1024, 1024, 256, fd);
      if(len != 256) { printf("2nd read failed\n"); exit(-1); }
    }
  }
  fclose(fd);
}

#ifdef FDC_TEST
// code taken from minimig firmware fdd.c
#define TRACK_SIZE 12668
#define HEADER_SIZE 0x40
#define DATA_SIZE 0x400
#define SECTOR_SIZE (HEADER_SIZE + DATA_SIZE)
#define SECTOR_COUNT 11
#define LAST_SECTOR (SECTOR_COUNT - 1)
#define GAP_SIZE (TRACK_SIZE - SECTOR_COUNT * SECTOR_SIZE)

unsigned char track_buffer[TRACK_SIZE];

void SPI(int data) {
  static int cnt = 0;

  if(data == -1) {
    printf("resetting buffer\n");
    cnt=0;
    return;
  }
  
  // we may receive more than a full track. This happens if the software
  // requests more than 12668 bytes. The track then wraps and starts
  // transmitting from the track start again ...
  // We ignore this data on minimig size and wrap accordingly during
  // comparison
  if(cnt >= TRACK_SIZE) {
    // printf("Track buffer overflow by %d\n", cnt - TRACK_SIZE);
    cnt++;
    return;
  }
  
  track_buffer[cnt++] = data;  
  if(cnt == TRACK_SIZE) {
    printf("Minimig: complete firmware generated track in buffer\n");
#if 0
    // dump a single sector and header split into data and clock
    for(int i=0;i<SECTOR_SIZE;i) {
      printf("%04x:", i);
#if 0
      // print hex words
      for(int j=0;j<8;j++,i+=2) {
	unsigned short w = 256*track_buffer[i]+track_buffer[i+1];	
	printf(" %04x", w);
      }
#else
      // print data split clock and data bytes
      for(int j=0;j<8;j++,i+=2) {
	unsigned short w = 256*track_buffer[i]+track_buffer[i+1];
	unsigned char b =
	  ((w&0x8000)>>8)|((w&0x2000)>>7)|((w&0x0800)>>6)|((w&0x0200)>>5)|
	  ((w&0x0080)>>4)|((w&0x0020)>>3)|((w&0x0008)>>2)|((w&0x0002)>>1);	
	printf(" %02x", b);
      }

      printf(" ");
      i-=16;
      
      for(int j=0;j<8;j++,i+=2) {
	unsigned short w = 256*track_buffer[i]+track_buffer[i+1];
	unsigned char b =
	  ((w&0x4000)>>7)|((w&0x1000)>>6)|((w&0x0400)>>5)|((w&0x0100)>>4)|
	  ((w&0x0040)>>3)|((w&0x0100)>>2)|((w&0x0004)>>1)|((w&0x0001)>>0);	
	printf(" %02x", b);
      }
#endif      
      printf("\n");
    }    
#endif
  }
}

void SendSector(unsigned char *pData, unsigned char sector, unsigned char track,
		unsigned char dsksynch, unsigned char dsksyncl)
{
    unsigned char header_checksum[4];
    unsigned char data_checksum[4];
    unsigned short i;
    unsigned char x;
    unsigned char *p;

    // preamble
    SPI(0xAA);
    SPI(0xAA);
    SPI(0xAA);
    SPI(0xAA);

    // synchronization
    SPI(dsksynch);
    SPI(dsksyncl);
    SPI(dsksynch);
    SPI(dsksyncl);

    // odd bits of header
    x = 0x55;
    header_checksum[0] = x;
    SPI(x);
    x = track >> 1 & 0x55;
    header_checksum[1] = x;
    SPI(x);
    x = sector >> 1 & 0x55;
    header_checksum[2] = x;
    SPI(x);
    x = 11 - sector >> 1 & 0x55;
    header_checksum[3] = x;
    SPI(x);

    // even bits of header
    x = 0x55;
    header_checksum[0] ^= x;
    SPI(x);
    x = track & 0x55;
    header_checksum[1] ^= x;
    SPI(x);
    x = sector & 0x55;
    header_checksum[2] ^= x;
    SPI(x);
    x = 11 - sector & 0x55;
    header_checksum[3] ^= x;
    SPI(x);

    // sector label and reserved area (changes nothing to checksum)
    i = 0x20;
    while (i--)
        SPI(0xAA);

    // send header checksum
    SPI(0xAA);
    SPI(0xAA);
    SPI(0xAA);
    SPI(0xAA);
    SPI(header_checksum[0] | 0xAA);
    SPI(header_checksum[1] | 0xAA);
    SPI(header_checksum[2] | 0xAA);
    SPI(header_checksum[3] | 0xAA);

    // calculate data checksum
    data_checksum[0] = 0;
    data_checksum[1] = 0;
    data_checksum[2] = 0;
    data_checksum[3] = 0;
    p = pData;
    i = DATA_SIZE / 2 / 4;
    while (i--)
    {
        x = *p++;
        data_checksum[0] ^= x ^ x >> 1;
        x = *p++;
        data_checksum[1] ^= x ^ x >> 1;
        x = *p++;
        data_checksum[2] ^= x ^ x >> 1;
        x = *p++;
        data_checksum[3] ^= x ^ x >> 1;
    }

    // send data checksum
    SPI(0xAA);
    SPI(0xAA);
    SPI(0xAA);
    SPI(0xAA);
    SPI(data_checksum[0] | 0xAA);
    SPI(data_checksum[1] | 0xAA);
    SPI(data_checksum[2] | 0xAA);
    SPI(data_checksum[3] | 0xAA);

    // odd bits of data field
    i = DATA_SIZE / 2;
    p = pData;
    while (i--)
        SPI(*p++ >> 1 | 0xAA);

    // even bits of data field
    i = DATA_SIZE / 2;
    p = pData;
    while (i--)
      SPI(*p++ | 0xAA);

#if 0
    printf("header checksum: %02x/%02x/%02x/%02x\n",
           header_checksum[0] | 0xAA,header_checksum[1] | 0xAA,
           header_checksum[2] | 0xAA,header_checksum[3] | 0xAA);
    
    printf("data checksum: %02x/%02x/%02x/%02x\n",
           data_checksum[0] | 0xAA,data_checksum[1] | 0xAA,
           data_checksum[2] | 0xAA,data_checksum[3] | 0xAA);   
#endif
}

void SendGap(void) {
  unsigned short i = GAP_SIZE;
  while (i--)
    SPI(0xAA);
}

static unsigned char sector_buffer[11][512];

void build_track_buffer(int sector, unsigned char *data) {
  static int last_track = -1;
  
  int track_sec = sector % 11;   // sector within track

  if(sector/11 != last_track) {
    printf("track now %d\n", sector/11);
    last_track = sector/11;
    SPI(-1);
  }

  printf("Loading track %d, side %d, sector %d\n", sector/22, (sector/11)%2, sector%11);
  
  if(!data) {
    fseek(adf_fd, sector*512, SEEK_SET);
    if(fread(sector_buffer[track_sec], 1, 512, adf_fd) != 512) {  perror("read error"); return; }
  } else
    memcpy(sector_buffer[track_sec], data, 512);

  SendSector(sector_buffer[track_sec], track_sec, sector/11, 0x44, 0x89);

  // send GAP after last sector
  if(track_sec == 10)
    SendGap();
}

// The ram_test programs the hardware to sync onto 0x4489. This
// will result in the first 6 bytes not being written to ram
#define FDC_SKIP 6

#ifdef SD_EMU
// Calculate CRC7
// It's a 7 bit CRC with polynomial x^7 + x^3 + 1
// input:
//   crcIn - the CRC before (0 for first step)
//   data - byte for CRC calculation
// return: the new CRC7
uint8_t CRC7_one(uint8_t crcIn, uint8_t data) {
  const uint8_t g = 0x89;
  uint8_t i;

  crcIn ^= data;
  for (i = 0; i < 8; i++) {
    if (crcIn & 0x80) crcIn ^= g;
    crcIn <<= 1;
  }
  
  return crcIn;
}

// Calculate CRC16 CCITT
// It's a 16 bit CRC with polynomial x^16 + x^12 + x^5 + 1
// input:
//   crcIn - the CRC before (0 for rist step)
//   data - byte for CRC calculation
// return: the CRC16 value
uint16_t CRC16_one(uint16_t crcIn, uint8_t data) {
  crcIn  = (uint8_t)(crcIn >> 8)|(crcIn << 8);
  crcIn ^=  data;
  crcIn ^= (uint8_t)(crcIn & 0xff) >> 4;
  crcIn ^= (crcIn << 8) << 4;
  crcIn ^= ((crcIn & 0xff) << 4) << 1;
  
  return crcIn;
}

uint8_t getCRC(unsigned char cmd, unsigned long arg) {
  uint8_t CRC = CRC7_one(0, cmd);
  for (int i=0; i<4; i++) CRC = CRC7_one(CRC, ((unsigned char*)(&arg))[3-i]);
  return CRC;
}

uint8_t getCRC_bytes(unsigned char *data, int len) {
  uint8_t CRC = 0;
  while(len--) CRC = CRC7_one(CRC, *data++);
  return CRC;  
}

unsigned long long reply(unsigned char cmd, unsigned long arg) {
  unsigned long r = 0;
  r |= ((unsigned long long)cmd) << 40;
  r |= ((unsigned long long)arg) << 8;
  r |= getCRC(cmd, arg);
  r |= 1;
  return r;
}

#define OCR  0xc0ff8000  // not busy, CCS=1(SDHC card), all voltage, not dual-voltage card
#define RCA  0x0013

// total cid respose is 136 bits / 17 bytes
unsigned char cid[17] = "\x3f" "\x02TMS" "A08G" "\x14\x39\x4a\x67" "\xc7\x00\xe4";

void sd_handle()  {
  static int last_sdclk = -1;
  static unsigned long sector = 0xffffffff;
  static unsigned long long flen;
  static FILE *fd = NULL;
  static uint8_t sector_data[520];   // 512 bytes + four 16 bit crcs
  static long long cmd_in = -1;
  static long long cmd_out = -1;
  static unsigned char *cmd_ptr = 0;
  static int cmd_bits = 0;
  static unsigned char *dat_ptr = 0;
  static int dat_bits = 0;
  static int last_was_acmd = 0;
  
  if(tb->sdclk != last_sdclk) {
    // rising sd card clock edge
    if(tb->sdclk) {
      cmd_in = ((cmd_in << 1) | tb->sdcmd) & 0xffffffffffffll;

      // sending 4 data bits
      if(dat_ptr && dat_bits) {
        if(dat_bits == 128*8 + 16 + 1 + 1) {
          // card sends start bit
          tb->sddat_in = 0;
          printf("READ-4 START\n");
        } else if(dat_bits > 1) {
          if(dat_bits == 128*8 + 16 + 1) printf("READ DATA START\n");
          if(dat_bits == 1) printf("READ DATA END\n");
          int nibble = dat_bits&1;   // 1: high nibble, 0: low nibble
          if(nibble) tb->sddat_in = (*dat_ptr >> 4)&15;
          else       tb->sddat_in = *dat_ptr++ & 15;
        } else
	  tb->sddat_in = 15;
	
        dat_bits--;
      }
      
      if(cmd_ptr && cmd_bits) {
        int bit = 7-((cmd_bits-1) & 7);
        tb->sdcmd_in = (*cmd_ptr & (0x80>>bit))?1:0;
        if(bit == 7) cmd_ptr++;
        cmd_bits--;
      } else {      
        tb->sdcmd_in = (cmd_out & (1ll<<47))?1:0;
        cmd_out = (cmd_out << 1)|1;
      }
      
      // check if bit 47 is 0, 46 is 1 and 0 is 1
      if( !(cmd_in & (1ll<<47)) && (cmd_in & (1ll<<46)) && (cmd_in & (1ll<<0))) {
        unsigned char cmd  = (cmd_in >> 40) & 0x7f;
        unsigned long arg  = (cmd_in >>  8) & 0xffffffff;
        unsigned char crc7 = cmd_in & 0xfe;
	
        // r1 reply:
        // bit 7 - 0
        // bit 6 - parameter error
        // bit 5 - address error
        // bit 4 - erase sequence error
        // bit 3 - com crc error
        // bit 2 - illegal command
        // bit 1 - erase reset
        // bit 0 - in idle state

        if(crc7 == getCRC(cmd, arg)) {
          printf("%cCMD %2d, ARG %08lx\n", last_was_acmd?'A':' ', cmd & 0x3f, arg);
          switch(cmd & 0x3f) {
          case 0:  // Go Idle State
            break;
          case 8:  // Send Interface Condition Command
            cmd_out = reply(8, arg);
            break;
          case 55: // Application Specific Command
            cmd_out = reply(55, 0);
            break;
          case 41: // Send Host Capacity Support
            cmd_out = reply(63, OCR);
            break;
          case 2:  // Send CID
            cid[16] = getCRC_bytes(cid, 16) | 1;  // Adjust CRC
            cmd_ptr = cid;
            cmd_bits = 136;
            break;
           case 3:  // Send Relative Address
            cmd_out = reply(3, (RCA<<16) | 0);  // status = 0
            break;
          case 7:  // select card
            cmd_out = reply(7, 0);    // may indicate busy          
            break;
          case 6:  // set bus width
            printf("Set bus width to %ld\n", arg);
            cmd_out = reply(6, 0);
            break;
          case 16: // set block len (should be 512)
            printf("Set block len to %ld\n", arg);
            cmd_out = reply(16, 0);    // ok
            break;
          case 17:  // read block
            printf("Request to read single block %ld\n", arg);
            cmd_out = reply(17, 0);    // ok

            // load sector
            {
	      // check for floppy data request
	      if(!fd) {
		fd = fopen(FLOPPY_ADF, "rb");
		if(!fd) { perror("OPEN ERROR"); exit(-1); }
		fseek(fd, 0, SEEK_END);
		flen = ftell(fd);
		printf("Image size is %lld\n", flen);
		fseek(fd, 0, SEEK_SET);
	      }
	      
              fseek(fd, 512 * arg, SEEK_SET);
              int items = fread(sector_data, 2, 256, fd);
              if(items != 256) perror("fread()");

	      // trigger minimig MFM encoding for comparison
	      build_track_buffer(arg, sector_data);
            }
            {
              unsigned short crc[4] = { 0,0,0,0 };
              unsigned char dbits[4];
              for(int i=0;i<512;i++) {
                // calculate the crc for each data line seperately
                for(int c=0;c<4;c++) {
                  if((i & 3) == 0) dbits[c] = 0;
                  dbits[c] = (dbits[c] << 2) | ((sector_data[i]&(0x10<<c))?2:0) | ((sector_data[i]&(0x01<<c))?1:0);      
                  if((i & 3) == 3) crc[c] = CRC16_one(crc[c], dbits[c]);
                }
              }

              printf("SDC CRC = %04x/%04x/%04x/%04x\n", crc[0], crc[1], crc[2], crc[3]);

              // append crc's to sector_data
              for(int i=0;i<8;i++) sector_data[512+i] = 0;
              for(int i=0;i<16;i++) {
                int crc_nibble =
                  ((crc[0] & (0x8000 >> i))?1:0) +
                  ((crc[1] & (0x8000 >> i))?2:0) +
                  ((crc[2] & (0x8000 >> i))?4:0) +
                  ((crc[3] & (0x8000 >> i))?8:0);

                sector_data[512+i/2] |= (i&1)?(crc_nibble):(crc_nibble<<4);
              }
            }
            dat_ptr = sector_data;
            dat_bits = 128*8 + 16 + 1 + 1;
	    break;
            
          default:
            printf("unexpected command\n");
          }

          last_was_acmd = (cmd & 0x3f) == 55;
          
          cmd_in = -1;
        } else
          printf("CMD %02x, ARG %08lx, CRC7 %02x != %02x!!\n", cmd, arg, crc7, getCRC(cmd, arg));         
      }      
    }      
    last_sdclk = tb->sdclk;     
  }
}      
#endif
#endif
 
#if MEMTRACE > 0
FILE *mem_fd = NULL;
#endif

#define RDB_U32(a)  (((unsigned long)(sector_buffer[0][4*(a)])<<24) + ((unsigned long)(sector_buffer[0][4*(a)+1])<<16) + ((unsigned long)(sector_buffer[0][4*(a)+2])<<8) + (unsigned long)(sector_buffer[0][4*(a)+3]))

// proceed simulation by one tick
void tick(int c) {
  static uint64_t ticks = 0;
  static int sector_tx = 0;
  static int sector_tx_cnt = 512;
  static int sector_rx_cnt = 512;
#ifndef SD_EMU      
  static int write_drv;
  static int write_sector;
#endif
  
#if MEMTRACE > 0
  if(!mem_fd) {
#if MEMTRACE == 1
    printf("Writing memory trace\n");
    mem_fd = fopen("memtrace.txt", "w");
    if(!mem_fd) { perror("cannot open 'memtrace.txt' for writing"); exit(-1); }
#else
    printf("Verifying memory trace\n");
    mem_fd = fopen("memtrace.txt", "r");
    if(!mem_fd) { perror("cannot open 'memtrace.txt' for reading"); exit(-1); }
#endif
  }  
#endif
  
  tb->clk = c;

  if(c /* && !tb->reset */ ) {

    static int cpu_reset = -1;
    if (tb->cpu_reset != cpu_reset) {
      printf("%.3fms <<<<<<<<<<<<<CPU changed reset to %d>>>>>>>>>>>>>\n",
	     simulation_time*1000, tb->cpu_reset);
      cpu_reset = tb->cpu_reset;
    }
    
    // leave reset after 20 ms of simulation time
    if ( tb->reset && simulation_time > 0.02 && simulation_time < 0.03) {
      printf("%.3fms Out of reset\n", simulation_time*1000);
      tb->reset = 0;
    }
    
#ifndef UART_ONLY
    // check for power led
    static int pwr_led = -1;
    if(tb->pwr_led != pwr_led) {
      printf("%.3fms Power LED = %s\n", simulation_time*1000, tb->pwr_led?"ON":"OFF");
      pwr_led = tb->pwr_led;
    }
    
    // check for fdd led
    static int fdd_led = -1;
    if(tb->fdd_led != fdd_led) {
      printf("%.3fms FDD LED = %s\n", simulation_time*1000, tb->fdd_led?"ON":"OFF");
      fdd_led = tb->fdd_led;
    }
    
    // check for hdd led
    static int hdd_led = -1;
    if(tb->hdd_led != hdd_led) {
      printf("%.3fms HDD LED = %s\n", simulation_time*1000, tb->hdd_led?"ON":"OFF");
      hdd_led = tb->hdd_led;
    }
#endif
    
    // ========================== analyze uart output (for diag rom) ===========================
    static int tx_data = tb->uart_tx;
    static double tx_last = simulation_time;
    static int tx_byte = 0xffff;
    
    // data changed
    if(tb->uart_tx != tx_data) {
      // save new value      
      tx_data = tb->uart_tx;
      
      // and synchronize to the arrival time of this bit
      tx_last = simulation_time - (0.5/9600);
    }
    
    // sample every 105us (9600 bit/s)
    if(simulation_time-tx_last >= (1.0/9600)) {
      // printf("SAMPLE %s\n", tx_data?"Hi":"LOW");
      
      // shift "from top" as uart sends LSB first
      tx_byte = (tx_byte >> 1)&0x1ff;
      if(tx_data) tx_byte |= 0x200;
      
      // printf("DATA %s now %02x\n", tx_data?"H":"L", tx_byte);
      
      // start bit?
      if((tx_byte & 0x01) == 0) {
	if(!(tx_byte & 0x200)) {
	  printf("----> broken stop bit!!!!!!!!!!!\n");
	}
	else {
#ifndef UART_ONLY
	  printf("UART(%02x %c)\n", (tx_byte >> 1)&0xff, (tx_byte >> 1)&0xff);
#else
	  printf("%c", (tx_byte >> 1)&0xff);
	  fflush(stdout);
#endif
	}
	tx_byte = 0xffff;
      }
      
      tx_last = simulation_time;
    }
  
#ifdef FDC_TEST
    /* ----------------- sdc interface ---------------- */
    
#ifndef SD_EMU
    // send bytes into sdc buffer
    tb->sdc_byte_in_strobe = 0;
    static int sub_cnt = 0;

    if(sub_cnt++ == 8) {
      sub_cnt = 0;

      if(tb->sdc_done) {
	tb->sdc_byte_addr = 0;      
	tb->sdc_done = 0;
      }
	
      // push requested sector data into core
      if(tb->sdc_busy) {
	if(sector_rx_cnt < 512) {

	  // the address has been put out already. Now read data and
	  // increase the address
	  sector_buffer[0][sector_rx_cnt++] = tb->sdc_byte_out_data;
	  
	  if(sector_rx_cnt == 512) {
	    // dump data that should be written
	    hexdump(sector_buffer[0], 512);

	    printf("Writing to %d: %d\n", write_drv, write_sector);
	    if(write_drv < 4) {
#if 0
	      // dump original sector for comparison
	      fseeko(adf_fd, write_sector*512ll, SEEK_SET);
	      if(fread(sector_buffer[0], 1, 512, adf_fd) != 512) {
		perror("adf read error"); return; }
	      
	      printf("previous:\n");
	      hexdump(sector_buffer[0], 512);
#endif

#if 0
	      fseeko(adf_fd, write_sector*512ll, SEEK_SET);
	      if(fwrite(sector_buffer[0], 1, 512, adf_fd) != 512) {
		perror("adf write error"); return; }
#endif
	    } else {	      
	      /* write data to image */
	      fseeko(hdf_fd[write_drv-4], write_sector*512ll, SEEK_SET);
	      if(fwrite(sector_buffer[0], 1, 512, hdf_fd[write_drv-4]) != 512) {
		perror("hdf write error"); return; }
	    }
	      
	    tb->sdc_done = 1;
	    tb->sdc_busy = 0;
	  } else
	    tb->sdc_byte_addr = sector_rx_cnt;
	}
	  
	if(sector_tx_cnt < 512) {
	  // printf("Send %d/%d\n", sector_tx, sector_tx_cnt);
	  
	  tb->sdc_byte_in_strobe = 1;
	  tb->sdc_byte_in_data = sector_buffer[sector_tx][sector_tx_cnt];
	  tb->sdc_byte_addr = sector_tx_cnt++;
	  
	  if(sector_tx_cnt == 512) {
	    tb->sdc_done = 1;
	    tb->sdc_busy = 0;
	  }
	}
      }
    }
#endif
    
    if(tb->clk7n_en) {    
#ifdef FDC_RAM_TEST_VERIFY
      static int ram_cnt = 0;
      
      if(!tb->_ram_we && ((tb->ram_address<<1) >= 0x10000)) {
	int adr = (tb->ram_address <<1) - 0x10000 + FDC_SKIP;
	
       	ram_cnt++;
	// printf("Written: %d\n", ram_cnt);	

	// the track data should wrap when more than the a complete track is being read
	while(adr >= TRACK_SIZE) adr -= TRACK_SIZE;
	
	unsigned short mm_orig = track_buffer[adr+1] + 256*track_buffer[adr];
		printf("MFM WR %d (%d/%d) = %04x (%04x)\n", adr,
		       adr/SECTOR_SIZE, (adr%SECTOR_SIZE)/2, tb->ram_data, mm_orig);

	// verify with mfm data generated from the original
	// minimig firmware code
	if(tb->ram_data != mm_orig) {
	  tb->trigger = 1;
	  printf("MFM mismatch %d (sector %d/word %d) is %04x, expected %04x\n",
		 adr, adr/SECTOR_SIZE, (adr%SECTOR_SIZE)/2,
		 tb->ram_data, mm_orig);
	}
      }
#endif

#ifndef SD_EMU      
      static int sdc_wr = -1;
      if(tb->sdc_wr != sdc_wr && (!tb->sdc_wr || (!tb->sdc_busy && !tb->sdc_done))) {
	printf("%.3fms SD: sdc_wr = %d\n", simulation_time*1000, tb->sdc_wr);
	sdc_wr = tb->sdc_wr;

	if(tb->sdc_wr & 0x0f ) {
	  int drv = (tb->sdc_wr&0x01)?0:
	    (tb->sdc_wr&0x02)?1:
	    (tb->sdc_wr&0x04)?2:
	    3;
	    
	  tb->sdc_busy = 1;

	  printf("%.3fms SD FDC %d write request, sector %d (tr %d, sd %d, sec %d)\n",
		 simulation_time*1000, drv, tb->sdc_sector, tb->sdc_sector/22,
		 (tb->sdc_sector/11)&1, tb->sdc_sector%11);

	  write_drv = drv;
	  write_sector = tb->sdc_sector;
	  tb->sdc_byte_addr = sector_rx_cnt = 0;
	}
	
	if(tb->sdc_wr & 0x30 ) {
	  int drv = (tb->sdc_wr&0x10)?4:5;
	  tb->sdc_busy = 1;

	  printf("%.3fms SD HDD %d write request, sector %d\n",
		 simulation_time*1000, drv, tb->sdc_sector);

	  write_drv = drv;
	  write_sector = tb->sdc_sector;
	  tb->sdc_byte_addr = sector_rx_cnt = 0;
	}
      }

      static int sdc_rd = -1;
      if(tb->sdc_rd != sdc_rd && (!tb->sdc_rd || (!tb->sdc_busy && !tb->sdc_done))) {
	printf("%.3fms SD: sdc_rd = %d\n", simulation_time*1000, tb->sdc_rd);
	sdc_rd = tb->sdc_rd;
	
	if(tb->sdc_rd == 1) {
	  tb->sdc_busy = 1;
	  printf("%.3fms SD FDC read request, sector %d (tr %d, sd %d, sec %d)\n",
		 simulation_time*1000, tb->sdc_sector, tb->sdc_sector/22,
		 (tb->sdc_sector/11)&1, tb->sdc_sector%11);
	  
	  // this triggers two things:
	  // - the track is read into a track buffer using the minimig MFM encoder
	  // - the sectors are sent into Paula/Floppy as raw sectors
	  build_track_buffer(tb->sdc_sector, NULL);
	  sector_tx_cnt = 0;
	  sector_tx = tb->sdc_sector%11;
	}
	
	if(tb->sdc_rd & 0x30 && (!tb->sdc_rd || (!tb->sdc_busy && !tb->sdc_done))) {
	  int drv = (tb->sdc_rd&0x10)?0:1;
	  
	  tb->sdc_busy = 1;
	  printf("%.3fms SD HDD %d read request, sector %d\n",
		 simulation_time*1000, drv, tb->sdc_sector);

	  // send one sector into core

	  // Minimig 80MB image:
	  // 80936960 Bytes
	  // 158080 sectors total (2*2*2*2*2*2*2*5*13*19)
	  // CSH from RDB: 627/63/4 = 158004
	  
	  if(hdf_fd[drv]) {
	    fseeko(hdf_fd[drv], tb->sdc_sector*512ll, SEEK_SET);
	    if(fread(sector_buffer[0], 1, 512, hdf_fd[drv]) != 512) {
	      perror("hdf read error"); return; }
	    hexdump(sector_buffer[0], 512);

	    // dump some info on rdb
	    if(tb->sdc_sector == 0) {
	      if( strncmp((char*)sector_buffer[0], "RDSK", 4) != 0)
		printf("Not a RDB image!!\n");
	      else {
		printf("DRV%d RDB ID ok\n", drv);
		printf("Blocksize:  %ld\n", RDB_U32(4));
		printf("Cylinders:  %ld\n", RDB_U32(16));
		printf("Heads:      %ld\n", RDB_U32(18));
		printf("Sectors:    %ld\n", RDB_U32(17));
	      }
	    }
	  }
	  
	  sector_tx_cnt = 0;
	  sector_tx = 0;
	}
      }
#endif
    }

    // fake a disk image insertion
    static int insert_counter = 0;
    if(insert_counter < 1000) {
      // check if floppy image can be mounted    
      if(insert_counter == 100) {
#ifdef FLOPPY_ADF
	printf("FLOPPY: Using image '%s'\n", FLOPPY_ADF);
#endif
	if(adf_fd) {
	  fseek(adf_fd, 0, SEEK_END);
	  tb->sdc_img_size = ftello(adf_fd);
 
	  printf("FLOPPY: Mounting df0 image size %ld bytes.\n", tb->sdc_img_size);	
	} else
	  printf("FLOPPY: Unable to open floppy disk image. Not mounting disk.\n");
      }
      
      if(insert_counter == 200 || insert_counter == 300) {
	int drv = (insert_counter == 200)?0:1;
	
	if(!drv) {
#ifdef HARDDISK0_HDF
	  printf("HDD0: Using image '%s'\n", HARDDISK0_HDF);
#endif
	} else {
#ifdef HARDDISK1_HDF
	  printf("HDD1: Using image '%s'\n", HARDDISK1_HDF);
#endif
	}
	
	if(hdf_fd[drv]) {
	  fseek(hdf_fd[drv], 0, SEEK_END);
	  tb->sdc_img_size = ftello(hdf_fd[drv]);
	  
	  printf("HDD%d: Mounting image size %ld bytes.\n", drv, tb->sdc_img_size);	
	} else
	  printf("HDD%d: Unable to open harddisk image. Not mounting disk.\n", drv);
      }
      
      if(tb->sdc_img_size) {  
	if(insert_counter == 120) tb->sdc_img_mounted = 1<<0;
	if(insert_counter == 220) tb->sdc_img_mounted = 1<<4;
	if(insert_counter == 320) tb->sdc_img_mounted = 1<<5;
	if(insert_counter == 140 || insert_counter == 240 || insert_counter == 340) tb->sdc_img_mounted = 0;
	if(insert_counter == 160 || insert_counter == 260 || insert_counter == 360) tb->sdc_img_size = 0;
      }
      insert_counter++;
    }

#ifdef SD_EMU
    // full sd card emulation enabled
    sd_handle();
#endif    
    
#endif
    
    /* ----------------- simulate ram/kick ---------------- */

    // counter within 7 Mhz cycle
    static unsigned char ram_delay = 0;
    if(tb->clk7n_en) ram_delay = 0;
    else             ram_delay++;
    
    // ram works on/after falling 7mhz edge
    if(ram_delay == 1) {
      unsigned char *ram_b = (unsigned char*)(ram+tb->ram_address);
	
      if(!tb->_ram_oe) {
	// big edian read
	tb->ramdata_in = 256*ram_b[0] + ram_b[1];

	// ===== check for kick 1.3 fatal error routine being executed =====
	// these blink the power led
	static int fatal = 0;
	if(tb->ram_address == (0x7c05b8 >> 1) && !fatal) {
	  printf("%.3fms Kick 1.3 fatal error #1\n", simulation_time*1000);
	  fatal = 1;
	}

	// fast kick triggers this at 1432.701 ms
	if(tb->ram_address == (0x7c30b6 >> 1) && !fatal) {
	  printf("%.3fms Kick 1.3 fatal error #2\n", simulation_time*1000);
	  fatal = 1;
	}	
	
#if MEMTRACE == 1
	if(tb->ram_address >= 0x3e0000) {	
	  // write kick access to trace file
	  fprintf(mem_fd, "K %08x %04x\n", tb->ram_address, tb->ramdata_in);
	}
#elif MEMTRACE == 2
	if(tb->ram_address >= 0x3e0000) {	
	  static int err_cnt = 0;

	  if(err_cnt < 30) {
	    static int skip_to_addr = 0;
	    static int skipped = 0;

	    if(skip_to_addr && tb->ram_address != skip_to_addr) {
	      // printf("skipping %08x\n", tb->ram_address);
	      skipped++;
	    } else if(skip_to_addr) {
	      printf("%.3fms skipped %d in simulation\n", simulation_time*1000, skipped);
	      skip_to_addr = 0;
	    } else {
	      
	      // read trace file and compare to kick access
	      char m_c;
	      int m_a, m_d; 
	      int x = fscanf(mem_fd, "%c %x %x\n", &m_c, &m_a, &m_d);
	      if(x != 3) { printf("======> End of trace <==========\n"); err_cnt = 100; }
	      else {
		
		static int last_addr = 0;
		
		// we need to skip certain code when running the CPU at different speeds
		// as kickstart will wait for certain hardware events and will wait a different
		// time of CPU speed varies.
		
		// VPOS subroutine at kick 1.3 $fcb00c
		// if the previous address was the one beforehand, then this is not
		// actually the call to this routine but only the prefetching of the code before
		if( tb->ram_address == (0x7cb00c>>1) && last_addr != (0x7cb00a>>1)) {		
		  printf("Entered vpos routine from %08x\n", last_addr<<1);
		  
		  // the last address is read again when the execution returns to the caller
		  int skip = 0;
		  do {
		    x = fscanf(mem_fd, "%c %x %x\n", &m_c, &m_a, &m_d);
		    skip++;
		  } while(x == 3 && m_a != last_addr);
		  
		  printf("Skipping %d reads in trace\n", skip);
		  skip_to_addr = last_addr;
		  skipped = 0;
		} else {
		
		  last_addr = tb->ram_address;
		
		  if(m_c != 'K' || m_a != tb->ram_address || m_d != tb->ramdata_in) {
		    // stop complaining after 20 errors
		    printf("%.3fms Kick read verify failed: %c is %08x/%04x, expected %08x/%04x\n",
			   simulation_time*1000, m_c, tb->ram_address<<1, tb->ramdata_in, m_a<<1, m_d);
		    err_cnt++;
		  }
		}
	      }
	    }
	  }
	}
#endif
	
	// printf("%.3fms MEM RD ADDR %08x = %04x\n", simulation_time*1000, tb->ram_address << 1, tb->ramdata_in);
      }
      if(!tb->_ram_we) {
	// printf("%.3fms MEM WR ADDR %08x = %04x\n", simulation_time*1000, tb->ram_address << 1, tb->ram_data);
	// exit(-1);
	// ram[tb->ram_address] = tb->ram_data;

	// big edian write
	if(!tb->_ram_bhe) ram_b[0] = tb->ram_data>>8;
	if(!tb->_ram_ble) ram_b[1] = tb->ram_data&0xff;
      }
    }
  }
  
  tb->eval();

#ifdef VIDEO
  if(c) capture_video();
#endif

  if(simulation_time == 0)
    ticks = GetTickCountMs();
  
  // after one simulated millisecond calculate real time */
  if(simulation_time >= 0.001 && ticks) {
    ticks = GetTickCountMs() - ticks;
    printf("Speed factor = %lu\n", ticks);
    ticks = 0;
  }
  
  // trace after
#ifdef TRACESTART
  if(simulation_time > TRACESTART) trace->dump(1000000000000 * simulation_time);
#endif
  simulation_time += TICKLEN;
}

int main(int argc, char **argv) {
  // Initialize Verilators variables
  Verilated::commandArgs(argc, argv);
  // Verilated::debug(1);
  Verilated::traceEverOn(true);
  trace = new VerilatedFstC;
  trace->spTrace()->set_time_unit("1ns");
  trace->spTrace()->set_time_resolution("1ps");
  simulation_time = 0;
  
  load_kick();

#ifdef VIDEO
  init_video();
#endif

  // Create an instance of our module under test
  tb = new Vnanomig_tb;
  tb->trace(trace, 99);
  trace->open("nanomig.fst");
  
#ifdef FDC_TEST
#ifdef FLOPPY_ADF
  // try to open adf floppy image
  adf_fd = fopen(FLOPPY_ADF, "r+b");
  if(!adf_fd) { perror("open adf file"); }
#else
  printf("No floppy adf specified\n");
#endif
  
#ifdef HARDDISK0_HDF
  // try to open hdf harddisk image
  hdf_fd[0] = fopen(HARDDISK0_HDF, "r+b");
  if(!hdf_fd[0]) { perror("DRV0: open hdf file"); }
#else
  printf("DRV0: No harddisk hdf specified\n");
#endif
  
#ifdef HARDDISK1_HDF
  // try to open hdf harddisk image
  hdf_fd[1] = fopen(HARDDISK1_HDF, "rb");
  if(!hdf_fd[1]) { perror("DRV1: open hdf file"); }
#else
  printf("DRV1: No harddisk hdf specified\n");
#endif
#endif

  tb->reset = 1;
  tb->memory_config = 0x00; // 0x00=512k, 0x01=1M, 0x0f=3.5M
  tb->fastram_config = 0x2; // 0=none, 1=2MB, 2=4MB
  tb->floppy_config = 0x1;  // 1 = one fast drive
  tb->ide_config = 0x7;     // 7=two drives
  
  /* run for a while */
  while(
#ifdef TRACEEND
	simulation_time<TRACEEND &&
#endif
#ifdef VIDEO 
	!sdl_cancelled &&
#endif
	1) {
#ifdef TRACEEND
    // do some progress outout
    int percentage = 100 * simulation_time / TRACEEND;
    static int last_perc = -1;
    if(percentage != last_perc) {
#ifndef UART_ONLY
      printf("progress: %d%%\n", percentage);
#endif
      last_perc = percentage;
    }
#endif

    // apply reset after 6 seconds for 1ms
    if(simulation_time < 0.1) {      
      static int x_reset = -1;
      tb->reset = (int)(simulation_time * 1000) == 6000;
      if(tb->reset != x_reset){
	if(x_reset != -1) printf("%.3fms RESET changed to %d\n",
				 1000*simulation_time, tb->reset);
      }
      x_reset = tb->reset;
    }
	
    tick(1);
    tick(0);
  }
  
  printf("stopped after %.3fms\n", 1000*simulation_time);
  
  trace->close();

  // hexdump(ram+(0x97f0/2), 512);
  
#ifdef FDC_TEST
  if(adf_fd) fclose(adf_fd);
  if(hdf_fd[0]) fclose(hdf_fd[0]);
  if(hdf_fd[1]) fclose(hdf_fd[1]);
#endif

#if MEMTRACE > 0
  if(mem_fd) fclose(mem_fd);
#endif
}
