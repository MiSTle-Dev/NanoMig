#!/bin/bash

builds=("nano20k" "nano20k aga" "nano20k lcd" "nano20k aga lcd" "tp25k" "tp25k aga" "gw5a_25")

if [[ "$#" -eq 1 && "$1" = "all" ]]; then
   for i in "${builds[@]}"; do
       grc --config=gw_sh.grc gw_sh scripts/build.tcl $(echo $i)
   done
   exit 0
fi

# run with nosyn option to regenerate all files without synthesis
if [[ "$#" -eq 1 && "$1" = "allfiles" ]]; then
   for i in "${builds[@]}"; do
       grc --config=gw_sh.grc gw_sh scripts/build.tcl $(echo $i) nosyn
   done
   exit 0
fi

# run through grc to highlight NOTEs, WARNings and ERRORs
grc --config=gw_sh.grc gw_sh scripts/build.tcl $@
