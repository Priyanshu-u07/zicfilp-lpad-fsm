# Build, run, lint, and assert-check the Zicfilp landing-pad FSM.
#   make          lint the RTL, then compile and run the testbench (Icarus)
#   make sim      run the testbench under Icarus Verilog
#   make sim-vl   run the testbench under Verilator
#   make assert   run the testbench under Verilator with SVA assertions (bind)
#   make lint     lint the synthesizable RTL under Verilator (-Wall, zero warnings)
#   make clean    remove build artifacts

RTL   := rtl/lpad_pkg.sv rtl/lpad_fsm.sv
PROPS := rtl/lpad_fsm_props.sv
TB    := tb/tb_lpad_fsm.sv
TOP   := tb_lpad_fsm

.PHONY: all sim sim-vl assert lint clean
all: lint sim

sim:
	iverilog -g2012 -s $(TOP) -o sim.vvp $(RTL) $(TB)
	vvp sim.vvp

sim-vl:
	verilator --binary --timing --timescale 1ns/1ps --top-module $(TOP) $(RTL) $(TB) -o sim_vl
	./obj_dir/sim_vl

assert:
	verilator --binary --timing --timescale 1ns/1ps --assert --top-module $(TOP) $(RTL) $(PROPS) $(TB) -o sim_assert
	./obj_dir/sim_assert

lint:
	verilator --lint-only -Wall $(RTL)

clean:
	rm -f sim.vvp
	rm -rf obj_dir *.vcd
