/*
 * Copyright 2026 Priyanshu
 * SPDX-License-Identifier: Apache-2.0
 *
 * Module: lpad_fsm_props
 * SVA properties for lpad_fsm, attached by `bind` so the RTL stays untouched
 * and gains no verification-only ports. The four properties restate the
 * behavior contract as assertions; the same file is reusable by a formal tool
 * (e.g. SymbiYosys). Concurrent SVA requires Verilator (`make assert`) --
 * Icarus does not support it.
 */
module lpad_fsm_props
  import lpad_pkg::*;
(
    input logic        clk_i,
    input logic        rstn_i,
    input lpad_state_e state_q,
    input logic [23:0] label_q,
    input logic [7:0]  cmd,
    input logic [23:0] data
);

  // ERROR is sticky. Reset is the only exit, so it is excluded via disable iff.
  a_error_sticky: assert property (@(posedge clk_i) disable iff (!rstn_i)
    (state_q == LPAD_ERROR) |=> (state_q == LPAD_ERROR));

  // No false trap: an LPAD while in IDLE is a no-op, never a violation.
  a_lpad_idle_noop: assert property (@(posedge clk_i) disable iff (!rstn_i)
    (state_q == LPAD_IDLE && cmd == CMD_LPAD) |=> (state_q == LPAD_IDLE));

  // The only exit from CHECK to IDLE is a matching LPAD; anything else traps.
  a_check_nonmatch_traps: assert property (@(posedge clk_i) disable iff (!rstn_i)
    (state_q == LPAD_CHECK && !(cmd == CMD_LPAD && data == label_q))
      |=> (state_q == LPAD_ERROR));

  // The label changes only on SET-in-IDLE.
  a_label_stable: assert property (@(posedge clk_i) disable iff (!rstn_i)
    !(state_q == LPAD_IDLE && cmd == CMD_SET) |=> (label_q == $past(label_q)));

endmodule

// Attach the checker to every lpad_fsm instance without editing the RTL.
bind lpad_fsm lpad_fsm_props u_props (
    .clk_i   (clk_i),
    .rstn_i  (rstn_i),
    .state_q (state_q),
    .label_q (label_q),
    .cmd     (cmd),
    .data    (data)
);
