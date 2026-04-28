#!/usr/bin/env python3
"""
Reads 16-bit signed samples from the FIR filter over UART and plots them.
"""

import argparse
import struct
import numpy as np
import matplotlib.pyplot as plt
import serial

BAUD       = 115_200
N_SAMPLES  = 512     # how many samples to collect before plotting
SAMPLE_RATE = 27_000  # Hz

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", default="/dev/ttyUSB0")
    args = parser.parse_args()

    print(f"Opening {args.port} @ {BAUD} baud …")
    ser = serial.Serial(args.port, BAUD, timeout=5)

    samples = []
    print(f"Collecting {N_SAMPLES} samples …")
    while len(samples) < N_SAMPLES:
        raw = ser.read(2)
        if len(raw) < 2:
            print("Timeout — check connections and FPGA is programmed.")
            break
        # Big-endian signed 16-bit
        val = struct.unpack(">h", raw)[0]
        samples.append(val)

    ser.close()
    samples = np.array(samples, dtype=np.float32)

    # Time domain
    t = np.arange(len(samples)) / SAMPLE_RATE * 1000  # ms

    # Frequency domain
    fft_mag = np.abs(np.fft.rfft(samples))
    freqs   = np.fft.rfftfreq(len(samples), 1 / SAMPLE_RATE)

    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(10, 7))
    fig.suptitle("FIR Low-Pass Filter Output (cutoff = 1 kHz)", fontsize=14)

    ax1.plot(t, samples, linewidth=0.8)
    ax1.set_xlabel("Time (ms)")
    ax1.set_ylabel("Amplitude")
    ax1.set_title("Time Domain")
    ax1.grid(True, alpha=0.3)

    ax2.semilogy(freqs, fft_mag + 1e-6)
    ax2.axvline(500,  color='g', linestyle='--', label='500 Hz (pass)')
    ax2.axvline(1000, color='orange', linestyle='--', label='1kHz cutoff')
    ax2.axvline(5000, color='r', linestyle='--', label='5 kHz (stop)')
    ax2.set_xlabel("Frequency (Hz)")
    ax2.set_ylabel("Magnitude (log)")
    ax2.set_title("Frequency Domain")
    ax2.set_xlim(0, SAMPLE_RATE / 2)
    ax2.legend()
    ax2.grid(True, alpha=0.3)

    plt.tight_layout()
    plt.savefig("fir_output.png", dpi=150)
    print("Saved fir_output.png")
    plt.show()

if __name__ == "__main__":
    main()