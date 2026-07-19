/*
 * Copyright 2026 Priyanshu
 * SPDX-License-Identifier: Apache-2.0
 *
 * Module: lpad_fsm
 * Zicfilp landing-pad enforcement as a 3-state FSM tracking the expected-
 * landing-pad (ELP) state. A faithful simplification of the ratified RISC-V
 * Zicfilp mechanism, not a literal copy.
 */
module lpad_fsm
  import lpad_pkg::*;
(
    input  logic        clk_i,
    input  logic        rstn_i,    // asynchronous reset, active-low
    input  logic [31:0] packet_i,  // [31:24] = command, [23:0] = data
    output lpad_state_e state_o,   // observability
    output logic        error_o    // asserted in ERROR (models the CFI trap)
);

  // State and datapath registers (_d = next, _q = current).
  lpad_state_e state_d, state_q;
  logic [23:0] label_d, label_q;

  logic [7:0]  cmd;
  logic [23:0] data;
  assign cmd  = packet_i[31:24];
  assign data = packet_i[23:0];

  // Next-state / next-label logic ("decide").
  always_comb begin
    // Defaults first: hold both registers. This prevents inferred latches
    // (every path assigns) and enforces the property that the label is written
    // ONLY on SET-in-IDLE, via the single override below.
    state_d = state_q;
    label_d = label_q;

    case (state_q)
      LPAD_IDLE: begin
        case (cmd)
          CMD_SET:  label_d = data;         // store label, stay IDLE
          CMD_JUMP: state_d = LPAD_CHECK;    // expect a landing pad next
          default:  ;                        // LPAD or unknown: no-op, stay IDLE
        endcase
      end

      LPAD_CHECK: begin
        // Only a matching landing pad returns to IDLE. Anything else -- wrong
        // label, SET, JUMP, or unknown -- is a violation.
        if (cmd == CMD_LPAD && data == label_q) state_d = LPAD_IDLE;
        else                                     state_d = LPAD_ERROR;
      end

      LPAD_ERROR: state_d = LPAD_ERROR;       // sticky: trapped forever

      default:    state_d = LPAD_ERROR;       // fail-closed: illegal encoding -> trap
    endcase
  end

  // State register ("remember").
  always_ff @(posedge clk_i, negedge rstn_i) begin
    if (!rstn_i) begin
      state_q <= LPAD_IDLE;
      label_q <= '0;
    end else begin
      state_q <= state_d;
      label_q <= label_d;
    end
  end

  assign state_o = state_q;
  assign error_o = (state_q == LPAD_ERROR);

endmodule
