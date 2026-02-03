import sys
import csv
from pathlib import Path

import matplotlib.pyplot as plt

if len(sys.argv) < 2:
    print("Usage: python plot_mem.py <memtime_dir>")
    sys.exit(1)

out_dir = Path(sys.argv[1])
csv_path = out_dir / "mem_rss.csv"
png_path = out_dir / "mem_rss.png"

t_min = []
rss_gib = []

with csv_path.open() as f:
    reader = csv.DictReader(f)
    for row in reader:
        t_min.append(float(row["min_since_start"]))
        rss_gib.append(float(row["rss_total_gib"]))

if not t_min:
    raise SystemExit(f"No data in {csv_path}")

peak = max(rss_gib)
peak_t = t_min[rss_gib.index(peak)]

plt.figure()
plt.plot(t_min, rss_gib)
plt.xlabel("Time (min)")
plt.ylabel("Total RSS (GiB)")
plt.title("Memory usage over time (RSS)")
plt.axvline(peak_t, linestyle="--")
plt.text(peak_t, peak, f" peak {peak:.3f} GiB", rotation=90, va="bottom")
plt.tight_layout()
plt.savefig(png_path, dpi=200)
print("Saved:", png_path)