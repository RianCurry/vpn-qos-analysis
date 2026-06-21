import os, re, csv

base = "../results"
out = "../csv/ping.csv"

with open(out, "w") as f:
    w = csv.writer(f)
    w.writerow(["mode","level","run","avg_ms"])

    for mode in os.listdir(base):
        for level in os.listdir(f"{base}/{mode}"):
            for file in os.listdir(f"{base}/{mode}/{level}"):

                if file.startswith("ping"):
                    path = f"{base}/{mode}/{level}/{file}"
                    text = open(path).read()

                    m = re.search(r"rtt min/avg/max", text)
                    if m:
                        avg = text.split("=")[-1].split("/")[1]
                        run = file.split("_")[1].split(".")[0]
                        w.writerow([mode, level, run, avg])
