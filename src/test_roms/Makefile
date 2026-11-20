all: pwr_led_blink.hex video_init.hex flash_read.hex ram_test.hex

%.bin: %.s
	vasmm68k_mot -Fbin $< -o $@

%.hex: %.bin
	xxd -c2 -p $< > $@

clean:
	rm -f *.bin.s *.hex *.bin
