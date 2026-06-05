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
pss_gib = []
proc_count = []
metric_source = []

with csv_path.open() as f:
    reader = csv.DictReader(f)
    for row in reader:
        t_min.append(float(row["min_since_start"]))
        rss_gib.append(float(row["rss_total_gib"]))
        if "pss_total_gib" in row and row["pss_total_gib"] not in (None, ""):
            pss_gib.append(float(row["pss_total_gib"]))
        if "proc_count" in row and row["proc_count"] not in (None, ""):
            proc_count.append(int(float(row["proc_count"])))
        if "metric_source" in row:
            metric_source.append(row["metric_source"])

if not t_min:
    raise SystemExit(f"No data in {csv_path}")

have_pss = len(pss_gib) == len(t_min)

if have_pss:
    fig, (ax1, ax2) = plt.subplots(
        2,
        1,
        figsize=(9, 7),
        sharex=True,
        gridspec_kw={"height_ratios": [4, 1.4]},
    )
    peak = max(pss_gib)
    peak_t = t_min[pss_gib.index(peak)]
    ax1.plot(t_min, rss_gib, label="RSS sum", color="#9ca3af", linewidth=1.4)
    ax1.plot(t_min, pss_gib, label="PSS sum", color="#2563eb", linewidth=1.8)
    ax1.axvline(peak_t, linestyle="--", color="#2563eb", alpha=0.6)
    ax1.text(peak_t, peak, f" PSS peak {peak:.3f} GiB", va="bottom", fontsize=9)
    ax1.set_ylabel("Memory (GiB)")
    ax1.set_title("Memory usage over time")
    ax1.legend(frameon=False)
    ax1.grid(alpha=0.25)

    if len(proc_count) == len(t_min):
        ax2.plot(t_min, proc_count, color="#7c3aed", linewidth=1.4)
        ax2.set_ylabel("Proc")
        unique_sources = sorted(set(metric_source)) if metric_source else []
        if unique_sources:
            ax2.set_title("Process count | metric source: " + ", ".join(unique_sources), fontsize=10)
        else:
            ax2.set_title("Process count", fontsize=10)
        ax2.grid(alpha=0.25)
    else:
        ax2.axis("off")

    ax2.set_xlabel("Time (min)")
    plt.tight_layout()
else:
    peak = max(rss_gib)
    peak_t = t_min[rss_gib.index(peak)]
    plt.figure(figsize=(9, 4.8))
    plt.plot(t_min, rss_gib, color="#4b5563")
    plt.xlabel("Time (min)")
    plt.ylabel("Total RSS (GiB)")
    plt.title("Memory usage over time (RSS)")
    plt.axvline(peak_t, linestyle="--")
    plt.text(peak_t, peak, f" peak {peak:.3f} GiB", rotation=0, va="bottom")
    plt.grid(alpha=0.25)
    plt.tight_layout()

plt.savefig(png_path, dpi=200)
print("Saved:", png_path)
