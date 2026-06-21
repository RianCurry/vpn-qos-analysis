import pandas as pd
import matplotlib.pyplot as plt
from pathlib import Path

Path("graphs").mkdir(exist_ok=True)

df=pd.read_csv("csv/summary.csv")

# ==================
# Throughput
# ==================

tp=df.groupby("vpn")["throughput_mbps"].mean()

plt.figure(figsize=(7,5))
tp.plot(kind="bar")
plt.ylabel("Mbps")
plt.title("Average Throughput")
plt.tight_layout()
plt.savefig("graphs/throughput.png")
plt.close()

# ==================
# Latency
# ==================

lat=df.groupby("vpn")["latency_ms"].mean()

plt.figure(figsize=(7,5))
lat.plot(kind="bar")
plt.ylabel("ms")
plt.title("Average Latency")
plt.tight_layout()
plt.savefig("graphs/latency.png")
plt.close()

# ==================
# Packet loss
# ==================

loss=df.groupby("vpn")["packet_loss_percent"].mean()

plt.figure(figsize=(7,5))
loss.plot(kind="bar")
plt.ylabel("%")
plt.title("Average Packet Loss")
plt.tight_layout()
plt.savefig("graphs/loss.png")
plt.close()

# ==================
# Throughput by load
# ==================

pivot=df.pivot_table(
    values="throughput_mbps",
    index="load",
    columns="vpn",
    aggfunc="mean"
)

pivot.plot(kind="bar", figsize=(8,5))
plt.ylabel("Mbps")
plt.title("Throughput vs Load")
plt.tight_layout()
plt.savefig("graphs/throughput_load.png")
plt.close()

print("done")

