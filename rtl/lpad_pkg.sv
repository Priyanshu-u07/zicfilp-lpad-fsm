/*
 * Copyright 2026 Priyanshu
 * SPDX-License-Identifier: Apache-2.0
 *
 * Package: lpad_pkg
 * Shared encodings for the Zicfilp landing-pad FSM, imported by both the design
 * (lpad_fsm) and the testbench so the two can never disagree on an encoding.
 */
package lpad_pkg;

  // FSM states. Explicit encodings: state is an observable output, so its
  // values are part of the module's public contract.
  typedef enum logic [1:0] {
    LPAD_IDLE  = 2'd0,  // NO_LP_EXPECTED — normal execution
    LPAD_CHECK = 2'd1,  // LP_EXPECTED    — an lpad must arrive next
    LPAD_ERROR = 2'd2   // trapped        — models a raised CFI exception
  } lpad_state_e;

  // Command field, packet_i[31:24]. The CMD_ prefix keeps the command family
  // distinct from the LPAD_ state family under wildcard import.
  localparam logic [7:0] CMD_SET  = 8'h01;  // store data into label
  localparam logic [7:0] CMD_JUMP = 8'h02;  // indirect jump -> expect a landing pad
  localparam logic [7:0] CMD_LPAD = 8'h03;  // landing pad

endpackage
