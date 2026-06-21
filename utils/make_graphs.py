import pandas as pd
import matplotlib.pyplot as plt

df = pd.read_csv("../csv/iperf.csv")

for mode in df["mode"].unique():
    d = df[df["mode"] == mode]

    plt.figure()
    plt.title(f"Throughput - {mode}")
    plt.plot(d["mbps"])
    plt.savefig(f"../graphs/{mode}_throughput.png")
