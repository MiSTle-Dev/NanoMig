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

#include <SDL.h>
#include <SDL_image.h>

#include "Vnanomig_tb.h"
#include "Vnanomig_tb_nanomig_tb.h"

// get access into the floppy structures
#include "Vnanomig_tb_nanomig.h"
#include "Vnanomig_tb_minimig.h"
#include "Vnanomig_tb_paula.h"
#include "Vnanomig_tb_paula_floppy.h"

#include "verilated.h"
#include "verilated_fst_c.h"

#include "Vnanomig_tb.h"

//#define KICK "kick12.rom" 
#define KICK "kick13.rom" 
// #define KICK "kick31.rom" 
// #define KICK "DiagROM/DiagROM"
// #define KICK "../src/ram_test/ram_test.bin"
// #define KICK "test_rom/test_rom.bin"

Vnanomig_tb *tb;
static VerilatedFstC *trace;
double simulation_time;

#define TICKLEN   (0.5/28375160)
#include "sd_card_config.h"       // for TICKLEN

// with kick 1.3 and 512k
//#define TRACESTART   3.5    // first floppy read

// with kick 3.1 and 512k
//#define TRACESTART   0.74    // power led on
//#define TRACESTART   3.2     // floppy read
//#define TRACESTART   4.7     // "no floppy" image
//#define TRACESTART   9.6       // IDE test write

// specfiy simulation runtime and from which point in time a trace should
// be written
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
// #define TRACESTART   10.9   // FDC write

#ifdef TRACESTART
#define TRACEEND     (TRACESTART + 0.1)
#endif

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

// disable colorization for easier handling in editors 
#if 1
#define RED      "\033[1;31m"
#define GREEN    "\033[1;32m"
#define YELLOW   "\033[1;33m"
#define END      "\033[0m"
#else
#define RED
#define GREEN
#define YELLOW
#define END
#endif

// optionally parse a sector address into track/side/sector
char *sector_string(int drive, uint32_t lba) {
  static char str[32];
  strcpy(str, "");
  return str;
}

/* =============================== video =================================== */

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
      
      printf("%.3fms frame %d is %dx%d\n", simulation_time*1000, frame, frame_line_len, sy);

      frame++;
      frame_line_len = 0;
      sy = 0;
    }    
  }
}

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

static void hexdiff(void *data, void *cmp, int size) {
  int i, b2c;
  int n=0;
  char *ptr = (char*)data;
  char *cptr = (char*)cmp;

  if(!size) return;

  // check if there's a difference at all
  if(memcmp(data, cmp, size) == 0) {
    hexdump(data, size);
    return;
  }
   
  while(size>0) {
    printf("%04x: ", n);

    b2c = (size>16)?16:size;
    for(i=0;i<b2c;i++) {
      if(cptr[i] == ptr[i])      
        printf(" %02x  ", 0xff&ptr[i]);
      else
        printf(RED "%02x" GREEN "%02x" END " ",
	       0xff&ptr[i], 0xff&cptr[i]);
    }
      
    printf("  ");
    for(i=0;i<(16-b2c);i++) printf("   ");
    for(i=0;i<b2c;i++) {
      if(cptr[i] == ptr[i])      
	printf("%c ", isprint(ptr[i])?ptr[i]:'.');
      else
	printf(RED "%c" GREEN "%c" END,
	       isprint(ptr[i])?ptr[i]:'.', isprint(cptr[i])?cptr[i]:'.');	
    }
    printf("\n");

    ptr  += b2c;
    cptr  += b2c;
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

void fdc_verify(uint16_t word) {
  static uint16_t header[24];
  static uint16_t csum[4];
  static uint16_t data[512];
  
  static int state = -1;
  static int count = 0;

  static int track, sector;
  
  // decode MFM encoded data as sent by
  // the amiga paula floppy interface to the CPU
  // printf("%d/%d busrd %04x\n", state, count, word);

  // in whatever state we are, the sync marker
  // throws us back into the start state
  if(word == 0x4489) {
    printf("FDC sync detected\n");
    state = 0;
    count = 0;
    return;
  }

  // in state -1 only the sync marker is accepted
  if(state < 0) return;
  
  switch(state) {
  case 0:
    // state 0: collect header data
    header[count++] = ((word&0xff) << 8) | ((word&0xff00) >> 8);
    if(count == 24) {
      // parse header
      uint16_t csum0 = (header[0] ^ header[2]) & 0x5555;
      uint16_t csum1 = (header[1] ^ header[3]) & 0x5555;
      if((csum0 == (header[22]&0x5555)) && (csum1 == (header[23]&0x5555))) {
	uint8_t *hdr8 = (uint8_t*)header;
	
	// checksum ok

	// extract track and sector
	track = ((hdr8[1] & 0x55)<<1) | (hdr8[5] & 0x55);
	sector = ((hdr8[2] & 0x55)<<1) | (hdr8[6]& 0x55);

	uint8_t sec2end = ((hdr8[3] & 0x55)<<1) | (hdr8[7]& 0x55);
	printf("CPU reading FDC data for track %d, side %d, sector %d\n", track>>1, 1^(track&1), sector);

	// expected sectors to end is 11-sector
	if(sec2end != 11-sector) printf(RED "Unexpected sector to end %d" END "\n", sec2end);
      
	state = 1;
	count = 0;
      } else {
	printf(RED "Header checksum failed:  %04x,%04x != %04x,%04x" END "\n", csum0, csum1, header[22]&0x5555, header[23]&0x5555);	
	state = -1;
	exit(-1);
      }	
    }
    break;

  case 1:
    // state 1: collect data checksum
    csum[count++] = ((word&0xff) << 8) | ((word&0xff00) >> 8);
    if(count == 4) { state = 2; count = 0; }
    break;

  case 2:
    // state 2: collect data 
    data[count++] = ((word&0xff) << 8) | ((word&0xff00) >> 8);
    if(count == 512) {
      // decode data
      uint8_t decoded[512];

      uint8_t *d8 = (uint8_t*)data;
      // decode odd bits
      for(int i=0;i<512;i++) decoded[i]  = (d8[i] & 0x55)<<1;
      // decode even bits
      for(int i=0;i<512;i++) decoded[i] |= (d8[512+i] & 0x55);

      // mask clock bits from received checksum
      csum[0] &= 0x5555; csum[1] &= 0x5555; csum[2] &= 0x5555; csum[3] &= 0x5555;      

      // calculate checksum from received data
      uint32_t dcsum = 0;
      uint32_t *dec32 = (uint32_t*)decoded;
      for(int i=0;i<128;i++) dcsum ^= (dec32[i] ^ dec32[i]>>1) & 0x55555555;

      if(dcsum != *(uint32_t*)(csum+2))
	printf(RED "Data checksum failure 0x%08x != 0x%08x" END "\n", dcsum, *(uint32_t*)(csum+2));
      
      // get original sector data from sd card
      uint8_t orig[512];
      // TODO: fix drive index
      sd_get_sector(0, track*11+sector, orig);

      if(memcmp(decoded, orig, 512) != 0) {
	printf(RED "Data LBA %d comparison failed with checksum %08x" END "\n",  track*11+sector, dcsum);
	hexdiff(decoded, orig, 512);
      } else
	printf(GREEN "Data successfully received for LBA %d with checksum %08x" END "\n",  track*11+sector, dcsum);
	
      state = -1;
    }
    break;
  }
}

// proceed simulation by one tick
void tick(int c) {
  static uint64_t ticks = 0;
  static int sector_tx = 0;
  static int sector_tx_cnt = 512;
  static int sector_rx_cnt = 512;  
  
  tb->clk = c;

  if(c /* && !tb->reset */ ) {

    static int cpu_reset = -1;
    if (tb->cpu_reset != cpu_reset) {
      printf("%.3fms CPU changed reset to %d\n", simulation_time*1000, tb->cpu_reset);
      cpu_reset = tb->cpu_reset;
    }
    
    // release reset after 10 ms of simulation time
    if ( tb->reset && simulation_time > 0.005 && simulation_time < 0.0051) {
      printf("%.3fms Releasing reset\n", simulation_time*1000);
      tb->reset = 0;
    }
    
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
	else 
	  printf("UART(%02x %c)\n", (tx_byte >> 1)&0xff, (tx_byte >> 1)&0xff);

	tx_byte = 0xffff;
      }
      
      tx_last = simulation_time;
    }
  
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

    }
    
    // full sd card emulation enabled
    sd_handle();

    // capture CPU access to floppy fifo in order to verify sd card/floppy
    // encoding/decoding
    
    if(tb->clk7n_en) {    
      // analyze CPU accessing paula/floppy
      if(tb->nanomig_tb->nanomig->minimig->PAULA1->pf1->busrd)
	fdc_verify(tb->nanomig_tb->nanomig->minimig->PAULA1->pf1->fifo_out);
    }
      
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

  if(c) capture_video();

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

  init_video();

  // Create an instance of our module under test
  tb = new Vnanomig_tb;
  tb->trace(trace, 99);
  trace->open("nanomig.fst");

  sd_init();
  
  tb->reset = 1;
  tb->memory_config = 0x00; // 0x00=512k, 0x01=1M, 0x0f=3.5M
  tb->fastram_config = 0;   // 0=none, 1=2MB, 2=4MB
  tb->floppy_config = 0x1;  // 1 = one fast drive
  tb->ide_config = 0x7;     // 7=two drives

  /* run for a while */
  while(
#ifdef TRACESTART
	simulation_time<TRACEEND &&
#endif
	!sdl_cancelled) {
#ifdef TRACESTART
    // do some progress outout
    int percentage = 100 * simulation_time / TRACEEND;
    static int last_perc = -1;
    if(percentage != last_perc) {
      printf("progress: %d%%\n", percentage);
      last_perc = percentage;
    }
#endif

    tick(1);
    tick(0);
  }
  
  printf("stopped after %.3fms\n", 1000*simulation_time);
  
  trace->close();
}
