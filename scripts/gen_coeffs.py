#!/usr/bin/env python3
"""
FIR Filter Coefficient + Sine LUT Generator
For Tang Nano 20K (27 MHz clock)
Generates: coeffs.mem and sine_lut.mem for Verilog

To generate coeffs.mem and sine_lut.mem
python3 gen_coeffs.py
"""

import numpy as np
from scipy import signal

# ── Parameters ────────────────────────────────────────────────────────────────
CLK_FREQ    = 27_000_000   # 27 MHz onboard oscillator
SAMPLE_RATE =     27_000   # CLK / 1000 → 27 kHz sample rate
CUTOFF_HZ   =      1_000 
TAPS        =         16   
COEFF_WIDTH =         16  
DATA_WIDTH  =         16  
SINE_DEPTH  =        256   # Sine LUT entries (power of 2)

# FIR Coefficients (low-pass, Hamming window)
nyq          = SAMPLE_RATE / 2
cutoff_norm  = CUTOFF_HZ / nyq
coeffs       = signal.firwin(TAPS, cutoff_norm, window='hamming')
scale        = 2 ** (COEFF_WIDTH - 1) - 1
coeffs_fixed = np.round(coeffs * scale).astype(int)

print("=== FIR Coefficients (fixed-point 16-bit signed) ===")
for i, c in enumerate(coeffs_fixed):
    print(f"  coeff[{i:2d}] = {c:6d}  →  0x{c & 0xFFFF:04X}")

# Write coeffs.mem  
# 16-bit hex, one per line, Verilog $readmemh format
with open("coeffs.mem", "w") as f:
    for c in coeffs_fixed:
        f.write(f"{c & 0xFFFF:04X}\n")
print("\nWrote coeffs.mem")

#  Sine Wave LUT 
angles    = np.linspace(0, 2 * np.pi, SINE_DEPTH, endpoint=False)
sine_vals = np.round(np.sin(angles) * (2 ** (DATA_WIDTH - 1) - 1)).astype(int)

with open("sine_lut.mem", "w") as f:
    for v in sine_vals:
        f.write(f"{v & 0xFFFF:04X}\n")
print("Wrote sine_lut.mem")

# constantss
clk_div       = CLK_FREQ // SAMPLE_RATE
phase_inc_500 = round(SINE_DEPTH * 500  / SAMPLE_RATE)
phase_inc_5k  = round(SINE_DEPTH * 5000 / SAMPLE_RATE)

print(f"""
=== Verilog Parameters ===
  CLK_DIV        = {clk_div}      // counter top for sample-rate strobe
  PHASE_INC_500  = {phase_inc_500}       // 500 Hz (passes filter)
  PHASE_INC_5K   = {phase_inc_5k}      // 5 kHz  (attenuated)
  PRODUCT_WIDTH  = {DATA_WIDTH + COEFF_WIDTH}     // DATA_WIDTH + COEFF_WIDTH
  SUM_WIDTH      = {DATA_WIDTH + COEFF_WIDTH + int(np.ceil(np.log2(TAPS)))}     // + log2(TAPS) guard bits
""")