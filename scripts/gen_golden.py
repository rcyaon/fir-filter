#!/usr/bin/env python3
"""
gen_golden.py — Generate golden reference outputs for FIR filter verification.

This script computes the expected filter output using floating-point Python,
then quantises to Q1.15 to can compare against RTL simulation.

Outputs:
    golden_impulse.txt   — impulse response (one value per line)
    golden_passband.txt  — filtered passband sine
    golden_stopband.txt  — filtered stopband sine

These files can be loaded into GTKWave or compared against $display output
from top_level_tb.v.
"""

import numpy as np
from scipy.signal import firwin, lfilter

# ── Must match fir_filter.v and gen_coeffs.py ────────
TAPS     = 16
CUTOFF   = 0.2
Q        = 15
SCALE    = 2 ** Q        # 32768
N        = 256
# ─────────────────────────────────────────────────────

def to_q15(x):
    """Clip and round float array to Q1.15 integers."""
    return np.clip(np.round(x * SCALE), -(SCALE), SCALE - 1).astype(int)

def from_q15(x):
    """Convert Q1.15 integer array back to float."""
    return x / SCALE

# ── Design same filter as gen_coeffs.py ──────────────
h_float = firwin(TAPS, CUTOFF, window='hamming')
h_q15   = to_q15(h_float)

print(f"Coefficients (Q1.15):")
for i, (hf, hq) in enumerate(zip(h_float, h_q15)):
    print(f"  h[{i:2d}] = {hq:6d}  (float: {hf:.6f})")

# ── Test signals (matches testbench) ─────────────────
FREQ_PASS = 0.05
FREQ_STOP = 0.40
k         = np.arange(N)

impulse   = np.zeros(N); impulse[0] = 1.0          # unit impulse (full scale)
sine_pass = np.sin(2 * np.pi * FREQ_PASS * k)
sine_stop = np.sin(2 * np.pi * FREQ_STOP * k)

# ── Filter using float coefficients ──────────────────
# lfilter: b = h, a = [1] for FIR
y_impulse = lfilter(h_float, [1.0], impulse)
y_pass    = lfilter(h_float, [1.0], sine_pass)
y_stop    = lfilter(h_float, [1.0], sine_stop)

# ── Quantise outputs ──────────────────────────────────
# Input is already at Q1.15 scale (multiply by SCALE),
# then the filter output has the same scale.
y_impulse_q = to_q15(y_impulse)   # impulse → SCALE * output
y_pass_q    = to_q15(y_pass)
y_stop_q    = to_q15(y_stop)

# ── Write golden files ────────────────────────────────
for fname, data, label in [
    ("golden_impulse.txt",  y_impulse_q, "Impulse response"),
    ("golden_passband.txt", y_pass_q,    "Passband sine"),
    ("golden_stopband.txt", y_stop_q,    "Stopband sine"),
]:
    with open(fname, "w") as f:
        f.write(f"# {label} — Q1.15 integer values (signed)\n")
        f.write(f"# Compare against RTL simulation output\n")
        for i, v in enumerate(data):
            f.write(f"{v}\n")
    print(f"Written {fname}")

# ── Quick sanity checks ───────────────────────────────
peak_pass = np.max(np.abs(y_pass[TAPS:]))
peak_stop = np.max(np.abs(y_stop[TAPS:]))
print(f"\nPassband peak amplitude : {peak_pass:.4f}  (expect ≈ 1.0)")
print(f"Stopband peak amplitude : {peak_stop:.4f}  (expect << 1.0)")
print(f"Stopband attenuation    : {20*np.log10(peak_stop+1e-12):.1f} dB")

# ── Optional: plot ────────────────────────────────────
try:
    import matplotlib.pyplot as plt

    fig, axes = plt.subplots(3, 1, figsize=(10, 8))

    axes[0].stem(np.arange(len(y_impulse)), y_impulse, markerfmt='C0o', linefmt='C0-', basefmt='k-')
    axes[0].set_title('Impulse Response')
    axes[0].set_xlabel('Sample'); axes[0].set_ylabel('Amplitude')
    axes[0].grid(True, alpha=0.3)

    axes[1].plot(sine_pass[:64], 'C2--', alpha=0.5, label='Input')
    axes[1].plot(y_pass[:64], 'C0-', label='Output')
    axes[1].set_title(f'Passband Sine (f={FREQ_PASS}) — should pass')
    axes[1].legend(); axes[1].grid(True, alpha=0.3)

    axes[2].plot(sine_stop[:64], 'C2--', alpha=0.5, label='Input')
    axes[2].plot(y_stop[:64], 'C3-', label='Output')
    axes[2].set_title(f'Stopband Sine (f={FREQ_STOP}) — should attenuate')
    axes[2].legend(); axes[2].grid(True, alpha=0.3)

    plt.tight_layout()
    plt.savefig('golden_plots.png', dpi=150)
    print("\nPlots saved to golden_plots.png")
except ImportError:
    print("\n(matplotlib not available — skipping plots)")