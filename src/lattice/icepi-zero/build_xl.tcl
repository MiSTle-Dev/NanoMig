# build.tcl — headless Lattice Diamond build for NanoMif on icepi-zero

set proj "nanomig_xl.ldf"

prj_project open $proj

prj_run Export -impl impl_xl -forceAll -task Bitgen

puts "=== Saving and closing ==="
# prj_project save
prj_project close

puts "=== Done ==="
puts "You can now e.g. run 'openFPGALoader -cft231X --pins=7:3:5:6 impl/nanomig_xl_impl.bit'"
