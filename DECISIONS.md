# DECISIONS.md — locked design & verification contract

Every entry is a locked decision with its one-line justification.
This file is the single source of truth; chat memory is not.

**Scope:** decisions about the code that a mentor would ask "why" about.
Process, planning, and status live elsewhere.

## Interface
- **No `valid_i` port.** Primary reason: spec fidelity — the challenge specifies
  a packet every cycle, so a valid strobe would model a *different machine* than
  the one specified. Secondary, practical: an extra undriven port could break a
  grader's harness (looks broken). Pipeline-awareness is noted in the README instead.
- **`rstn_i`, async active-low.** Verified against Sargantana RTL (434× `rstn_i`,
  tested `negedge rstn_i`) — matched, not asserted.
- **`state_o` enum-typed output** — for observability, not necessity; a bind-based
  checker could replace it. Its encoding is public API, hence explicit values.
- **`error_o`** — models the point where the ratified Zicfilp mechanism raises a
  software-check exception (cause=18, xtval=2 "landing pad fault") on a violation;
  redundant in information with `state_o == LPAD_ERROR` but distinct in role
  (trap signal vs debug).

## Encodings (single source of truth: lpad_pkg.sv)
- States: `LPAD_IDLE=2'd0, LPAD_CHECK=2'd1, LPAD_ERROR=2'd2` — explicit (observable API).
- Commands: `CMD_SET=8'h01, CMD_JUMP=8'h02, CMD_LPAD=8'h03` — `CMD_` prefix so the
  command family can't be confused with the `LPAD_` state family under wildcard import.
- `CMD_NOP=8'h00` lives in the TB only — test stimulus, not design vocabulary.
- Module-scoped import (`module lpad_fsm import lpad_pkg::*;`), not `$unit` scope.

## Internal design
- Two-process: `always_comb` (decide) + `always_ff @(posedge clk_i, negedge rstn_i)`.
- `_d`/`_q` for state and 24-bit label.
- **Defaults-first** in `always_comb` (`state_d=state_q; label_d=label_q;`) — prevents
  inferred latches AND enforces "label written only on SET-in-IDLE" via a single override.
- Plain `case` + explicit **fail-closed `default -> LPAD_ERROR`** (illegal 4th
  encoding traps).

## Behavior spec — architectural (the 10 rows)
| State | Input | Next | Action |
|---|---|---|---|
| IDLE  | SET               | IDLE  | label <- data |
| IDLE  | JUMP              | CHECK | label unchanged |
| IDLE  | LPAD              | IDLE  | no-op (pitfall #1, not a violation) |
| IDLE  | unknown           | IDLE  | no-op |
| CHECK | LPAD, data==label | IDLE  | label unchanged |
| CHECK | LPAD, data!=label | ERROR | mismatch |
| CHECK | SET               | ERROR | label NOT updated (pitfall #2) |
| CHECK | JUMP              | ERROR | pitfall #2 |
| CHECK | unknown           | ERROR | violation |
| ERROR | anything          | ERROR | sticky (pitfall #3) |

- Non-architectural: illegal 4th state encoding -> ERROR, in the RTL default arm.
- "pitfall" not "trap" — *trap* = taking an exception, which the ERROR state models.

## Verification — 15 tests, self-checking, count reported in the "checks" unit
- T1 reset->IDLE; T2 SET-IDLE; T3 JUMP->CHECK; T4 LPAD-IDLE no-op; T5 unknown-IDLE
- T6 happy path; T7 mismatch->ERROR; T8 SET-CHECK->ERROR; T9 JUMP-CHECK->ERROR
- T10 ERROR sticky under matching LPAD; T11 label reuse; T12 label overwrite
- **T13 unknown-in-CHECK -> ERROR** (fills the row hole)
- **T14 reset recovers from ERROR** (label cleared, then a happy path to prove recovery)
- **T8 label-untouched** via hierarchical peek (`dut.label_q`) — unobservable
  behaviorally once ERROR is sticky; two observation methods used deliberately.
- **T15 ~1000 random packets vs a spec-derived golden model.** Independence is by
  *derivation* — the model is written from the behavior table without looking at the
  RTL, so a spec misreading would have to occur twice, independently, to escape
  detection (holds even though both files end up structurally similar). Sharing
  `lpad_pkg` does not break this: the *alphabet* is shared, the *behavior* is not.
- Each violation test is preceded by a reset.

## Tools
- **Sim:** `iverilog -g2012` (primary; `make`). Verilator `--binary --timing
  --timescale 1ns/1ps` is a verified alternative (`make sim-vl`); the flag is
  required because the TB carries a `timescale but the RTL does not -- matching
  Sargantana's convention (23 timescale files in the repo, all testbenches, 0
  design files).
- **Lint:** `verilator --lint-only -Wall` — zero warnings required.
- Plain `case` is verified, not just preferred: Icarus prints
  `sorry: Case unique/unique0 qualities are ignored`, so `unique` would be silently
  dropped by part of the toolchain — plain `case` + fail-closed `default` instead.

