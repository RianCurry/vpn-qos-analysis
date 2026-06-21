# VPN QoS & Resource Usage Analysis on Raspberry Pi 4B

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
![Platform](https://img.shields.io/badge/platform-Raspberry%20Pi%204B-blue)

**Automated benchmarking suite for evaluating Quality of Service (QoS) and system resource consumption (CPU, RAM, temperature) under WireGuard and OpenVPN tunnels using multi‑level stress tests.**

---

## 📖 Table of Contents

- [Overview](#overview)
- [Project Structure](#project-structure)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Configuration](#configuration)
- [Usage](#usage)
- [Test Scenarios](#test-scenarios)
- [Output Files](#output-files)
- [Data Analysis & Visualization](#data-analysis--visualization)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

---

## Overview

This project provides a fully automated script to evaluate the performance impact of VPN tunnels (WireGuard and OpenVPN) on a **Raspberry Pi 4B** acting as a client. It measures:

- **QoS metrics**: throughput (Mbps), latency (RTT), packet loss (%) using `iperf3`, `ping`, and `mtr`.
- **System resource usage**: CPU utilisation (%), RAM consumption (MB), and CPU temperature (°C) using a lightweight sampling script.

Tests are repeated across three stress levels (light, medium, heavy) and multiple iterations to ensure statistical reliability. The entire process is logged and results are stored in structured directories for further analysis.

---

## Project Structure
vpn-qos-lab/
├── run.sh # Main orchestration script
├── collect_pi_metrics.sh # System metrics sampler (CSV output)
├── config.env # User-configurable parameters
├── summarize.py # (Optional) Summary report generator
├── graph.py # (Optional) Plotting script
├── utils_bck/ # Utility scripts (backup)
├── results/ # Output directory (created at runtime)
│ ├── baseline/ # No VPN tests
│ ├── wireguard/ # WireGuard tunnel tests
│ └── openvpn/ # OpenVPN tunnel tests
│ └── <level>/ # light / medium / heavy
│ ├── iperf_<n>.json # iperf3 JSON output
│ ├── ping_<n>.txt # Ping statistics
│ ├── mtr_<n>.txt # MTR report
│ └── sys_<n>.csv # System metrics (timestamp, CPU%, RAM MB, temp °C)
├── logs/ # Execution logs (created at runtime)
└── README.md # This document



---

## Prerequisites

### Hardware
- **Raspberry Pi 4B** (client) running Raspberry Pi OS (or Ubuntu) with SSH access.
- A separate **server** machine (can be another Pi or a PC) with `iperf3` in server mode (`iperf3 -s`).

### Software (installed on the Pi)
- `iperf3`
- `mtr` (`mtr-tiny`)
- `ping` (iputils-ping)
- `wireguard-tools` (for WireGuard mode)
- `openvpn` (for OpenVPN mode)
- `bc` (for floating-point arithmetic)
- `sudo` privileges

Install all required packages with:
```bash
sudo apt update
sudo apt install -y iperf3 mtr-tiny wireguard-tools openvpn bc



Installation

Clone the repository onto your Raspberry Pi:
bash

git clone https://github.com/yourusername/vpn-qos-lab.git
cd vpn-qos-lab

Make the scripts executable:
bash

chmod +x run.sh collect_pi_metrics.sh

Configuration

Edit the config.env file to set your test parameters:
bash

# Target IP addresses (set according to your network)
SERVER_IP=10.10.10.1           # WireGuard server IP (or OpenVPN)

# Number of repetitions per (mode, level)
ITER=5

# Ping and MTR packet counts
PING_COUNT=50
MTR_COUNT=10

# Sampling interval for system metrics (seconds)
SAMPLE_INTERVAL=1

# iperf3 parameters per stress level
DURATION_LIGHT=30
DURATION_MEDIUM=60
DURATION_HEAVY=60

P_LIGHT=1      # parallel streams
P_MEDIUM=4
P_HEAVY=8

    Important: For WireGuard or OpenVPN modes, ensure the VPN tunnel is already established before running the script. The script does not start/stop VPNs; it only tests connectivity and iperf3 server availability.

Usage

Run the main script from the project directory:
bash

./run.sh

You will be presented with a menu:
text

Select mode:
0) Exit
1) Baseline (LAN)
2) WireGuard
3) OpenVPN

Select the desired mode. The script will:

    Verify connectivity to the target IP.

    Check if the iperf3 server is responsive.

    For each stress level (light, medium, heavy) and each iteration (1..$ITER):

        Start the system metrics sampler.

        Run iperf3 (with timeout and retry on failure).

        Stop the sampler.

        Run ping and mtr.

        Wait a short gap before the next iteration.

All output is logged to logs/run_<timestamp>.log and also displayed on the terminal.
Test Scenarios
Level	iperf3 Duration	Parallel Streams	Description
Light	30 sec	1	Low network load
Medium	60 sec	4	Moderate load
Heavy	60 sec	8	High load (stress test)

These levels are applied to each VPN mode and repeated ITER times, giving a comprehensive dataset for statistical comparison.
Output Files

All results are stored under results/<mode>/<level>/.
File pattern	Content
iperf_<n>.json	Full iperf3 JSON output (throughput, retransmits, CPU utilisation)
iperf_<n>_retry.json	Second attempt if first failed
iperf_<n>_error.log	Error messages (if any)
ping_<n>.txt	Ping summary: round‑trip times and packet loss
mtr_<n>.txt	MTR report with loss and latency per hop
sys_<n>.csv	System metrics sampled during the iperf3 run:
	timestamp, cpu_percent, ram_used_mb, temp_c

All timestamps are UNIX epoch seconds. Temperature is read from /sys/class/thermal/thermal_zone0/temp or vcgencmd (Raspberry Pi specific), with two‑decimal precision.
Data Analysis & Visualization

You can extend the project by using the included Python scripts (if present):

    summarize.py – aggregates all JSON/CSV files into a summary table (mean, std, min, max).

    graph.py – generates plots (throughput, latency, CPU usage) for comparative analysis.

Example (if you have Python and matplotlib installed):
bash

pip install -r requirements.txt   # if provided
python graph.py

You may also manually parse the files using your favourite data analysis tool (Excel, R, Pandas, etc.).
Troubleshooting
1. vcgencmd: command not found

    The script falls back to /sys/class/thermal/thermal_zone0/temp; this is fine.

    If both fail, temperature will read 0.00 – check kernel modules.

2. iperf3 fails with "Address already in use"

    The server might still be running. On the server machine, run:
    bash

sudo pkill iperf3
iperf3 -s

3. WireGuard interface wg0 not found

    The script checks for the interface and skips the mode if missing.

    Start WireGuard with:
    bash

sudo wg-quick up wg0

4. CPU / RAM columns empty in CSV

    The collect_pi_metrics.sh script uses top, free, and /proc/stat; ensure these are available.

    If you see empty columns, check if the commands output the expected format.

5. mtr: invalid argument: ''

    This occurs if MTR_COUNT is not set. It now defaults to 10 in the script.

Contributing

Contributions are welcome! Please open an issue or submit a pull request for improvements, bug fixes, or additional features.
License

This project is licensed under the MIT License – see the LICENSE file for details.
Contact & Credits

    Maintainer: Rian Eka Saputra

    Inspired by QoS analysis for VPN performance evaluation on resource‑constrained devices.

Happy benchmarking!
