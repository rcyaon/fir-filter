# Makefile — FIR filter + unit tests
# Requires: iverilog, vvp, gtkwave (optional), python3 + scipy/numpy

SRC     = fir_filter.v
TB      = fir_filter_tb.v
OUT     = fir_tb
VCD     = fir_filter_tb.vcd
GOLDEN  = gen_golden.py
COEFFS  = gen_coeffs.py

.PHONY: all sim wave golden coeffs clean help \
        sim_all sim_shift sim_mult sim_sine sim_uart \
        wave_shift wave_mult wave_sine wave_uart

all: sim

# ── Full integration test ─────────────────────────────────
coeffs:
	python3 $(COEFFS)

golden:
	python3 $(GOLDEN)

sim: $(SRC) $(TB)
	iverilog -g2012 -Wall -o $(OUT) $(TB) $(SRC)
	vvp $(OUT)

wave: $(VCD)
	gtkwave $(VCD) &

verify: coeffs sim golden
	@echo "Compare RTL output above against golden_*.txt files."

# ── Unit tests ────────────────────────────────────────────
sim_all: sim_shift sim_mult sim_sine sim_uart
	@echo "\n════ All unit tests complete ════"

sim_shift:
	iverilog -g2012 -Wall -o tb_shift_reg  tb_shift_reg.v  && vvp tb_shift_reg

sim_mult:
	iverilog -g2012 -Wall -o tb_multiplier tb_multiplier.v && vvp tb_multiplier

sim_sine:
	iverilog -g2012 -Wall -o tb_sine_gen   tb_sine_gen.v   && vvp tb_sine_gen

sim_uart:
	iverilog -g2012 -Wall -o tb_uart_tx    tb_uart_tx.v    && vvp tb_uart_tx

wave_shift: ; gtkwave tb_shift_reg.vcd &
wave_mult:  ; gtkwave tb_multiplier.vcd &
wave_sine:  ; gtkwave tb_sine_gen.vcd &
wave_uart:  ; gtkwave tb_uart_tx.vcd &

# ── Clean ─────────────────────────────────────────────────
clean:
	rm -f $(OUT) fir_tb tb_shift_reg tb_multiplier tb_sine_gen tb_uart_tx
	rm -f *.vcd golden_*.txt golden_plots.png fir_response.png

help:
	@echo "Integration test:"
	@echo "  make sim          — compile and run full FIR testbench"
	@echo "  make verify       — coeffs + sim + golden reference"
	@echo "  make wave         — GTKWave for integration test"
	@echo ""
	@echo "Unit tests:"
	@echo "  make sim_all      — run all four unit tests"
	@echo "  make sim_shift    — shift register"
	@echo "  make sim_mult     — multiplier"
	@echo "  make sim_sine     — sine generator"
	@echo "  make sim_uart     — UART TX"
	@echo "  make wave_<name>  — GTKWave for that module"
	@echo ""
	@echo "  make clean        — remove all build artifacts"