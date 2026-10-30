#!/usr/bin/env python3
# Apply posted-write -> chip-read store-to-load forwarding to sdram_ctrl.v.
# Root-cause fix for the D-cache-ON steady-state garble (Universe): a CPU write
# sits in the 1-entry write buffer (posted, not yet committed to SDRAM) while a
# chipset/DMA read of the same 4-word block returns stale SDRAM. We merge the
# buffered writeDat into the matching captured burst word. Replaces "Variant R"
# (the global write-bypass that slowed every D-cache-ON game).
#
# CRLF-preserving, exact-block replacement with a strict count==1 check per edit.
import sys, os

F = os.path.join(os.path.dirname(__file__), "..", "..", "sdram_ctrl.v")
c = open(F, "r", newline="").read()
NL = "\r\n"

edits = []

# 1: forwarding state registers (after the write-buffer regs)
edits.append((
    "reg [15:0] writeDat;\r\n",
    "reg [15:0] writeDat;\r\n"
    "// 2026-05-30 store-to-load forwarding: when the chipset reads a 4-word block\r\n"
    "// the 1-entry CPU write buffer still holds (posted but not yet committed to\r\n"
    "// SDRAM), merge writeDat into the matching burst word so the chipset never\r\n"
    "// sees stale pre-write data. Closes the posted-write vs chip-read coherency\r\n"
    "// hole Universe hits with the turbo D-cache on (replaces blunt Variant R).\r\n"
    "reg        fwd_en = 1'b0;\r\n"
    "reg  [1:0] fwd_pos;\r\n"
    "reg [15:0] fwd_dat;\r\n"
    "reg  [1:0] fwd_dqm;\r\n",
))

# 2: chip-burst capture block -- merge the forwarded write into the matching word
edits.append((
    "always @ (posedge sysclk) begin\r\n"
    "\treg [15:0] sdata_chip;\r\n"
    "\r\n"
    "\tsdata_chip <= sdata_reg;\r\n"
    "\tif(slot_type == CHIP) begin\r\n"
    "\t\tcase(sdram_state)\r\n"
    "\t\t\t 9: chipRD   <= sdata_chip;\r\n"
    "\t\t\t11: chip48_1 <= sdata_chip;\r\n"
    "\t\t\t13: chip48_2 <= sdata_chip;\r\n"
    "\t\t\t15: chip48_3 <= sdata_chip;\r\n"
    "\t\tendcase\r\n"
    "\tend\r\n"
    "end\r\n",

    "always @ (posedge sysclk) begin\r\n"
    "\treg [15:0] sdata_chip;\r\n"
    "\treg [15:0] m;\r\n"
    "\r\n"
    "\tsdata_chip <= sdata_reg;\r\n"
    "\t// byte-merge the pending forwarded CPU write into this burst word\r\n"
    "\tm = sdata_chip;\r\n"
    "\tif(fwd_en) begin\r\n"
    "\t\tif(!fwd_dqm[1]) m[15:8] = fwd_dat[15:8];\r\n"
    "\t\tif(!fwd_dqm[0]) m[7:0]  = fwd_dat[7:0];\r\n"
    "\tend\r\n"
    "\tif(slot_type == CHIP) begin\r\n"
    "\t\tcase(sdram_state)\r\n"
    "\t\t\t 9: chipRD   <= (fwd_en && fwd_pos==2'd0) ? m : sdata_chip;\r\n"
    "\t\t\t11: chip48_1 <= (fwd_en && fwd_pos==2'd1) ? m : sdata_chip;\r\n"
    "\t\t\t13: chip48_2 <= (fwd_en && fwd_pos==2'd2) ? m : sdata_chip;\r\n"
    "\t\t\t15: chip48_3 <= (fwd_en && fwd_pos==2'd3) ? m : sdata_chip;\r\n"
    "\t\tendcase\r\n"
    "\tend\r\n"
    "end\r\n",
))

# 3a: default fwd_en low at the start of each state-0 arbitration
edits.append((
    "\t\t\t\tslot_type       <= IDLE;\r\n",
    "\t\t\t\tslot_type       <= IDLE;\r\n"
    "\t\t\t\tfwd_en          <= 0;\r\n",
))

# 3b: latch the forward decision when a CHIP READ slot is selected
edits.append((
    "\t\t\t\t\tchipWE       <= !chipRW;\r\n"
    "\t\t\t\tend\r\n",
    "\t\t\t\t\tchipWE       <= !chipRW;\r\n"
    "\t\t\t\t\t// posted CPU write pending to the same 4-word block this chip\r\n"
    "\t\t\t\t\t// READ is fetching -> forward it into the burst (chipRW=1 read).\r\n"
    "\t\t\t\t\tif(chipRW & write_req & (writeAddr[24:3] == chipAddr[24:3])) begin\r\n"
    "\t\t\t\t\t\tfwd_en  <= 1'b1;\r\n"
    "\t\t\t\t\t\tfwd_pos <= writeAddr[2:1] - chipAddr[2:1];\r\n"
    "\t\t\t\t\t\tfwd_dat <= writeDat;\r\n"
    "\t\t\t\t\t\tfwd_dqm <= write_dqm;\r\n"
    "\t\t\t\t\tend\r\n"
    "\t\t\t\tend\r\n",
))

for i, (old, new) in enumerate(edits):
    n = c.count(old)
    if n != 1:
        sys.exit(f"edit {i}: anchor count {n} != 1 -- aborting")
    c = c.replace(old, new)

open(F, "w", newline="").write(c)
print(f"patched {F}: all {len(edits)} edits applied exactly once")
