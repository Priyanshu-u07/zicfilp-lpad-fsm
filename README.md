# zicfilp-lpad-fsm

A synthesizable SystemVerilog FSM modeling the RISC-V **Zicfilp** landing-pad
enforcement mechanism, with a self-checking testbench, bound SVA assertions, and
dual-simulator support (Icarus Verilog and Verilator).

The FSM tracks the *expected-landing-pad* (ELP) state and traps on a control-flow
violation. It is a faithful simplification of the ratified Zicfilp mechanism, not
a literal copy: two of its states are the real ELP states, and a third models the
point at which hardware would raise a software-check exception.

## Interface

```
module lpad_fsm (
    input  logic        clk_i,
    input  logic        rstn_i,     // asynchronous reset, active-low
    input  logic [31:0] packet_i,   // [31:24] = command, [23:0] = data
    output lpad_state_e state_o,    // current state
    output logic        error_o     // asserted in ERROR
);
```

One 32-bit packet is accepted per cycle: the top 8 bits are a command
(`SET=0x01`, `JUMP=0x02`, `LPAD=0x03`), the low 24 bits are data.

## Behavior

Three states, mapped to the real Zicfilp mechanism:

| State        | Zicfilp meaning  | Role                              |
|--------------|------------------|-----------------------------------|
| `LPAD_IDLE`  | `NO_LP_EXPECTED` | normal execution                  |
| `LPAD_CHECK` | `LP_EXPECTED`    | a landing pad must arrive next    |
| `LPAD_ERROR` | (trapped)        | models a raised CFI exception     |

| State | Input                | Next  | Action                          |
|-------|----------------------|-------|---------------------------------|
| IDLE  | SET                  | IDLE  | store data into label           |
| IDLE  | JUMP                 | CHECK | –                               |
| IDLE  | LPAD / unknown       | IDLE  | no-op (a stray LPAD is safe)    |
| CHECK | LPAD, data == label  | IDLE  | –                               |
| CHECK | anything else        | ERROR | violation (label not written)   |
| ERROR | anything             | ERROR | sticky; reset is the only exit  |

## Building and running

Tested with Icarus Verilog 12.0 and Verilator 5.032.

```
make          # lint the RTL, then compile and run the testbench (Icarus)
make sim      # run the testbench under Icarus Verilog
make sim-vl   # run the testbench under Verilator
make assert   # run under Verilator with the SVA assertions enabled
make lint     # lint the synthesizable RTL (Verilator -Wall, zero warnings)
make clean    # remove build artifacts
```

A successful run ends with:

```
ALL TESTS PASSED (24 checks)
```

A waveform can be dumped with the Icarus flow: `vvp sim.vvp +dump` produces
`dump.vcd`.

## Design decisions

- **Reset is asynchronous, active-low, named `rstn_i`** — matching the Sargantana
  core's own convention (verified across its RTL: `rstn_i` throughout, `negedge
  rstn_i`).
- **State and command encodings live in one package (`lpad_pkg`)**, imported by
  both the design and the testbench, so the two can never disagree on an
  encoding. State values are explicit (`LPAD_IDLE = 2'd0`, ...) because `state_o`
  is an observable output, hence a public contract.
- **No `valid_i` port.** The challenge specifies a packet every cycle; adding a
  valid strobe would model a different machine than the one specified.
- **Plain `case` with an explicit fail-closed `default -> LPAD_ERROR`.** The
  illegal fourth state encoding traps rather than recovering silently — the safe
  choice for a security primitive. Plain `case` is used because `unique` is
  silently ignored by part of the toolchain (Icarus).
- **Defaults-first in `always_comb`** (`state_d = state_q; label_d = label_q;`).
  This prevents inferred latches and enforces that the label is written *only* on
  SET-in-IDLE, via a single override.
- **Assertions are a separate module attached by `bind`** (`lpad_fsm_props.sv`),
  so the synthesizable RTL stays free of verification-only code and ports.

## Verification

Three independent layers. Layers 1 and 2 run under both Icarus and Verilator;
layer 3 runs under Verilator only (`make assert`), as Icarus does not support
concurrent SVA.

1. **Directed tests** — every row of the behavior table, the three edge-case
   pitfalls, label persistence, and reset recovery.
2. **Randomized cross-check** — ~1000 packets compared against a golden model
   written from the behavior table (not the RTL), so agreement is meaningful.
   Data is drawn from a small set on purpose, so matching-landing-pad cases
   actually occur.
3. **Bound SVA assertions** — four properties checked on every clock: ERROR is
   sticky, an LPAD in IDLE never traps, the only exit from CHECK is a matching
   LPAD, and the label changes only on SET-in-IDLE.

The assertion layer was **mutation-tested**: deliberately breaking the
sticky-ERROR transition makes `a_error_sticky` fail (at 435 ns), confirming the
assertions catch real faults rather than passing vacuously.

**Reproducibility.** Icarus runs are bit-identical across machines (`$finish` at
`16450000 ps`, verified on two machines). Each engine is deterministic within
itself; the random sequences differ between engines because Verilator ignores
`$random`'s seed argument.

## Repository layout

```
rtl/lpad_pkg.sv         shared state/command encodings
rtl/lpad_fsm.sv         the FSM (synthesizable)
rtl/lpad_fsm_props.sv   SVA properties, bound to the FSM
tb/tb_lpad_fsm.sv       self-checking testbench (directed + randomized)
Makefile                build/run/lint/assert targets
```

## License

Apache-2.0. See the [LICENSE](LICENSE) file; each source file carries an SPDX header.
