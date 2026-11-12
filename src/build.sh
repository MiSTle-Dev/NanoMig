#!/bin/bash

if [[ "$#" -eq 1 && "$1" = "all" ]]; then
   builds=("nano20k" "nano20k aga" "nano20k lcd" "nano20k aga lcd" "gw5a_25")
   for i in "${builds[@]}"; do
       grc --config=gw_sh.grc gw_sh scripts/build.tcl $(echo $i)
   done

   exit 0
fi

# run through grc to highlight NOTEs, WARNings and ERRORs
grc --config=gw_sh.grc gw_sh scripts/build.tcl $@
