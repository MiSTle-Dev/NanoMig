#!/usr/bin/env bash
# build.sh — headless Lattice Diamond build wrapper
#
# Always run from the directory this script lives in (where build_xl.tcl / .ldf are).
cd "$(dirname "$(readlink -f "$0")")"

# --- run the build ----------------------------------------------------------
grc --config=diamondc.grc diamondc build_xl.tcl "$@"

openFPGALoader -cft231X --pins=7:3:5:6 impl_xl/nanomig_impl_xl.bit
