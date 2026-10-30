#!/usr/bin/env python3
# Apply the fill/snoop coherency interlock to cpu_cache_new.v.
# CRLF-preserving, exact-block replacement with a strict count==1 check per edit.
import sys, os

F = os.path.join(os.path.dirname(__file__), "..", "..", "cpu_cache_new.v")
c = open(F, "r", newline="").read()
NL = "\r\n"

edits = []

# A: new FSM state param
edits.append((
    "\tCPU_SM_FILLW = 4'd10;",
    "\tCPU_SM_FILLW = 4'd10,\r\n\tCPU_SM_INVAL = 4'd11;",
))

# B: interlock tracking registers
edits.append((
    "reg         cpu_sm_dlru;\r\nreg   [9:0] sdr_sm_adr;",
    "reg         cpu_sm_dlru;\r\n"
    "// 2026-05-29 fill/snoop interlock: track the in-flight fill line so a chip/\r\n"
    "// bridge write (snoop) that lands while the line is being filled invalidates\r\n"
    "// the just-filled line, forcing a re-fill from now-committed RAM. Closes the\r\n"
    "// D-Cache-ON image coherency hole (see module top doc / known-issues).\r\n"
    "reg         fill_active;\r\n"
    "reg   [7:0] fill_idx;\r\n"
    "reg  [17:0] fill_tag;\r\n"
    "reg         fill_snooped;\r\n"
    "reg         inv_sel;\r\n"
    "reg   [9:0] sdr_sm_adr;",
))

# C: reset init
edits.append((
    "    cpu_sm_bs         <= 2'b11;\r\n  end else begin",
    "    cpu_sm_bs         <= 2'b11;\r\n"
    "    fill_active       <= 1'b0;\r\n"
    "    fill_snooped      <= 1'b0;\r\n"
    "    inv_sel           <= 1'b0;\r\n"
    "  end else begin",
))

# D: miss entry - begin tracking the fill line
edits.append((
    "        end else begin\r\n"
    "          // on miss fetch data from SDRAM\r\n"
    "          sdr_read_req <= 1'b1;\r\n"
    "          cpu_sm_state <= CPU_SM_FILL1;\r\n"
    "        end",
    "        end else begin\r\n"
    "          // on miss fetch data from SDRAM\r\n"
    "          sdr_read_req <= 1'b1;\r\n"
    "          cpu_sm_state <= CPU_SM_FILL1;\r\n"
    "          // begin tracking this fill line for the snoop interlock\r\n"
    "          fill_active  <= 1'b1;\r\n"
    "          fill_snooped <= 1'b0;\r\n"
    "          fill_idx     <= cpu_adr_idx;\r\n"
    "          fill_tag     <= cpu_adr_tag;\r\n"
    "        end",
))

# E: FILL1 cache-bypass path cancels tracking (no line written)
edits.append((
    "          if (cache_inhibit || (!cpu_ir && !cc_den)) begin\r\n"
    "            // don't update cache if caching is inhibited; also bypass\r\n"
    "            // D-cache fill when SW has disabled D-cache (2026-05-27).\r\n"
    "            cpu_sm_state <= CPU_SM_FILLW;",
    "          if (cache_inhibit || (!cpu_ir && !cc_den)) begin\r\n"
    "            // don't update cache if caching is inhibited; also bypass\r\n"
    "            // D-cache fill when SW has disabled D-cache (2026-05-27).\r\n"
    "            // no cache line written -> nothing to invalidate.\r\n"
    "            fill_active  <= 1'b0;\r\n"
    "            cpu_sm_state <= CPU_SM_FILLW;",
))

# F: FILLW diverts to INVAL when the fill line was snooped; add INVAL state
edits.append((
    "      CPU_SM_FILLW : begin\r\n"
    "        if (!cpu_ack) begin\r\n"
    "          cpu_sm_state <= CPU_SM_IDLE;\r\n"
    "        end\r\n"
    "      end",
    "      CPU_SM_FILLW : begin\r\n"
    "        if (!cpu_ack) begin\r\n"
    "          if (fill_active && fill_snooped) begin\r\n"
    "            // a snoop hit the line while it was being filled: the filled data\r\n"
    "            // may be stale (the fill's SDRAM read predates the chip write), so\r\n"
    "            // invalidate the line; the next read re-fills from committed RAM.\r\n"
    "            inv_sel          <= 1'b1;\r\n"
    "            cpu_sm_tag_dat_w <= 40'd0;\r\n"
    "            cpu_sm_itag_we   <=  cpu_sm_id;\r\n"
    "            cpu_sm_dtag_we   <= !cpu_sm_id;\r\n"
    "            cpu_sm_state     <= CPU_SM_INVAL;\r\n"
    "          end else begin\r\n"
    "            fill_active  <= 1'b0;\r\n"
    "            cpu_sm_state <= CPU_SM_IDLE;\r\n"
    "          end\r\n"
    "        end\r\n"
    "      end\r\n"
    "      CPU_SM_INVAL : begin\r\n"
    "        // tag-invalidate write to fill_idx fires this cycle (inv_sel mux);\r\n"
    "        // drop tracking and return to idle.\r\n"
    "        inv_sel      <= 1'b0;\r\n"
    "        fill_active  <= 1'b0;\r\n"
    "        fill_snooped <= 1'b0;\r\n"
    "        cpu_sm_state <= CPU_SM_IDLE;\r\n"
    "      end",
))

# G: snoop-hit-fill detection (after the cpu_sm case)
edits.append((
    "    endcase\r\n    // when CPU lowers its request signal, lower ack too",
    "    endcase\r\n"
    "    // snoop interlock: a chip/bridge write hitting the line currently being\r\n"
    "    // filled is remembered so the line is invalidated at fill completion.\r\n"
    "    if (fill_active && snoop_act\r\n"
    "        && (snoop_adr[10:3] == fill_idx) && (snoop_adr[28:11] == fill_tag))\r\n"
    "      fill_snooped <= 1'b1;\r\n"
    "    // when CPU lowers its request signal, lower ack too",
))

# H: tag-RAM address muxes select fill_idx during the invalidate cycle
edits.append((
    "assign itram_cpu_adr    = cpu_adr_idx;",
    "assign itram_cpu_adr    = inv_sel ? fill_idx : cpu_adr_idx;",
))
edits.append((
    "assign dtram_cpu_adr    = cpu_adr_idx;",
    "assign dtram_cpu_adr    = inv_sel ? fill_idx : cpu_adr_idx;",
))

for i, (old, new) in enumerate(edits):
    n = c.count(old)
    if n != 1:
        print(f"EDIT {i}: expected 1 match, found {n}")
        sys.exit(1)
    c = c.replace(old, new)

open(F, "w", newline="").write(c)
print("patched OK; all", len(edits), "edits applied exactly once")
