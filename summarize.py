import json
import re
import csv
from pathlib import Path

rows=[]

for vpn in ["baseline","wireguard","openvpn"]:

    vpn_dir=Path("results")/vpn

    if not vpn_dir.exists():
        continue

    for level in ["light","medium","heavy"]:

        level_dir=vpn_dir/level

        if not level_dir.exists():
            continue

        for iperf_file in sorted(level_dir.glob("iperf_*.json")):

            if "retry" in iperf_file.name:
                continue

            run=iperf_file.stem.split("_")[1]

            throughput=None
            latency=None
            loss=None

            try:
                with open(iperf_file) as f:
                    data=json.load(f)

                throughput=(
                    data["end"]["sum_received"]["bits_per_second"]
                    /1000000
                )
            except:
                continue

            ping_file=level_dir/f"ping_{run}.txt"

            if ping_file.exists():

                txt=ping_file.read_text()

                m=re.search(
                    r'=\s*([\d\.]+)/([\d\.]+)/([\d\.]+)/',
                    txt
                )

                if m:
                    latency=float(m.group(2))

                p=re.search(
                    r'(\d+)% packet loss',
                    txt
                )

                if p:
                    loss=float(p.group(1))

            rows.append([
                vpn,
                level,
                run,
                throughput,
                latency,
                loss
            ])

Path("csv").mkdir(exist_ok=True)

with open("csv/summary.csv","w",newline="") as f:

    writer=csv.writer(f)

    writer.writerow([
        "vpn",
        "load",
        "run",
        "throughput_mbps",
        "latency_ms",
        "packet_loss_percent"
    ])

    writer.writerows(rows)

print("saved csv/summary.csv")
print("rows =",len(rows))
