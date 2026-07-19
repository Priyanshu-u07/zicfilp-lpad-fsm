`timescale 1ns/1ps
/*
 * Copyright 2026 Priyanshu
 * SPDX-License-Identifier: Apache-2.0
 *
 * Testbench: tb_lpad_fsm
 * Self-checking testbench for lpad_fsm. Imports lpad_pkg so state and command
 * encodings are never mirrored. Directed tests cover every row of the behavior
 * table, the three pitfalls, label persistence, and reset recovery. Failures
 * are counted; a non-zero count ends the run with $fatal. A final randomized
 * run cross-checks ~1000 packets against a golden model derived from the table.
 */
module tb_lpad_fsm;
  import lpad_pkg::*;

  // Test-only stimulus: an unknown command, deliberately outside the design's
  // vocabulary (hence not in lpad_pkg).
  localparam logic [7:0] CMD_NOP = 8'h00;

  logic        clk = 1'b0;
  logic        rstn;
  logic [31:0] packet;
  lpad_state_e state;
  logic        error;

  int unsigned checks = 0;
  int unsigned fails  = 0;

  lpad_fsm dut (
    .clk_i    (clk),
    .rstn_i   (rstn),
    .packet_i (packet),
    .state_o  (state),
    .error_o  (error)
  );

  // 10 ns clock.
  always #5 clk = ~clk;

  // Optional waveform dump: run with +dump (e.g. `vvp sim.vvp +dump`) -> dump.vcd.
  initial if ($test$plusargs("dump")) begin
    $dumpfile("dump.vcd");
    $dumpvars(0, tb_lpad_fsm);
  end

  // Present one packet just before a rising edge (when the FSM samples), then
  // let the outputs settle.
  task automatic send(input logic [7:0] c, input logic [23:0] d);
    @(negedge clk);
    packet = {c, d};
    @(posedge clk);
    #1;
  endtask

  // Assert the current state, and that error_o is consistent with it.
  task automatic check(input lpad_state_e exp, input string name);
    checks++;
    if (state !== exp) begin
      fails++;
      $display("[FAIL] %s: expected state=%0d, got %0d", name, exp, state);
    end else if (error !== (exp == LPAD_ERROR)) begin
      fails++;
      $display("[FAIL] %s: error_o=%0b inconsistent with state=%0d", name, error, state);
    end else begin
      $display("[PASS] %s", name);
    end
  endtask

  // Assert an arbitrary boolean condition.
  task automatic check_true(input logic cond, input string name);
    checks++;
    if (!cond) begin
      fails++;
      $display("[FAIL] %s", name);
    end else begin
      $display("[PASS] %s", name);
    end
  endtask

  // Pulse reset: hold low across a couple of edges, release on a negedge.
  task automatic apply_reset();
    rstn   = 1'b0;
    packet = '0;
    repeat (2) @(posedge clk);
    #1;
    rstn = 1'b1;
    @(negedge clk);
  endtask

  // Randomized cross-check. The golden model is written from the behavior
  // table (not the RTL), so agreement between them is meaningful.
  //
  // Data is drawn from a tiny set on purpose: with full 24-bit random data a
  // matching LPAD is ~1 in 16M, so the CHECK+matching-LPAD case would never
  // fire. A small set makes matches, mismatches, and reuse common.
  task automatic run_random(input int n);
    lpad_state_e gm_state;        // golden state
    logic [23:0] gm_label;        // golden label
    logic [23:0] dvals [3];       // small data set
    logic [7:0]  rc;
    logic [23:0] rd;
    int          seed;
    int          mism;
    int          k;

    dvals[0] = 24'h000000;
    dvals[1] = 24'h000001;
    dvals[2] = 24'hABCDEF;
    seed = 32'h600D5EED;          // fixed seed -> reproducible run
    mism = 0;

    apply_reset();
    gm_state = LPAD_IDLE;
    gm_label = '0;

    for (k = 0; k < n; k++) begin
      // Biased command: mostly meaningful, occasionally an unknown byte.
      case ({$random(seed)} % 4)
        0:       rc = CMD_SET;
        1:       rc = CMD_JUMP;
        2:       rc = CMD_LPAD;
        default: rc = 8'hF0;      // unknown (not 0x01/0x02/0x03)
      endcase
      rd = dvals[{$random(seed)} % 3];

      send(rc, rd);

      // Golden step -- straight from the behavior table.
      if (gm_state == LPAD_IDLE) begin
        if      (rc == CMD_SET)  gm_label = rd;
        else if (rc == CMD_JUMP) gm_state = LPAD_CHECK;
        // LPAD or unknown: no-op, stay IDLE
      end else if (gm_state == LPAD_CHECK) begin
        if (rc == CMD_LPAD && rd == gm_label) gm_state = LPAD_IDLE;
        else                                  gm_state = LPAD_ERROR;
      end else begin
        gm_state = LPAD_ERROR;    // sticky
      end

      // Compare DUT against the golden model -- both state and label.
      if (state !== gm_state || dut.label_q !== gm_label) begin
        if (mism < 5)
          $display("  [T15 mismatch] k=%0d cmd=%02h data=%06h : dut(%0d,%06h) gm(%0d,%06h)",
                   k, rc, rd, state, dut.label_q, gm_state, gm_label);
        mism++;
      end

      // Once ERROR is correctly reached, reset both sides so the run keeps
      // exploring instead of getting stuck in the sticky state.
      if (gm_state == LPAD_ERROR) begin
        apply_reset();
        gm_state = LPAD_IDLE;
        gm_label = '0;
      end
    end

    check_true(mism == 0, "T15 1000 random packets match golden model");
  endtask

  initial begin
    apply_reset();

    // --- IDLE-state rows ---
    check(LPAD_IDLE, "T1  reset -> IDLE");

    send(CMD_SET , 24'hAAAAAA); check(LPAD_IDLE , "T2  SET in IDLE stays IDLE");
    send(CMD_JUMP, 24'h000000); check(LPAD_CHECK, "T3  JUMP in IDLE -> CHECK");
    send(CMD_LPAD, 24'hAAAAAA); check(LPAD_IDLE , "T3b matching LPAD -> IDLE");
    send(CMD_LPAD, 24'h123456); check(LPAD_IDLE , "T4  LPAD in IDLE = no-op (pitfall 1)");
    send(CMD_NOP , 24'h000000); check(LPAD_IDLE , "T5  unknown in IDLE stays IDLE");

    // --- Happy path, end to end ---
    apply_reset();
    send(CMD_SET , 24'hBEEF01);
    send(CMD_JUMP, 24'h000000); check(LPAD_CHECK, "T6a in CHECK");
    send(CMD_LPAD, 24'hBEEF01); check(LPAD_IDLE , "T6b happy path -> IDLE");

    // --- CHECK-state violations (each preceded by a reset) ---
    apply_reset();
    send(CMD_SET , 24'h001122);
    send(CMD_JUMP, 24'h000000);
    send(CMD_LPAD, 24'h999999); check(LPAD_ERROR, "T7  LPAD mismatch -> ERROR");

    // T8: SET in CHECK -> ERROR, and the label must be UNCHANGED. Once ERROR is
    // sticky the label is unobservable behaviorally, so peek the register
    // hierarchically -- the second of the two observation methods.
    apply_reset();
    send(CMD_SET , 24'h0ABCDE);
    send(CMD_JUMP, 24'h000000);
    send(CMD_SET , 24'h0FFFFF);           // SET while a landing pad is expected
    check     (LPAD_ERROR,               "T8a SET in CHECK -> ERROR (pitfall 2)");
    check_true(dut.label_q == 24'h0ABCDE, "T8b label untouched by SET-in-CHECK");

    apply_reset();
    send(CMD_JUMP, 24'h000000);
    send(CMD_JUMP, 24'h000000); check(LPAD_ERROR, "T9  JUMP in CHECK -> ERROR (pitfall 2)");

    // T13: unknown command in CHECK -> ERROR (fills the behavior-table row).
    apply_reset();
    send(CMD_JUMP, 24'h000000);
    send(CMD_NOP , 24'h000000); check(LPAD_ERROR, "T13 unknown in CHECK -> ERROR");

    // --- ERROR is sticky (pitfall 3) ---
    apply_reset();
    send(CMD_SET , 24'h5A5A5A);
    send(CMD_JUMP, 24'h000000);
    send(CMD_LPAD, 24'hBADBAD); check(LPAD_ERROR, "T10a entered ERROR");
    send(CMD_LPAD, 24'h5A5A5A); check(LPAD_ERROR, "T10b sticky under matching LPAD");
    send(CMD_SET , 24'h5A5A5A); check(LPAD_ERROR, "T10c sticky under SET");

    // --- Label persistence ---
    apply_reset();
    send(CMD_SET , 24'h0F0F0F);
    send(CMD_JUMP, 24'h000000);
    send(CMD_LPAD, 24'h0F0F0F); check(LPAD_IDLE, "T11a first landing ok");
    send(CMD_JUMP, 24'h000000);
    send(CMD_LPAD, 24'h0F0F0F); check(LPAD_IDLE, "T11b reused label ok (no re-SET)");

    apply_reset();
    send(CMD_SET , 24'hAAAAAA);
    send(CMD_SET , 24'hBBBBBB);            // overwrite before use
    send(CMD_JUMP, 24'h000000);
    send(CMD_LPAD, 24'hBBBBBB); check(LPAD_IDLE, "T12 latest label wins");

    // --- Reset is the only exit from ERROR ---
    apply_reset();
    send(CMD_JUMP, 24'h000000);
    send(CMD_JUMP, 24'h000000); check(LPAD_ERROR, "T14a in ERROR");
    apply_reset();
    check     (LPAD_IDLE,                "T14b reset recovers to IDLE");
    check_true(dut.label_q == 24'h000000, "T14c label cleared by reset");
    send(CMD_SET , 24'h112233);
    send(CMD_JUMP, 24'h000000);
    send(CMD_LPAD, 24'h112233); check(LPAD_IDLE, "T14d happy path after recovery");

    // --- Randomized cross-check (directed for coverage, random for confidence) ---
    run_random(1000);

    // --- Summary ---
    $display("-------------------------------------------");
    if (fails == 0) $display("ALL TESTS PASSED (%0d checks)", checks);
    else            $display("TESTS FAILED: %0d of %0d checks", fails, checks);
    $display("-------------------------------------------");
    if (fails != 0) $fatal(1, "Testbench failed");
    $finish;
  end

endmodule
