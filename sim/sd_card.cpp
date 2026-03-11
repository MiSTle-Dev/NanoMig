/*
  sd_card.cpp

  The simulation does only partly include the FPGA Companion. There's thus
  no instance that maps the different floppy/SCSI devices onto the
  SD card. The simulation thus includes the target device into
  fixed offsets inside the sd card and this sd card simulation maps the
  request onto the four images files based on that.

  There's no reason to simulate images stored inside a real sd image.
*/

#include <stdio.h>
#include <ctype.h>
#include <cstdint>

#define SD_CARD_CPP
#include "sd_card_config.h"

int file_image_len[8] = {-1,-1,-1,-1,-1,-1,-1,-1 };

extern TB_NAME *tb;
extern double simulation_time;

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

extern char *sector_string(int drive, uint32_t lba);

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

static void hexdiff_color(void *data, void *cmp, int size, char *color) {
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
        printf("%s%02x" GREEN "%02x" END " ", color,
	       0xff&ptr[i], 0xff&cptr[i]);
    }
      
    printf("  ");
    for(i=0;i<(16-b2c);i++) printf("   ");
    for(i=0;i<b2c;i++) {
      if(cptr[i] == ptr[i])      
	printf("%c ", isprint(ptr[i])?ptr[i]:'.');
      else
	printf("%s%c" GREEN "%c" END, color,
	       isprint(ptr[i])?ptr[i]:'.', isprint(cptr[i])?cptr[i]:'.');	
    }
    printf("\n");

    ptr  += b2c;
    cptr  += b2c;
    size -= b2c;
    n    += b2c;
  }
}

void hexdiff(void *data, void *cmp, int size) {
  hexdiff_color(data, cmp, size, (char*)RED);
}

/* ============================= FPGA Companion (sd card part) ====================== */
void sd_setup_fake_sector(uint16_t sector, uint8_t *buf, uint8_t mask) {  
  // fill buffer with dummy data that is unique for this sector
  for(int i=0;i<256;i++) {
    buf[2*i]   = (i & 0xff) ^ (sector>>0) ^ mask;
    buf[2*i+1] = (i & 0xff) ^ (sector>>8) ^ mask;
  }
}

#define MS2FC(a) ((long)((a)/(2000*TICKLEN)))
static int mcu_read_handler(int index) {
  static uint32_t sector;
  static int cnt = -1;
  static uint8_t buf[512];
  
  // printf("%.3fms MCU read handler(%d), %02x\n", simulation_time*1000, index, tb->mcu_data_out);
  
  if(!index) {
    cnt = -1;
    tb->mcu_data_in = 3;  // MCU read command
    tb->mcu_data_start = 1;

    sector = random() & 0xffff;
  }
  else if(index == 1) tb->mcu_data_in = sector >> 24;
  else if(index == 2) tb->mcu_data_in = sector >> 16;
  else if(index == 3) tb->mcu_data_in = sector >> 8;
  else if(index == 4) tb->mcu_data_in = sector >> 0;
  if(index < 5) return 0;

  if(cnt<0) {
    // printf("WAIT flag %02x\n", tb->mcu_data_out);    
    if(tb->mcu_data_out) return 0;   // still waiting
    cnt = 0;
    return 0;
  }
  
  buf[cnt++] = tb->mcu_data_out;
  if(cnt == 512) {
    uint8_t ref[512];
    
    // compare with original data
    
    sd_setup_fake_sector(sector, ref, 0x55);
    
    hexdiff(buf, ref, 512);

    assert(!memcmp(buf, ref, 512));
  }
    
  return cnt == 512;   // done
}

static int mcu_write_handler(int index) {
  static uint32_t sector;
  static uint8_t buf[512];
  static int wait = 0;

  // make sure sectors always follow the same pattern
  if(!index) {
    // fake image is 64k sectors
    sector = random() & 0xffff;
  }
  
  if(index == 0) {
    tb->mcu_data_in = 5;     // MCU write command
    tb->mcu_data_start = 1;  //     -"-
    sd_setup_fake_sector(sector, buf, 0x00);
    wait = 0;
  }
  else if(index == 1) tb->mcu_data_in = sector >> 24;
  else if(index == 2) tb->mcu_data_in = sector >> 16;
  else if(index == 3) tb->mcu_data_in = sector >> 8;
  else if(index == 4) tb->mcu_data_in = sector >> 0;
  else if(index >= 5) tb->mcu_data_in = buf[index-5];
  if(index < 512+5) return 0;

  wait++;
  if(!tb->mcu_data_out)
    printf("Write done after %d\n", wait);
  
  // core returns 01 as long as the sector has not been written
  return !tb->mcu_data_out;    
}

static int mcu_irq_handler(int index) {
  static uint8_t req;
  static uint32_t sector;
  
  // printf("%.3fms MCU irq handler(%d), %02x\n", simulation_time*1000, index, tb->mcu_data_out);

  if(index == 0) {
    tb->mcu_data_in = 1;  // get status
    tb->mcu_data_start = 1;
  } else if(index == 1)
    tb->mcu_data_in = 0;
  else if(index == 2) {
    req = tb->mcu_data_out;
    sector = 0;
  } else if(index <= 6)
    sector = (sector << 8) | tb->mcu_data_out; 

  if(index == 6) {
    printf("\033[1;33m%.3fms MCU sector translation req 0x%02x, sector %u\033[0m\n", simulation_time*1000, req, sector);
    // set request in msb to allow sd_card.cpp to distinguish the drives
    sector |= (req<<24);
  }

  // send reply from index 6 on
  if(index == 7) {
    tb->mcu_data_start = 1;
    tb->mcu_data_in = 2;
  } else if(index > 7 && index <= 11) {
    tb->mcu_data_start = 0;
    tb->mcu_data_in = (sector >> 24);
    sector <<= 8;
  }    

  // monitor until the core reports "not busy"
  return (index > 11) && !tb->mcu_data_out;
}

void sd_mount(float);

static int mcu_sdc_insert_handler(int index) {
  if(index == 0) {
    printf("\033[1;33m%.3fms MCU sdc insert handler\033[0m\n", simulation_time*1000);
    sd_mount(simulation_time*1000);
  }

  // max 3 drives (two floppies, one hdd)
  int drive = index / 16;
  int drive_idx = index % 16;
  if(file_image_len[drive] >= 0) {
    if(!drive_idx) {
      tb->mcu_data_in = 4;  // insert disk command
      tb->mcu_data_start = 1;
    }
    else if(drive_idx == 1) tb->mcu_data_in = drive;
    else if(drive_idx == 2) tb->mcu_data_in = file_image_len[drive] >> 24;
    else if(drive_idx == 3) tb->mcu_data_in = file_image_len[drive] >> 16;
    else if(drive_idx == 4) tb->mcu_data_in = file_image_len[drive] >> 8;
    else if(drive_idx == 5) tb->mcu_data_in = file_image_len[drive] >> 0;

#ifdef ENABLE_DIRECT_MAP
    else if(drive_idx == 6)
      tb->mcu_data_strobe = 0;
    else if(drive_idx == 7) {
      tb->mcu_data_in = 6;         // direct enable signal
      tb->mcu_data_start = 1;
    } else if(drive_idx == 8)
      tb->mcu_data_in = drive;
    else if(drive_idx == 9)
      tb->mcu_data_in = 1<<drive;  // drive maps to sectors
    else if(drive_idx <= 12)
      tb->mcu_data_in = 0;
#endif
    
    else tb->mcu_data_strobe = 0;	  
  }  
  
  return index > MAX_DRIVES*12;
}

void fc_handle(void) {
  // FPGA companion
  static int companion_byte = 0;
  static int companion_cnt = 0;
  static int companion_next = MS2FC(10);
  static int (*handler)(int) = mcu_sdc_insert_handler;

  // if(!(companion_cnt % 1000)) printf("%d of %d\n", (long)(3/(2*TICKLEN)), companion_cnt);

  // report IRQ
  static int last_irq = 0;
  tb->mcu_iack = 0;
  if(tb->mcu_irq && !last_irq) printf("\033[1;32m%.3fms MCU raised IRQ\033[0m\n", simulation_time*1000);
  last_irq = tb->mcu_irq;
  
  if(tb->mcu_data_strobe) tb->mcu_data_strobe = 0;
  else {
    // still events in queue and current one being in progress?
    if(handler && companion_cnt >= companion_next) {	
      // printf("EV %d %d %d %d\n", companion_event, fc_cmds[companion_event].len, companion_cnt, companion_next);
      
      tb->mcu_data_in = 0;
      tb->mcu_data_strobe = 1;
      tb->mcu_data_start = 0;
      
      // run handler if present
      if(handler(companion_byte++)) {
	handler = NULL;
	companion_byte = 0;
	
	// check if irq is pending and run its handler then
	if(tb->mcu_irq) {
	  printf("\033[1;32m%.3fms MCU delayed handling IRQ\033[0m\n", simulation_time*1000);
	  tb->mcu_iack = 1;
	  handler = mcu_irq_handler;
	  companion_next = companion_cnt;
	}
      }
    } else {
      // no more companion events in the main list or current one not active, yet
      // then process IRQ request immediately
      if(tb->mcu_irq) {
	printf("\033[1;32m%.3fms MCU immediately handling IRQ\033[0m\n", simulation_time*1000);
	tb->mcu_iack = 1;
	handler = mcu_irq_handler;
	companion_next = companion_cnt;
	companion_byte = 0;
      }
    }
  }
  companion_cnt++;

#ifdef FC_RW_STORM
  // do random mcu sector read/write accesses
  if(companion_cnt > MS2FC(20) && !handler && !(random() % 100000)) {
    // printf("\033[1;33m%.3fms PÖNG!\033[0m\n", simulation_time*1000);
    if(random() & 1) handler = mcu_read_handler;
    else             handler = mcu_write_handler;
    companion_next = companion_cnt;
    companion_byte = 0;
  }
#endif
}  

// =========================================== SD card itself ==========================================

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

static void update_crc(uint8_t *sector_data) {
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
  
  //   printf("%.3fms SDC: CRC = %04x/%04x/%04x/%04x\n", simulation_time*1000, crc[0], crc[1], crc[2], crc[3]);
  
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

#define OCR  0xc0ff8000  // not busy, CCS=1(SDHC card), all voltage, not dual-voltage card
#define RCA  0x0013

// total cid respose is 136 bits / 17 bytes
unsigned char cid[17] = "\x3f" "\x02TMS" "A08G" "\x14\x39\x4a\x67" "\xc7\x00\xe4";

static FILE *fd[8] = { NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL };

void fdclose(void) {
  for(int i=0;i<8;i++) {  
    if(fd[i]) {
      printf("closing file image %d\n", i);
      fclose(fd[i]);
      fd[i] = NULL;
    }
  }
}

void sd_mount(float ms) {
  for(int drive=0;drive<8;drive++) {  
    if(file_image[drive]) {
      fd[drive] = fopen(file_image[drive], "r+b");
      if(!fd[drive]) {
	printf("Unable to open %s\n", file_image[drive]);
	exit(-1);
      }
    }
      
    if(fd[drive]) {	
      fseek(fd[drive], 0, SEEK_END);
      file_image_len[drive] = ftello(fd[drive]);
      printf("%.3fms DRV %d mounting %s, size = %d\n", ms, drive, file_image[drive], file_image_len[drive]);
      fseek(fd[drive], 0, SEEK_SET);
    }
  }
}

void sd_handle(void)  {
  static int last_sdclk = -1;
  static unsigned long sector = 0xffffffff;
  static unsigned long long flen;
  static uint8_t sector_data[520];   // 512 bytes + four 16 bit crcs
  static long long cmd_in = -1;
  static long long cmd_out = -1;
  static unsigned char *cmd_ptr = 0;
  static int cmd_bits = 0;
  static unsigned char *dat_ptr = 0;
  static int dat_write = 0;
  static int dat_bits = 0;
  static unsigned long dat_arg;
  static int last_was_acmd = 0;
  static int write_busy = 0;
  static int read_busy = 0;

  // ----------------- simulate sd card itself --------------------------
  if(tb->sdclk != last_sdclk) {
    // rising sd card clock edge
    if(tb->sdclk) {
      cmd_in = ((cmd_in << 1) | tb->sdcmd) & 0xffffffffffffll;

      if(dat_write) {
	// core writes to sd card
	if(dat_ptr && dat_bits) {
	  // 128*8 + 16 + 1 + 1
	  // printf("%.3fms SDC: WRITE %d %x\n", simulation_time*1000, dat_bits, tb->sddat);
	  if(dat_bits == 128*8 + 16 + 1 + 1 + 4) {
	    // wait for start bit(s)
	    if(tb->sddat != 0xf) {	    
	      // printf("%.3fms SDC: WRITE-4 START %x\n", simulation_time*1000, tb->sddat);	    
	      dat_bits--;
	    }
	  } else if(dat_bits > 1) {
	    if(dat_bits > 1+4) { 
	      int nibble = dat_bits&1;   // 1: high nibble, 0: low nibble
	      if(nibble) *dat_ptr   = (*dat_ptr & 0x0f) | (tb->sddat<<4);
	      else       *dat_ptr++ = (*dat_ptr & 0xf0) |  tb->sddat;
	    } else tb->sddat_in = 0;  // send 4 wack bits
	    
	    dat_bits--;
	  } else {
	    write_busy = 100;
	    // tb->sddat_in = 1;
	    
	    // save received crc
	    uint8_t crc_rx[8];
	    memcpy(crc_rx, sector_data+512, 8);    // copy supplied crc
	    update_crc(sector_data);               // recalc it

	    // and compare it
	    // printf("%.3fms SDC: WRITE DATA CRC is %s\n", simulation_time*1000, memcmp(sector_data+512, crc_rx, 8)?"INVALID!!!":"ok");
	    if(memcmp(sector_data+512, crc_rx, 8)) {
	      printf(RED "CRC received: "); hexdump(crc_rx, 8);
	      printf("CRC expected: "); hexdump(sector_data+512, 8);
	      printf("" END);
	    } else {
	      printf(GREEN "CRC ok: "); hexdump(crc_rx, 8);
	      printf("" END);
	    }

	    int i = dat_arg >> 24;
	    int drive = 0;
	    if(i) while(!(i&1)) { drive++; i>>=1; }
	    int lba = dat_arg & 0xffffff;

	    if(i) {	    
	      if(fd[drive]) {
		uint8_t ref[512];
		
		// read original sector for comparison
		fseek(fd[drive], 512 * lba, SEEK_SET);
		int items = fread(ref, 2, 256, fd[drive]);
		if(items != 256) perror("fread()");

		// a difference in data for writing does not mean
		// an error but just that data has been modified
		// by the amiga. Thus will color the changed parts yellow
		hexdiff_color(sector_data, ref, 512, (char*)YELLOW);
	      } else 	    
		hexdump(sector_data, 520);
	      
#ifdef WRITE_BACK
	      fseek(fd[drive], 512 * lba, SEEK_SET);
	      if(fwrite(sector_data, 2, 256, fd[drive]) != 256) {
		printf("SDC WRITE ERROR\n");
		exit(-1);
	      }	    
	      fflush(fd[drive]);
#endif
	    } else {
	      // MCU data
	      printf("MCU wrote %u:\n", lba);

	      // compare this with the generated data
	      uint8_t ref[512];
	      sd_setup_fake_sector(lba, ref, 0x00);
	      hexdiff(sector_data, ref, 512);

	      assert(!memcmp(sector_data, ref, 512));
	    }
	      
	    dat_bits--;
	  }
	}
	else if(write_busy) {
	  write_busy--;	  
	  tb->sddat_in = write_busy?0:15;
	}
      } else {      
	// core reads from sd card
	
	// sending 4 data bits
	if(dat_ptr && dat_bits) {
	  if(read_busy) {
	    tb->sddat_in = 15;	    
	    read_busy--;
	  } else {
	    if(dat_bits == 128*8 + 16 + 1 + 1) {
	      // card sends start bit
	      tb->sddat_in = 0;
	      // printf("%.3fms SDC: READ-4 START\n", simulation_time*1000);
	    } else if(dat_bits > 1) {
	      // if(dat_bits == 128*8 + 16 + 1) printf("%.3fms SDC: READ DATA START\n", simulation_time*1000);
	      int nibble = dat_bits&1;   // 1: high nibble, 0: low nibble
	      if(nibble) tb->sddat_in = (*dat_ptr >> 4)&15;
	      else       tb->sddat_in = *dat_ptr++ & 15;
	    } else
	      tb->sddat_in = 15;
	    
	    dat_bits--;
	  }
	}
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
          printf("%.3fms SDC: %sCMD %2d, ARG %08lx\n", simulation_time*1000, last_was_acmd?"A":"", cmd & 0x3f, arg);
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
            printf("%.3fms SDC: Set bus width to %ld\n", simulation_time*1000, arg);
            cmd_out = reply(6, 0);
            break;
          case 16: // set block len (should be 512)
            printf("%.3fms SDC: Set block len to %ld\n", simulation_time*1000, arg);
            cmd_out = reply(16, 0);    // ok
            break;
          case 17: { // read block
	    int i = arg >> 24;
	    int drive = 0;
	    // i == 0 for MCU request
	    int lba = arg & 0xffffff;
	    if(i) { while(!(i&1)) { drive++; i>>=1; }
	      printf("%.3fms SDC: Request drive #%d read single block %d (%s)\n", simulation_time*1000,
		     drive, lba, sector_string(drive, lba));

	      // check if sector is actually within the drive image
	      if(lba >= file_image_len[drive]/512) {
		printf("Error, core drive %d access outside image\n", drive);
		exit(-1);  // exit to never miss this!		
	      }
	    } else {
	      printf("%.3fms SDC: Request MCU read single block %d\n", simulation_time*1000, lba);

	      if(lba >= 65535) {
		printf("Error, MCU access outside image\n");
		exit(-1);  // exit to never miss this!		
	      }
	    }
	      
	    cmd_out = reply(17, 0);    // ok

	    if(i) {	    
	      if(fd[drive]) {
		// load sector
		fseek(fd[drive], 512 * lba, SEEK_SET);
		int items = fread(sector_data, 2, 256, fd[drive]);
		if(items != 256) perror("fread()");

		hexdump(sector_data, 32);
	      } else {
		printf("%.3fms SDC: No image loaded, sending empty data\n", simulation_time*1000);
		memset(sector_data, 0, 512);
	      }
	    } else {
	      // MCU read
	      printf("%.3fms SDC: Fake MCU read data\n", simulation_time*1000);
	      sd_setup_fake_sector(lba, sector_data, 0x55);  
	    }
	      
	    update_crc(sector_data);
	    dat_ptr = sector_data;
	    dat_write = 0;
	    dat_bits = 128*8 + 16 + 1 + 1;
	      
	    read_busy = READ_BUSY_COUNT;  // some delay to simulate card actually doing some read
	  } break;
            
          case 24: {  // write block
	    int i = arg >> 24;
	    int drive = 0;
	    // i == 0 for MCU request
	    int lba = arg & 0xffffff;
	    if(i) { while(!(i&1)) { drive++; i>>=1; }
	      printf("%.3fms SDC: Request drive #%d write single block %d (%s)\n", simulation_time*1000,
		     drive, lba, sector_string(drive, lba));
	    } else
	      printf("%.3fms SDC: Request MCU write single block %d\n", simulation_time*1000, lba);
	    
            cmd_out = reply(24, 0);    // ok

	    // prepare to receive data
	    dat_arg = arg;
            dat_ptr = sector_data;
            dat_write = 1;
            dat_bits = 128*8 + 16 + 1 + 1 + 4;

	  } break;

          default:
            printf("%.3fms SDC: unexpected command\n", simulation_time*1000);
          }

          last_was_acmd = (cmd & 0x3f) == 55;
          
          cmd_in = -1;
        } else
          printf("%.3fms SDC: CMD %02x, ARG %08lx, CRC7 %02x != %02x!!\n", simulation_time*1000, cmd, arg, crc7, getCRC(cmd, arg));         
      }      
    }      
    last_sdclk = tb->sdclk;     
  }

  // do a simple FPGA Companion
  fc_handle();
}      

void sd_init(void) {
  // assure reproducable results
  srandom(0x12345678);

  // mcu is idle
  tb->mcu_data_strobe = 0;
  tb->mcu_data_start = 0;
  tb->mcu_data_in = 0;
  tb->mcu_iack = 0;

  // put sd card bus into idle state
  tb->sdcmd_in = 1;
  tb->sddat_in = 0xf;
}

void sd_get_sector(int drive, int lba, uint8_t *data) {
  // read original sector for comparison
  fseek(fd[drive], 512 * lba, SEEK_SET);
  int items = fread(data, 2, 256, fd[drive]);
  if(items != 256) perror("fread()");
}
