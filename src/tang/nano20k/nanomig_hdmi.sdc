create_clock -name clk_hdmi -period 7 -waveform {0 3} [get_nets {clk_pixel_x5}] -add

// The hdmi audio sample words cross from the 48kHz audio clock into the pixel
// clock domain through a toggle handshake: the data is written a full audio
// period (~10us) before the synchronized toggle releases the capture, so the
// single cycle relationship the analyzer assumes here is meaningless. Left
// unconstrained the path is only met by lucky placement, and when it is not
// the captured sample words pick up wrong bits - audible as noisy samples.
set_false_path -from [get_regs {*packet_picker/audio_sample_word_transfer*}] -to [get_regs {*packet_picker/audio_sample_word_buffer*}]
