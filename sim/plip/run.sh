#!/bin/bash
# Simulations of the virtual parallel port (plipbox peer), iverilog >= 12
#   ./run.sh            run all
set -e
cd "$(dirname "$0")"
S=../../src
O=/tmp/plip_sim; mkdir -p $O

echo "== plip_peer alone (driver model of hwpar.asm)"
iverilog -g2012 -o $O/peer.vvp tb_plip_peer.v $S/minimig-aga/plip_peer.v && vvp -n $O/peer.vvp | tail -2

echo "== real ciaa/ciab/bridge + plip_peer (glue taken verbatim from minimig.v)"
python3 mkglue.py $S/minimig-aga/minimig.v $O/minimig_cia_glue.vh
iverilog -g2012 -DENABLE_PLIP -I$O -o $O/cia.vvp tb_cia_plip.v \
  $S/minimig-aga/{amiga_clk,minimig_m68k_bridge,ciaa,ciab,cia_int,cia_timera,cia_timerb,cia_timerd,plip_peer}.v && vvp -n $O/cia.vvp | tail -2

echo "== plip_host with byte-level SPI target interface"
iverilog -g2012 -o $O/host.vvp tb_plip_host.v $S/misc/plip_host.v $S/minimig-aga/plip_peer.v && vvp -n $O/host.vvp | tail -2

echo "== real mcu_spi.v at bit level (19.2 MHz) + plip_host + plip_peer, 100 ns between bytes"
sed 's/integer sp_gap = 0;/integer sp_gap = 100;/' tb_spi_net.v > $O/tb_spi_net.v
iverilog -g2012 -DENABLE_PLIP -o $O/spi.vvp $O/tb_spi_net.v $S/misc/mcu_spi.v $S/misc/plip_host.v $S/minimig-aga/plip_peer.v && vvp -n $O/spi.vvp | tail -2

echo "== PLIP_LITE (no statistics, no loopback): host-mediated tests only"
iverilog -g2012 -DPLIP_LITE -o $O/host_lite.vvp tb_plip_host.v $S/misc/plip_host.v $S/minimig-aga/plip_peer.v && vvp -n $O/host_lite.vvp | tail -2
iverilog -g2012 -DENABLE_PLIP -DPLIP_LITE -o $O/spi_lite.vvp $O/tb_spi_net.v $S/misc/mcu_spi.v $S/misc/plip_host.v $S/minimig-aga/plip_peer.v && vvp -n $O/spi_lite.vvp | tail -2
