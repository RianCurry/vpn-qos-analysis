import json, os, csv

base = "../results"
out = "../csv/iperf.csv"

os.makedirs("../csv", exist_ok=True)

with open(out, "w") as f:
    w = csv.writer(f)
    w.writerow(["mode","level","run","mbps"])

    for mode in os.listdir(base):
        for level in os.listdir(f"{base}/{mode}"):
            for file in os.listdir(f"{base}/{mode}/{level}"):
                if file.endswith(".json"):
                    path = f"{base}/{mode}/{level}/{file}"
                    data = json.load(open(path))

                    try:
                        mbps = data["end"]["sum_received"]["bits_per_second"] / 1e6
                        run = file.split("_")[1].split(".")[0]
                        w.writerow([mode, level, run, mbps])
                    except:
                        pass
