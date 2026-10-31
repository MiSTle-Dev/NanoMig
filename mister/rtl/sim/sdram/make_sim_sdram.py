#!/usr/bin/env python3
# Generate sdram_ctrl_sim.v from the real rtl/sdram_ctrl.v for ModelSim ASE.
# Quartus elaborates module-scope signals order-independently; ModelSim -sv
# requires declaration-before-use. We hoist exactly the forward-referenced
# declarations to just after the port list. Behavior-identical -- this copy is
# ONLY for the tb_sdram_fwd sim; the real file is never reordered.
import os

SRC = os.path.join(os.path.dirname(__file__), "..", "..", "sdram_ctrl.v")
DST = os.path.join(os.path.dirname(__file__), "sdram_ctrl_sim.v")
NL = "\r\n"

c = open(SRC, "r", newline="").read()

# the exact declaration lines that are used before their point of declaration
hoist = [
    "reg cache_fill;",
    "reg       init_done;",
    "reg [3:0] sdram_state;",
    "reg  [2:0] slot_type = IDLE;",
    "reg [15:0] sdata_reg;",
    "reg        chipWE;",
]
for d in hoist:
    n = c.count(d + NL)
    assert n == 1, f"hoist anchor {d!r} count {n} != 1"
    c = c.replace(d + NL, "", 1)   # remove original declaration

# ModelSim won't accept procedural assignment to an `inout reg`; convert the
# tristate SDRAM data pad to a net driven by an internal reg (sd_data_o sits at
# Z for our read-only test, so the bench's read pattern always wins).
def sub1(old, new):
    global c
    assert c.count(old) == 1, f"sd_data anchor {old!r} count {c.count(old)} != 1"
    c = c.replace(old, new, 1)

sub1("\tinout  reg [15:0] sd_data,\r\n", "\tinout      [15:0] sd_data,\r\n")
sub1("\t\tsd_data               <= 16'hZZZZ;\r\n", "\t\tsd_data_o             <= 16'hZZZZ;\r\n")
sub1("\t\t\t\t\tsd_data      <= datawr;\r\n", "\t\t\t\t\tsd_data_o    <= datawr;\r\n")

block = (
    "// --- sim-only forward declarations (hoisted for ModelSim -sv) ---" + NL
    + "reg [15:0] sd_data_o = 16'hzzzz;" + NL
    + "assign sd_data = sd_data_o;" + NL
    + NL.join(hoist) + NL
)
# insert AFTER the localparam block (slot_type's initializer references IDLE)
anchor = "\tCPU_WRITECACHE = 3;" + NL
assert c.count(anchor) == 1
c = c.replace(anchor, anchor + NL + block, 1)

open(DST, "w", newline="").write(c)
print(f"wrote {DST} ({len(hoist)} decls hoisted)")
